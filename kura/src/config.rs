use std::path::PathBuf;

use tokio::fs;

use crate::constants::{
    DEFAULT_BOOTSTRAP_MAX_CONCURRENT_PEERS, DEFAULT_BOOTSTRAP_TIMEOUT_MS,
    DEFAULT_MULTIPART_JANITOR_INTERVAL_MS, DEFAULT_MULTIPART_UPLOAD_TTL_MS,
    DEFAULT_OUTBOX_MAX_DEPTH, DEFAULT_USAGE_BATCH_SIZE, DEFAULT_USAGE_DELIVERY_INTERVAL_MS,
    DEFAULT_USAGE_FLUSH_INTERVAL_MS, DEFAULT_USAGE_MAX_BUCKETS, DEFAULT_USAGE_OUTBOX_MAX_DEPTH,
    DEFAULT_USAGE_WINDOW_SECS,
};

const KURA_PORT: &str = "KURA_PORT";
const KURA_GRPC_PORT: &str = "KURA_GRPC_PORT";
const KURA_TENANT_ID: &str = "KURA_TENANT_ID";
const KURA_REGION: &str = "KURA_REGION";
const KURA_TMP_DIR: &str = "KURA_TMP_DIR";
const KURA_DATA_DIR: &str = "KURA_DATA_DIR";
const KURA_NODE_URL: &str = "KURA_NODE_URL";
const KURA_PEERS: &str = "KURA_PEERS";
const KURA_DISCOVERY_DNS_NAME: &str = "KURA_DISCOVERY_DNS_NAME";
const KURA_INTERNAL_PORT: &str = "KURA_INTERNAL_PORT";
const KURA_INTERNAL_TLS_CA_CERT_PATH: &str = "KURA_INTERNAL_TLS_CA_CERT_PATH";
const KURA_INTERNAL_TLS_CERT_PATH: &str = "KURA_INTERNAL_TLS_CERT_PATH";
const KURA_INTERNAL_TLS_KEY_PATH: &str = "KURA_INTERNAL_TLS_KEY_PATH";
const KURA_GRPC_TLS_CERT_PATH: &str = "KURA_GRPC_TLS_CERT_PATH";
const KURA_GRPC_TLS_KEY_PATH: &str = "KURA_GRPC_TLS_KEY_PATH";
const KURA_PUBLIC_TLS_CERT_PATH: &str = "KURA_PUBLIC_TLS_CERT_PATH";
const KURA_PUBLIC_TLS_KEY_PATH: &str = "KURA_PUBLIC_TLS_KEY_PATH";
const KURA_HTTPS_PORT: &str = "KURA_HTTPS_PORT";
const KURA_ACCELERATED_FILE_SERVING_ENABLED: &str = "KURA_ACCELERATED_FILE_SERVING_ENABLED";
const KURA_ACCELERATED_FILE_SERVING_MODE: &str = "KURA_ACCELERATED_FILE_SERVING_MODE";
const KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT: &str =
    "KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT";
const KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES: &str = "KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES";

const DEFAULT_HTTPS_PORT: u16 = 4443;
const KURA_FILE_DESCRIPTOR_POOL_SIZE: &str = "KURA_FILE_DESCRIPTOR_POOL_SIZE";
const KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS: &str = "KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS";
const KURA_DRAIN_COMPLETION_TIMEOUT_MS: &str = "KURA_DRAIN_COMPLETION_TIMEOUT_MS";
const KURA_SEGMENT_HANDLE_CACHE_SIZE: &str = "KURA_SEGMENT_HANDLE_CACHE_SIZE";
const KURA_MEMORY_SOFT_LIMIT_BYTES: &str = "KURA_MEMORY_SOFT_LIMIT_BYTES";
const KURA_MEMORY_HARD_LIMIT_BYTES: &str = "KURA_MEMORY_HARD_LIMIT_BYTES";
const KURA_MANIFEST_CACHE_MAX_BYTES: &str = "KURA_MANIFEST_CACHE_MAX_BYTES";
const KURA_MAX_KEYVALUE_BYTES: &str = "KURA_MAX_KEYVALUE_BYTES";
const KURA_METADATA_STORE_MAX_OPEN_FILES: &str = "KURA_METADATA_STORE_MAX_OPEN_FILES";
const KURA_METADATA_STORE_MAX_BACKGROUND_JOBS: &str = "KURA_METADATA_STORE_MAX_BACKGROUND_JOBS";
const KURA_METADATA_STORE_READ_CACHE_BYTES: &str = "KURA_METADATA_STORE_READ_CACHE_BYTES";
const KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES: &str =
    "KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES";
const KURA_METADATA_STORE_WRITE_BUFFER_BYTES: &str = "KURA_METADATA_STORE_WRITE_BUFFER_BYTES";
const KURA_METADATA_STORE_MAX_WRITE_BUFFERS: &str = "KURA_METADATA_STORE_MAX_WRITE_BUFFERS";
const KURA_ANALYTICS_SERVER_URL: &str = "KURA_ANALYTICS_SERVER_URL";
const KURA_ANALYTICS_SIGNING_KEY: &str = "KURA_ANALYTICS_SIGNING_KEY";
const KURA_ANALYTICS_BATCH_SIZE: &str = "KURA_ANALYTICS_BATCH_SIZE";
const KURA_ANALYTICS_BATCH_TIMEOUT_MS: &str = "KURA_ANALYTICS_BATCH_TIMEOUT_MS";
const KURA_ANALYTICS_QUEUE_CAPACITY: &str = "KURA_ANALYTICS_QUEUE_CAPACITY";
const KURA_ANALYTICS_REQUEST_TIMEOUT_MS: &str = "KURA_ANALYTICS_REQUEST_TIMEOUT_MS";
const KURA_ANALYTICS_CIRCUIT_BREAKER_FAILURE_THRESHOLD: &str =
    "KURA_ANALYTICS_CIRCUIT_BREAKER_FAILURE_THRESHOLD";
const KURA_ANALYTICS_CIRCUIT_BREAKER_OPEN_MS: &str = "KURA_ANALYTICS_CIRCUIT_BREAKER_OPEN_MS";
const KURA_CONTROL_PLANE_URL: &str = "KURA_CONTROL_PLANE_URL";
const KURA_CONTROL_PLANE_CLIENT_ID: &str = "KURA_CONTROL_PLANE_CLIENT_ID";
const KURA_CONTROL_PLANE_CLIENT_SECRET: &str = "KURA_CONTROL_PLANE_CLIENT_SECRET";
const KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL: &str = "KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL";
const KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID: &str = "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID";
const KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_SECRET: &str =
    "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_SECRET";
const KURA_USAGE_WINDOW_SECS: &str = "KURA_USAGE_WINDOW_SECS";
const KURA_USAGE_FLUSH_INTERVAL_MS: &str = "KURA_USAGE_FLUSH_INTERVAL_MS";
const KURA_USAGE_DELIVERY_INTERVAL_MS: &str = "KURA_USAGE_DELIVERY_INTERVAL_MS";
const KURA_USAGE_BATCH_SIZE: &str = "KURA_USAGE_BATCH_SIZE";
const KURA_USAGE_MAX_BUCKETS: &str = "KURA_USAGE_MAX_BUCKETS";
const KURA_USAGE_OUTBOX_MAX_DEPTH: &str = "KURA_USAGE_OUTBOX_MAX_DEPTH";
const KURA_OUTBOX_MAX_DEPTH: &str = "KURA_OUTBOX_MAX_DEPTH";
const KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND: &str =
    "KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND";
const KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS: &str = "KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS";
const KURA_MULTIPART_UPLOAD_TTL_MS: &str = "KURA_MULTIPART_UPLOAD_TTL_MS";
const KURA_MULTIPART_JANITOR_INTERVAL_MS: &str = "KURA_MULTIPART_JANITOR_INTERVAL_MS";
const KURA_BOOTSTRAP_TIMEOUT_MS: &str = "KURA_BOOTSTRAP_TIMEOUT_MS";
const KURA_BOOTSTRAP_MAX_CONCURRENT_PEERS: &str = "KURA_BOOTSTRAP_MAX_CONCURRENT_PEERS";
const KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: &str = "KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT";
const KURA_OTEL_SERVICE_NAME: &str = "KURA_OTEL_SERVICE_NAME";
const KURA_OTEL_DEPLOYMENT_ENVIRONMENT: &str = "KURA_OTEL_DEPLOYMENT_ENVIRONMENT";
const KURA_SENTRY_DSN: &str = "KURA_SENTRY_DSN";
const KURA_GEOIP_REFRESH_INTERVAL_SECS: &str = "KURA_GEOIP_REFRESH_INTERVAL_SECS";
const DEFAULT_GEOIP_REFRESH_INTERVAL_SECS: u64 = 86_400;
const KURA_NODE_COUNTRY: &str = "KURA_NODE_COUNTRY";
const KURA_NODE_SUBDIVISION: &str = "KURA_NODE_SUBDIVISION";

const BYTES_PER_MIB: u64 = 1024 * 1024;
const DEFAULT_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS: u64 = 5_000;
const DEFAULT_DRAIN_COMPLETION_TIMEOUT_MS: u64 = 240_000;
const DEFAULT_MAX_KEYVALUE_BYTES: usize = 1024 * 1024;
const DEFAULT_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND: u64 = 512 * BYTES_PER_MIB;
const DEFAULT_REPLICATION_PUBLIC_LATENCY_TARGET_MS: u64 = 100;
const FALLBACK_HOST_FD_LIMIT: usize = 4096;
const FALLBACK_HOST_MEMORY_LIMIT_BYTES: u64 = 1024 * BYTES_PER_MIB;
const FALLBACK_HOST_CPU_COUNT: usize = 4;

