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
use tokio::sync::{Notify, Semaphore, oneshot, watch};
use tokio::{task::JoinHandle, time::Instant};
use tracing::{Instrument, info, warn};

use crate::{
    accelerated_file_serving,
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
    peer_tls::{build_internal_rustls_config, build_public_rustls_config},
    reapi,
    replication::{spawn_membership_task, spawn_outbox_task},
    runtime::{DataDirLock, RuntimeState},
    state::{AppState, ReadinessState},
    store::Store,
    telemetry::{init_tracing, log_context_span},
    usage::Usage,
    utils::directory_size_bytes,
};

const HTTP2_MAX_CONCURRENT_STREAMS: u32 = 128;
const HTTP2_INITIAL_STREAM_WINDOW_BYTES: u32 = 1024 * 1024;
const HTTP2_INITIAL_CONNECTION_WINDOW_BYTES: u32 = 16 * 1024 * 1024;
const HTTP2_MAX_FRAME_SIZE: u32 = 64 * 1024;
const HTTP2_MAX_SEND_BUFFER_BYTES: usize = 512 * 1024;
const HTTP2_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(30);
const HTTP2_KEEP_ALIVE_TIMEOUT: Duration = Duration::from_secs(20);

// The combined HTTP+gRPC listener carries large Bazel REAPI uploads, so it pins
// the REAPI server's 4 MiB stream window instead of the smaller public-HTTP one,
// which would cap a single ByteStream write at ~window/RTT. It reuses the shared
// 16 MiB connection window. Kept in sync with REAPI_HTTP2_STREAM_WINDOW_BYTES.
const COMBINED_HTTP2_STREAM_WINDOW_BYTES: u32 = 4 * 1024 * 1024;

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
    let nofile_raise_error = raise_nofile_soft_to_hard().err();

    let enrollment = crate::enrollment::enroll_on_boot().await?;

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
    if let Some(error) = nofile_raise_error {
        warn!("failed to raise RLIMIT_NOFILE soft limit: {error}");
    }
    let log_context = log_context_span(&config, &node_location);
    let result = run_with_config(config, geoip, node_location, enrollment)
        .instrument(log_context)
        .await;

    telemetry.shutdown();
    result
}

