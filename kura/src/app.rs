use std::{
    future::Future,
    net::{Ipv4Addr, SocketAddr},
    sync::Arc,
    time::Duration,
};

use axum_server::Handle;
use hyper_util::{
    rt::{TokioExecutor, TokioTimer},
    server::conn::auto::Builder as HttpBuilder,
};
use tokio::sync::{Notify, Semaphore, oneshot};
use tokio::{task::JoinHandle, time::Instant};
use tracing::{Instrument, info, warn};

use crate::{
    analytics::Analytics,
    bandwidth::BandwidthLimiter,
    config::Config,
    extension::ExtensionEngine,
    geoip::GeoIp,
    http,
    io::IoController,
    memory::{MemoryController, MemoryPressure},
    metrics::Metrics,
    node_location::resolve_node_location,
    peer_tls::{build_internal_rustls_config, build_peer_client, build_public_rustls_config},
    reapi,
    replication::{spawn_membership_task, spawn_outbox_task},
    runtime::{DataDirLock, RuntimeState},
    state::{AppState, ReadinessState},
    store::Store,
    telemetry::{init_tracing, log_context_span},
    usage::Usage,
};

const HTTP2_MAX_CONCURRENT_STREAMS: u32 = 128;
const HTTP2_INITIAL_STREAM_WINDOW_BYTES: u32 = 1024 * 1024;
const HTTP2_INITIAL_CONNECTION_WINDOW_BYTES: u32 = 16 * 1024 * 1024;
const HTTP2_MAX_FRAME_SIZE: u32 = 64 * 1024;
const HTTP2_MAX_SEND_BUFFER_BYTES: usize = 512 * 1024;
const HTTP2_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(30);
const HTTP2_KEEP_ALIVE_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Clone, Copy, Debug)]
struct ShutdownBudget {
    deadline: Instant,
}

impl ShutdownBudget {
    fn new(duration: Duration) -> Self {
        Self {
            deadline: Instant::now() + duration,
        }
    }

    fn remaining(self) -> Duration {
        self.deadline.saturating_duration_since(Instant::now())
    }
}

pub async fn run() -> Result<(), String> {
    let config = Config::from_env().map_err(|error| format!("invalid configuration: {error}"))?;
    let geoip = GeoIp::open();
    let node_location = resolve_node_location(
        config.node_country_override.as_deref(),
        config.node_subdivision_override.as_deref(),
        geoip.as_ref(),
        &config.region,
    )
    .await;
    let telemetry = init_tracing(&config, &node_location);
    let log_context = log_context_span(&config, &node_location);
    let result = run_with_config(config, geoip, node_location)
        .instrument(log_context)
        .await;

    telemetry.shutdown();
    result
}