#[derive(Clone, Debug)]
pub struct Config {
    pub port: u16,
    pub grpc_port: u16,
    pub internal_port: u16,
    pub tenant_id: String,
    pub region: String,
    pub tmp_dir: PathBuf,
    pub data_dir: PathBuf,
    pub node_url: String,
    pub peers: Vec<String>,
    pub discovery_dns_name: Option<String>,
    pub peer_tls: Option<PeerTlsConfig>,
    pub grpc_tls: Option<GrpcTlsConfig>,
    pub public_tls: Option<PublicTlsConfig>,
    pub https_port: u16,
    pub accelerated_file_serving: AcceleratedFileServingConfig,
    pub file_descriptor_pool_size: usize,
    pub file_descriptor_acquire_timeout_ms: u64,
    pub drain_completion_timeout_ms: u64,
    pub segment_handle_cache_size: usize,
    pub memory_soft_limit_bytes: u64,
    pub memory_hard_limit_bytes: u64,
    pub manifest_cache_max_bytes: usize,
    pub max_keyvalue_bytes: usize,
    pub rocksdb_max_open_files: i32,
    pub rocksdb_max_background_jobs: i32,
    pub rocksdb_block_cache_bytes: usize,
    pub rocksdb_write_buffer_manager_bytes: usize,
    pub rocksdb_write_buffer_size_bytes: usize,
    pub rocksdb_max_write_buffer_number: i32,
    pub outbox_max_depth: usize,
    pub replication_bandwidth_limit_bytes_per_second: u64,
    pub replication_public_latency_target_ms: u64,
    pub multipart_upload_ttl_ms: u64,
    pub multipart_janitor_interval_ms: u64,
    pub bootstrap_timeout_ms: u64,
    pub bootstrap_max_concurrent_peers: usize,
    pub analytics: Option<AnalyticsConfig>,
    pub usage: Option<UsageConfig>,
    pub otlp_traces_endpoint: Option<String>,
    pub otel_service_name: String,
    pub otel_deployment_environment: String,
    pub sentry_dsn: Option<String>,
    /// How often the in-process GeoIP database is refreshed against the
    /// upstream DB-IP Lite dump. `0` disables background refresh — the
    /// container-image copy is then used for the pod's lifetime.
    pub geoip_refresh_interval_secs: u64,
    /// Operator-provided ISO 3166-1 alpha-2 country code for the node.
    /// When set, it short-circuits the egress-IP probe used to stamp
    /// `geo.country.iso_code` on the OTel Resource.
    pub node_country_override: Option<String>,
    /// Operator-provided ISO 3166-2 subdivision code for the node (e.g.
    /// `US-CA`). When set, it short-circuits the egress-IP probe used to
    /// stamp `geo.region.iso_code` on the OTel Resource.
    pub node_subdivision_override: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PeerTlsConfig {
    pub ca_cert_path: PathBuf,
    pub cert_path: PathBuf,
    pub key_path: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GrpcTlsConfig {
    pub cert_path: PathBuf,
    pub key_path: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PublicTlsConfig {
    pub cert_path: PathBuf,
    pub key_path: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AcceleratedFileServingConfig {
    pub enabled: bool,
    pub mode: AcceleratedFileServingMode,
    pub max_concurrent: usize,
    pub chunk_bytes: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AcceleratedFileServingMode {
    Sendfile,
    Splice,
}

impl AcceleratedFileServingMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Sendfile => "sendfile",
            Self::Splice => "splice",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AnalyticsConfig {
    pub server_url: String,
    pub signing_key: String,
    pub batch_size: usize,
    pub batch_timeout_ms: u64,
    pub queue_capacity: usize,
    pub request_timeout_ms: u64,
    pub circuit_breaker_failure_threshold: usize,
    pub circuit_breaker_open_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UsageConfig {
    pub control_plane_url: String,
    pub client_id: String,
    pub client_secret: String,
    pub window_secs: u64,
    pub flush_interval_ms: u64,
    pub delivery_interval_ms: u64,
    pub batch_size: usize,
    pub max_buckets: usize,
    pub outbox_max_depth: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct HostResources {
    pub file_descriptor_limit: usize,
    pub memory_limit_bytes: u64,
    pub cpu_count: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct DerivedRuntimeDefaults {
    file_descriptor_pool_size: usize,
    file_descriptor_acquire_timeout_ms: u64,
    drain_completion_timeout_ms: u64,
    segment_handle_cache_size: usize,
    memory_soft_limit_bytes: u64,
    memory_hard_limit_bytes: u64,
    manifest_cache_max_bytes: usize,
    max_keyvalue_bytes: usize,
    metadata_store_max_open_files: i32,
    metadata_store_max_background_jobs: i32,
    metadata_store_read_cache_bytes: usize,
    metadata_store_write_buffer_pool_bytes: usize,
    metadata_store_write_buffer_bytes: usize,
    metadata_store_max_write_buffers: i32,
}

impl HostResources {
    fn detect() -> Self {
        Self {
            file_descriptor_limit: detect_file_descriptor_limit()
                .unwrap_or(FALLBACK_HOST_FD_LIMIT)
                .max(256),
            memory_limit_bytes: detect_memory_limit_bytes()
                .unwrap_or(FALLBACK_HOST_MEMORY_LIMIT_BYTES)
                .max(256 * BYTES_PER_MIB),
            cpu_count: detect_cpu_count().max(1),
        }
    }
}

impl DerivedRuntimeDefaults {
    fn from_host_resources(host_resources: HostResources) -> Self {
        let reserved_fds = host_resources.file_descriptor_limit.max(64) / 8;
        let usable_fds = host_resources
            .file_descriptor_limit
            .saturating_sub(reserved_fds.max(64))
            .max(256);
        let file_descriptor_pool_size = clamp_usize(usable_fds / 8, 64, 256);
        let segment_handle_cache_size = clamp_usize(file_descriptor_pool_size / 4, 16, 64)
            .min(file_descriptor_pool_size.saturating_sub(1).max(1));
        let metadata_store_max_open_files =
            clamp_usize(usable_fds / 2, 128, 1024).min(i32::MAX as usize) as i32;

        let memory_limit_bytes = host_resources.memory_limit_bytes.max(256 * BYTES_PER_MIB);
        let memory_soft_limit_bytes =
            round_down_to_mib(memory_limit_bytes * 70 / 100).max(128 * BYTES_PER_MIB);
        let memory_hard_limit_bytes = round_down_to_mib(
            (memory_limit_bytes * 85 / 100).max(memory_soft_limit_bytes + 64 * BYTES_PER_MIB),
        );
        let manifest_cache_max_bytes = clamp_bytes_to_usize(
            round_down_to_mib(memory_soft_limit_bytes / 16),
            8 * BYTES_PER_MIB,
            64 * BYTES_PER_MIB,
        );
        let metadata_store_read_cache_bytes = clamp_bytes_to_usize(
            round_down_to_mib(memory_limit_bytes / 32),
            16 * BYTES_PER_MIB,
            128 * BYTES_PER_MIB,
        );
        let metadata_store_write_buffer_pool_bytes = clamp_bytes_to_usize(
            round_down_to_mib(memory_limit_bytes / 32),
            16 * BYTES_PER_MIB,
            128 * BYTES_PER_MIB,
        );
        let metadata_store_write_buffer_bytes = clamp_bytes_to_usize(
            round_down_to_mib((metadata_store_write_buffer_pool_bytes as u64) / 4),
            4 * BYTES_PER_MIB,
            32 * BYTES_PER_MIB,
        )
        .min(metadata_store_write_buffer_pool_bytes);
        let metadata_store_max_write_buffers = clamp_usize(
            metadata_store_write_buffer_pool_bytes / metadata_store_write_buffer_bytes.max(1),
            2,
            8,
        ) as i32;

        Self {
            file_descriptor_pool_size,
            file_descriptor_acquire_timeout_ms: DEFAULT_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS,
            drain_completion_timeout_ms: DEFAULT_DRAIN_COMPLETION_TIMEOUT_MS,
            segment_handle_cache_size,
            memory_soft_limit_bytes,
            memory_hard_limit_bytes,
            manifest_cache_max_bytes,
            max_keyvalue_bytes: DEFAULT_MAX_KEYVALUE_BYTES,
            metadata_store_max_open_files,
            metadata_store_max_background_jobs: clamp_usize(host_resources.cpu_count, 1, 8) as i32,
            metadata_store_read_cache_bytes,
            metadata_store_write_buffer_pool_bytes,
            metadata_store_write_buffer_bytes,
            metadata_store_max_write_buffers,
        }
    }
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        Self::from_lookup_with_resources(|key| std::env::var(key).ok(), HostResources::detect())
    }

    pub(crate) fn from_lookup_with_resources<F>(
        mut lookup: F,
        host_resources: HostResources,
    ) -> Result<Self, String>
    where
        F: FnMut(&str) -> Option<String>,
    {
        let mut missing = Vec::new();
        let mut invalid = Vec::new();
        let derived_defaults = DerivedRuntimeDefaults::from_host_resources(host_resources);

        let port =
            required_value(&mut lookup, KURA_PORT, &mut missing).and_then(|value| {
                match value.parse::<u16>() {
                    Ok(port) => Some(port),
                    Err(_) => {
                        invalid.push(format!("{KURA_PORT} must be a valid u16"));
                        None
                    }
                }
            });
        let grpc_port =
            required_value(&mut lookup, KURA_GRPC_PORT, &mut missing).and_then(|value| match value
                .parse::<u16>(
            ) {
                Ok(port) => Some(port),
                Err(_) => {
                    invalid.push(format!("{KURA_GRPC_PORT} must be a valid u16"));
                    None
                }
            });
        let internal_port =
            required_value(&mut lookup, KURA_INTERNAL_PORT, &mut missing).and_then(|value| {
                value
                    .parse::<u16>()
                    .map_err(|_| format!("{KURA_INTERNAL_PORT} must be a valid u16"))
                    .map(Some)
                    .unwrap_or_else(|error| {
                        invalid.push(error);
                        None
                    })
            });
        let tenant_id = required_value(&mut lookup, KURA_TENANT_ID, &mut missing);
        let region = required_value(&mut lookup, KURA_REGION, &mut missing);
        let tmp_dir = required_value(&mut lookup, KURA_TMP_DIR, &mut missing).map(PathBuf::from);
        let data_dir = required_value(&mut lookup, KURA_DATA_DIR, &mut missing).map(PathBuf::from);
        let node_url = required_value(&mut lookup, KURA_NODE_URL, &mut missing);
        let peers = lookup(KURA_PEERS)
            .map(|value| {
                value
                    .split(',')
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(ToOwned::to_owned)
                    .collect()
            })
            .or_else(|| node_url.as_ref().map(|value| vec![value.clone()]));
        let discovery_dns_name = lookup(KURA_DISCOVERY_DNS_NAME)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let accelerated_file_serving_enabled = optional_parsed_value(
            &mut lookup,
            KURA_ACCELERATED_FILE_SERVING_ENABLED,
            &mut invalid,
            |value| {
                value.parse::<bool>().map_err(|_| {
                    format!("{KURA_ACCELERATED_FILE_SERVING_ENABLED} must be a valid bool")
                })
            },
        )
        .unwrap_or(true);
        let accelerated_file_serving_mode =
            lookup(KURA_ACCELERATED_FILE_SERVING_MODE).unwrap_or_else(|| "splice".to_owned());
        let accelerated_file_serving_mode = match accelerated_file_serving_mode.as_str() {
            "sendfile" => Some(AcceleratedFileServingMode::Sendfile),
            "splice" => Some(AcceleratedFileServingMode::Splice),
            _ => {
                invalid.push(format!(
                    "{KURA_ACCELERATED_FILE_SERVING_MODE} must be either sendfile or splice"
                ));
                None
            }
        };
        let accelerated_file_serving_max_concurrent = optional_parsed_value(
            &mut lookup,
            KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT,
            &mut invalid,
            |value| {
                value.parse::<usize>().map_err(|_| {
                    format!("{KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT} must be a valid usize")
                })
            },
        )
        .unwrap_or(32);
        if accelerated_file_serving_max_concurrent == 0 {
            invalid.push(format!(
                "{KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT} must be greater than 0"
            ));
        }
        let accelerated_file_serving_chunk_bytes = optional_parsed_value(
            &mut lookup,
            KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES,
            &mut invalid,
            |value| {
                value.parse::<usize>().map_err(|_| {
                    format!("{KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES} must be a valid usize")
                })
            },
        )
        .unwrap_or(1024 * 1024);
        if accelerated_file_serving_chunk_bytes == 0 {
            invalid.push(format!(
                "{KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES} must be greater than 0"
            ));
        }
        let accelerated_file_serving =
            accelerated_file_serving_mode.map(|mode| AcceleratedFileServingConfig {
                enabled: accelerated_file_serving_enabled,
                mode,
                max_concurrent: accelerated_file_serving_max_concurrent,
                chunk_bytes: accelerated_file_serving_chunk_bytes,
            });
        let internal_tls_ca_cert_path = lookup(KURA_INTERNAL_TLS_CA_CERT_PATH)
            .map(PathBuf::from)
            .filter(|value| !value.as_os_str().is_empty());
        let internal_tls_cert_path = lookup(KURA_INTERNAL_TLS_CERT_PATH)
            .map(PathBuf::from)
            .filter(|value| !value.as_os_str().is_empty());
        let internal_tls_key_path = lookup(KURA_INTERNAL_TLS_KEY_PATH)
            .map(PathBuf::from)
            .filter(|value| !value.as_os_str().is_empty());
        let peer_tls = match (
            internal_tls_ca_cert_path,
            internal_tls_cert_path,
            internal_tls_key_path,
        ) {
            (None, None, None) => None,
            (Some(ca_cert_path), Some(cert_path), Some(key_path)) => Some(PeerTlsConfig {
                ca_cert_path,
                cert_path,
                key_path,
            }),
            _ => {
                invalid.push(format!(
                    "{KURA_INTERNAL_TLS_CA_CERT_PATH}, {KURA_INTERNAL_TLS_CERT_PATH}, and {KURA_INTERNAL_TLS_KEY_PATH} must either all be set or all be unset"
                ));
                None
            }
        };
        let grpc_tls_cert_path = lookup(KURA_GRPC_TLS_CERT_PATH)
            .map(PathBuf::from)
            .filter(|value| !value.as_os_str().is_empty());
        let grpc_tls_key_path = lookup(KURA_GRPC_TLS_KEY_PATH)
            .map(PathBuf::from)
            .filter(|value| !value.as_os_str().is_empty());
        let grpc_tls = match (grpc_tls_cert_path, grpc_tls_key_path) {
            (None, None) => None,
            (Some(cert_path), Some(key_path)) => Some(GrpcTlsConfig {
                cert_path,
                key_path,
            }),
            _ => {
                invalid.push(format!(
                    "{KURA_GRPC_TLS_CERT_PATH} and {KURA_GRPC_TLS_KEY_PATH} must either both be set or both be unset"
                ));
                None
            }
        };
        let public_tls_cert_path = lookup(KURA_PUBLIC_TLS_CERT_PATH)
            .map(PathBuf::from)
            .filter(|value| !value.as_os_str().is_empty());
        let public_tls_key_path = lookup(KURA_PUBLIC_TLS_KEY_PATH)
            .map(PathBuf::from)
            .filter(|value| !value.as_os_str().is_empty());
        let public_tls = match (public_tls_cert_path, public_tls_key_path) {
            (None, None) => None,
            (Some(cert_path), Some(key_path)) => Some(PublicTlsConfig {
                cert_path,
                key_path,
            }),
            _ => {
                invalid.push(format!(
                    "{KURA_PUBLIC_TLS_CERT_PATH} and {KURA_PUBLIC_TLS_KEY_PATH} must either both be set or both be unset"
                ));
                None
            }
        };
        let https_port =
            optional_parsed_value(&mut lookup, KURA_HTTPS_PORT, &mut invalid, |value| {
                value
                    .parse::<u16>()
                    .map_err(|_| format!("{KURA_HTTPS_PORT} must be a valid u16"))
            })
            .unwrap_or(DEFAULT_HTTPS_PORT);
        let file_descriptor_pool_size = optional_parsed_value(
            &mut lookup,
            KURA_FILE_DESCRIPTOR_POOL_SIZE,
            &mut invalid,
            |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_FILE_DESCRIPTOR_POOL_SIZE} must be a valid usize"))
            },
        )
        .unwrap_or(derived_defaults.file_descriptor_pool_size);
        if file_descriptor_pool_size == 0 {
            invalid.push(format!(
                "{KURA_FILE_DESCRIPTOR_POOL_SIZE} must be greater than 0"
            ));
        }
        let file_descriptor_acquire_timeout_ms = optional_parsed_value(
            &mut lookup,
            KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS,
            &mut invalid,
            |value| {
                value.parse::<u64>().map_err(|_| {
                    format!("{KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS} must be a valid u64")
                })
            },
        )
        .unwrap_or(derived_defaults.file_descriptor_acquire_timeout_ms);
        if file_descriptor_acquire_timeout_ms == 0 {
            invalid.push(format!(
                "{KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS} must be greater than 0"
            ));
        }
        let drain_completion_timeout_ms = optional_parsed_value(
            &mut lookup,
            KURA_DRAIN_COMPLETION_TIMEOUT_MS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_DRAIN_COMPLETION_TIMEOUT_MS} must be a valid u64"))
            },
        )
        .unwrap_or(derived_defaults.drain_completion_timeout_ms);
        if drain_completion_timeout_ms == 0 {
            invalid.push(format!(
                "{KURA_DRAIN_COMPLETION_TIMEOUT_MS} must be greater than 0"
            ));
        }
        let segment_handle_cache_size = optional_parsed_value(
            &mut lookup,
            KURA_SEGMENT_HANDLE_CACHE_SIZE,
            &mut invalid,
            |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_SEGMENT_HANDLE_CACHE_SIZE} must be a valid usize"))
            },
        )
        .unwrap_or_else(|| {
            derived_defaults
                .segment_handle_cache_size
                .min(file_descriptor_pool_size.saturating_sub(1).max(1))
        });
        if segment_handle_cache_size >= file_descriptor_pool_size {
            invalid.push(format!(
                "{KURA_SEGMENT_HANDLE_CACHE_SIZE} must be less than {KURA_FILE_DESCRIPTOR_POOL_SIZE} so transient file operations keep headroom"
            ));
        }
        let memory_soft_limit_bytes = optional_parsed_value(
            &mut lookup,
            KURA_MEMORY_SOFT_LIMIT_BYTES,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_MEMORY_SOFT_LIMIT_BYTES} must be a valid u64"))
            },
        )
        .unwrap_or(derived_defaults.memory_soft_limit_bytes);
        if memory_soft_limit_bytes == 0 {
            invalid.push(format!(
                "{KURA_MEMORY_SOFT_LIMIT_BYTES} must be greater than 0"
            ));
        }
        let memory_hard_limit_bytes = optional_parsed_value(
            &mut lookup,
            KURA_MEMORY_HARD_LIMIT_BYTES,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_MEMORY_HARD_LIMIT_BYTES} must be a valid u64"))
            },
        )
        .unwrap_or_else(|| {
            derived_defaults
                .memory_hard_limit_bytes
                .max(memory_soft_limit_bytes.saturating_add(64 * BYTES_PER_MIB))
        });
        if memory_hard_limit_bytes <= memory_soft_limit_bytes {
            invalid.push(format!(
                "{KURA_MEMORY_HARD_LIMIT_BYTES} must be greater than {KURA_MEMORY_SOFT_LIMIT_BYTES}"
            ));
        }
        let manifest_cache_default = clamp_usize(
            round_down_to_mib(memory_soft_limit_bytes / 16) as usize,
            (8 * BYTES_PER_MIB) as usize,
            (64 * BYTES_PER_MIB) as usize,
        );
        let manifest_cache_max_bytes = optional_parsed_value(
            &mut lookup,
            KURA_MANIFEST_CACHE_MAX_BYTES,
            &mut invalid,
            |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_MANIFEST_CACHE_MAX_BYTES} must be a valid usize"))
            },
        )
        .unwrap_or(manifest_cache_default);
        if manifest_cache_max_bytes == 0 {
            invalid.push(format!(
                "{KURA_MANIFEST_CACHE_MAX_BYTES} must be greater than 0"
            ));
        } else if manifest_cache_max_bytes as u64 >= memory_soft_limit_bytes {
            invalid.push(format!(
                "{KURA_MANIFEST_CACHE_MAX_BYTES} must be less than {KURA_MEMORY_SOFT_LIMIT_BYTES} so the cache leaves heap headroom"
            ));
        }
        let max_keyvalue_bytes = optional_parsed_value(
            &mut lookup,
            KURA_MAX_KEYVALUE_BYTES,
            &mut invalid,
            |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_MAX_KEYVALUE_BYTES} must be a valid usize"))
            },
        )
        .unwrap_or(derived_defaults.max_keyvalue_bytes);
        if max_keyvalue_bytes == 0 {
            invalid.push(format!("{KURA_MAX_KEYVALUE_BYTES} must be greater than 0"));
        }
        let rocksdb_max_open_files = optional_parsed_value(
            &mut lookup,
            KURA_METADATA_STORE_MAX_OPEN_FILES,
            &mut invalid,
            |value| {
                value.parse::<i32>().map_err(|_| {
                    format!("{KURA_METADATA_STORE_MAX_OPEN_FILES} must be a valid i32")
                })
            },
        )
        .unwrap_or(derived_defaults.metadata_store_max_open_files);
        if !(rocksdb_max_open_files > 0 || rocksdb_max_open_files == -1) {
            invalid.push(format!(
                "{KURA_METADATA_STORE_MAX_OPEN_FILES} must be -1 or greater than 0"
            ));
        }
        let rocksdb_max_background_jobs = optional_parsed_value(
            &mut lookup,
            KURA_METADATA_STORE_MAX_BACKGROUND_JOBS,
            &mut invalid,
            |value| {
                value.parse::<i32>().map_err(|_| {
                    format!("{KURA_METADATA_STORE_MAX_BACKGROUND_JOBS} must be a valid i32")
                })
            },
        )
        .unwrap_or(derived_defaults.metadata_store_max_background_jobs);
        if rocksdb_max_background_jobs <= 0 {
            invalid.push(format!(
                "{KURA_METADATA_STORE_MAX_BACKGROUND_JOBS} must be greater than 0"
            ));
        }
        let rocksdb_block_cache_bytes = optional_parsed_value(
            &mut lookup,
            KURA_METADATA_STORE_READ_CACHE_BYTES,
            &mut invalid,
            |value| {
                value.parse::<usize>().map_err(|_| {
                    format!("{KURA_METADATA_STORE_READ_CACHE_BYTES} must be a valid usize")
                })
            },
        )
        .unwrap_or(derived_defaults.metadata_store_read_cache_bytes);
        if rocksdb_block_cache_bytes == 0 {
            invalid.push(format!(
                "{KURA_METADATA_STORE_READ_CACHE_BYTES} must be greater than 0"
            ));
        }
        let rocksdb_write_buffer_manager_bytes = optional_parsed_value(
            &mut lookup,
            KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES,
            &mut invalid,
            |value| {
                value.parse::<usize>().map_err(|_| {
                    format!("{KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES} must be a valid usize")
                })
            },
        )
        .unwrap_or(derived_defaults.metadata_store_write_buffer_pool_bytes);
        if rocksdb_write_buffer_manager_bytes == 0 {
            invalid.push(format!(
                "{KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES} must be greater than 0"
            ));
        }
        let rocksdb_write_buffer_size_bytes = optional_parsed_value(
            &mut lookup,
            KURA_METADATA_STORE_WRITE_BUFFER_BYTES,
            &mut invalid,
            |value| {
                value.parse::<usize>().map_err(|_| {
                    format!("{KURA_METADATA_STORE_WRITE_BUFFER_BYTES} must be a valid usize")
                })
            },
        )
        .unwrap_or(derived_defaults.metadata_store_write_buffer_bytes);
        if rocksdb_write_buffer_size_bytes == 0 {
            invalid.push(format!(
                "{KURA_METADATA_STORE_WRITE_BUFFER_BYTES} must be greater than 0"
            ));
        } else if rocksdb_write_buffer_size_bytes > rocksdb_write_buffer_manager_bytes {
            invalid.push(format!(
                "{KURA_METADATA_STORE_WRITE_BUFFER_BYTES} must be less than or equal to {KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES}"
            ));
        }
        let rocksdb_max_write_buffer_number = optional_parsed_value(
            &mut lookup,
            KURA_METADATA_STORE_MAX_WRITE_BUFFERS,
            &mut invalid,
            |value| {
                value.parse::<i32>().map_err(|_| {
                    format!("{KURA_METADATA_STORE_MAX_WRITE_BUFFERS} must be a valid i32")
                })
            },
        )
        .unwrap_or(derived_defaults.metadata_store_max_write_buffers);
        if rocksdb_max_write_buffer_number <= 0 {
            invalid.push(format!(
                "{KURA_METADATA_STORE_MAX_WRITE_BUFFERS} must be greater than 0"
            ));
        }
        let outbox_max_depth =
            optional_parsed_value(&mut lookup, KURA_OUTBOX_MAX_DEPTH, &mut invalid, |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_OUTBOX_MAX_DEPTH} must be a valid usize"))
            })
            .unwrap_or(DEFAULT_OUTBOX_MAX_DEPTH);
        if outbox_max_depth == 0 {
            invalid.push(format!("{KURA_OUTBOX_MAX_DEPTH} must be greater than 0"));
        }
        let replication_bandwidth_limit_bytes_per_second = optional_parsed_value(
            &mut lookup,
            KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND,
            &mut invalid,
            |value| {
                value.parse::<u64>().map_err(|_| {
                    format!(
                        "{KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND} must be a valid u64"
                    )
                })
            },
        )
        .unwrap_or(DEFAULT_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND);
        let replication_public_latency_target_ms = optional_parsed_value(
            &mut lookup,
            KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS,
            &mut invalid,
            |value| {
                value.parse::<u64>().map_err(|_| {
                    format!("{KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS} must be a valid u64")
                })
            },
        )
        .unwrap_or(DEFAULT_REPLICATION_PUBLIC_LATENCY_TARGET_MS);
        let multipart_upload_ttl_ms = optional_parsed_value(
            &mut lookup,
            KURA_MULTIPART_UPLOAD_TTL_MS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_MULTIPART_UPLOAD_TTL_MS} must be a valid u64"))
            },
        )
        .unwrap_or(DEFAULT_MULTIPART_UPLOAD_TTL_MS);
        if multipart_upload_ttl_ms == 0 {
            invalid.push(format!(
                "{KURA_MULTIPART_UPLOAD_TTL_MS} must be greater than 0"
            ));
        }
        let multipart_janitor_interval_ms = optional_parsed_value(
            &mut lookup,
            KURA_MULTIPART_JANITOR_INTERVAL_MS,
            &mut invalid,
            |value| {
                value.parse::<u64>().map_err(|_| {
                    format!("{KURA_MULTIPART_JANITOR_INTERVAL_MS} must be a valid u64")
                })
            },
        )
        .unwrap_or(DEFAULT_MULTIPART_JANITOR_INTERVAL_MS);
        if multipart_janitor_interval_ms == 0 {
            invalid.push(format!(
                "{KURA_MULTIPART_JANITOR_INTERVAL_MS} must be greater than 0"
            ));
        }
        let bootstrap_timeout_ms = optional_parsed_value(
            &mut lookup,
            KURA_BOOTSTRAP_TIMEOUT_MS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_BOOTSTRAP_TIMEOUT_MS} must be a valid u64"))
            },
        )
        .unwrap_or(DEFAULT_BOOTSTRAP_TIMEOUT_MS);
        if bootstrap_timeout_ms == 0 {
            invalid.push(format!(
                "{KURA_BOOTSTRAP_TIMEOUT_MS} must be greater than 0"
            ));
        }
        let bootstrap_max_concurrent_peers = optional_parsed_value(
            &mut lookup,
            KURA_BOOTSTRAP_MAX_CONCURRENT_PEERS,
            &mut invalid,
            |value| {
                value.parse::<usize>().map_err(|_| {
                    format!("{KURA_BOOTSTRAP_MAX_CONCURRENT_PEERS} must be a valid usize")
                })
            },
        )
        .unwrap_or(DEFAULT_BOOTSTRAP_MAX_CONCURRENT_PEERS);
        if bootstrap_max_concurrent_peers == 0 {
            invalid.push(format!(
                "{KURA_BOOTSTRAP_MAX_CONCURRENT_PEERS} must be greater than 0"
            ));
        }
        let analytics_server_url = lookup(KURA_ANALYTICS_SERVER_URL)
            .map(|value| value.trim().trim_end_matches('/').to_owned())
            .filter(|value| !value.is_empty());
        let analytics_signing_key = lookup(KURA_ANALYTICS_SIGNING_KEY)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let analytics_batch_size = optional_parsed_value(
            &mut lookup,
            KURA_ANALYTICS_BATCH_SIZE,
            &mut invalid,
            |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_ANALYTICS_BATCH_SIZE} must be a valid usize"))
            },
        )
        .unwrap_or(100);
        if analytics_batch_size == 0 {
            invalid.push(format!(
                "{KURA_ANALYTICS_BATCH_SIZE} must be greater than 0"
            ));
        }
        let analytics_batch_timeout_ms = optional_parsed_value(
            &mut lookup,
            KURA_ANALYTICS_BATCH_TIMEOUT_MS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_ANALYTICS_BATCH_TIMEOUT_MS} must be a valid u64"))
            },
        )
        .unwrap_or(5_000);
        if analytics_batch_timeout_ms == 0 {
            invalid.push(format!(
                "{KURA_ANALYTICS_BATCH_TIMEOUT_MS} must be greater than 0"
            ));
        }
        let analytics_queue_capacity = optional_parsed_value(
            &mut lookup,
            KURA_ANALYTICS_QUEUE_CAPACITY,
            &mut invalid,
            |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_ANALYTICS_QUEUE_CAPACITY} must be a valid usize"))
            },
        )
        .unwrap_or(1_000);
        if analytics_queue_capacity == 0 {
            invalid.push(format!(
                "{KURA_ANALYTICS_QUEUE_CAPACITY} must be greater than 0"
            ));
        }
        let analytics_request_timeout_ms = optional_parsed_value(
            &mut lookup,
            KURA_ANALYTICS_REQUEST_TIMEOUT_MS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_ANALYTICS_REQUEST_TIMEOUT_MS} must be a valid u64"))
            },
        )
        .unwrap_or(5_000);
        if analytics_request_timeout_ms == 0 {
            invalid.push(format!(
                "{KURA_ANALYTICS_REQUEST_TIMEOUT_MS} must be greater than 0"
            ));
        }
        let analytics_circuit_breaker_failure_threshold = optional_parsed_value(
            &mut lookup,
            KURA_ANALYTICS_CIRCUIT_BREAKER_FAILURE_THRESHOLD,
            &mut invalid,
            |value| {
                value.parse::<usize>().map_err(|_| {
                    format!(
                        "{KURA_ANALYTICS_CIRCUIT_BREAKER_FAILURE_THRESHOLD} must be a valid usize"
                    )
                })
            },
        )
        .unwrap_or(5);
        if analytics_circuit_breaker_failure_threshold == 0 {
            invalid.push(format!(
                "{KURA_ANALYTICS_CIRCUIT_BREAKER_FAILURE_THRESHOLD} must be greater than 0"
            ));
        }
        let analytics_circuit_breaker_open_ms = optional_parsed_value(
            &mut lookup,
            KURA_ANALYTICS_CIRCUIT_BREAKER_OPEN_MS,
            &mut invalid,
            |value| {
                value.parse::<u64>().map_err(|_| {
                    format!("{KURA_ANALYTICS_CIRCUIT_BREAKER_OPEN_MS} must be a valid u64")
                })
            },
        )
        .unwrap_or(30_000);
        if analytics_circuit_breaker_open_ms == 0 {
            invalid.push(format!(
                "{KURA_ANALYTICS_CIRCUIT_BREAKER_OPEN_MS} must be greater than 0"
            ));
        }
        let analytics = match (analytics_server_url, analytics_signing_key) {
            (None, None) => None,
            (Some(server_url), Some(signing_key)) => match reqwest::Url::parse(&server_url) {
                Ok(_) => Some(AnalyticsConfig {
                    server_url,
                    signing_key,
                    batch_size: analytics_batch_size,
                    batch_timeout_ms: analytics_batch_timeout_ms,
                    queue_capacity: analytics_queue_capacity,
                    request_timeout_ms: analytics_request_timeout_ms,
                    circuit_breaker_failure_threshold: analytics_circuit_breaker_failure_threshold,
                    circuit_breaker_open_ms: analytics_circuit_breaker_open_ms,
                }),
                Err(error) => {
                    invalid.push(format!(
                        "{KURA_ANALYTICS_SERVER_URL} must be a valid URL: {error}"
                    ));
                    None
                }
            },
            _ => {
                invalid.push(format!(
                    "{KURA_ANALYTICS_SERVER_URL} and {KURA_ANALYTICS_SIGNING_KEY} must either both be set or both be unset"
                ));
                None
            }
        };
        let usage_window_secs =
            optional_parsed_value(&mut lookup, KURA_USAGE_WINDOW_SECS, &mut invalid, |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_USAGE_WINDOW_SECS} must be a valid u64"))
            })
            .unwrap_or(DEFAULT_USAGE_WINDOW_SECS);
        if usage_window_secs == 0 {
            invalid.push(format!("{KURA_USAGE_WINDOW_SECS} must be greater than 0"));
        }
        let usage_flush_interval_ms = optional_parsed_value(
            &mut lookup,
            KURA_USAGE_FLUSH_INTERVAL_MS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_USAGE_FLUSH_INTERVAL_MS} must be a valid u64"))
            },
        )
        .unwrap_or(DEFAULT_USAGE_FLUSH_INTERVAL_MS);
        if usage_flush_interval_ms == 0 {
            invalid.push(format!(
                "{KURA_USAGE_FLUSH_INTERVAL_MS} must be greater than 0"
            ));
        }
        let usage_delivery_interval_ms = optional_parsed_value(
            &mut lookup,
            KURA_USAGE_DELIVERY_INTERVAL_MS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_USAGE_DELIVERY_INTERVAL_MS} must be a valid u64"))
            },
        )
        .unwrap_or(DEFAULT_USAGE_DELIVERY_INTERVAL_MS);
        if usage_delivery_interval_ms == 0 {
            invalid.push(format!(
                "{KURA_USAGE_DELIVERY_INTERVAL_MS} must be greater than 0"
            ));
        }
        let usage_batch_size =
            optional_parsed_value(&mut lookup, KURA_USAGE_BATCH_SIZE, &mut invalid, |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_USAGE_BATCH_SIZE} must be a valid usize"))
            })
            .unwrap_or(DEFAULT_USAGE_BATCH_SIZE);
        if usage_batch_size == 0 {
            invalid.push(format!("{KURA_USAGE_BATCH_SIZE} must be greater than 0"));
        }
        let usage_max_buckets =
            optional_parsed_value(&mut lookup, KURA_USAGE_MAX_BUCKETS, &mut invalid, |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_USAGE_MAX_BUCKETS} must be a valid usize"))
            })
            .unwrap_or(DEFAULT_USAGE_MAX_BUCKETS);
        if usage_max_buckets == 0 {
            invalid.push(format!("{KURA_USAGE_MAX_BUCKETS} must be greater than 0"));
        }
        let usage_outbox_max_depth = optional_parsed_value(
            &mut lookup,
            KURA_USAGE_OUTBOX_MAX_DEPTH,
            &mut invalid,
            |value| {
                value
                    .parse::<usize>()
                    .map_err(|_| format!("{KURA_USAGE_OUTBOX_MAX_DEPTH} must be a valid usize"))
            },
        )
        .unwrap_or(DEFAULT_USAGE_OUTBOX_MAX_DEPTH);
        if usage_outbox_max_depth == 0 {
            invalid.push(format!(
                "{KURA_USAGE_OUTBOX_MAX_DEPTH} must be greater than 0"
            ));
        }
        let control_plane_url = lookup(KURA_CONTROL_PLANE_URL)
            .or_else(|| lookup(KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL))
            .map(|value| value.trim().trim_end_matches('/').to_owned())
            .filter(|value| !value.is_empty());
        let control_plane_client_id = lookup(KURA_CONTROL_PLANE_CLIENT_ID)
            .or_else(|| lookup(KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID))
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let control_plane_client_secret = lookup(KURA_CONTROL_PLANE_CLIENT_SECRET)
            .or_else(|| lookup(KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_SECRET))
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let usage = match (
            control_plane_url,
            control_plane_client_id,
            control_plane_client_secret,
        ) {
            (None, None, None) => None,
            (Some(control_plane_url), Some(client_id), Some(client_secret)) => {
                match reqwest::Url::parse(&control_plane_url) {
                    Ok(_) => Some(UsageConfig {
                        control_plane_url,
                        client_id,
                        client_secret,
                        window_secs: usage_window_secs,
                        flush_interval_ms: usage_flush_interval_ms,
                        delivery_interval_ms: usage_delivery_interval_ms,
                        batch_size: usage_batch_size,
                        max_buckets: usage_max_buckets,
                        outbox_max_depth: usage_outbox_max_depth,
                    }),
                    Err(error) => {
                        invalid.push(format!(
                            "{KURA_CONTROL_PLANE_URL} must be a valid URL: {error}"
                        ));
                        None
                    }
                }
            }
            _ => {
                invalid.push(format!(
                    "{KURA_CONTROL_PLANE_URL}, {KURA_CONTROL_PLANE_CLIENT_ID}, and {KURA_CONTROL_PLANE_CLIENT_SECRET} must either all be set or all be unset"
                ));
                None
            }
        };
        let geoip_refresh_interval_secs = optional_parsed_value(
            &mut lookup,
            KURA_GEOIP_REFRESH_INTERVAL_SECS,
            &mut invalid,
            |value| {
                value
                    .parse::<u64>()
                    .map_err(|_| format!("{KURA_GEOIP_REFRESH_INTERVAL_SECS} must be a valid u64"))
            },
        )
        .unwrap_or(DEFAULT_GEOIP_REFRESH_INTERVAL_SECS);
        let node_country_override = lookup(KURA_NODE_COUNTRY)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let node_subdivision_override = lookup(KURA_NODE_SUBDIVISION)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let otlp_traces_endpoint = lookup(KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let otel_service_name = required_value(&mut lookup, KURA_OTEL_SERVICE_NAME, &mut missing);
        let otel_deployment_environment =
            required_value(&mut lookup, KURA_OTEL_DEPLOYMENT_ENVIRONMENT, &mut missing);
        let sentry_dsn = lookup(KURA_SENTRY_DSN)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        if let Some(dsn) = sentry_dsn.as_deref()
            && let Err(error) = dsn.parse::<sentry::types::Dsn>()
        {
            invalid.push(format!(
                "{KURA_SENTRY_DSN} must be a valid Sentry DSN: {error}"
            ));
        }

        if let (Some(port), Some(grpc_port), Some(internal_port)) = (port, grpc_port, internal_port)
        {
            if internal_port == port {
                invalid.push(format!("{KURA_INTERNAL_PORT} must differ from {KURA_PORT}"));
            }
            if internal_port == grpc_port {
                invalid.push(format!(
                    "{KURA_INTERNAL_PORT} must differ from {KURA_GRPC_PORT}"
                ));
            }
            if public_tls.is_some() {
                if https_port == port {
                    invalid.push(format!("{KURA_HTTPS_PORT} must differ from {KURA_PORT}"));
                }
                if https_port == grpc_port {
                    invalid.push(format!(
                        "{KURA_HTTPS_PORT} must differ from {KURA_GRPC_PORT}"
                    ));
                }
                if https_port == internal_port {
                    invalid.push(format!(
                        "{KURA_HTTPS_PORT} must differ from {KURA_INTERNAL_PORT}"
                    ));
                }
            }
        }

        if let (Some(node_url), Some(peers), Some(internal_port)) =
            (node_url.as_ref(), peers.as_ref(), internal_port)
        {
            let expected_scheme = if peer_tls.is_some() { "https" } else { "http" };
            let scheme_error = if peer_tls.is_some() {
                format!("{KURA_NODE_URL} must use https when peer mTLS is enabled")
            } else {
                format!("{KURA_NODE_URL} must use http when peer mTLS is disabled")
            };
            match reqwest::Url::parse(node_url) {
                Ok(url) => {
                    let scheme = url.scheme();
                    let port = url.port_or_known_default();
                    if scheme != expected_scheme {
                        invalid.push(scheme_error.clone());
                    }
                    if port != Some(internal_port) {
                        invalid.push(format!("{KURA_NODE_URL} must target port {internal_port}"));
                    }
                }
                Err(error) => invalid.push(format!("{KURA_NODE_URL} must be a valid URL: {error}")),
            }

            for peer in peers.iter().map(String::as_str) {
                match reqwest::Url::parse(peer) {
                    Ok(url) => {
                        if url.scheme() != expected_scheme {
                            invalid.push(format!("peer URL {peer} must use {expected_scheme}"));
                        }
                        if url.port_or_known_default() != Some(internal_port) {
                            invalid
                                .push(format!("peer URL {peer} must target port {internal_port}"));
                        }
                    }
                    Err(error) => invalid.push(format!("peer URL {peer} must be valid: {error}")),
                }
            }
        }

        if !missing.is_empty() || !invalid.is_empty() {
            let mut errors = Vec::new();
            if !missing.is_empty() {
                errors.push(format!(
                    "missing required environment variables: {}",
                    missing.join(", ")
                ));
            }
            errors.extend(invalid);
            return Err(errors.join("; "));
        }

        Ok(Self {
            port: port.expect("port should be present when configuration is valid"),
            grpc_port: grpc_port.expect("grpc_port should be present when configuration is valid"),
            internal_port: internal_port
                .expect("internal_port should be present when configuration is valid"),
            tenant_id: tenant_id.expect("tenant_id should be present when configuration is valid"),
            region: region.expect("region should be present when configuration is valid"),
            tmp_dir: tmp_dir.expect("tmp_dir should be present when configuration is valid"),
            data_dir: data_dir.expect("data_dir should be present when configuration is valid"),
            node_url: node_url.expect("node_url should be present when configuration is valid"),
            peers: peers.expect("peers should be present when configuration is valid"),
            discovery_dns_name,
            peer_tls,
            grpc_tls,
            public_tls,
            https_port,
            accelerated_file_serving: accelerated_file_serving
                .expect("accelerated_file_serving should be present when configuration is valid"),
            file_descriptor_pool_size,
            file_descriptor_acquire_timeout_ms,
            drain_completion_timeout_ms,
            segment_handle_cache_size,
            memory_soft_limit_bytes,
            memory_hard_limit_bytes,
            manifest_cache_max_bytes,
            max_keyvalue_bytes,
            rocksdb_max_open_files,
            rocksdb_max_background_jobs,
            rocksdb_block_cache_bytes,
            rocksdb_write_buffer_manager_bytes,
            rocksdb_write_buffer_size_bytes,
            rocksdb_max_write_buffer_number,
            outbox_max_depth,
            replication_bandwidth_limit_bytes_per_second,
            replication_public_latency_target_ms,
            multipart_upload_ttl_ms,
            multipart_janitor_interval_ms,
            bootstrap_timeout_ms,
            bootstrap_max_concurrent_peers,
            analytics,
            usage,
            otlp_traces_endpoint,
            otel_service_name: otel_service_name
                .expect("otel_service_name should be present when configuration is valid"),
            otel_deployment_environment: otel_deployment_environment.expect(
                "otel_deployment_environment should be present when configuration is valid",
            ),
            sentry_dsn,
            geoip_refresh_interval_secs,
            node_country_override,
            node_subdivision_override,
        })
    }

    pub async fn ensure_directories(&self) -> Result<(), std::io::Error> {
        fs::create_dir_all(self.tmp_dir.join("uploads")).await?;
        fs::create_dir_all(self.tmp_dir.join("parts")).await?;
        fs::create_dir_all(self.data_dir.join("rocksdb")).await?;
        fs::create_dir_all(self.data_dir.join("blobs")).await?;
        fs::create_dir_all(self.data_dir.join("segments")).await?;
        fs::create_dir_all(self.data_dir.join("multipart")).await?;
        Ok(())
    }
}