async fn run_with_config(
    config: Config,
    geoip: Option<GeoIp>,
    node_location: crate::node_location::NodeLocation,
    enrollment: Option<crate::enrollment::EnrollmentOutcome>,
) -> Result<(), String> {
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
    match store.sweep_orphaned_segments().await {
        Ok(0) => {}
        Ok(swept) => tracing::info!(swept, "removed orphaned segment files"),
        Err(error) => tracing::warn!("failed to sweep orphaned segments: {error}"),
    }
    let peer_client_factory = crate::peer_tls::PeerClientFactory::from_config(&config).await?;
    let client = peer_client_factory.build()?;
    let internal_tls = match &config.peer_tls {
        Some(peer_tls) => Some(build_internal_rustls_config(peer_tls).await?),
        None => None,
    };
    let runtime = RuntimeState::new();
    let replication_bandwidth_limiter = BandwidthLimiter::new(
        config.replication_bandwidth_limit_bytes_per_second,
        config.replication_public_latency_target_ms,
        runtime.clone(),
    )
    .map(Arc::new);
    let notify = Notify::new();

    let bootstrap_semaphore = Arc::new(Semaphore::new(config.bootstrap_max_concurrent_peers));
    let bootstrap_staging_budget = crate::utils::TmpBudget::new(config.tmp_dir_max_bytes);
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
        client: arc_swap::ArcSwap::from_pointee(client),
        peer_client_factory,
        internal_tls,
        dynamic_peers: arc_swap::ArcSwap::from_pointee(Vec::new()),
        replication_bandwidth_limiter,
        notify,
        readiness: tokio::sync::Mutex::new(ReadinessState::new(Instant::now())),
        bootstrap_semaphore,
        bootstrap_staging_budget,
        bootstrap_fetch_locks: (0..crate::constants::BOOTSTRAP_FETCH_LOCK_STRIPES)
            .map(|_| tokio::sync::Mutex::new(()))
            .collect(),
        replication_backoff: tokio::sync::Mutex::new(std::collections::HashMap::new()),
    });
    state.sync_runtime_metrics().await;
    let drain_completion_timeout = Duration::from_millis(state.config.drain_completion_timeout_ms);

    spawn_membership_task(state.clone());
    spawn_outbox_task(state.clone());
    Usage::spawn_tasks(state.clone());

    if let Some(registration) =
        crate::registration::RegistrationConfig::from_env(&state.config.node_url)
    {
        crate::registration::spawn(state.clone(), registration);
    }

    spawn_snapshot_task(state.clone());
    spawn_runtime_metrics_task(state.clone());
    spawn_drain_signal_task(state.clone());
    spawn_multipart_janitor_task(state.clone());
    spawn_tmp_dir_metrics_task(state.clone());
    spawn_geoip_refresh_task(state.clone());

    // When the node enrolled on boot, keep its peer certificate fresh in-process
    // so a short leaf does not require a restart.
    if let Some(enrollment) = enrollment
        && state.config.peer_tls.is_some()
    {
        state
            .dynamic_peers
            .store(std::sync::Arc::new(enrollment.peers.clone()));
        spawn_cert_renewal_task(state.clone(), enrollment.renew_after_seconds);
    }

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

    let internal_handle = if state.config.peer_tls.is_some() {
        let tls_config = state
            .internal_tls
            .clone()
            .expect("internal_tls is present whenever peer_tls is configured");
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
    let combined_handle = Handle::new();
    let public_shutdown_handle = public_handle.clone();
    let https_shutdown_handle = https_handle.clone();
    let combined_shutdown_handle = combined_handle.clone();
    let public_shutdown_state = state.clone();
    let (public_plain_shutdown_tx, public_plain_shutdown_rx) = watch::channel(false);
    let (combined_plain_shutdown_tx, combined_plain_shutdown_rx) = watch::channel(false);
    tokio::spawn(
        async move {
            shutdown_signal().await;
            let budget = ShutdownBudget::new(drain_completion_timeout);
            let _ = shutdown_budget_tx.send(budget);
            let _ = public_shutdown_state.enter_draining();
            public_shutdown_state.sync_runtime_metrics().await;
            let _ = public_plain_shutdown_tx.send(true);
            // The combined listener runs either the accelerated server (watch
            // channel) or the axum fallback (handle); signal both, whichever is
            // bound. No-ops when the combined listener is disabled.
            let _ = combined_plain_shutdown_tx.send(true);
            public_shutdown_handle.graceful_shutdown(Some(budget.remaining()));
            https_shutdown_handle.graceful_shutdown(Some(budget.remaining()));
            combined_shutdown_handle.graceful_shutdown(Some(budget.remaining()));
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

    // Optional additive listener that co-hosts the HTTP cache API and the h2c
    // REAPI gRPC service on one port, dispatching by request path. It lets a
    // single client-facing endpoint (e.g. the runner-cache URL) serve both
    // protocols, so a client that derives its gRPC target from the cache URL
    // reaches REAPI instead of the plain-HTTP listener. The dedicated
    // `port`/`grpc_port` listeners are unaffected and keep serving.
    //
    // Three modes, in precedence order:
    //   * TLS (when `public_tls` is set): terminates TLS with the public cert
    //     and serves HTTP + gRPC over one TLS port, ALPN-negotiated (`h2` for
    //     gRPC, `http/1.1` for HTTP). TLS is incompatible with the sendfile
    //     accelerator, so it uses the plain hyper path like the HTTPS listener.
    //   * accelerated plaintext: routes through the same accelerated server as
    //     the public port, so HTTP/1 artifact GETs get the sendfile/splice fast
    //     path and gRPC (h2c) / other requests fall through to hyper.
    //   * plain plaintext: the merged router over the axum builder.
    // All modes use the fixed gRPC-sized HTTP/2 windows so co-hosted REAPI
    // uploads run at full speed.
    let combined_handle_task = if let Some(combined_port) = state.config.combined_port {
        let combined_address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, combined_port));
        let combined_router =
            http::public_router(state.clone()).merge(reapi::routes(state.clone()));
        if let Some(public_tls) = state.config.public_tls.clone() {
            info!("Kura combined HTTP+gRPC service listening on {combined_address} (TLS)");
            let tls_config = build_public_rustls_config(&public_tls).await?;
            Some(tokio::spawn(
                async move {
                    let mut server =
                        axum_server::bind_rustls(combined_address, tls_config).handle(combined_handle);
                    configure_combined_http_builder(server.http_builder());
                    if let Err(error) = server.serve(combined_router.into_make_service()).await {
                        tracing::error!("combined HTTP+gRPC server failed: {error}");
                    }
                }
                .in_current_span(),
            ))
        } else if state.config.accelerated_file_serving.enabled {
            info!("Kura combined HTTP+gRPC service listening on {combined_address}");
            let combined_state = state.clone();
            let combined_config = state.config.accelerated_file_serving.clone();
            Some(tokio::spawn(
                async move {
                    if let Err(error) = accelerated_file_serving::serve_public_http(
                        combined_address,
                        combined_router,
                        combined_state,
                        combined_config,
                        combined_plain_shutdown_rx,
                        configure_combined_http_builder,
                    )
                    .await
                    {
                        tracing::error!("combined HTTP+gRPC server failed: {error}");
                    }
                }
                .in_current_span(),
            ))
        } else {
            info!("Kura combined HTTP+gRPC service listening on {combined_address}");
            Some(tokio::spawn(
                async move {
                    let mut server = axum_server::bind(combined_address).handle(combined_handle);
                    configure_combined_http_builder(server.http_builder());
                    if let Err(error) = server.serve(combined_router.into_make_service()).await {
                        tracing::error!("combined HTTP+gRPC server failed: {error}");
                    }
                }
                .in_current_span(),
            ))
        }
    } else {
        None
    };

    if state.config.accelerated_file_serving.enabled {
        accelerated_file_serving::serve_public_http(
            address,
            router,
            state.clone(),
            state.config.accelerated_file_serving.clone(),
            public_plain_shutdown_rx,
            configure_public_http_builder,
        )
        .await
        .map_err(|error| format!("server error: {error}"))?;
    } else {
        let mut public_server = axum_server::bind(address).handle(public_handle);
        configure_public_http_builder(public_server.http_builder());
        public_server
            .serve(router.into_make_service())
            .await
            .map_err(|error| format!("server error: {error}"))?;
    }
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
    if let Some(combined_handle_task) = combined_handle_task {
        wait_for_task_shutdown(combined_handle_task, "combined HTTP+gRPC", shutdown_budget).await;
    }

    Ok(())
}