async fn run_with_config(
    config: Config,
    geoip: Option<GeoIp>,
    node_location: crate::node_location::NodeLocation,
) -> Result<(), String> {
    if let Err(error) = raise_nofile_soft_to_hard() {
        tracing::warn!("failed to raise RLIMIT_NOFILE soft limit: {error}");
    }

    config
        .ensure_directories()
        .await
        .map_err(|error| format!("failed to create directories: {error}"))?;

    let metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
    metrics.record_node_geo(&node_location);
    let data_dir_lock = DataDirLock::acquire(&config.data_dir).inspect_err(|_| {
        metrics.record_writer_lock_acquire_failure();
    })?;
    let extension = ExtensionEngine::from_env(metrics.clone())
        .await
        .map_err(|error| format!("failed to initialize extension engine: {error}"))?;
    let analytics =
        Analytics::from_config(config.analytics.as_ref(), &config.node_url, metrics.clone())
            .map_err(|error| format!("failed to initialize analytics: {error}"))?;
    let usage = Usage::from_config(config.usage.as_ref(), &config.node_url, metrics.clone())
        .map_err(|error| format!("failed to initialize usage metering: {error}"))?;
    let io = IoController::new(
        metrics.clone(),
        config.file_descriptor_pool_size,
        Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
        vec![config.tmp_dir.clone(), config.data_dir.clone()],
    )?;
    let memory = MemoryController::new(
        metrics.clone(),
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let store = Store::open(&config, io.clone(), memory.clone())?;
    let client = build_peer_client(&config).await?;
    let runtime = RuntimeState::new();
    let replication_bandwidth_limiter = BandwidthLimiter::new(
        config.replication_bandwidth_limit_bytes_per_second,
        config.replication_public_latency_target_ms,
        runtime.clone(),
    )
    .map(Arc::new);
    let notify = Notify::new();

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
        geoip,
        client,
        replication_bandwidth_limiter,
        notify,
        readiness: tokio::sync::Mutex::new(ReadinessState::new(Instant::now())),
        bootstrap_semaphore,
    });
    state.sync_runtime_metrics().await;
    let drain_completion_timeout = Duration::from_millis(state.config.drain_completion_timeout_ms);

    spawn_membership_task(state.clone());
    spawn_outbox_task(state.clone());
    Usage::spawn_tasks(state.clone());
    spawn_snapshot_task(state.clone());
    spawn_runtime_metrics_task(state.clone());
    spawn_drain_signal_task(state.clone());
    spawn_multipart_janitor_task(state.clone());
    spawn_tmp_dir_metrics_task(state.clone());
    spawn_geoip_refresh_task(state.clone());

    let address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, state.config.port));
    let grpc_address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, state.config.grpc_port));
    let https_address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, state.config.https_port));
    info!("Kura service listening on {address}");
    if state.config.public_tls.is_some() {
        info!("Kura HTTPS service listening on {https_address} (TLS)");
    }
    if state.config.grpc_tls.is_some() {
        info!("Kura REAPI service listening on {grpc_address} (TLS)");
    } else {
        info!("Kura REAPI service listening on {grpc_address}");
    }
    let internal_address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, state.config.internal_port));
    if state.config.peer_tls.is_some() {
        info!("Kura internal mTLS service listening on {internal_address}");
    } else {
        info!("Kura internal HTTP service listening on {internal_address}");
    }

    let grpc_listener = tokio::net::TcpListener::bind(grpc_address)
        .await
        .map_err(|error| format!("failed to bind gRPC listener: {error}"))?;
    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(None::<ShutdownBudget>);
    let (shutdown_budget_tx, shutdown_budget_rx) = oneshot::channel::<ShutdownBudget>();
    let grpc_shutdown_rx = shutdown_rx.clone();
    let grpc_state = state.clone();
    let grpc_handle = tokio::spawn(
        async move {
            let grpc_shutdown = async move {
                let mut shutdown_rx = grpc_shutdown_rx;
                if shutdown_rx.borrow().is_some() {
                    return;
                }
                while shutdown_rx.changed().await.is_ok() {
                    if shutdown_rx.borrow().is_some() {
                        return;
                    }
                }
            };

            if let Err(error) = reapi::serve(grpc_listener, grpc_state, grpc_shutdown).await {
                tracing::error!("gRPC server failed: {error}");
            }
        }
        .in_current_span(),
    );

    let internal_handle = if let Some(peer_tls) = state.config.peer_tls.clone() {
        let tls_config = build_internal_rustls_config(&peer_tls).await?;
        let internal_router = http::internal_router(state.clone());
        let mut internal_shutdown_rx = shutdown_rx.clone();
        let handle = Handle::new();
        let shutdown_handle = handle.clone();
        tokio::spawn(
            async move {
                if let Some(budget) = *internal_shutdown_rx.borrow() {
                    shutdown_handle.graceful_shutdown(Some(budget.remaining()));
                    return;
                }
                while internal_shutdown_rx.changed().await.is_ok() {
                    if let Some(budget) = *internal_shutdown_rx.borrow() {
                        shutdown_handle.graceful_shutdown(Some(budget.remaining()));
                        return;
                    }
                }
            }
            .in_current_span(),
        );
        Some(tokio::spawn(
            async move {
                if let Err(error) = axum_server::bind_rustls(internal_address, tls_config)
                    .handle(handle)
                    .serve(internal_router.into_make_service())
                    .await
                {
                    tracing::error!("internal mTLS server failed: {error}");
                }
            }
            .in_current_span(),
        ))
    } else {
        let internal_router = http::internal_router(state.clone());
        let mut internal_shutdown_rx = shutdown_rx.clone();
        let handle = Handle::new();
        let shutdown_handle = handle.clone();
        tokio::spawn(
            async move {
                if let Some(budget) = *internal_shutdown_rx.borrow() {
                    shutdown_handle.graceful_shutdown(Some(budget.remaining()));
                    return;
                }
                while internal_shutdown_rx.changed().await.is_ok() {
                    if let Some(budget) = *internal_shutdown_rx.borrow() {
                        shutdown_handle.graceful_shutdown(Some(budget.remaining()));
                        return;
                    }
                }
            }
            .in_current_span(),
        );
        Some(tokio::spawn(
            async move {
                if let Err(error) = axum_server::bind(internal_address)
                    .handle(handle)
                    .serve(internal_router.into_make_service())
                    .await
                {
                    tracing::error!("internal server failed: {error}");
                }
            }
            .in_current_span(),
        ))
    };

    let router = http::public_router(state.clone());
    let public_handle = Handle::new();
    let https_handle = Handle::new();
    let public_shutdown_handle = public_handle.clone();
    let https_shutdown_handle = https_handle.clone();
    let public_shutdown_state = state.clone();
    tokio::spawn(
        async move {
            shutdown_signal().await;
            let budget = ShutdownBudget::new(drain_completion_timeout);
            let _ = shutdown_budget_tx.send(budget);
            let _ = public_shutdown_state.enter_draining();
            public_shutdown_state.sync_runtime_metrics().await;
            public_shutdown_handle.graceful_shutdown(Some(budget.remaining()));
            https_shutdown_handle.graceful_shutdown(Some(budget.remaining()));
        }
        .in_current_span(),
    );

    let https_handle_task = if let Some(public_tls) = state.config.public_tls.clone() {
        let tls_config = build_public_rustls_config(&public_tls).await?;
        let https_router = http::public_router(state.clone());
        Some(tokio::spawn(
            async move {
                let mut server =
                    axum_server::bind_rustls(https_address, tls_config).handle(https_handle);
                configure_public_http_builder(server.http_builder());
                if let Err(error) = server.serve(https_router.into_make_service()).await {
                    tracing::error!("public HTTPS server failed: {error}");
                }
            }
            .in_current_span(),
        ))
    } else {
        None
    };

    let mut public_server = axum_server::bind(address).handle(public_handle);
    configure_public_http_builder(public_server.http_builder());
    public_server
        .serve(router.into_make_service())
        .await
        .map_err(|error| format!("server error: {error}"))?;
    let shutdown_budget = shutdown_budget_rx.await.unwrap_or_else(|_| {
        warn!("shutdown budget channel closed before graceful shutdown completed");
        ShutdownBudget::new(drain_completion_timeout)
    });
    let _ = shutdown_tx.send(Some(shutdown_budget));
    let drained = wait_for_inflight_drain(state.clone(), shutdown_budget).await;
    if !drained {
        warn!(
            http_inflight = state.runtime.http_inflight(),
            grpc_inflight = state.runtime.grpc_inflight(),
            drain_timeout_ms = state.config.drain_completion_timeout_ms,
            "timed out waiting for inflight requests to drain during shutdown"
        );
    }
    wait_for_task_shutdown(grpc_handle, "gRPC", shutdown_budget).await;
    if let Some(internal_handle) = internal_handle {
        wait_for_task_shutdown(internal_handle, "internal", shutdown_budget).await;
    }
    if let Some(https_handle_task) = https_handle_task {
        wait_for_task_shutdown(https_handle_task, "public HTTPS", shutdown_budget).await;
    }

    Ok(())
}

