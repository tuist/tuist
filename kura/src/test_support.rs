use std::{sync::Arc, time::Duration};

use axum::response::Response;
use http_body_util::BodyExt;
use reqwest::Client;
use tempfile::TempDir;
use tokio::sync::Notify;
use tokio::time::Instant;

use crate::{
    analytics::Analytics,
    auth::SharedAuth,
    bandwidth::BandwidthLimiter,
    config::{AcceleratedFileServingConfig, AcceleratedFileServingMode, Config},
    io::IoController,
    memory::MemoryController,
    metrics::Metrics,
    peer_tls::PeerClientFactory,
    runtime::{DataDirLock, RuntimeState},
    state::{AppState, ReadinessState},
    store::Store,
    usage::Usage,
};

pub(crate) struct TestContext {
    pub _temp_dir: TempDir,
    pub state: Arc<AppState>,
}

pub(crate) async fn test_context<F>(override_config: F) -> TestContext
where
    F: FnOnce(&mut Config),
{
    test_context_with_auth(override_config, None).await
}

pub(crate) async fn test_context_with_auth<F>(
    override_config: F,
    auth: Option<SharedAuth>,
) -> TestContext
where
    F: FnOnce(&mut Config),
{
    let temp_dir = tempfile::tempdir().expect("failed to create temp dir");
    let mut config = Config {
        port: 0,
        internal_port: 7443,
        tenant_id: "test-tenant".into(),
        region: "local".into(),
        tmp_dir: temp_dir.path().join("tmp"),
        data_dir: temp_dir.path().join("data"),
        tmp_dir_max_bytes: 8 * 1024 * 1024 * 1024,
        cas_capacity_bytes: None,
        node_url: "http://127.0.0.1:7443".into(),
        peer_gateway_url: None,
        peers: vec!["http://127.0.0.1:7443".into()],
        discovery_dns_name: None,
        global_discovery_dns_name: None,
        peer_tls: None,
        public_tls: None,
        https_port: 0,
        accelerated_file_serving: AcceleratedFileServingConfig {
            enabled: true,
            mode: AcceleratedFileServingMode::Splice,
            max_concurrent: 32,
            chunk_bytes: 1024 * 1024,
        },
        action_cache_eviction_cascade_enabled: true,
        file_descriptor_pool_size: 32,
        file_descriptor_acquire_timeout_ms: 5_000,
        drain_completion_timeout_ms: 240_000,
        segment_handle_cache_size: 8,
        memory_limit_bytes: 512 * 1024 * 1024,
        memory_soft_limit_bytes: 128 * 1024 * 1024,
        memory_hard_limit_bytes: 256 * 1024 * 1024,
        memory_floor_bytes: None,
        anon_cache_fit: None,
        snapshot_cache_max_bytes: 32 * 1024 * 1024,
        manifest_cache_max_bytes: 8 * 1024 * 1024,
        max_keyvalue_bytes: 512 * 1024,
        rocksdb_max_open_files: 256,
        rocksdb_max_background_jobs: 2,
        rocksdb_block_cache_bytes: 32 * 1024 * 1024,
        rocksdb_write_buffer_manager_bytes: 32 * 1024 * 1024,
        rocksdb_write_buffer_size_bytes: 8 * 1024 * 1024,
        rocksdb_max_write_buffer_number: 4,
        outbox_max_depth: 100_000,
        outbox_max_inflight: 8,
        replication_bandwidth_limit_bytes_per_second: 0,
        replication_public_latency_target_ms: 100,
        replication_upload_stall_ms: crate::constants::DEFAULT_REPLICATION_UPLOAD_STALL_MS,
        multipart_upload_ttl_ms: 24 * 60 * 60 * 1000,
        multipart_janitor_interval_ms: 10 * 60 * 1000,
        multipart_max_active_uploads: 128,
        multipart_max_stored_bytes: 8 * 1024 * 1024 * 1024,
        backfill_margin_percent: 40,
        backfill_ready_ring_percent: crate::constants::default_backfill_ready_ring_percent(40),
        backfill_batch_bytes: crate::constants::DEFAULT_BACKFILL_BATCH_BYTES,
        analytics: None,
        usage: None,
        otlp_traces_endpoint: Some("http://127.0.0.1:4318/v1/traces".into()),
        otel_service_name: "kura-test".into(),
        otel_deployment_environment: "test".into(),
        sentry_dsn: None,
        node_country_override: None,
        node_subdivision_override: None,
    };
    override_config(&mut config);
    config
        .ensure_data_dir_for_lock()
        .await
        .expect("failed to create test data directory");

    let data_dir_lock =
        DataDirLock::acquire(&config.data_dir).expect("failed to acquire test writer lock");
    config
        .ensure_directories(&data_dir_lock)
        .await
        .expect("failed to create test directories");

    let metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
    let io = IoController::new(
        metrics.clone(),
        config.file_descriptor_pool_size,
        Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
        vec![config.tmp_dir.clone(), config.data_dir.clone()],
    )
    .expect("failed to create test io controller");
    let memory = MemoryController::with_runtime_limit(
        metrics.clone(),
        config.memory_limit_bytes,
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let snapshot_cache = Arc::new(crate::reapi::SnapshotCache::new(
        config.snapshot_cache_max_bytes,
    ));
    let store =
        Store::open(&config, io.clone(), memory.clone()).expect("failed to open test store");
    let tmp_staging_budget = store.tmp_staging_budget();
    let analytics =
        Analytics::from_config(config.analytics.as_ref(), &config.node_url, metrics.clone())
            .expect("failed to build test analytics");
    let usage = Usage::from_config(config.usage.as_ref(), &config.node_url, metrics.clone())
        .expect("failed to build test usage");
    let peer_client_factory = PeerClientFactory::plain();
    let client = Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .expect("failed to build test client");
    // Production builds this without any total timeout — the stall watchdog is
    // the deadline there. Tests keep the same 5s cap as `client` so a test
    // driving the upload path against a server that never answers fails at 5s
    // instead of hanging for the whole watchdog window.
    let upload_client = Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .expect("failed to build test upload client");
    let runtime = RuntimeState::new();
    let replication_bandwidth_limiter = BandwidthLimiter::new(
        config.replication_bandwidth_limit_bytes_per_second,
        config.replication_public_latency_target_ms,
        runtime.clone(),
    )
    .map(Arc::new);
    let peer_staging_budget = crate::utils::TmpBudget::new(
        config
            .tmp_dir_max_bytes
            .min(memory.peer_staging_budget_bytes()),
    );
    let state = Arc::new(AppState {
        config,
        _data_dir_lock: data_dir_lock,
        store: Arc::new(store),
        io,
        memory,
        snapshot_cache,
        metrics,
        runtime,
        auth,
        analytics,
        usage,
        client: arc_swap::ArcSwap::from_pointee(client),
        upload_client: arc_swap::ArcSwap::from_pointee(upload_client),
        peer_client_factory,
        internal_tls: None,
        dynamic_peers: arc_swap::ArcSwap::from_pointee(Vec::new()),
        replication_bandwidth_limiter,
        notify: Notify::new(),
        readiness: tokio::sync::Mutex::new(ReadinessState::new(Instant::now())),
        tmp_staging_budget,
        peer_staging_budget,
        replication_backoff: tokio::sync::Mutex::new(std::collections::HashMap::new()),
        backfill_bodies_peer_slots: Arc::new(crate::state::BackfillBodiesPeerSlots::default()),
        backfill: crate::backfill::lifecycle::BackfillLifecycle::new(),
    });
    state.sync_runtime_metrics().await;

    TestContext {
        _temp_dir: temp_dir,
        state,
    }
}

/// Drives the backfill lifecycle through one settled membership view with no
/// peers — the state a node with nothing to catch up from reaches on its first
/// membership tick, and what readiness gates on. Production reaches it from
/// the membership loop; tests that assert readiness without exercising a peer
/// pass need it explicitly.
pub(crate) fn settle_empty_backfill_cycle(state: &Arc<AppState>) {
    state.backfill.test_evaluate(
        &crate::backfill::lifecycle::MembershipTick {
            discovered: &[],
            lost: &[],
            view_settled: true,
            control_plane_peers: &[],
            admission: true,
        },
        Instant::now(),
    );
}

pub(crate) async fn response_text(response: Response) -> String {
    let bytes = response
        .into_body()
        .collect()
        .await
        .expect("failed to collect response body")
        .to_bytes();
    String::from_utf8(bytes.to_vec()).expect("response body should be utf-8")
}
