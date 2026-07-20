
use super::*;
use std::collections::BTreeMap;
use tempfile::tempdir;

const TEST_HOST_RESOURCES: HostResources = HostResources {
    file_descriptor_limit: 4096,
    memory_limit_bytes: 1024 * 1024 * 1024,
    cpu_count: 6,
};

fn base_values() -> BTreeMap<String, String> {
    [
        (KURA_PORT, "4500"),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_owned(), value.to_owned()))
    .collect()
}

fn config_from(values: &[(&str, &str)]) -> Result<Config, String> {
    let mut merged = base_values();
    for (key, value) in values.iter() {
        merged.insert((*key).to_owned(), (*value).to_owned());
    }
    Config::from_lookup_with_resources(|key| merged.get(key).cloned(), TEST_HOST_RESOURCES)
}

#[test]
fn from_lookup_reports_all_missing_variables() {
    let error = Config::from_lookup_with_resources(|_| None, TEST_HOST_RESOURCES)
        .expect_err("expected missing config to fail");

    assert!(error.contains(KURA_PORT));
    assert!(error.contains(KURA_INTERNAL_PORT));
    assert!(error.contains(KURA_TENANT_ID));
    assert!(error.contains(KURA_REGION));
    assert!(error.contains(KURA_TMP_DIR));
    assert!(error.contains(KURA_DATA_DIR));
    assert!(error.contains(KURA_NODE_URL));
    // KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT is now optional —
    // unset disables tracing rather than failing config validation.
    assert!(error.contains(KURA_OTEL_SERVICE_NAME));
    assert!(error.contains(KURA_OTEL_DEPLOYMENT_ENVIRONMENT));
}

#[test]
fn from_lookup_derives_resource_defaults_for_optional_tuning() {
    let config = config_from(&[]).expect("expected config defaults to derive from host resources");

    assert_eq!(config.internal_port, 7443);
    assert!(config.peers.is_empty());
    assert_eq!(config.file_descriptor_pool_size, 1792);
    assert_eq!(config.file_descriptor_acquire_timeout_ms, 5_000);
    assert_eq!(config.drain_completion_timeout_ms, 240_000);
    assert_eq!(config.segment_handle_cache_size, 224);
    assert_eq!(config.memory_soft_limit_bytes, 716 * BYTES_PER_MIB);
    assert_eq!(config.memory_hard_limit_bytes, 870 * BYTES_PER_MIB);
    assert_eq!(
        config.manifest_cache_max_bytes,
        (44 * BYTES_PER_MIB) as usize
    );
    assert_eq!(config.max_keyvalue_bytes, 1024 * 1024);
    assert_eq!(config.rocksdb_max_open_files, 1024);
    assert_eq!(config.rocksdb_max_background_jobs, 6);
    assert_eq!(
        config.rocksdb_block_cache_bytes,
        (32 * BYTES_PER_MIB) as usize
    );
    assert_eq!(
        config.rocksdb_write_buffer_manager_bytes,
        (32 * BYTES_PER_MIB) as usize
    );
    assert_eq!(
        config.rocksdb_write_buffer_size_bytes,
        (8 * BYTES_PER_MIB) as usize
    );
    assert_eq!(config.rocksdb_max_write_buffer_number, 4);
    assert_eq!(
        config.replication_bandwidth_limit_bytes_per_second,
        512 * BYTES_PER_MIB
    );
    assert_eq!(config.tmp_dir_max_bytes, DEFAULT_TMP_DIR_MAX_BYTES);
    assert_eq!(config.replication_public_latency_target_ms, 100);
    assert_eq!(
        config.accelerated_file_serving,
        AcceleratedFileServingConfig {
            enabled: true,
            mode: AcceleratedFileServingMode::Splice,
            max_concurrent: 32,
            chunk_bytes: 1024 * 1024,
        }
    );
    assert_eq!(config.sentry_dsn, None);
}

#[test]
fn derived_file_descriptor_defaults_scale_with_high_process_limits() {
    let defaults = DerivedRuntimeDefaults::from_host_resources(HostResources {
        file_descriptor_limit: 16_384,
        memory_limit_bytes: 1024 * 1024 * 1024,
        cpu_count: 6,
    });

    assert_eq!(defaults.file_descriptor_pool_size, 4096);
    assert_eq!(defaults.segment_handle_cache_size, 256);
    assert_eq!(defaults.file_descriptor_acquire_timeout_ms, 5_000);
}