fn required_value<F>(
    lookup: &mut F,
    key: &'static str,
    missing: &mut Vec<&'static str>,
) -> Option<String>
where
    F: FnMut(&str) -> Option<String>,
{
    match lookup(key) {
        Some(value) => Some(value),
        None => {
            missing.push(key);
            None
        }
    }
}

fn optional_parsed_value<T, F, P>(
    lookup: &mut F,
    key: &'static str,
    invalid: &mut Vec<String>,
    parse: P,
) -> Option<T>
where
    F: FnMut(&str) -> Option<String>,
    P: FnOnce(&str) -> Result<T, String>,
{
    let value = lookup(key)?;
    match parse(&value) {
        Ok(parsed) => Some(parsed),
        Err(error) => {
            invalid.push(error);
            None
        }
    }
}

fn clamp_usize(value: usize, min: usize, max: usize) -> usize {
    value.clamp(min, max)
}

fn clamp_bytes_to_usize(value: u64, min: u64, max: u64) -> usize {
    value.clamp(min, max).min(usize::MAX as u64) as usize
}

fn round_down_to_mib(value: u64) -> u64 {
    (value / BYTES_PER_MIB) * BYTES_PER_MIB
}

fn detect_cpu_count() -> usize {
    std::thread::available_parallelism()
        .map(|count| count.get())
        .unwrap_or(FALLBACK_HOST_CPU_COUNT)
}

