//! Point-in-time views of what the running process holds in memory.
//!
//! These deliberately overlap with `/metrics` only where a number is cheap to
//! repeat. The reason this surface exists at all is that Prometheus labels have
//! to stay bounded, so everything entity-scoped (which peer is backed off, which
//! segment generation is stuck, what configuration actually resolved) is
//! aggregated away into a count before it reaches a time series. Those are the
//! facts an operator wants when debugging one node, and they are the facts a
//! metric cannot carry.
//!
//! Everything here is a snapshot taken under whatever locks the underlying
//! state uses, then released. Nothing is held across serialization.

use serde::{Deserialize, Serialize};

use crate::{
    config::Config,
    control::runtime_file::{RuntimeInfo, now_unix_ms},
    state::SharedState,
    store::StoreSnapshot,
};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RuntimeReport {
    pub node: NodeReport,
    pub traffic: TrafficReport,
    pub membership: MembershipReport,
    pub replication: ReplicationReport,
    pub memory: MemoryReport,
    pub pools: PoolsReport,
    pub store: StoreReport,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NodeReport {
    pub version: String,
    pub pid: u32,
    pub started_at_unix_ms: u64,
    pub uptime_seconds: u64,
    pub node_url: String,
    pub region: String,
    pub tenant_id: String,
    pub port: u16,
    pub internal_port: u16,
    pub peer_tls_enabled: bool,
    pub public_tls_enabled: bool,
    pub extension_enabled: bool,
    pub analytics_enabled: bool,
    pub usage_metering_enabled: bool,
    pub geoip_loaded: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TrafficReport {
    pub state: String,
    pub ready: bool,
    /// Why the node is not ready. Empty when it is.
    pub reasons: Vec<String>,
    pub draining: bool,
    pub serving: bool,
    pub writer_lock_owned: bool,
    pub http_inflight: usize,
    pub public_http_inflight: usize,
    pub grpc_inflight: usize,
    pub public_request_latency_ewma_ms: Option<u64>,
}

impl TrafficReport {
    pub async fn capture(state: &SharedState) -> Self {
        let readiness = state.readiness_report().await;
        Self {
            state: readiness.state.as_str().to_string(),
            ready: readiness.ready,
            reasons: readiness.reasons,
            draining: readiness.draining,
            serving: state.runtime.is_serving(),
            writer_lock_owned: readiness.writer_lock_owned,
            http_inflight: readiness.http_inflight,
            public_http_inflight: state.runtime.public_http_inflight(),
            grpc_inflight: readiness.grpc_inflight,
            public_request_latency_ewma_ms: state
                .runtime
                .public_request_latency_ewma()
                .map(|latency| latency.as_millis() as u64),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MembershipReport {
    pub generation: u64,
    pub initial_discovery_completed: bool,
    pub peer_view_pending: bool,
    /// Bumped when bootstrap progress is reset. A pass that started under an
    /// older epoch has its completion discarded, which is otherwise only
    /// visible as an increment of `kura_bootstrap_completions_discarded_total`.
    pub bootstrap_epoch: u64,
    /// Whether this node had usable local cache data when it began its current
    /// joining cycle. A warm node serves that data while anti-entropy catches
    /// up; a cold one waits for a clean bootstrap pass.
    pub local_data_available_at_join: bool,
    /// Peers from static configuration, which the control plane does not manage.
    pub configured_peers: Vec<String>,
    /// The control-plane-authoritative peer view, refreshed at heartbeat cadence.
    pub dynamic_peers: Vec<String>,
    pub known_peers: Vec<String>,
    pub bootstrapped_peers: Vec<String>,
    pub bootstrap_inflight_peers: Vec<String>,
    /// Peers only ever seen through discovery. Outbox pruning never drops their
    /// messages, because nothing re-bootstraps them after a network flap, so
    /// this set explains outbox growth that the depth alone does not.
    pub discovered_only_peers: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReplicationReport {
    pub outbox_depth: usize,
    pub outbox_max_depth: usize,
    pub configured_bandwidth_limit_bytes_per_second: u64,
    pub effective_bandwidth_limit_bytes_per_second: Option<u64>,
    pub public_latency_target_ms: u64,
    /// Per-target backoff. There is no metric for this: the target URL would be
    /// an unbounded label, so a peer that has stopped accepting writes is
    /// currently invisible from the outside.
    pub backoff: Vec<ReplicationBackoffEntry>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReplicationBackoffEntry {
    pub target: String,
    pub consecutive_failures: u32,
    pub retry_in_ms: u64,
}

impl ReplicationReport {
    pub async fn capture(state: &SharedState) -> Result<Self, String> {
        let config = &state.config;
        Ok(Self {
            outbox_depth: state.store.outbox_message_count()?,
            outbox_max_depth: config.outbox_max_depth,
            configured_bandwidth_limit_bytes_per_second: config
                .replication_bandwidth_limit_bytes_per_second,
            effective_bandwidth_limit_bytes_per_second: state
                .replication_bandwidth_limiter
                .as_ref()
                .map(|limiter| limiter.effective_bytes_per_second()),
            public_latency_target_ms: config.replication_public_latency_target_ms,
            backoff: state.replication_backoff_snapshot().await,
        })
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MemoryReport {
    pub pressure: String,
    pub uses_container_accounting: bool,
    pub observation_sequence: u64,
    pub runtime_limit_bytes: u64,
    pub hard_limit_bytes: u64,
    pub transient_capacity_bytes: u64,
    pub transient_reserved_bytes: u64,
    /// Pool sizes as they stand under the current pressure level. The static
    /// limits are exported as metrics; these derived values are recomputed on
    /// demand and are otherwise unobservable.
    pub mmap_serving_pool_bytes: usize,
    pub response_streaming_pool_bytes: usize,
    pub foreground_response_streaming_pool_bytes: usize,
    pub elastic_foreground_response_streaming_pool_bytes: usize,
    pub degraded_response_stream_slots: usize,
    pub reapi_response_budget_bytes: usize,
    pub reapi_materialization_limit_bytes: usize,
    pub manifest_cache_target_bytes: usize,
    pub snapshot_cache_target_bytes: usize,
    pub bootstrap_staging_budget_bytes: u64,
    pub background_admission_allowed: bool,
    pub outbox_paused: bool,
    pub segment_refresh_allowed: bool,
    pub manifest_cache_admission_allowed: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PoolsReport {
    pub bootstrap_peer_permits_available: usize,
    pub bootstrap_artifact_permits_available: usize,
    pub tmp_staging_capacity_bytes: u64,
    pub tmp_staging_reserved_bytes: u64,
    pub bootstrap_staging_capacity_bytes: u64,
    pub bootstrap_staging_reserved_bytes: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StoreReport {
    pub outbox_messages: usize,
    pub multipart_uploads: usize,
    pub promotion_queue_depth: usize,
    pub segment_counts: Vec<SegmentCount>,
    pub segment_fsync_count: u64,
    pub rocksdb_block_cache_usage_bytes: u64,
    pub rocksdb_block_cache_pinned_usage_bytes: u64,
    pub rocksdb_block_cache_capacity_bytes: u64,
    pub rocksdb_write_buffer_usage_bytes: u64,
    pub rocksdb_write_buffer_capacity_bytes: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SegmentCount {
    pub generation: String,
    pub segments: usize,
}

impl From<StoreSnapshot> for StoreReport {
    fn from(snapshot: StoreSnapshot) -> Self {
        Self {
            outbox_messages: snapshot.outbox_messages,
            multipart_uploads: snapshot.multipart_uploads,
            promotion_queue_depth: snapshot.promotion_queue_depth,
            segment_counts: snapshot
                .segment_counts
                .into_iter()
                .map(|(generation, segments)| SegmentCount {
                    generation: generation.to_string(),
                    segments,
                })
                .collect(),
            segment_fsync_count: snapshot.segment_fsync_count,
            rocksdb_block_cache_usage_bytes: snapshot.rocksdb_block_cache_usage_bytes,
            rocksdb_block_cache_pinned_usage_bytes: snapshot.rocksdb_block_cache_pinned_usage_bytes,
            rocksdb_block_cache_capacity_bytes: snapshot.rocksdb_block_cache_capacity_bytes,
            rocksdb_write_buffer_usage_bytes: snapshot.rocksdb_write_buffer_usage_bytes,
            rocksdb_write_buffer_capacity_bytes: snapshot.rocksdb_write_buffer_capacity_bytes,
        }
    }
}

impl RuntimeReport {
    pub async fn capture(state: &SharedState, info: &RuntimeInfo) -> Result<Self, String> {
        let readiness = state.readiness_report().await;
        let config = &state.config;

        let node = NodeReport {
            version: info.version.clone(),
            pid: info.pid,
            started_at_unix_ms: info.started_at_unix_ms,
            uptime_seconds: now_unix_ms().saturating_sub(info.started_at_unix_ms) / 1_000,
            node_url: config.node_url.clone(),
            region: config.region.clone(),
            tenant_id: config.tenant_id.clone(),
            port: config.port,
            internal_port: config.internal_port,
            peer_tls_enabled: config.peer_tls.is_some(),
            public_tls_enabled: config.public_tls.is_some(),
            extension_enabled: state.extension.is_some(),
            analytics_enabled: state.analytics.is_some(),
            usage_metering_enabled: state.usage.is_some(),
            geoip_loaded: state.geoip.is_some(),
        };

        let traffic = TrafficReport {
            state: readiness.state.as_str().to_string(),
            ready: readiness.ready,
            reasons: readiness.reasons.clone(),
            draining: readiness.draining,
            serving: state.runtime.is_serving(),
            writer_lock_owned: readiness.writer_lock_owned,
            http_inflight: readiness.http_inflight,
            public_http_inflight: state.runtime.public_http_inflight(),
            grpc_inflight: readiness.grpc_inflight,
            public_request_latency_ewma_ms: state
                .runtime
                .public_request_latency_ewma()
                .map(|latency| latency.as_millis() as u64),
        };

        let membership = MembershipReport {
            generation: readiness.generation,
            initial_discovery_completed: readiness.initial_discovery_completed,
            peer_view_pending: state.runtime.peer_view_pending(),
            bootstrap_epoch: state.current_bootstrap_epoch().await,
            local_data_available_at_join: state
                .local_data_available_at_join
                .load(std::sync::atomic::Ordering::Relaxed),
            configured_peers: config.peers.clone(),
            dynamic_peers: state.dynamic_peers.load().as_ref().clone(),
            known_peers: readiness.known_peers.clone(),
            bootstrapped_peers: readiness.bootstrapped_peers.clone(),
            bootstrap_inflight_peers: readiness.bootstrap_inflight_peers.clone(),
            discovered_only_peers: state
                .discovered_only_peer_history()
                .await
                .into_iter()
                .collect(),
        };

        let store_snapshot = state.store.snapshot()?;

        let replication = ReplicationReport {
            outbox_depth: store_snapshot.outbox_messages,
            outbox_max_depth: config.outbox_max_depth,
            configured_bandwidth_limit_bytes_per_second: config
                .replication_bandwidth_limit_bytes_per_second,
            effective_bandwidth_limit_bytes_per_second: state
                .replication_bandwidth_limiter
                .as_ref()
                .map(|limiter| limiter.effective_bytes_per_second()),
            public_latency_target_ms: config.replication_public_latency_target_ms,
            backoff: state.replication_backoff_snapshot().await,
        };

        let memory_controller = &state.memory;
        let memory = MemoryReport {
            pressure: memory_controller.pressure().as_str().to_string(),
            uses_container_accounting: memory_controller.uses_container_accounting(),
            observation_sequence: memory_controller.observation_sequence(),
            runtime_limit_bytes: memory_controller.runtime_limit_bytes(),
            hard_limit_bytes: memory_controller.hard_limit_bytes(),
            transient_capacity_bytes: memory_controller.transient_capacity_bytes(),
            transient_reserved_bytes: memory_controller.transient_reserved_bytes(),
            mmap_serving_pool_bytes: memory_controller.mmap_serving_pool_bytes(),
            response_streaming_pool_bytes: memory_controller.response_streaming_pool_bytes(),
            foreground_response_streaming_pool_bytes: memory_controller
                .foreground_response_streaming_pool_bytes(),
            elastic_foreground_response_streaming_pool_bytes: memory_controller
                .elastic_foreground_response_streaming_pool_bytes(),
            degraded_response_stream_slots: memory_controller.degraded_response_stream_slots(),
            reapi_response_budget_bytes: memory_controller.reapi_response_budget_bytes(),
            reapi_materialization_limit_bytes: memory_controller
                .reapi_materialization_limit_bytes(),
            manifest_cache_target_bytes: memory_controller
                .manifest_cache_target_bytes(config.manifest_cache_max_bytes),
            snapshot_cache_target_bytes: memory_controller
                .snapshot_cache_target_bytes(config.snapshot_cache_max_bytes),
            bootstrap_staging_budget_bytes: memory_controller.bootstrap_staging_budget_bytes(),
            background_admission_allowed: memory_controller.allow_background_admission(),
            outbox_paused: memory_controller.pause_outbox(),
            segment_refresh_allowed: memory_controller.allow_segment_refresh(),
            manifest_cache_admission_allowed: memory_controller.allow_manifest_cache_admission(),
        };

        let pools = PoolsReport {
            bootstrap_peer_permits_available: state.bootstrap_semaphore.available_permits(),
            bootstrap_artifact_permits_available: state
                .bootstrap_artifact_semaphore
                .available_permits(),
            tmp_staging_capacity_bytes: state.tmp_staging_budget.capacity_bytes(),
            tmp_staging_reserved_bytes: state.tmp_staging_budget.reserved_bytes(),
            bootstrap_staging_capacity_bytes: state.bootstrap_staging_budget.capacity_bytes(),
            bootstrap_staging_reserved_bytes: state.bootstrap_staging_budget.reserved_bytes(),
        };

        Ok(Self {
            node,
            traffic,
            membership,
            replication,
            memory,
            pools,
            store: store_snapshot.into(),
        })
    }
}

/// The resolved configuration, with credentials replaced by a marker.
///
/// This answers a question the pod spec cannot: env vars show what was
/// requested, not what was resolved after defaults, clamps, and derivation from
/// host resources. It is also the only way to see values that enrollment
/// injects into the process after startup, which a freshly exec'd shell would
/// read at their pre-enrollment values.
/// Serialize-only: the client treats the configuration as opaque JSON rather
/// than round-tripping it, so adding a field to `Config` never breaks an older
/// CLI reading a newer node.
#[derive(Clone, Debug, Serialize)]
pub struct ConfigReport {
    pub config: Config,
}

impl ConfigReport {
    pub fn capture(state: &SharedState) -> Self {
        Self {
            config: state.config.clone(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerListReport {
    pub peers: Vec<PeerEntry>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerEntry {
    pub url: String,
    /// How the node learned about this peer: `configured`, `control-plane`, or
    /// `discovered`. A peer can be known through more than one source; the
    /// most authoritative one wins.
    pub source: String,
    pub bootstrapped: bool,
    pub bootstrap_inflight: bool,
    pub consecutive_replication_failures: u32,
    pub retry_in_ms: Option<u64>,
}

impl PeerListReport {
    pub async fn capture(state: &SharedState) -> Self {
        let readiness = state.readiness_report().await;
        let backoff = state.replication_backoff_snapshot().await;
        let configured: std::collections::BTreeSet<&String> = state.config.peers.iter().collect();
        let dynamic = state.dynamic_peers.load();
        let dynamic_set: std::collections::BTreeSet<&String> = dynamic.iter().collect();

        let mut urls: std::collections::BTreeSet<String> =
            readiness.known_peers.iter().cloned().collect();
        urls.extend(state.config.peers.iter().cloned());
        urls.extend(dynamic.iter().cloned());

        let peers = urls
            .into_iter()
            .map(|url| {
                let entry = backoff.iter().find(|entry| entry.target == url);
                PeerEntry {
                    source: if configured.contains(&url) {
                        "configured".to_string()
                    } else if dynamic_set.contains(&url) {
                        "control-plane".to_string()
                    } else {
                        "discovered".to_string()
                    },
                    bootstrapped: readiness.bootstrapped_peers.contains(&url),
                    bootstrap_inflight: readiness.bootstrap_inflight_peers.contains(&url),
                    consecutive_replication_failures: entry
                        .map(|entry| entry.consecutive_failures)
                        .unwrap_or(0),
                    retry_in_ms: entry.map(|entry| entry.retry_in_ms),
                    url,
                }
            })
            .collect();

        Self { peers }
    }
}