// Shared HTTP/1 + HTTP/2 tuning for the plaintext auto-negotiating listeners.
// `stream_window` and `adaptive` are the only knobs that differ between them, so
// they are explicit parameters — `adaptive` in particular, because hyper's
// `adaptive_window(true)` OVERRIDES the fixed `initial_stream_window_size` and
// ramps a single stream up from hyper's ~64KB default, which under WAN latency
// halves single-stream REAPI upload throughput (measured 9.84 vs 20.65 MB/s at
// 100ms RTT). The combined port must therefore pin a fixed window (adaptive =
// false); the public port keeps its adaptive one.
fn configure_http_builder(
    builder: &mut HttpBuilder<TokioExecutor>,
    stream_window: u32,
    adaptive: bool,
) {
    builder
        .http1()
        .keep_alive(true)
        .timer(TokioTimer::new())
        .header_read_timeout(Some(Duration::from_secs(30)));
    let mut http2 = builder.http2();
    http2
        .initial_stream_window_size(Some(stream_window))
        .initial_connection_window_size(Some(HTTP2_INITIAL_CONNECTION_WINDOW_BYTES))
        .max_concurrent_streams(Some(HTTP2_MAX_CONCURRENT_STREAMS))
        .max_frame_size(Some(HTTP2_MAX_FRAME_SIZE))
        .max_send_buf_size(HTTP2_MAX_SEND_BUFFER_BYTES)
        .keep_alive_interval(Some(HTTP2_KEEP_ALIVE_INTERVAL))
        .keep_alive_timeout(HTTP2_KEEP_ALIVE_TIMEOUT)
        .timer(TokioTimer::new());
    if adaptive {
        http2.adaptive_window(true);
    }
}

fn configure_public_http_builder(builder: &mut HttpBuilder<TokioExecutor>) {
    configure_http_builder(builder, HTTP2_INITIAL_STREAM_WINDOW_BYTES, true);
}