#[test]
fn from_lookup_parses_overrides() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (
            KURA_PEERS,
            "http://kura-a.example.com:7443, http://kura-b.example.com:7443",
        ),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_DRAIN_COMPLETION_TIMEOUT_MS, "120000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_TMP_DIR_MAX_BYTES, "1073741824"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (KURA_ACCELERATED_FILE_SERVING_ENABLED, "false"),
        (KURA_ACCELERATED_FILE_SERVING_MODE, "sendfile"),
        (KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT, "16"),
        (KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES, "2097152"),
        (
            KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND,
            "10485760",
        ),
        (KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS, "75"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected config overrides to parse");

    assert_eq!(config.port, 4500);
    assert_eq!(config.internal_port, 7443);
    assert_eq!(config.tenant_id, "acme");
    assert_eq!(config.region, "eu_west");
    assert_eq!(config.tmp_dir, PathBuf::from("/tmp/kura"));
    assert_eq!(config.data_dir, PathBuf::from("/tmp/kura-data"));
    assert_eq!(config.node_url, "http://kura.example.com:7443");
    assert_eq!(
        config.peers,
        vec![
            "http://kura-a.example.com:7443".to_owned(),
            "http://kura-b.example.com:7443".to_owned()
        ]
    );
    assert_eq!(config.discovery_dns_name, None);
    assert_eq!(config.peer_tls, None);
    assert_eq!(config.file_descriptor_pool_size, 64);
    assert_eq!(config.file_descriptor_acquire_timeout_ms, 5000);
    assert_eq!(config.drain_completion_timeout_ms, 120000);
    assert_eq!(config.segment_handle_cache_size, 16);
    assert_eq!(config.memory_soft_limit_bytes, 268_435_456);
    assert_eq!(config.memory_hard_limit_bytes, 536_870_912);
    assert_eq!(config.tmp_dir_max_bytes, 1_073_741_824);
    assert_eq!(config.manifest_cache_max_bytes, 16_777_216);
    assert_eq!(config.max_keyvalue_bytes, 1_048_576);
    assert_eq!(config.rocksdb_max_open_files, 1024);
    assert_eq!(config.rocksdb_max_background_jobs, 4);
    assert_eq!(config.rocksdb_block_cache_bytes, 32 * 1024 * 1024);
    assert_eq!(config.rocksdb_write_buffer_manager_bytes, 32 * 1024 * 1024);
    assert_eq!(config.rocksdb_write_buffer_size_bytes, 8 * 1024 * 1024);
    assert_eq!(config.rocksdb_max_write_buffer_number, 4);
    assert_eq!(
        config.accelerated_file_serving,
        AcceleratedFileServingConfig {
            enabled: false,
            mode: AcceleratedFileServingMode::Sendfile,
            max_concurrent: 16,
            chunk_bytes: 2 * 1024 * 1024,
        }
    );
    assert_eq!(
        config.replication_bandwidth_limit_bytes_per_second,
        10_485_760
    );
    assert_eq!(config.replication_public_latency_target_ms, 75);
    assert_eq!(config.analytics, None);
    assert_eq!(
        config.otlp_traces_endpoint.as_deref(),
        Some("https://otel.example.com/v1/traces")
    );
    assert_eq!(config.otel_service_name, "kura-eu");
    assert_eq!(config.otel_deployment_environment, "staging");
    assert_eq!(config.sentry_dsn, None);
    assert_eq!(
        config.geoip_refresh_interval_secs,
        DEFAULT_GEOIP_REFRESH_INTERVAL_SECS
    );
}

#[test]
fn from_lookup_parses_geoip_refresh_interval_override() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_GEOIP_REFRESH_INTERVAL_SECS, "3600"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected geoip config to parse");

    assert_eq!(config.geoip_refresh_interval_secs, 3_600);
}

#[test]
fn cas_capacity_bytes_defaults_to_unset() {
    let config = config_from(&[]).expect("expected config to parse");

    assert_eq!(config.cas_capacity_bytes, None);
}