fn configure_public_http_builder(builder: &mut HttpBuilder<TokioExecutor>) {
    builder
        .http1()
        .keep_alive(true)
        .timer(TokioTimer::new())
        .header_read_timeout(Some(Duration::from_secs(30)));
    builder
        .http2()
        .initial_stream_window_size(Some(HTTP2_INITIAL_STREAM_WINDOW_BYTES))
        .initial_connection_window_size(Some(HTTP2_INITIAL_CONNECTION_WINDOW_BYTES))
        .adaptive_window(true)
        .max_concurrent_streams(Some(HTTP2_MAX_CONCURRENT_STREAMS))
        .max_frame_size(Some(HTTP2_MAX_FRAME_SIZE))
        .max_send_buf_size(HTTP2_MAX_SEND_BUFFER_BYTES)
        .keep_alive_interval(Some(HTTP2_KEEP_ALIVE_INTERVAL))
        .keep_alive_timeout(HTTP2_KEEP_ALIVE_TIMEOUT)
        .timer(TokioTimer::new());
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };

    #[cfg(unix)]
    let terminate = async {
        let mut signal = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler");
        signal.recv().await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    wait_for_shutdown_signal(ctrl_c, terminate).await;
}

fn spawn_snapshot_task(state: Arc<AppState>) {
    tokio::spawn(
        async move {
            loop {
                let worker_state = state.clone();
                match tokio::task::spawn_blocking(move || {
                    let snapshot = worker_state.store.snapshot();
                    let memory = process_memory_snapshot();
                    (snapshot, memory)
                })
                .await
                {
                    Ok((Ok(snapshot), memory)) => {
                        state
                            .metrics
                            .update_outbox_messages(snapshot.outbox_messages);
                        state.runtime.update_outbox_depth(snapshot.outbox_messages);
                        state
                            .metrics
                            .update_multipart_uploads(snapshot.multipart_uploads);
                        for (generation, count) in snapshot.segment_counts {
                            state
                                .metrics
                                .update_segment_generation_count(generation, count);
                        }
                        state.metrics.update_rocksdb_memory(
                            snapshot.rocksdb_block_cache_usage_bytes,
                            snapshot.rocksdb_block_cache_pinned_usage_bytes,
                            snapshot.rocksdb_block_cache_capacity_bytes,
                            snapshot.rocksdb_write_buffer_usage_bytes,
                            snapshot.rocksdb_write_buffer_capacity_bytes,
                        );
                        if let Some(memory) = memory {
                            state
                                .metrics
                                .update_process_memory(memory.resident_bytes, memory.virtual_bytes);
                            let pressure = state.memory.observe(memory.resident_bytes);
                            let target_bytes = state
                                .memory
                                .manifest_cache_target_bytes(state.config.manifest_cache_max_bytes);
                            let evicted =
                                state.store.trim_manifest_cache_to(target_bytes, "pressure");
                            if evicted > 0 {
                                state.metrics.record_memory_action("manifest_cache_trim");
                            }
                            let existence_evicted = state.store.trim_existence_cache_to(
                                state.memory.bounded_cache_target_entries(
                                    crate::store::EXISTENCE_CACHE_CAPACITY,
                                ),
                            );
                            if existence_evicted > 0 {
                                state.metrics.record_memory_action("existence_cache_trim");
                            }
                            let segment_handle_evicted = state
                                .store
                                .trim_segment_handle_cache_to(
                                    state.memory.bounded_cache_target_entries(
                                        state.config.segment_handle_cache_size,
                                    ),
                                    "pressure",
                                )
                                .await;
                            if segment_handle_evicted > 0 {
                                state
                                    .metrics
                                    .record_memory_action("segment_handle_cache_trim");
                            }
                            if pressure == MemoryPressure::Critical
                                && let Some(extension) = &state.extension
                            {
                                let evicted = extension.clear_caches().await;
                                if evicted > 0 {
                                    state.metrics.record_memory_action("extension_cache_trim");
                                }
                            }
                            state.metrics.update_background_work_paused(
                                "outbox",
                                state.memory.pause_outbox(),
                            );
                            state.metrics.update_background_work_paused(
                                "segment_refresh",
                                !state.memory.allow_segment_refresh(),
                            );
                            state
                                .metrics
                                .update_memory_pressure_state(pressure.as_i64());
                        }
                    }
                    Ok((Err(error), _)) => {
                        tracing::warn!("failed to collect store snapshot metrics: {error}");
                    }
                    Err(error) => {
                        tracing::warn!("snapshot metrics task failed: {error}");
                    }
                }

                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
        .in_current_span(),
    );
}

fn spawn_runtime_metrics_task(state: Arc<AppState>) {
    tokio::spawn(
        async move {
            loop {
                state.sync_runtime_metrics().await;
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        }
        .in_current_span(),
    );
}

fn spawn_multipart_janitor_task(state: Arc<AppState>) {
    let interval = Duration::from_millis(state.config.multipart_janitor_interval_ms);
    let ttl_ms = state.config.multipart_upload_ttl_ms;
    tokio::spawn(
        async move {
            loop {
                tokio::time::sleep(interval).await;
                let now = crate::utils::now_ms();
                let cutoff_ms = now.saturating_sub(ttl_ms);
                let stale = match state.store.multipart_uploads_older_than(cutoff_ms) {
                    Ok(stale) => stale,
                    Err(error) => {
                        warn!("multipart janitor scan failed: {error}");
                        continue;
                    }
                };
                if stale.is_empty() {
                    continue;
                }
                for upload_id in &stale {
                    if let Err(error) = state.store.abort_multipart_upload(upload_id).await {
                        warn!("multipart janitor failed to expire {upload_id}: {error}");
                    }
                }
                state
                    .metrics
                    .record_memory_action("multipart_janitor_pruned");
                info!(
                    ttl_ms,
                    expired = stale.len(),
                    "multipart janitor pruned stale uploads"
                );
            }
        }
        .in_current_span(),
    );
}

fn spawn_tmp_dir_metrics_task(state: Arc<AppState>) {
    tokio::spawn(
        async move {
            loop {
                tokio::time::sleep(Duration::from_secs(30)).await;
                let tmp_dir = state.config.tmp_dir.clone();
                let bytes = tokio::task::spawn_blocking(move || directory_size_bytes(&tmp_dir))
                    .await
                    .unwrap_or(0);
                state.metrics.update_tmp_dir_bytes(bytes);
            }
        }
        .in_current_span(),
    );
}

fn spawn_geoip_refresh_task(state: Arc<AppState>) {
    if state.geoip.is_none() {
        return;
    }
    let interval_secs = state.config.geoip_refresh_interval_secs;
    if interval_secs == 0 {
        info!("GeoIP background refresh disabled");
        return;
    }
    let http = match reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(60))
        .build()
    {
        Ok(client) => client,
        Err(error) => {
            warn!("failed to build GeoIP refresh client: {error}");
            return;
        }
    };
    let interval = Duration::from_secs(interval_secs);
    tokio::spawn(
        async move {
            loop {
                tokio::time::sleep(interval).await;
                let geoip = state
                    .geoip
                    .as_ref()
                    .expect("geoip presence checked before spawning the refresh task");
                let outcome = geoip.refresh(&http).await;
                state.metrics.record_geoip_refresh(outcome.as_str());
                if matches!(outcome, crate::geoip::RefreshOutcome::Updated) {
                    info!("GeoIP database refreshed");
                }
            }
        }
        .in_current_span(),
    );
}

#[cfg(unix)]
fn raise_nofile_soft_to_hard() -> Result<(), String> {
    let mut limit = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    let read = unsafe { libc::getrlimit(libc::RLIMIT_NOFILE, &mut limit) };
    if read != 0 {
        return Err(format!(
            "getrlimit failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    if limit.rlim_cur >= limit.rlim_max {
        return Ok(());
    }
    let target = libc::rlimit {
        rlim_cur: limit.rlim_max,
        rlim_max: limit.rlim_max,
    };
    let set = unsafe { libc::setrlimit(libc::RLIMIT_NOFILE, &target) };
    if set != 0 {
        return Err(format!(
            "setrlimit failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    info!(
        previous_soft = limit.rlim_cur,
        new_soft = target.rlim_cur,
        "raised RLIMIT_NOFILE soft limit to hard limit"
    );
    Ok(())
}

#[cfg(not(unix))]
fn raise_nofile_soft_to_hard() -> Result<(), String> {
    Ok(())
}

fn directory_size_bytes(path: &std::path::Path) -> u64 {
    let mut total = 0_u64;
    let mut stack = vec![path.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = match std::fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_dir() {
                stack.push(entry.path());
            } else if let Ok(metadata) = entry.metadata() {
                total = total.saturating_add(metadata.len());
            }
        }
    }
    total
}

#[cfg(unix)]
fn spawn_drain_signal_task(state: Arc<AppState>) {
    tokio::spawn(
        async move {
            let mut signal =
                tokio::signal::unix::signal(tokio::signal::unix::SignalKind::user_defined1())
                    .expect("failed to install SIGUSR1 handler");
            loop {
                if signal.recv().await.is_none() {
                    return;
                }
                if state.enter_draining() {
                    state.sync_runtime_metrics().await;
                    info!("received SIGUSR1, entering draining state");
                }
            }
        }
        .in_current_span(),
    );
}

#[cfg(not(unix))]
fn spawn_drain_signal_task(_state: Arc<AppState>) {}

struct ProcessMemorySnapshot {
    resident_bytes: u64,
    virtual_bytes: u64,
}

#[cfg(target_os = "linux")]
fn process_memory_snapshot() -> Option<ProcessMemorySnapshot> {
    let status = std::fs::read_to_string("/proc/self/status").ok()?;
    let resident_bytes = parse_status_memory_kib(&status, "VmRSS:")?.saturating_mul(1024);
    let virtual_bytes = parse_status_memory_kib(&status, "VmSize:")?.saturating_mul(1024);
    Some(ProcessMemorySnapshot {
        resident_bytes,
        virtual_bytes,
    })
}

#[cfg(not(target_os = "linux"))]
fn process_memory_snapshot() -> Option<ProcessMemorySnapshot> {
    None
}

#[cfg(target_os = "linux")]
fn parse_status_memory_kib(status: &str, field: &str) -> Option<u64> {
    status
        .lines()
        .find_map(|line| line.strip_prefix(field))
        .and_then(|value| value.split_whitespace().next())
        .and_then(|value| value.parse::<u64>().ok())
}

async fn wait_for_shutdown_signal<C, T>(ctrl_c: C, terminate: T)
where
    C: Future<Output = ()>,
    T: Future<Output = ()>,
{
    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}

async fn wait_for_inflight_drain(state: Arc<AppState>, budget: ShutdownBudget) -> bool {
    loop {
        let inflight_changed = state.runtime.inflight_changed();
        if state.runtime.total_inflight() == 0 {
            return true;
        }

        let remaining = budget.remaining();
        if remaining.is_zero() {
            return false;
        }

        if tokio::time::timeout(remaining, inflight_changed)
            .await
            .is_err()
        {
            return false;
        }
    }
}

async fn wait_for_task_shutdown<T>(
    mut handle: JoinHandle<T>,
    server: &str,
    budget: ShutdownBudget,
) {
    let remaining = budget.remaining();
    match tokio::time::timeout(remaining, &mut handle).await {
        Ok(Ok(_)) => {}
        Ok(Err(error)) => {
            warn!("{server} server task ended unexpectedly: {error}");
        }
        Err(_) => {
            warn!(
                timeout_ms = remaining.as_millis(),
                "timed out waiting for {server} server to shut down; aborting task"
            );
            handle.abort();
            let _ = handle.await;
        }
    }
}

#[cfg(test)]
mod tests {
    use tokio::{sync::oneshot, time::timeout};

    use super::*;
    use crate::test_support::test_context;

    #[test]
    fn public_http_builder_accepts_http1_and_http2() {
        let mut builder = HttpBuilder::new(TokioExecutor::new());

        configure_public_http_builder(&mut builder);

        assert!(builder.is_http1_available());
        assert!(builder.is_http2_available());
    }

    #[tokio::test]
    async fn wait_for_shutdown_signal_returns_when_ctrl_c_resolves() {
        let (ctrl_c_tx, ctrl_c_rx) = oneshot::channel::<()>();
        let (_terminate_tx, terminate_rx) = oneshot::channel::<()>();

        let waiter = tokio::spawn(wait_for_shutdown_signal(
            async move {
                let _ = ctrl_c_rx.await;
            },
            async move {
                let _ = terminate_rx.await;
            },
        ));

        ctrl_c_tx.send(()).expect("ctrl-c sender should be open");

        timeout(Duration::from_secs(1), waiter)
            .await
            .expect("shutdown waiter should return after ctrl-c")
            .expect("shutdown waiter task should finish cleanly");
    }

    #[tokio::test]
    async fn wait_for_shutdown_signal_returns_when_terminate_resolves() {
        let (_ctrl_c_tx, ctrl_c_rx) = oneshot::channel::<()>();
        let (terminate_tx, terminate_rx) = oneshot::channel::<()>();

        let waiter = tokio::spawn(wait_for_shutdown_signal(
            async move {
                let _ = ctrl_c_rx.await;
            },
            async move {
                let _ = terminate_rx.await;
            },
        ));

        terminate_tx
            .send(())
            .expect("terminate sender should be open");

        timeout(Duration::from_secs(1), waiter)
            .await
            .expect("shutdown waiter should return after terminate")
            .expect("shutdown waiter task should finish cleanly");
    }

    #[tokio::test]
    async fn wait_for_inflight_drain_returns_when_requests_finish() {
        let context = test_context(|_| {}).await;
        let guard = context
            .state
            .start_http_request(crate::runtime::HttpTrafficClass::Public);
        let waiter = tokio::spawn(wait_for_inflight_drain(
            context.state.clone(),
            ShutdownBudget::new(Duration::from_millis(250)),
        ));

        tokio::time::sleep(Duration::from_millis(20)).await;
        drop(guard);

        assert!(
            waiter
                .await
                .expect("wait task should finish after request completion")
        );
    }

    #[tokio::test]
    async fn wait_for_inflight_drain_times_out_when_requests_do_not_finish() {
        let context = test_context(|_| {}).await;
        let _guard = context.state.start_grpc_request();

        assert!(
            !wait_for_inflight_drain(
                context.state.clone(),
                ShutdownBudget::new(Duration::from_millis(25)),
            )
            .await
        );
    }
}