// The combined listener co-hosts REAPI gRPC, so it pins a fixed window (see
// `configure_http_builder`) — never adaptive. The auto builder serves HTTP/1.1
// and HTTP/2 (incl. h2c prior-knowledge), so one listener handles cache + gRPC.
fn configure_combined_http_builder(builder: &mut HttpBuilder<TokioExecutor>) {
    configure_http_builder(builder, COMBINED_HTTP2_STREAM_WINDOW_BYTES, false);
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
                        state
                            .metrics
                            .update_segment_fsyncs(snapshot.segment_fsync_count);
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

// Re-enrolls before the peer certificate's leaf expires and hot-reloads the new
// material into both the inbound mTLS server and the outbound peer client, so a
// short leaf never requires a restart.
fn spawn_cert_renewal_task(state: Arc<AppState>, initial_renew_after_seconds: u64) {
    tokio::spawn(
        async move {
            let mut renew_after = initial_renew_after_seconds.max(60);
            loop {
                tokio::time::sleep(Duration::from_secs(renew_after)).await;
                match crate::enrollment::renew().await {
                    Ok(outcome) => match apply_renewed_certs(&state, &outcome).await {
                        Ok(()) => {
                            info!("renewed peer certificate");
                            renew_after = outcome.renew_after_seconds.max(60);
                        }
                        Err(error) => {
                            warn!("cert renewal: failed to apply new certificate: {error}");
                            renew_after = 60;
                        }
                    },
                    Err(error) => {
                        warn!("cert renewal failed: {error}; retrying in 60s");
                        renew_after = 60;
                    }
                }
            }
        }
        .in_current_span(),
    );
}

async fn apply_renewed_certs(
    state: &Arc<AppState>,
    outcome: &crate::enrollment::EnrollmentOutcome,
) -> Result<(), String> {
    // Outbound: reload the peer identity and rebuild the cached client so new
    // dials use the renewed certificate.
    state
        .peer_client_factory
        .reload_from_config(&state.config)
        .await?;
    let new_client = state.peer_client_factory.build()?;
    state.client.store(Arc::new(new_client));

    // Inbound: rebuild the internal mTLS server config (preserving the client
    // verifier) and hot-swap the leaf.
    if let (Some(peer_tls), Some(rustls)) = (&state.config.peer_tls, &state.internal_tls) {
        let server_config = crate::peer_tls::build_internal_server_config(peer_tls).await?;
        rustls.reload_from_config(server_config);
    }

    // Pick up any newly-learned peers for discovery.
    state.dynamic_peers.store(Arc::new(outcome.peers.clone()));
    Ok(())
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

    #[test]
    fn combined_http_builder_accepts_http1_and_http2() {
        let mut builder = HttpBuilder::new(TokioExecutor::new());

        configure_combined_http_builder(&mut builder);

        // The combined listener must accept HTTP/1.1 (HTTP cache clients) and
        // HTTP/2 (h2c REAPI gRPC) on the same socket.
        assert!(builder.is_http1_available());
        assert!(builder.is_http2_available());
    }

    // End-to-end proof that the co-hosted listener dispatches by path: an HTTP
    // cache probe and a REAPI gRPC call both succeed against the same port. This
    // is the behavior the combined port exists to provide — a client that
    // derives its gRPC target from the single cache URL reaches REAPI, not the
    // plain-HTTP listener.
    #[tokio::test]
    async fn combined_listener_serves_http_and_grpc() {
        use bazel_remote_apis::build::bazel::remote::execution::v2::{
            GetCapabilitiesRequest, capabilities_client::CapabilitiesClient,
        };

        let context = test_context(|_| {}).await;
        let state = context.state.clone();

        let router =
            crate::http::public_router(state.clone()).merge(crate::reapi::routes(state.clone()));
        let handle = Handle::new();
        let server_handle = handle.clone();
        let server = tokio::spawn(async move {
            let mut server =
                axum_server::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0))).handle(server_handle);
            configure_combined_http_builder(server.http_builder());
            let _ = server.serve(router.into_make_service()).await;
        });

        let addr = timeout(Duration::from_secs(5), handle.listening())
            .await
            .expect("combined listener should bind within timeout")
            .expect("combined listener should report its bound address");

        // HTTP cache surface answers on the combined port.
        let http = reqwest::Client::new()
            .get(format!("http://{addr}/up"))
            .send()
            .await
            .expect("combined port should answer the HTTP /up probe");
        assert_eq!(http.status(), reqwest::StatusCode::OK);

        // REAPI gRPC (h2c) answers on the same port.
        let mut grpc_client = None;
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(format!("http://{addr}"))
                .expect("valid gRPC endpoint")
                .connect()
                .await
            {
                Ok(channel) => {
                    grpc_client = Some(CapabilitiesClient::new(channel));
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let mut grpc_client =
            grpc_client.expect("combined port should accept gRPC (h2c) connections");
        let capabilities = grpc_client
            .get_capabilities(GetCapabilitiesRequest {
                instance_name: String::new(),
            })
            .await
            .expect("combined port should answer REAPI GetCapabilities")
            .into_inner();
        assert!(
            capabilities.cache_capabilities.is_some(),
            "REAPI GetCapabilities over the combined port should return cache capabilities"
        );

        handle.shutdown();
        let _ = server.await;
    }

    // Same as above but over TLS (reusing the public cert): both HTTPS and REAPI
    // gRPC ride one TLS port, ALPN-negotiated (http/1.1 for HTTP, h2 for gRPC).
    #[tokio::test]
    async fn combined_listener_serves_http_and_grpc_over_tls() {
        use bazel_remote_apis::build::bazel::remote::execution::v2::{
            GetCapabilitiesRequest, capabilities_client::CapabilitiesClient,
        };

        let context = test_context(|_| {}).await;
        let state = context.state.clone();

        // Self-signed cert for "localhost", loaded through PublicTlsConfig so the
        // test exercises the real build_public_rustls_config path (ALPN + all).
        let cert = rcgen::generate_simple_self_signed(vec!["localhost".to_string()])
            .expect("generate self-signed cert");
        let cert_pem = cert.cert.pem();
        let key_pem = cert.signing_key.serialize_pem();
        let dir = tempfile::tempdir().expect("temp dir");
        let cert_path = dir.path().join("tls.crt");
        let key_path = dir.path().join("tls.key");
        std::fs::write(&cert_path, &cert_pem).expect("write cert");
        std::fs::write(&key_path, &key_pem).expect("write key");
        let public_tls = crate::config::PublicTlsConfig { cert_path, key_path };
        let tls_config = crate::peer_tls::build_public_rustls_config(&public_tls)
            .await
            .expect("build public rustls config");

        let router =
            crate::http::public_router(state.clone()).merge(crate::reapi::routes(state.clone()));
        let handle = Handle::new();
        let server_handle = handle.clone();
        let server = tokio::spawn(async move {
            let mut server =
                axum_server::bind_rustls(SocketAddr::from((Ipv4Addr::LOCALHOST, 0)), tls_config)
                    .handle(server_handle);
            configure_combined_http_builder(server.http_builder());
            let _ = server.serve(router.into_make_service()).await;
        });

        let addr = timeout(Duration::from_secs(5), handle.listening())
            .await
            .expect("combined TLS listener should bind within timeout")
            .expect("combined TLS listener should report its bound address");

        // HTTPS cache surface answers on the combined port.
        let http = reqwest::Client::builder()
            .add_root_certificate(
                reqwest::Certificate::from_pem(cert_pem.as_bytes()).expect("trust test cert"),
            )
            .resolve("localhost", addr)
            .build()
            .expect("build https client")
            .get(format!("https://localhost:{}/up", addr.port()))
            .send()
            .await
            .expect("combined TLS port should answer HTTPS /up");
        assert_eq!(http.status(), reqwest::StatusCode::OK);

        // REAPI gRPC answers over TLS (ALPN h2) on the same port. Dial the IP and
        // pin the cert domain so the test never depends on localhost resolution.
        let client_tls = tonic::transport::ClientTlsConfig::new()
            .ca_certificate(tonic::transport::Certificate::from_pem(cert_pem.as_bytes()))
            .domain_name("localhost");
        let mut grpc_client = None;
        for _ in 0..50 {
            let endpoint = tonic::transport::Endpoint::from_shared(format!("https://{addr}"))
                .expect("valid gRPC endpoint")
                .tls_config(client_tls.clone())
                .expect("apply client tls");
            match endpoint.connect().await {
                Ok(channel) => {
                    grpc_client = Some(CapabilitiesClient::new(channel));
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let mut grpc_client =
            grpc_client.expect("combined TLS port should accept gRPC (h2 over TLS) connections");
        let capabilities = grpc_client
            .get_capabilities(GetCapabilitiesRequest {
                instance_name: String::new(),
            })
            .await
            .expect("combined TLS port should answer REAPI GetCapabilities")
            .into_inner();
        assert!(
            capabilities.cache_capabilities.is_some(),
            "REAPI GetCapabilities over the combined TLS port should return cache capabilities"
        );

        handle.shutdown();
        let _ = server.await;
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