fn detect_memory_limit_bytes() -> Option<u64> {
    let physical = detect_physical_memory_bytes();
    let cgroup = detect_cgroup_memory_limit_bytes();

    match (cgroup, physical) {
        (Some(cgroup_limit), Some(physical_limit)) if cgroup_limit > 0 => {
            Some(cgroup_limit.min(physical_limit))
        }
        (Some(cgroup_limit), None) if cgroup_limit > 0 => Some(cgroup_limit),
        (_, Some(physical_limit)) if physical_limit > 0 => Some(physical_limit),
        _ => None,
    }
}

fn detect_cgroup_memory_limit_bytes() -> Option<u64> {
    #[cfg(target_os = "linux")]
    {
        for path in [
            "/sys/fs/cgroup/memory.max",
            "/sys/fs/cgroup/memory/memory.limit_in_bytes",
        ] {
            let Ok(raw) = std::fs::read_to_string(path) else {
                continue;
            };
            let trimmed = raw.trim();
            if trimmed.is_empty() || trimmed == "max" {
                continue;
            }
            if let Ok(value) = trimmed.parse::<u64>()
                && value > 0
            {
                return Some(value);
            }
        }
        None
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

fn detect_physical_memory_bytes() -> Option<u64> {
    #[cfg(unix)]
    {
        let pages = unsafe { libc::sysconf(libc::_SC_PHYS_PAGES) };
        let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
        if pages <= 0 || page_size <= 0 {
            None
        } else {
            Some((pages as u64).saturating_mul(page_size as u64))
        }
    }
    #[cfg(not(unix))]
    {
        None
    }
}

fn detect_file_descriptor_limit() -> Option<usize> {
    #[cfg(unix)]
    {
        let mut limit = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        let result = unsafe { libc::getrlimit(libc::RLIMIT_NOFILE, &mut limit) };
        if result != 0 {
            return None;
        }
        if limit.rlim_cur == libc::RLIM_INFINITY {
            return Some(FALLBACK_HOST_FD_LIMIT);
        }
        Some((limit.rlim_cur as usize).max(256))
    }
    #[cfg(not(unix))]
    {
        None
    }
}

#[cfg(test)]
mod tests {
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
            (KURA_GRPC_PORT, "5500"),
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
        assert!(error.contains(KURA_GRPC_PORT));
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
        let config =
            config_from(&[]).expect("expected config defaults to derive from host resources");

        assert_eq!(config.internal_port, 7443);
        assert_eq!(
            config.peers,
            vec!["http://kura.example.com:7443".to_owned()]
        );
        assert_eq!(config.file_descriptor_pool_size, 256);
        assert_eq!(config.file_descriptor_acquire_timeout_ms, 5_000);
        assert_eq!(config.drain_completion_timeout_ms, 240_000);
        assert_eq!(config.segment_handle_cache_size, 64);
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
    fn from_lookup_parses_overrides() {
        let config = config_from(&[
            (KURA_PORT, "4500"),
            (KURA_GRPC_PORT, "5500"),
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
        assert_eq!(config.grpc_port, 5500);
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
        assert_eq!(config.grpc_tls, None);
        assert_eq!(config.file_descriptor_pool_size, 64);
        assert_eq!(config.file_descriptor_acquire_timeout_ms, 5000);
        assert_eq!(config.drain_completion_timeout_ms, 120000);
        assert_eq!(config.segment_handle_cache_size, 16);
        assert_eq!(config.memory_soft_limit_bytes, 268_435_456);
        assert_eq!(config.memory_hard_limit_bytes, 536_870_912);
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
            (KURA_GRPC_PORT, "5500"),
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
    fn from_lookup_parses_node_location_overrides() {
        let config = config_from(&[
            (KURA_PORT, "4500"),
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "invalid"),
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
        assert!(error.contains(KURA_GRPC_PORT));
        assert!(error.contains("valid u16"));
        assert!(error.contains(KURA_FILE_DESCRIPTOR_POOL_SIZE));
        assert!(error.contains(KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS));
        assert!(error.contains(KURA_DRAIN_COMPLETION_TIMEOUT_MS));
        assert!(error.contains(KURA_SEGMENT_HANDLE_CACHE_SIZE));
        assert!(error.contains(KURA_MEMORY_SOFT_LIMIT_BYTES));
        assert!(error.contains(KURA_MEMORY_HARD_LIMIT_BYTES));
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
            (KURA_GRPC_PORT, "5500"),
            (KURA_TENANT_ID, "acme"),
            (KURA_REGION, "eu_west"),
            (KURA_TMP_DIR, "/tmp/kura"),
            (KURA_DATA_DIR, "/tmp/kura-data"),
            (KURA_NODE_URL, "http://kura.example.com:7443"),
            (KURA_PEERS, "http://kura-a.example.com:7443"),
            (KURA_DISCOVERY_DNS_NAME, "kura-ring.internal"),
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
    }

    #[test]
    fn from_lookup_parses_optional_analytics_config() {
        let config = config_from(&[
            (KURA_PORT, "4500"),
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "5000"),
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
            (KURA_GRPC_PORT, "5000"),
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
            (KURA_GRPC_PORT, "5500"),
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
    fn from_lookup_parses_grpc_tls_config() {
        let config = config_from(&[
            (KURA_PORT, "4500"),
            (KURA_GRPC_PORT, "5500"),
            (KURA_TENANT_ID, "acme"),
            (KURA_REGION, "eu_west"),
            (KURA_TMP_DIR, "/tmp/kura"),
            (KURA_DATA_DIR, "/tmp/kura-data"),
            (KURA_NODE_URL, "http://kura.example.com:7443"),
            (KURA_PEERS, "http://kura-a.example.com:7443"),
            (KURA_INTERNAL_PORT, "7443"),
            (KURA_GRPC_TLS_CERT_PATH, "/etc/kura/grpc-tls/tls.crt"),
            (KURA_GRPC_TLS_KEY_PATH, "/etc/kura/grpc-tls/tls.key"),
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
        .expect("expected gRPC tls config to parse");

        assert_eq!(
            config.grpc_tls,
            Some(GrpcTlsConfig {
                cert_path: PathBuf::from("/etc/kura/grpc-tls/tls.crt"),
                key_path: PathBuf::from("/etc/kura/grpc-tls/tls.key"),
            })
        );
    }

    #[test]
    fn from_lookup_parses_public_tls_config() {
        let config = config_from(&[
            (KURA_PORT, "4500"),
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "5500"),
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
    fn from_lookup_requires_complete_grpc_tls_config() {
        let error = config_from(&[
            (KURA_PORT, "4500"),
            (KURA_GRPC_PORT, "5500"),
            (KURA_TENANT_ID, "acme"),
            (KURA_REGION, "eu_west"),
            (KURA_TMP_DIR, "/tmp/kura"),
            (KURA_DATA_DIR, "/tmp/kura-data"),
            (KURA_NODE_URL, "http://kura.example.com:7443"),
            (KURA_PEERS, "http://kura-a.example.com:7443"),
            (KURA_INTERNAL_PORT, "7443"),
            (KURA_GRPC_TLS_CERT_PATH, "/etc/kura/grpc-tls/tls.crt"),
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
        .expect_err("expected incomplete grpc tls config to fail");

        assert!(error.contains(KURA_GRPC_TLS_CERT_PATH));
        assert!(error.contains(KURA_GRPC_TLS_KEY_PATH));
    }

    #[test]
    fn from_lookup_requires_complete_peer_tls_config() {
        let error = config_from(&[
            (KURA_PORT, "4500"),
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "5500"),
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
            (KURA_GRPC_PORT, "5000"),
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

        config
            .ensure_directories()
            .await
            .expect("failed to create Kura directories");

        assert!(config.tmp_dir.join("uploads").exists());
        assert!(config.tmp_dir.join("parts").exists());
        assert!(config.data_dir.join("rocksdb").exists());
        assert!(config.data_dir.join("blobs").exists());
        assert!(config.data_dir.join("segments").exists());
        assert!(config.data_dir.join("multipart").exists());
    }
}
