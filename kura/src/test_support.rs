use std::{sync::Arc, time::Duration};

use axum::response::Response;
use http_body_util::BodyExt;
use reqwest::Client;
use tempfile::TempDir;
use tokio::sync::{Notify, Semaphore};
use tokio::time::Instant;

use crate::{
    analytics::Analytics,
    bandwidth::BandwidthLimiter,
    config::Config,
    extension::SharedExtension,
    io::IoController,
    memory::MemoryController,
    metrics::Metrics,
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
    test_context_with_extension(override_config, None).await
}

pub(crate) async fn test_context_with_extension<F>(
    override_config: F,
    extension: Option<SharedExtension>,
) -> TestContext
where
    F: FnOnce(&mut Config),
{
    let temp_dir = tempfile::tempdir().expect("failed to create temp dir");
    let mut config = Config {
        port: 0,
        grpc_port: 0,
        internal_port: 7443,
        tenant_id: "test-tenant".into(),
        region: "local".into(),
        tmp_dir: temp_dir.path().join("tmp"),
        data_dir: temp_dir.path().join("data"),
        node_url: "http://127.0.0.1:7443".into(),
        peers: vec!["http://127.0.0.1:7443".into()],
        discovery_dns_name: None,
        peer_tls: None,
        grpc_tls: None,
        public_tls: None,
        https_port: 0,
        accelerated_file_serving: None,
        file_descriptor_pool_size: 32,
        file_descriptor_acquire_timeout_ms: 5_000,
        drain_completion_timeout_ms: 240_000,
        segment_handle_cache_size: 8,
        memory_soft_limit_bytes: 128 * 1024 * 1024,
        memory_hard_limit_bytes: 256 * 1024 * 1024,
        manifest_cache_max_bytes: 8 * 1024 * 1024,
        max_keyvalue_bytes: 512 * 1024,
        rocksdb_max_open_files: 256,
        rocksdb_max_background_jobs: 2,
        rocksdb_block_cache_bytes: 32 * 1024 * 1024,
        rocksdb_write_buffer_manager_bytes: 32 * 1024 * 1024,
        rocksdb_write_buffer_size_bytes: 8 * 1024 * 1024,
        rocksdb_max_write_buffer_number: 4,
        outbox_max_depth: 100_000,
        replication_bandwidth_limit_bytes_per_second: 0,
        replication_public_latency_target_ms: 100,
        multipart_upload_ttl_ms: 24 * 60 * 60 * 1000,
        multipart_janitor_interval_ms: 10 * 60 * 1000,
        bootstrap_timeout_ms: 30 * 60 * 1000,
        bootstrap_max_concurrent_peers: 8,
        analytics: None,
        usage: None,
        otlp_traces_endpoint: Some("http://127.0.0.1:4318/v1/traces".into()),
        otel_service_name: "kura-test".into(),
        otel_deployment_environment: "test".into(),
        sentry_dsn: None,
        geoip_refresh_interval_secs: 0,
        node_country_override: None,
        node_subdivision_override: None,
    };
    override_config(&mut config);
    config
        .ensure_directories()
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
    let memory = MemoryController::new(
        metrics.clone(),
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let data_dir_lock =
        DataDirLock::acquire(&config.data_dir).expect("failed to acquire test writer lock");
    let store =
        Store::open(&config, io.clone(), memory.clone()).expect("failed to open test store");
    let analytics =
        Analytics::from_config(config.analytics.as_ref(), &config.node_url, metrics.clone())
            .expect("failed to build test analytics");
    let usage = Usage::from_config(config.usage.as_ref(), &config.node_url, metrics.clone())
        .expect("failed to build test usage");
    let client = Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .expect("failed to build test client");
    let runtime = RuntimeState::new();
    let replication_bandwidth_limiter = BandwidthLimiter::new(
        config.replication_bandwidth_limit_bytes_per_second,
        config.replication_public_latency_target_ms,
        runtime.clone(),
    )
    .map(Arc::new);
    let bootstrap_semaphore = Arc::new(Semaphore::new(config.bootstrap_max_concurrent_peers));
    let state = Arc::new(AppState {
        config,
        _data_dir_lock: data_dir_lock,
        store,
        io,
        memory,
        metrics,
        runtime,
        extension,
        analytics,
        usage,
        geoip: None,
        client,
        replication_bandwidth_limiter,
        notify: Notify::new(),
        readiness: tokio::sync::Mutex::new(ReadinessState::new(Instant::now())),
        bootstrap_semaphore,
    });
    state.sync_runtime_metrics().await;

    TestContext {
        _temp_dir: temp_dir,
        state,
    }
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
