use std::{
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::http::StatusCode;
use prometheus_client::{
    encoding::{EncodeLabelSet, text::encode},
    metrics::{
        counter::Counter,
        family::Family,
        gauge::Gauge,
        histogram::{Histogram, exponential_buckets},
    },
    registry::Registry,
};

use crate::{artifact::kind::ArtifactKind, utils::replication_target_label};

#[derive(Clone)]
pub struct Metrics {
    registry: Arc<Mutex<Registry>>,
    http_requests: Family<HttpRequestLabels, Counter>,
    http_request_duration: Family<HttpRouteLabels, Histogram>,
    http_exceptions: Family<HttpExceptionLabels, Counter>,
    artifact_reads: Family<ArtifactOpLabels, Counter>,
    artifact_writes: Family<ArtifactOpLabels, Counter>,
    artifact_read_bytes: Family<ArtifactOpLabels, Counter>,
    artifact_write_bytes: Family<ArtifactOpLabels, Counter>,
    segment_refreshes: Family<ArtifactOpLabels, Counter>,
    segment_refresh_bytes: Family<ArtifactOpLabels, Counter>,
    segment_refresh_duration: Family<ArtifactRouteLabels, Histogram>,
    segment_evicted_artifacts: Family<ArtifactOpLabels, Counter>,
    replication_requests: Family<ReplicationLabels, Counter>,
    replication_request_duration: Family<ReplicationRouteLabels, Histogram>,
    replication_apply_results: Family<ReplicationApplyLabels, Counter>,
    multipart_parts: Family<MultipartLabels, Counter>,
    node_info: Family<NodeInfoLabels, Gauge>,
    file_descriptor_wait: Family<FileDescriptorWaitLabels, Histogram>,
    file_operations: Family<FileOperationLabels, Counter>,
    file_operation_duration: Family<FileOperationRouteLabels, Histogram>,
    file_operation_bytes: Family<FileOperationLabels, Counter>,
    file_descriptor_in_use: Gauge,
    file_descriptor_available: Gauge,
    file_descriptor_waiting: Gauge,
    file_descriptor_capacity: Gauge,
    segment_handles_cached: Gauge,
    segment_handle_cache_capacity: Gauge,
    segment_handle_cache_lookups: Family<SegmentHandleCacheLookupLabels, Counter>,
    segment_handle_evictions: Family<SegmentHandleEvictionLabels, Counter>,
    manifest_index_entries: Gauge,
    manifest_cache_bytes: Gauge,
    manifest_cache_capacity_bytes: Gauge,
    manifest_cache_lookups: Family<ManifestCacheLookupLabels, Counter>,
    manifest_cache_admissions: Family<ManifestCacheAdmissionLabels, Counter>,
    manifest_cache_evictions: Family<ManifestCacheEvictionLabels, Counter>,
    manifest_index_rebuilds: Family<ManifestIndexResultLabels, Counter>,
    manifest_index_rebuild_duration: Histogram,
    outbox_messages: Gauge,
    multipart_uploads: Gauge,
    discovered_peer_nodes: Gauge,
    bootstrap_runs: Family<BootstrapResultLabels, Counter>,
    bootstrap_duration: Histogram,
    bootstrap_applied_items: Family<BootstrapItemLabels, Counter>,
    analytics_events: Family<AnalyticsLabels, Counter>,
    analytics_batches: Family<AnalyticsLabels, Counter>,
    analytics_batch_duration: Family<AnalyticsRouteLabels, Histogram>,
    analytics_queue_depth: Gauge,
    analytics_queue_capacity: Gauge,
    analytics_circuit_state: Family<AnalyticsRouteLabels, Gauge>,
    analytics_circuit_transitions: Family<AnalyticsCircuitTransitionLabels, Counter>,
    segment_generation_counts: Family<SegmentGenerationLabels, Gauge>,
    extension_hooks: Family<ExtensionHookLabels, Counter>,
    extension_hook_duration: Family<ExtensionHookRouteLabels, Histogram>,
    extension_cache: Family<ExtensionCacheLabels, Counter>,
    process_resident_memory_bytes: Gauge,
    process_virtual_memory_bytes: Gauge,
    rocksdb_block_cache_usage_bytes: Gauge,
    rocksdb_block_cache_pinned_usage_bytes: Gauge,
    rocksdb_block_cache_capacity_bytes: Gauge,
    rocksdb_write_buffer_usage_bytes: Gauge,
    rocksdb_write_buffer_capacity_bytes: Gauge,
    memory_pressure_state: Gauge,
    memory_soft_limit_bytes: Gauge,
    memory_hard_limit_bytes: Gauge,
    memory_pressure_transitions: Family<MemoryPressureTransitionLabels, Counter>,
    background_work_paused: Family<BackgroundWorkerLabels, Gauge>,
    memory_actions: Family<MemoryActionLabels, Counter>,
}

impl Metrics {
    pub fn new(region: String, tenant_id: String) -> Self {
        let mut registry = Registry::default();

        let http_requests = Family::<HttpRequestLabels, Counter>::default();
        let http_request_duration =
            Family::<HttpRouteLabels, Histogram>::new_with_constructor(|| {
                Histogram::new(exponential_buckets(0.001, 2.0, 16))
            });
        let http_exceptions = Family::<HttpExceptionLabels, Counter>::default();
        let artifact_reads = Family::<ArtifactOpLabels, Counter>::default();
        let artifact_writes = Family::<ArtifactOpLabels, Counter>::default();
        let artifact_read_bytes = Family::<ArtifactOpLabels, Counter>::default();
        let artifact_write_bytes = Family::<ArtifactOpLabels, Counter>::default();
        let segment_refreshes = Family::<ArtifactOpLabels, Counter>::default();
        let segment_refresh_bytes = Family::<ArtifactOpLabels, Counter>::default();
        let segment_refresh_duration =
            Family::<ArtifactRouteLabels, Histogram>::new_with_constructor(|| {
                Histogram::new(exponential_buckets(0.001, 2.0, 16))
            });
        let segment_evicted_artifacts = Family::<ArtifactOpLabels, Counter>::default();
        let replication_requests = Family::<ReplicationLabels, Counter>::default();
        let replication_request_duration =
            Family::<ReplicationRouteLabels, Histogram>::new_with_constructor(|| {
                Histogram::new(exponential_buckets(0.001, 2.0, 16))
            });
        let replication_apply_results = Family::<ReplicationApplyLabels, Counter>::default();
        let multipart_parts = Family::<MultipartLabels, Counter>::default();
        let node_info = Family::<NodeInfoLabels, Gauge>::default();
        let file_descriptor_wait =
            Family::<FileDescriptorWaitLabels, Histogram>::new_with_constructor(|| {
                Histogram::new(exponential_buckets(0.0005, 2.0, 16))
            });
        let file_operations = Family::<FileOperationLabels, Counter>::default();
        let file_operation_duration =
            Family::<FileOperationRouteLabels, Histogram>::new_with_constructor(|| {
                Histogram::new(exponential_buckets(0.0005, 2.0, 16))
            });
        let file_operation_bytes = Family::<FileOperationLabels, Counter>::default();
        let file_descriptor_in_use = Gauge::default();
        let file_descriptor_available = Gauge::default();
        let file_descriptor_waiting = Gauge::default();
        let file_descriptor_capacity = Gauge::default();
        let segment_handles_cached = Gauge::default();
        let segment_handle_cache_capacity = Gauge::default();
        let segment_handle_cache_lookups =
            Family::<SegmentHandleCacheLookupLabels, Counter>::default();
        let segment_handle_evictions = Family::<SegmentHandleEvictionLabels, Counter>::default();
        let manifest_index_entries = Gauge::default();
        let manifest_cache_bytes = Gauge::default();
        let manifest_cache_capacity_bytes = Gauge::default();
        let manifest_cache_lookups = Family::<ManifestCacheLookupLabels, Counter>::default();
        let manifest_cache_admissions = Family::<ManifestCacheAdmissionLabels, Counter>::default();
        let manifest_cache_evictions = Family::<ManifestCacheEvictionLabels, Counter>::default();
        let manifest_index_rebuilds = Family::<ManifestIndexResultLabels, Counter>::default();
        let manifest_index_rebuild_duration = Histogram::new(exponential_buckets(0.0005, 2.0, 16));
        let outbox_messages = Gauge::default();
        let multipart_uploads = Gauge::default();
        let discovered_peer_nodes = Gauge::default();
        let bootstrap_runs = Family::<BootstrapResultLabels, Counter>::default();
        let bootstrap_duration = Histogram::new(exponential_buckets(0.001, 2.0, 16));
        let bootstrap_applied_items = Family::<BootstrapItemLabels, Counter>::default();
        let analytics_events = Family::<AnalyticsLabels, Counter>::default();
        let analytics_batches = Family::<AnalyticsLabels, Counter>::default();
        let analytics_batch_duration =
            Family::<AnalyticsRouteLabels, Histogram>::new_with_constructor(|| {
                Histogram::new(exponential_buckets(0.001, 2.0, 16))
            });
        let analytics_queue_depth = Gauge::default();
        let analytics_queue_capacity = Gauge::default();
        let analytics_circuit_state = Family::<AnalyticsRouteLabels, Gauge>::default();
        let analytics_circuit_transitions =
            Family::<AnalyticsCircuitTransitionLabels, Counter>::default();
        let segment_generation_counts = Family::<SegmentGenerationLabels, Gauge>::default();
        let extension_hooks = Family::<ExtensionHookLabels, Counter>::default();
        let extension_hook_duration =
            Family::<ExtensionHookRouteLabels, Histogram>::new_with_constructor(|| {
                Histogram::new(exponential_buckets(0.0005, 2.0, 16))
            });
        let extension_cache = Family::<ExtensionCacheLabels, Counter>::default();
        let process_resident_memory_bytes = Gauge::default();
        let process_virtual_memory_bytes = Gauge::default();
        let rocksdb_block_cache_usage_bytes = Gauge::default();
        let rocksdb_block_cache_pinned_usage_bytes = Gauge::default();
        let rocksdb_block_cache_capacity_bytes = Gauge::default();
        let rocksdb_write_buffer_usage_bytes = Gauge::default();
        let rocksdb_write_buffer_capacity_bytes = Gauge::default();
        let memory_pressure_state = Gauge::default();
        let memory_soft_limit_bytes = Gauge::default();
        let memory_hard_limit_bytes = Gauge::default();
        let memory_pressure_transitions =
            Family::<MemoryPressureTransitionLabels, Counter>::default();
        let background_work_paused = Family::<BackgroundWorkerLabels, Gauge>::default();
        let memory_actions = Family::<MemoryActionLabels, Counter>::default();
        let process_start_time_seconds = Gauge::<i64>::default();
        process_start_time_seconds.set(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64,
        );

        registry.register(
            "kura_http_requests_total",
            "HTTP requests by route and status code",
            http_requests.clone(),
        );
        registry.register(
            "kura_http_request_duration_seconds",
            "HTTP request latency by route",
            http_request_duration.clone(),
        );
        registry.register(
            "kura_http_exceptions_total",
            "HTTP exceptions by route and class",
            http_exceptions.clone(),
        );
        registry.register(
            "kura_artifact_reads_total",
            "Artifact reads by kind and result",
            artifact_reads.clone(),
        );
        registry.register(
            "kura_artifact_writes_total",
            "Artifact writes by kind and result",
            artifact_writes.clone(),
        );
        registry.register(
            "kura_artifact_read_bytes_total",
            "Artifact read throughput by kind and result",
            artifact_read_bytes.clone(),
        );
        registry.register(
            "kura_artifact_write_bytes_total",
            "Artifact write throughput by kind and result",
            artifact_write_bytes.clone(),
        );
        registry.register(
            "kura_segment_refreshes_total",
            "Segment refreshes by kind and result",
            segment_refreshes.clone(),
        );
        registry.register(
            "kura_segment_refresh_bytes_total",
            "Bytes copied while refreshing artifacts out of old segments",
            segment_refresh_bytes.clone(),
        );
        registry.register(
            "kura_segment_refresh_duration_seconds",
            "Time spent refreshing artifacts out of old segments",
            segment_refresh_duration.clone(),
        );
        registry.register(
            "kura_segment_evicted_artifacts_total",
            "Artifacts removed when old segments are evicted",
            segment_evicted_artifacts.clone(),
        );
        registry.register(
            "kura_replication_requests_total",
            "Peer replication requests by target, operation, and result",
            replication_requests.clone(),
        );
        registry.register(
            "kura_replication_request_duration_seconds",
            "Peer replication request latency by target and operation",
            replication_request_duration.clone(),
        );
        registry.register(
            "kura_replication_apply_results_total",
            "Receiver and bootstrap apply outcomes for replicated artifacts and namespace deletes",
            replication_apply_results.clone(),
        );
        registry.register(
            "kura_multipart_parts_total",
            "Multipart part uploads by result",
            multipart_parts.clone(),
        );
        registry.register(
            "kura_node_info",
            "Node info labels for each Kura region",
            node_info.clone(),
        );
        registry.register(
            "kura_file_descriptor_wait_seconds",
            "Time spent waiting to acquire a file descriptor permit",
            file_descriptor_wait.clone(),
        );
        registry.register(
            "kura_file_operations_total",
            "File operations by name and result",
            file_operations.clone(),
        );
        registry.register(
            "kura_file_operation_duration_seconds",
            "File operation latency by operation",
            file_operation_duration.clone(),
        );
        registry.register(
            "kura_file_operation_bytes_total",
            "Bytes transferred by file operation and result",
            file_operation_bytes.clone(),
        );
        registry.register(
            "kura_file_descriptor_in_use",
            "File descriptor permits currently checked out",
            file_descriptor_in_use.clone(),
        );
        registry.register(
            "kura_file_descriptor_available",
            "File descriptor permits currently available",
            file_descriptor_available.clone(),
        );
        registry.register(
            "kura_file_descriptor_waiting",
            "Requests waiting on a file descriptor permit",
            file_descriptor_waiting.clone(),
        );
        registry.register(
            "kura_file_descriptor_capacity",
            "Configured file descriptor permit capacity",
            file_descriptor_capacity.clone(),
        );
        registry.register(
            "kura_segment_handles_cached",
            "Long-lived segment file handles cached for offset-based reads",
            segment_handles_cached.clone(),
        );
        registry.register(
            "kura_segment_handle_cache_capacity",
            "Configured maximum number of long-lived segment handles cached in memory",
            segment_handle_cache_capacity.clone(),
        );
        registry.register(
            "kura_segment_handle_cache_lookups_total",
            "Segment handle cache lookups by result",
            segment_handle_cache_lookups.clone(),
        );
        registry.register(
            "kura_segment_handle_evictions_total",
            "Segment handle cache evictions by reason",
            segment_handle_evictions.clone(),
        );
        registry.register(
            "kura_manifest_index_entries",
            "Warm in-memory manifest index entries currently loaded",
            manifest_index_entries.clone(),
        );
        registry.register(
            "kura_manifest_cache_bytes",
            "Approximate bytes retained by the in-memory manifest cache",
            manifest_cache_bytes.clone(),
        );
        registry.register(
            "kura_manifest_cache_capacity_bytes",
            "Configured byte budget for the in-memory manifest cache",
            manifest_cache_capacity_bytes.clone(),
        );
        registry.register(
            "kura_manifest_cache_lookups_total",
            "Manifest cache lookups by result",
            manifest_cache_lookups.clone(),
        );
        registry.register(
            "kura_manifest_cache_admissions_total",
            "Manifest cache admissions by result",
            manifest_cache_admissions.clone(),
        );
        registry.register(
            "kura_manifest_cache_evictions_total",
            "Manifest cache evictions by reason",
            manifest_cache_evictions.clone(),
        );
        registry.register(
            "kura_manifest_index_rebuilds_total",
            "Manifest index rebuild attempts by result",
            manifest_index_rebuilds.clone(),
        );
        registry.register(
            "kura_manifest_index_rebuild_duration_seconds",
            "Time spent rebuilding the warm in-memory manifest index from RocksDB",
            manifest_index_rebuild_duration.clone(),
        );
        registry.register(
            "kura_outbox_messages",
            "Replication outbox messages waiting to be processed",
            outbox_messages.clone(),
        );
        registry.register(
            "kura_multipart_uploads",
            "Multipart uploads currently tracked in RocksDB",
            multipart_uploads.clone(),
        );
        registry.register(
            "kura_discovered_peer_nodes",
            "Peer nodes currently discovered through health checks and DNS",
            discovered_peer_nodes.clone(),
        );
        registry.register(
            "kura_bootstrap_runs_total",
            "Bootstrap runs from newly discovered peers by result",
            bootstrap_runs.clone(),
        );
        registry.register(
            "kura_bootstrap_duration_seconds",
            "Time spent bootstrapping from newly discovered peers",
            bootstrap_duration.clone(),
        );
        registry.register(
            "kura_bootstrap_applied_items_total",
            "Tombstones and artifacts applied during bootstrap",
            bootstrap_applied_items.clone(),
        );
        registry.register(
            "kura_analytics_events_total",
            "Analytics events by pipeline and result",
            analytics_events.clone(),
        );
        registry.register(
            "kura_analytics_batches_total",
            "Analytics webhook batch sends by pipeline and result",
            analytics_batches.clone(),
        );
        registry.register(
            "kura_analytics_batch_duration_seconds",
            "Analytics webhook batch latency by pipeline",
            analytics_batch_duration.clone(),
        );
        registry.register(
            "kura_analytics_queue_depth",
            "Pending analytics events currently buffered in memory",
            analytics_queue_depth.clone(),
        );
        registry.register(
            "kura_analytics_queue_capacity",
            "Configured capacity of the in-memory analytics queue",
            analytics_queue_capacity.clone(),
        );
        registry.register(
            "kura_analytics_circuit_state",
            "Analytics circuit breaker state where 0=closed, 1=open, 2=half_open",
            analytics_circuit_state.clone(),
        );
        registry.register(
            "kura_analytics_circuit_transitions_total",
            "Analytics circuit breaker transitions by pipeline",
            analytics_circuit_transitions.clone(),
        );
        registry.register(
            "kura_segment_generation_count",
            "Segments currently tracked by generation and artifact kind",
            segment_generation_counts.clone(),
        );
        registry.register(
            "kura_extension_hooks_total",
            "Extension hook invocations by hook and result",
            extension_hooks.clone(),
        );
        registry.register(
            "kura_extension_hook_duration_seconds",
            "Extension hook execution latency by hook",
            extension_hook_duration.clone(),
        );
        registry.register(
            "kura_extension_cache_total",
            "Extension cache lookups by cache and result",
            extension_cache.clone(),
        );
        registry.register(
            "kura_process_resident_memory_bytes",
            "Process resident memory size in bytes",
            process_resident_memory_bytes.clone(),
        );
        registry.register(
            "kura_process_virtual_memory_bytes",
            "Process virtual memory size in bytes",
            process_virtual_memory_bytes.clone(),
        );
        registry.register(
            "kura_rocksdb_block_cache_usage_bytes",
            "RocksDB block cache usage in bytes",
            rocksdb_block_cache_usage_bytes.clone(),
        );
        registry.register(
            "kura_rocksdb_block_cache_pinned_usage_bytes",
            "Pinned RocksDB block cache usage in bytes",
            rocksdb_block_cache_pinned_usage_bytes.clone(),
        );
        registry.register(
            "kura_rocksdb_block_cache_capacity_bytes",
            "Configured RocksDB block cache capacity in bytes",
            rocksdb_block_cache_capacity_bytes.clone(),
        );
        registry.register(
            "kura_rocksdb_write_buffer_usage_bytes",
            "RocksDB write buffer manager usage in bytes",
            rocksdb_write_buffer_usage_bytes.clone(),
        );
        registry.register(
            "kura_rocksdb_write_buffer_capacity_bytes",
            "Configured RocksDB write buffer manager capacity in bytes",
            rocksdb_write_buffer_capacity_bytes.clone(),
        );
        registry.register(
            "kura_memory_pressure_state",
            "Current memory pressure state where 0=normal, 1=constrained, 2=critical",
            memory_pressure_state.clone(),
        );
        registry.register(
            "kura_memory_soft_limit_bytes",
            "Configured soft memory limit in bytes",
            memory_soft_limit_bytes.clone(),
        );
        registry.register(
            "kura_memory_hard_limit_bytes",
            "Configured hard memory limit in bytes",
            memory_hard_limit_bytes.clone(),
        );
        registry.register(
            "kura_memory_pressure_transitions_total",
            "Memory pressure state transitions",
            memory_pressure_transitions.clone(),
        );
        registry.register(
            "kura_background_work_paused",
            "Whether a background worker is currently paused due to memory pressure",
            background_work_paused.clone(),
        );
        registry.register(
            "kura_memory_actions_total",
            "Memory pressure actions taken by the node",
            memory_actions.clone(),
        );
        registry.register(
            "kura_process_start_time_seconds",
            "Unix timestamp when the current Kura process started",
            process_start_time_seconds.clone(),
        );

        let metrics = Self {
            registry: Arc::new(Mutex::new(registry)),
            http_requests,
            http_request_duration,
            http_exceptions,
            artifact_reads,
            artifact_writes,
            artifact_read_bytes,
            artifact_write_bytes,
            segment_refreshes,
            segment_refresh_bytes,
            segment_refresh_duration,
            segment_evicted_artifacts,
            replication_requests,
            replication_request_duration,
            replication_apply_results,
            multipart_parts,
            node_info,
            file_descriptor_wait,
            file_operations,
            file_operation_duration,
            file_operation_bytes,
            file_descriptor_in_use,
            file_descriptor_available,
            file_descriptor_waiting,
            file_descriptor_capacity,
            segment_handles_cached,
            segment_handle_cache_capacity,
            segment_handle_cache_lookups,
            segment_handle_evictions,
            manifest_index_entries,
            manifest_cache_bytes,
            manifest_cache_capacity_bytes,
            manifest_cache_lookups,
            manifest_cache_admissions,
            manifest_cache_evictions,
            manifest_index_rebuilds,
            manifest_index_rebuild_duration,
            outbox_messages,
            multipart_uploads,
            discovered_peer_nodes,
            bootstrap_runs,
            bootstrap_duration,
            bootstrap_applied_items,
            analytics_events,
            analytics_batches,
            analytics_batch_duration,
            analytics_queue_depth,
            analytics_queue_capacity,
            analytics_circuit_state,
            analytics_circuit_transitions,
            segment_generation_counts,
            extension_hooks,
            extension_hook_duration,
            extension_cache,
            process_resident_memory_bytes,
            process_virtual_memory_bytes,
            rocksdb_block_cache_usage_bytes,
            rocksdb_block_cache_pinned_usage_bytes,
            rocksdb_block_cache_capacity_bytes,
            rocksdb_write_buffer_usage_bytes,
            rocksdb_write_buffer_capacity_bytes,
            memory_pressure_state,
            memory_soft_limit_bytes,
            memory_hard_limit_bytes,
            memory_pressure_transitions,
            background_work_paused,
            memory_actions,
        };

        metrics
            .node_info
            .get_or_create(&NodeInfoLabels { region, tenant_id })
            .set(1);

        metrics
    }

    pub fn record_http(
        &self,
        route: String,
        method: String,
        status: StatusCode,
        duration: Duration,
    ) {
        self.http_requests
            .get_or_create(&HttpRequestLabels {
                route: route.clone(),
                method,
                status: status.as_u16(),
            })
            .inc();
        self.http_request_duration
            .get_or_create(&HttpRouteLabels {
                route: route.clone(),
            })
            .observe(duration.as_secs_f64());

        if status.is_server_error() {
            self.http_exceptions
                .get_or_create(&HttpExceptionLabels {
                    route,
                    kind: "server_error".into(),
                })
                .inc();
        }
    }

    pub fn record_artifact_read(&self, kind: ArtifactKind, result: &str, bytes: u64) {
        let labels = ArtifactOpLabels {
            kind: kind.as_str().to_owned(),
            client: kind.client().as_str().to_owned(),
            artifact_class: kind.artifact_class().as_str().to_owned(),
            result: result.to_owned(),
        };
        self.artifact_reads.get_or_create(&labels).inc();
        if bytes > 0 {
            self.artifact_read_bytes
                .get_or_create(&labels)
                .inc_by(bytes);
        }
    }

    pub fn record_artifact_write(&self, kind: ArtifactKind, result: &str, bytes: u64) {
        let labels = ArtifactOpLabels {
            kind: kind.as_str().to_owned(),
            client: kind.client().as_str().to_owned(),
            artifact_class: kind.artifact_class().as_str().to_owned(),
            result: result.to_owned(),
        };
        self.artifact_writes.get_or_create(&labels).inc();
        if bytes > 0 {
            self.artifact_write_bytes
                .get_or_create(&labels)
                .inc_by(bytes);
        }
    }

    pub fn record_segment_refresh(
        &self,
        kind: ArtifactKind,
        result: &str,
        bytes: u64,
        duration: Duration,
    ) {
        let labels = ArtifactOpLabels {
            kind: kind.as_str().to_owned(),
            client: kind.client().as_str().to_owned(),
            artifact_class: kind.artifact_class().as_str().to_owned(),
            result: result.to_owned(),
        };
        self.segment_refreshes.get_or_create(&labels).inc();
        if bytes > 0 {
            self.segment_refresh_bytes
                .get_or_create(&labels)
                .inc_by(bytes);
        }
        self.segment_refresh_duration
            .get_or_create(&ArtifactRouteLabels {
                kind: kind.as_str().to_owned(),
                client: kind.client().as_str().to_owned(),
                artifact_class: kind.artifact_class().as_str().to_owned(),
            })
            .observe(duration.as_secs_f64());
    }

    pub fn record_segment_eviction(&self, kind: ArtifactKind, result: &str, artifacts: u64) {
        if artifacts == 0 {
            return;
        }
        self.segment_evicted_artifacts
            .get_or_create(&ArtifactOpLabels {
                kind: kind.as_str().to_owned(),
                client: kind.client().as_str().to_owned(),
                artifact_class: kind.artifact_class().as_str().to_owned(),
                result: result.to_owned(),
            })
            .inc_by(artifacts);
    }

    pub fn record_replication(
        &self,
        target: &str,
        operation: &str,
        result: &str,
        duration: Duration,
    ) {
        self.replication_requests
            .get_or_create(&ReplicationLabels {
                target: replication_target_label(target),
                operation: operation.to_owned(),
                result: result.to_owned(),
            })
            .inc();
        self.replication_request_duration
            .get_or_create(&ReplicationRouteLabels {
                target: replication_target_label(target),
                operation: operation.to_owned(),
            })
            .observe(duration.as_secs_f64());
    }

    pub fn record_replication_apply(&self, source: &str, item_type: &str, outcome: &str) {
        self.replication_apply_results
            .get_or_create(&ReplicationApplyLabels {
                source: source.to_owned(),
                item_type: item_type.to_owned(),
                outcome: outcome.to_owned(),
            })
            .inc();
    }

    pub fn record_multipart_part(&self, result: &str) {
        self.multipart_parts
            .get_or_create(&MultipartLabels {
                result: result.to_owned(),
            })
            .inc();
    }

    pub fn record_file_descriptor_wait(&self, result: &str, duration: Duration) {
        self.file_descriptor_wait
            .get_or_create(&FileDescriptorWaitLabels {
                result: result.to_owned(),
            })
            .observe(duration.as_secs_f64());
    }

    pub fn record_file_operation(
        &self,
        operation: &str,
        result: &str,
        duration: Duration,
        bytes: u64,
    ) {
        let labels = FileOperationLabels {
            operation: operation.to_owned(),
            result: result.to_owned(),
        };
        self.file_operations.get_or_create(&labels).inc();
        self.file_operation_duration
            .get_or_create(&FileOperationRouteLabels {
                operation: operation.to_owned(),
            })
            .observe(duration.as_secs_f64());
        if bytes > 0 {
            self.file_operation_bytes
                .get_or_create(&labels)
                .inc_by(bytes);
        }
    }

    pub fn update_file_descriptor_pool(
        &self,
        capacity: usize,
        in_use: usize,
        available: usize,
        waiting: usize,
    ) {
        self.file_descriptor_capacity.set(capacity as i64);
        self.file_descriptor_in_use.set(in_use as i64);
        self.file_descriptor_available.set(available as i64);
        self.file_descriptor_waiting.set(waiting as i64);
    }

    pub fn update_segment_handles_cached(&self, cached: usize) {
        self.segment_handles_cached.set(cached as i64);
    }

    pub fn update_segment_handle_cache_capacity(&self, capacity: usize) {
        self.segment_handle_cache_capacity.set(capacity as i64);
    }

    pub fn record_segment_handle_cache_lookup(&self, result: &str) {
        self.segment_handle_cache_lookups
            .get_or_create(&SegmentHandleCacheLookupLabels {
                result: result.to_owned(),
            })
            .inc();
    }

    pub fn record_segment_handle_evictions(&self, reason: &str, count: u64) {
        if count == 0 {
            return;
        }
        self.segment_handle_evictions
            .get_or_create(&SegmentHandleEvictionLabels {
                reason: reason.to_owned(),
            })
            .inc_by(count);
    }

    pub fn update_manifest_index_entries(&self, entries: usize) {
        self.manifest_index_entries.set(entries as i64);
    }

    pub fn update_manifest_cache_bytes(&self, bytes: usize) {
        self.manifest_cache_bytes.set(bytes as i64);
    }

    pub fn update_manifest_cache_capacity_bytes(&self, bytes: usize) {
        self.manifest_cache_capacity_bytes.set(bytes as i64);
    }

    pub fn record_manifest_cache_lookup(&self, result: &str) {
        self.manifest_cache_lookups
            .get_or_create(&ManifestCacheLookupLabels {
                result: result.to_owned(),
            })
            .inc();
    }

    pub fn record_manifest_cache_admission(&self, result: &str) {
        self.manifest_cache_admissions
            .get_or_create(&ManifestCacheAdmissionLabels {
                result: result.to_owned(),
            })
            .inc();
    }

    pub fn record_manifest_cache_evictions(&self, reason: &str, count: u64) {
        if count == 0 {
            return;
        }
        self.manifest_cache_evictions
            .get_or_create(&ManifestCacheEvictionLabels {
                reason: reason.to_owned(),
            })
            .inc_by(count);
    }

    pub fn record_manifest_index_rebuild(&self, result: &str, duration: Duration) {
        self.manifest_index_rebuilds
            .get_or_create(&ManifestIndexResultLabels {
                result: result.to_owned(),
            })
            .inc();
        self.manifest_index_rebuild_duration
            .observe(duration.as_secs_f64());
    }

    pub fn update_outbox_messages(&self, count: usize) {
        self.outbox_messages.set(count as i64);
    }

    pub fn update_multipart_uploads(&self, count: usize) {
        self.multipart_uploads.set(count as i64);
    }

    pub fn update_discovered_peer_nodes(&self, count: usize) {
        self.discovered_peer_nodes.set(count as i64);
    }

    pub fn record_bootstrap_run(
        &self,
        result: &str,
        duration: Duration,
        tombstones_applied: u64,
        artifacts_applied: u64,
    ) {
        self.bootstrap_runs
            .get_or_create(&BootstrapResultLabels {
                result: result.to_owned(),
            })
            .inc();
        self.bootstrap_duration.observe(duration.as_secs_f64());
        if tombstones_applied > 0 {
            self.bootstrap_applied_items
                .get_or_create(&BootstrapItemLabels {
                    item_type: "namespace_tombstone".to_owned(),
                })
                .inc_by(tombstones_applied);
        }
        if artifacts_applied > 0 {
            self.bootstrap_applied_items
                .get_or_create(&BootstrapItemLabels {
                    item_type: "artifact".to_owned(),
                })
                .inc_by(artifacts_applied);
        }
    }

    pub fn record_analytics_event(&self, pipeline: &str, result: &str, count: u64) {
        if count == 0 {
            return;
        }
        self.analytics_events
            .get_or_create(&AnalyticsLabels {
                pipeline: pipeline.to_owned(),
                result: result.to_owned(),
            })
            .inc_by(count);
    }

    pub fn record_analytics_batch(&self, pipeline: &str, result: &str, duration: Duration) {
        self.analytics_batches
            .get_or_create(&AnalyticsLabels {
                pipeline: pipeline.to_owned(),
                result: result.to_owned(),
            })
            .inc();
        self.analytics_batch_duration
            .get_or_create(&AnalyticsRouteLabels {
                pipeline: pipeline.to_owned(),
            })
            .observe(duration.as_secs_f64());
    }

    pub fn update_analytics_queue(&self, capacity: usize, depth: usize) {
        self.analytics_queue_capacity.set(capacity as i64);
        self.analytics_queue_depth.set(depth as i64);
    }

    pub fn update_analytics_circuit_state(&self, pipeline: &str, state: i64) {
        self.analytics_circuit_state
            .get_or_create(&AnalyticsRouteLabels {
                pipeline: pipeline.to_owned(),
            })
            .set(state);
    }

    pub fn record_analytics_circuit_transition(&self, pipeline: &str, from: &str, to: &str) {
        self.analytics_circuit_transitions
            .get_or_create(&AnalyticsCircuitTransitionLabels {
                pipeline: pipeline.to_owned(),
                from: from.to_owned(),
                to: to.to_owned(),
            })
            .inc();
    }

    pub fn update_segment_generation_count(
        &self,
        kind: ArtifactKind,
        generation: &str,
        count: usize,
    ) {
        self.segment_generation_counts
            .get_or_create(&SegmentGenerationLabels {
                kind: kind.as_str().to_owned(),
                generation: generation.to_owned(),
            })
            .set(count as i64);
    }

    pub fn record_extension_hook(&self, hook: &str, result: &str, duration: Duration) {
        self.extension_hooks
            .get_or_create(&ExtensionHookLabels {
                hook: hook.to_owned(),
                result: result.to_owned(),
            })
            .inc();
        self.extension_hook_duration
            .get_or_create(&ExtensionHookRouteLabels {
                hook: hook.to_owned(),
            })
            .observe(duration.as_secs_f64());
    }

    pub fn record_extension_cache(&self, cache: &str, result: &str) {
        self.extension_cache
            .get_or_create(&ExtensionCacheLabels {
                cache: cache.to_owned(),
                result: result.to_owned(),
            })
            .inc();
    }

    pub fn update_process_memory(&self, resident_bytes: u64, virtual_bytes: u64) {
        self.process_resident_memory_bytes
            .set(resident_bytes as i64);
        self.process_virtual_memory_bytes.set(virtual_bytes as i64);
    }

    pub fn update_rocksdb_memory(
        &self,
        block_cache_usage_bytes: u64,
        block_cache_pinned_usage_bytes: u64,
        block_cache_capacity_bytes: u64,
        write_buffer_usage_bytes: u64,
        write_buffer_capacity_bytes: u64,
    ) {
        self.rocksdb_block_cache_usage_bytes
            .set(block_cache_usage_bytes as i64);
        self.rocksdb_block_cache_pinned_usage_bytes
            .set(block_cache_pinned_usage_bytes as i64);
        self.rocksdb_block_cache_capacity_bytes
            .set(block_cache_capacity_bytes as i64);
        self.rocksdb_write_buffer_usage_bytes
            .set(write_buffer_usage_bytes as i64);
        self.rocksdb_write_buffer_capacity_bytes
            .set(write_buffer_capacity_bytes as i64);
    }

    pub fn update_memory_pressure_state(&self, state: i64) {
        self.memory_pressure_state.set(state);
    }

    pub fn update_memory_limits(&self, soft_limit_bytes: u64, hard_limit_bytes: u64) {
        self.memory_soft_limit_bytes.set(soft_limit_bytes as i64);
        self.memory_hard_limit_bytes.set(hard_limit_bytes as i64);
    }

    pub fn record_memory_pressure_transition(&self, from: &str, to: &str) {
        self.memory_pressure_transitions
            .get_or_create(&MemoryPressureTransitionLabels {
                from: from.to_owned(),
                to: to.to_owned(),
            })
            .inc();
    }

    pub fn update_background_work_paused(&self, worker: &str, paused: bool) {
        self.background_work_paused
            .get_or_create(&BackgroundWorkerLabels {
                worker: worker.to_owned(),
            })
            .set(if paused { 1 } else { 0 });
    }

    pub fn record_memory_action(&self, action: &str) {
        self.memory_actions
            .get_or_create(&MemoryActionLabels {
                action: action.to_owned(),
            })
            .inc();
    }

    pub fn render(&self) -> String {
        let mut encoded = String::new();
        let registry = self.registry.lock().expect("metrics registry poisoned");
        encode(&mut encoded, &registry).expect("failed to encode metrics");
        encoded
    }
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct HttpRequestLabels {
    route: String,
    method: String,
    status: u16,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct HttpRouteLabels {
    route: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct HttpExceptionLabels {
    route: String,
    kind: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ArtifactOpLabels {
    kind: String,
    client: String,
    artifact_class: String,
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ArtifactRouteLabels {
    kind: String,
    client: String,
    artifact_class: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ReplicationLabels {
    target: String,
    operation: String,
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ReplicationRouteLabels {
    target: String,
    operation: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ReplicationApplyLabels {
    source: String,
    item_type: String,
    outcome: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct MultipartLabels {
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct FileDescriptorWaitLabels {
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct FileOperationLabels {
    operation: String,
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct FileOperationRouteLabels {
    operation: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct NodeInfoLabels {
    region: String,
    tenant_id: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ManifestIndexResultLabels {
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ManifestCacheLookupLabels {
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ManifestCacheAdmissionLabels {
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ManifestCacheEvictionLabels {
    reason: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct SegmentHandleCacheLookupLabels {
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct SegmentHandleEvictionLabels {
    reason: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct SegmentGenerationLabels {
    kind: String,
    generation: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ExtensionHookLabels {
    hook: String,
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ExtensionHookRouteLabels {
    hook: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct ExtensionCacheLabels {
    cache: String,
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct BootstrapResultLabels {
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct BootstrapItemLabels {
    item_type: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct AnalyticsLabels {
    pipeline: String,
    result: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct AnalyticsRouteLabels {
    pipeline: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct AnalyticsCircuitTransitionLabels {
    pipeline: String,
    from: String,
    to: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct MemoryPressureTransitionLabels {
    from: String,
    to: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct BackgroundWorkerLabels {
    worker: String,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq, EncodeLabelSet)]
struct MemoryActionLabels {
    action: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn render_includes_recorded_metrics() {
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        metrics.record_http(
            "/up".into(),
            "GET".into(),
            StatusCode::OK,
            Duration::from_millis(10),
        );
        metrics.record_http(
            "/api/cache/keyvalue".into(),
            "PUT".into(),
            StatusCode::INTERNAL_SERVER_ERROR,
            Duration::from_millis(20),
        );
        metrics.record_artifact_read(ArtifactKind::Xcode, "ok", 5);
        metrics.record_artifact_write(ArtifactKind::Module, "ok", 10);
        metrics.record_segment_refresh(ArtifactKind::Xcode, "ok", 5, Duration::from_millis(4));
        metrics.record_segment_eviction(ArtifactKind::Xcode, "ok", 2);
        metrics.record_replication(
            "https://kura.example.com/internal",
            "upsert_artifact",
            "ok",
            Duration::from_millis(5),
        );
        metrics.record_replication_apply("replication", "artifact", "applied");
        metrics.record_replication_apply("bootstrap", "namespace_delete", "ignored_older");
        metrics.record_multipart_part("ok");
        metrics.record_file_descriptor_wait("ok", Duration::from_millis(1));
        metrics.record_file_operation("open_read", "ok", Duration::from_millis(2), 42);
        metrics.update_file_descriptor_pool(64, 3, 61, 1);
        metrics.update_segment_handles_cached(2);
        metrics.update_segment_handle_cache_capacity(8);
        metrics.record_segment_handle_cache_lookup("hit");
        metrics.record_segment_handle_cache_lookup("miss");
        metrics.record_segment_handle_evictions("capacity", 1);
        metrics.update_manifest_index_entries(7);
        metrics.update_manifest_cache_bytes(1024);
        metrics.update_manifest_cache_capacity_bytes(2048);
        metrics.record_manifest_cache_lookup("hit");
        metrics.record_manifest_cache_admission("admitted");
        metrics.record_manifest_cache_evictions("capacity", 1);
        metrics.record_manifest_index_rebuild("ok", Duration::from_millis(3));
        metrics.update_outbox_messages(4);
        metrics.update_multipart_uploads(2);
        metrics.update_discovered_peer_nodes(3);
        metrics.record_bootstrap_run("ok", Duration::from_millis(6), 2, 5);
        metrics.update_analytics_queue(1000, 2);
        metrics.record_analytics_event("xcode", "sent", 2);
        metrics.record_analytics_batch("xcode", "ok", Duration::from_millis(7));
        metrics.update_analytics_circuit_state("xcode", 1);
        metrics.record_analytics_circuit_transition("xcode", "closed", "open");
        metrics.update_segment_generation_count(ArtifactKind::Xcode, "old", 1);
        metrics.update_process_memory(1024, 2048);
        metrics.update_rocksdb_memory(256, 64, 4096, 512, 2048);
        metrics.update_memory_limits(4_096, 8_192);
        metrics.update_memory_pressure_state(1);
        metrics.record_memory_pressure_transition("normal", "constrained");
        metrics.update_background_work_paused("outbox", true);
        metrics.record_memory_action("manifest_cache_trim");

        let rendered = metrics.render();

        assert!(rendered.contains("kura_http_requests_total"));
        assert!(rendered.contains("kura_http_exceptions_total"));
        assert!(rendered.contains("kura_artifact_reads_total"));
        assert!(rendered.contains("kura_artifact_write_bytes_total"));
        assert!(rendered.contains("kura_segment_refreshes_total"));
        assert!(rendered.contains("kura_segment_evicted_artifacts_total"));
        assert!(rendered.contains("kura_replication_requests_total"));
        assert!(rendered.contains("kura_replication_apply_results_total"));
        assert!(rendered.contains("source=\"replication\""));
        assert!(rendered.contains("source=\"bootstrap\""));
        assert!(rendered.contains("item_type=\"artifact\""));
        assert!(rendered.contains("item_type=\"namespace_delete\""));
        assert!(rendered.contains("outcome=\"applied\""));
        assert!(rendered.contains("outcome=\"ignored_older\""));
        assert!(rendered.contains("kura_multipart_parts_total"));
        assert!(rendered.contains("kura_node_info"));
        assert!(rendered.contains("kura_file_descriptor_wait_seconds"));
        assert!(rendered.contains("kura_file_operations_total"));
        assert!(rendered.contains("kura_file_descriptor_in_use"));
        assert!(rendered.contains("kura_segment_handles_cached"));
        assert!(rendered.contains("kura_segment_handle_cache_capacity"));
        assert!(rendered.contains("kura_segment_handle_cache_lookups_total"));
        assert!(rendered.contains("kura_segment_handle_evictions_total"));
        assert!(rendered.contains("kura_manifest_index_entries"));
        assert!(rendered.contains("kura_manifest_cache_bytes"));
        assert!(rendered.contains("kura_manifest_cache_capacity_bytes"));
        assert!(rendered.contains("kura_manifest_cache_lookups_total"));
        assert!(rendered.contains("kura_manifest_cache_admissions_total"));
        assert!(rendered.contains("kura_manifest_cache_evictions_total"));
        assert!(rendered.contains("kura_manifest_index_rebuilds_total"));
        assert!(rendered.contains("kura_outbox_messages"));
        assert!(rendered.contains("kura_multipart_uploads"));
        assert!(rendered.contains("kura_discovered_peer_nodes"));
        assert!(rendered.contains("kura_bootstrap_runs_total"));
        assert!(rendered.contains("kura_bootstrap_duration_seconds"));
        assert!(rendered.contains("kura_bootstrap_applied_items_total"));
        assert!(rendered.contains("kura_analytics_events_total"));
        assert!(rendered.contains("kura_analytics_batches_total"));
        assert!(rendered.contains("kura_analytics_batch_duration_seconds"));
        assert!(rendered.contains("kura_analytics_queue_depth"));
        assert!(rendered.contains("kura_analytics_queue_capacity"));
        assert!(rendered.contains("kura_analytics_circuit_state"));
        assert!(rendered.contains("kura_analytics_circuit_transitions_total"));
        assert!(rendered.contains("kura_segment_generation_count"));
        assert!(rendered.contains("kura_process_resident_memory_bytes"));
        assert!(rendered.contains("kura_rocksdb_block_cache_usage_bytes"));
        assert!(rendered.contains("kura_rocksdb_block_cache_pinned_usage_bytes"));
        assert!(rendered.contains("kura_rocksdb_block_cache_capacity_bytes"));
        assert!(rendered.contains("kura_rocksdb_write_buffer_usage_bytes"));
        assert!(rendered.contains("kura_rocksdb_write_buffer_capacity_bytes"));
        assert!(rendered.contains("kura_memory_pressure_state"));
        assert!(rendered.contains("kura_memory_pressure_transitions_total"));
        assert!(rendered.contains("kura_background_work_paused"));
        assert!(rendered.contains("kura_memory_actions_total"));
        assert!(rendered.contains("kura_process_start_time_seconds"));
        assert!(rendered.contains("region=\"eu-west\""));
        assert!(rendered.contains("tenant_id=\"acme\""));
    }
}