#[test]
fn from_lookup_parses_cas_capacity_bytes_override() {
    let config = config_from(&[(KURA_CAS_CAPACITY_BYTES, "21474836480")])
        .expect("expected cas capacity config to parse");

    assert_eq!(config.cas_capacity_bytes, Some(21_474_836_480));
}

#[test]
fn from_lookup_rejects_invalid_cas_capacity_bytes() {
    let error = config_from(&[(KURA_CAS_CAPACITY_BYTES, "invalid")])
        .expect_err("expected invalid cas capacity to be rejected");
    assert!(error.contains(KURA_CAS_CAPACITY_BYTES));

    let error = config_from(&[(KURA_CAS_CAPACITY_BYTES, "0")])
        .expect_err("expected zero cas capacity to be rejected");
    assert!(error.contains(KURA_CAS_CAPACITY_BYTES));
}

#[test]
fn from_lookup_parses_node_location_overrides() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_NODE_COUNTRY, " fr "),
        (KURA_NODE_SUBDIVISION, " fr-idf "),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected node location config to parse");

    assert_eq!(config.node_country_override.as_deref(), Some("fr"));
    assert_eq!(config.node_subdivision_override.as_deref(), Some("fr-idf"));
}

#[test]
fn from_lookup_reports_invalid_port() {
    let error = config_from(&[
        (KURA_PORT, "invalid"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "invalid"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "invalid"),
        (KURA_DRAIN_COMPLETION_TIMEOUT_MS, "invalid"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "invalid"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "invalid"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "invalid"),
        (KURA_TMP_DIR_MAX_BYTES, "invalid"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "invalid"),
        (KURA_MAX_KEYVALUE_BYTES, "invalid"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "invalid"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "invalid"),
        (KURA_METADATA_STORE_READ_CACHE_BYTES, "invalid"),
        (KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES, "invalid"),
        (KURA_METADATA_STORE_WRITE_BUFFER_BYTES, "invalid"),
        (KURA_METADATA_STORE_MAX_WRITE_BUFFERS, "invalid"),
        (KURA_ACCELERATED_FILE_SERVING_ENABLED, "invalid"),
        (KURA_ACCELERATED_FILE_SERVING_MODE, "uring"),
        (KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT, "invalid"),
        (KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES, "invalid"),
        (KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND, "invalid"),
        (KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS, "invalid"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected invalid port to fail");

    assert!(error.contains(KURA_PORT));
    assert!(error.contains("valid u16"));
    assert!(error.contains(KURA_FILE_DESCRIPTOR_POOL_SIZE));
    assert!(error.contains(KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS));
    assert!(error.contains(KURA_DRAIN_COMPLETION_TIMEOUT_MS));
    assert!(error.contains(KURA_SEGMENT_HANDLE_CACHE_SIZE));
    assert!(error.contains(KURA_MEMORY_SOFT_LIMIT_BYTES));
    assert!(error.contains(KURA_MEMORY_HARD_LIMIT_BYTES));
    assert!(error.contains(KURA_TMP_DIR_MAX_BYTES));
    assert!(error.contains(KURA_MANIFEST_CACHE_MAX_BYTES));
    assert!(error.contains(KURA_MAX_KEYVALUE_BYTES));
    assert!(error.contains(KURA_METADATA_STORE_MAX_OPEN_FILES));
    assert!(error.contains(KURA_METADATA_STORE_MAX_BACKGROUND_JOBS));
    assert!(error.contains(KURA_METADATA_STORE_READ_CACHE_BYTES));
    assert!(error.contains(KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES));
    assert!(error.contains(KURA_METADATA_STORE_WRITE_BUFFER_BYTES));
    assert!(error.contains(KURA_METADATA_STORE_MAX_WRITE_BUFFERS));
    assert!(error.contains(KURA_ACCELERATED_FILE_SERVING_ENABLED));
    assert!(error.contains(KURA_ACCELERATED_FILE_SERVING_MODE));
    assert!(error.contains(KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT));
    assert!(error.contains(KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES));
    assert!(error.contains(KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND));
    assert!(error.contains(KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS));
}

#[test]
fn from_lookup_rejects_zero_tmp_dir_max_bytes() {
    let error = config_from(&[(KURA_TMP_DIR_MAX_BYTES, "0")])
        .expect_err("expected zero tmp dir budget to fail");

    assert!(error.contains(KURA_TMP_DIR_MAX_BYTES));
    assert!(error.contains("must be greater than 0"));
}

#[test]
fn from_lookup_rejects_zero_accelerated_file_serving_limits() {
    let error = config_from(&[
        (KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT, "0"),
        (KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES, "0"),
    ])
    .expect_err("expected invalid accelerated file serving limits to fail");

    assert!(error.contains(KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT));
    assert!(error.contains(KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES));
}

#[test]
fn from_lookup_parses_optional_discovery_dns_name() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEER_GATEWAY_URL, "http://peer.kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_DISCOVERY_DNS_NAME, "kura-ring.internal"),
        (KURA_GLOBAL_DISCOVERY_DNS_NAME, "acme.kura-peers.internal"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected config overrides to parse");

    assert_eq!(
        config.discovery_dns_name.as_deref(),
        Some("kura-ring.internal")
    );
    assert_eq!(
        config.global_discovery_dns_name.as_deref(),
        Some("acme.kura-peers.internal")
    );
    assert_eq!(
        config.peer_gateway_url.as_deref(),
        Some("http://peer.kura.example.com:7443")
    );
}

#[test]
fn from_lookup_parses_optional_analytics_config() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (KURA_METADATA_STORE_READ_CACHE_BYTES, "33554432"),
        (KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES, "50331648"),
        (KURA_METADATA_STORE_WRITE_BUFFER_BYTES, "8388608"),
        (KURA_METADATA_STORE_MAX_WRITE_BUFFERS, "6"),
        (KURA_ANALYTICS_SERVER_URL, "https://tuist.dev/"),
        (KURA_ANALYTICS_SIGNING_KEY, "secret-key"),
        (KURA_ANALYTICS_BATCH_SIZE, "25"),
        (KURA_ANALYTICS_BATCH_TIMEOUT_MS, "1500"),
        (KURA_ANALYTICS_QUEUE_CAPACITY, "250"),
        (KURA_ANALYTICS_REQUEST_TIMEOUT_MS, "3000"),
        (KURA_ANALYTICS_CIRCUIT_BREAKER_FAILURE_THRESHOLD, "3"),
        (KURA_ANALYTICS_CIRCUIT_BREAKER_OPEN_MS, "45000"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected analytics config to parse");

    assert_eq!(
        config.analytics,
        Some(AnalyticsConfig {
            server_url: "https://tuist.dev".into(),
            signing_key: "secret-key".into(),
            batch_size: 25,
            batch_timeout_ms: 1_500,
            queue_capacity: 250,
            request_timeout_ms: 3_000,
            circuit_breaker_failure_threshold: 3,
            circuit_breaker_open_ms: 45_000,
        })
    );
    assert_eq!(config.rocksdb_block_cache_bytes, 32 * 1024 * 1024);
    assert_eq!(config.rocksdb_write_buffer_manager_bytes, 48 * 1024 * 1024);
    assert_eq!(config.rocksdb_write_buffer_size_bytes, 8 * 1024 * 1024);
    assert_eq!(config.rocksdb_max_write_buffer_number, 6);
}

#[test]
fn from_lookup_parses_optional_sentry_dsn() {
    let config = config_from(&[(
        KURA_SENTRY_DSN,
        "https://public@example.ingest.sentry.io/12345",
    )])
    .expect("expected sentry dsn to parse");

    assert_eq!(
        config.sentry_dsn.as_deref(),
        Some("https://public@example.ingest.sentry.io/12345")
    );
}

#[test]
fn from_lookup_rejects_invalid_sentry_dsn() {
    let error = config_from(&[(KURA_SENTRY_DSN, "not-a-sentry-dsn")])
        .expect_err("expected invalid sentry dsn to fail");

    assert!(error.contains(KURA_SENTRY_DSN));
    assert!(error.contains("valid Sentry DSN"));
}

#[test]
fn from_lookup_requires_complete_analytics_config() {
    let error = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (KURA_ANALYTICS_SERVER_URL, "https://tuist.dev"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected partial analytics config to fail");

    assert!(error.contains(KURA_ANALYTICS_SERVER_URL));
    assert!(error.contains(KURA_ANALYTICS_SIGNING_KEY));
}

#[test]
fn from_lookup_requires_segment_handle_cache_headroom() {
    let error = config_from(&[
        (KURA_PORT, "4000"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "16"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "128"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "2"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected equal segment handle cache size to fail");

    assert!(error.contains(KURA_SEGMENT_HANDLE_CACHE_SIZE));
    assert!(error.contains(KURA_FILE_DESCRIPTOR_POOL_SIZE));
}

#[test]
fn from_lookup_requires_manifest_cache_to_leave_memory_headroom() {
    let error = config_from(&[
        (KURA_PORT, "4000"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "16"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "8"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "1048576"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "2097152"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "1048576"),
        (KURA_MAX_KEYVALUE_BYTES, "262144"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "128"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "2"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected manifest cache size at soft limit to fail");

    assert!(error.contains(KURA_MANIFEST_CACHE_MAX_BYTES));
    assert!(error.contains(KURA_MEMORY_SOFT_LIMIT_BYTES));
}

#[test]
fn from_lookup_parses_peer_tls_config() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "https://kura.example.com:7443"),
        (
            KURA_PEERS,
            "https://kura-a.example.com:7443, https://kura-b.example.com:7443",
        ),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_INTERNAL_TLS_CA_CERT_PATH, "/etc/kura/peer-ca.pem"),
        (KURA_INTERNAL_TLS_CERT_PATH, "/etc/kura/peer.pem"),
        (KURA_INTERNAL_TLS_KEY_PATH, "/etc/kura/peer.key"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected peer tls config to parse");

    assert_eq!(config.internal_port, 7443);
    assert_eq!(
        config.peer_tls,
        Some(PeerTlsConfig {
            ca_cert_path: PathBuf::from("/etc/kura/peer-ca.pem"),
            cert_path: PathBuf::from("/etc/kura/peer.pem"),
            key_path: PathBuf::from("/etc/kura/peer.key"),
        })
    );
}

#[test]
fn from_lookup_parses_public_tls_config() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_PUBLIC_TLS_CERT_PATH, "/etc/kura/public-tls/tls.crt"),
        (KURA_PUBLIC_TLS_KEY_PATH, "/etc/kura/public-tls/tls.key"),
        (KURA_HTTPS_PORT, "4443"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected public tls config to parse");

    assert_eq!(
        config.public_tls,
        Some(PublicTlsConfig {
            cert_path: PathBuf::from("/etc/kura/public-tls/tls.crt"),
            key_path: PathBuf::from("/etc/kura/public-tls/tls.key"),
        })
    );
    assert_eq!(config.https_port, 4443);
}

#[test]
fn from_lookup_defaults_https_port_when_unset() {
    let config = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect("expected config without public tls to parse");

    assert!(config.public_tls.is_none());
    assert_eq!(config.https_port, DEFAULT_HTTPS_PORT);
}

#[test]
fn from_lookup_requires_complete_public_tls_config() {
    let error = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_PUBLIC_TLS_CERT_PATH, "/etc/kura/public-tls/tls.crt"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected incomplete public tls config to fail");

    assert!(error.contains(KURA_PUBLIC_TLS_CERT_PATH));
    assert!(error.contains(KURA_PUBLIC_TLS_KEY_PATH));
}

#[test]
fn from_lookup_rejects_https_port_colliding_with_other_ports() {
    let error = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_PUBLIC_TLS_CERT_PATH, "/etc/kura/public-tls/tls.crt"),
        (KURA_PUBLIC_TLS_KEY_PATH, "/etc/kura/public-tls/tls.key"),
        (KURA_HTTPS_PORT, "4500"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected colliding https port to fail");

    assert!(error.contains(KURA_HTTPS_PORT));
    assert!(error.contains(KURA_PORT));
}

#[test]
fn from_lookup_requires_complete_peer_tls_config() {
    let error = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "https://kura.example.com:7443"),
        (KURA_PEERS, "https://kura-a.example.com:7443"),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_INTERNAL_TLS_CA_CERT_PATH, "/etc/kura/peer-ca.pem"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected incomplete peer tls config to fail");

    assert!(error.contains(KURA_INTERNAL_TLS_CA_CERT_PATH));
    assert!(error.contains(KURA_INTERNAL_TLS_CERT_PATH));
    assert!(error.contains(KURA_INTERNAL_TLS_KEY_PATH));
}

#[test]
fn from_lookup_requires_https_peer_urls_when_peer_tls_enabled() {
    let error = config_from(&[
        (KURA_PORT, "4500"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "eu_west"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://kura.example.com:7443"),
        (KURA_PEERS, "http://kura-a.example.com:7443"),
        (KURA_INTERNAL_PORT, "7443"),
        (KURA_INTERNAL_TLS_CA_CERT_PATH, "/etc/kura/peer-ca.pem"),
        (KURA_INTERNAL_TLS_CERT_PATH, "/etc/kura/peer.pem"),
        (KURA_INTERNAL_TLS_KEY_PATH, "/etc/kura/peer.key"),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "64"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "16"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "1024"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "4"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "https://otel.example.com/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-eu"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "staging"),
    ])
    .expect_err("expected non-https peer urls to fail");

    assert!(error.contains(KURA_NODE_URL));
    assert!(error.contains("https"));
    assert!(error.contains("peer URL"));
}

#[tokio::test]
async fn ensure_directories_creates_expected_layout() {
    let temp_dir = tempdir().expect("failed to create temp dir");
    let mut config = config_from(&[
        (KURA_PORT, "4000"),
        (KURA_TENANT_ID, "acme"),
        (KURA_REGION, "local"),
        (KURA_TMP_DIR, "/tmp/kura"),
        (KURA_DATA_DIR, "/tmp/kura-data"),
        (KURA_NODE_URL, "http://127.0.0.1:7443"),
        (KURA_PEERS, ""),
        (KURA_FILE_DESCRIPTOR_POOL_SIZE, "32"),
        (KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS, "5000"),
        (KURA_SEGMENT_HANDLE_CACHE_SIZE, "8"),
        (KURA_MEMORY_SOFT_LIMIT_BYTES, "268435456"),
        (KURA_MEMORY_HARD_LIMIT_BYTES, "536870912"),
        (KURA_MANIFEST_CACHE_MAX_BYTES, "16777216"),
        (KURA_MAX_KEYVALUE_BYTES, "1048576"),
        (KURA_METADATA_STORE_MAX_OPEN_FILES, "256"),
        (KURA_METADATA_STORE_MAX_BACKGROUND_JOBS, "2"),
        (
            KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
            "http://127.0.0.1:4318/v1/traces",
        ),
        (KURA_OTEL_SERVICE_NAME, "kura-local"),
        (KURA_OTEL_DEPLOYMENT_ENVIRONMENT, "local"),
    ])
    .expect("expected config to parse");
    config.tmp_dir = temp_dir.path().join("tmp");
    config.data_dir = temp_dir.path().join("data");

    // Pre-seed stale staging (as a crashed previous run leaves behind) plus a
    // real data file, to prove ensure_directories reclaims the former without
    // touching the latter.
    let stale = config.tmp_dir.join("bootstrap").join("leftover");
    let kept = config.data_dir.join("rocksdb").join("CURRENT");
    fs::create_dir_all(stale.parent().unwrap()).await.unwrap();
    fs::create_dir_all(kept.parent().unwrap()).await.unwrap();
    fs::write(&stale, b"stale").await.unwrap();
    fs::write(&kept, b"keep").await.unwrap();

    config
        .ensure_directories()
        .await
        .expect("failed to create Kura directories");

    assert!(config.tmp_dir.join("uploads").exists());
    assert!(config.tmp_dir.join("parts").exists());
    assert!(config.tmp_dir.join("bootstrap").exists());
    assert!(config.data_dir.join("rocksdb").exists());
    assert!(config.data_dir.join("blobs").exists());
    assert!(config.data_dir.join("segments").exists());
    assert!(config.data_dir.join("multipart").exists());

    assert!(
        !stale.exists(),
        "stale staging must be reclaimed on startup"
    );
    assert!(kept.exists(), "persistent data must be preserved");
}
