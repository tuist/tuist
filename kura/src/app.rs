use std::{
    net::{Ipv4Addr, SocketAddr},
    sync::Arc,
    time::Duration,
};

use axum_server::Handle;
use hyper_util::rt::TokioTimer;
use tokio::sync::Notify;
use tokio::time::Instant;
use tracing::info;

use crate::{
    analytics::Analytics,
    config::Config,
    extension::ExtensionEngine,
    http,
    io::IoController,
    memory::MemoryController,
    metrics::Metrics,
    peer_tls::{build_internal_rustls_config, build_peer_client},
    reapi,
    replication::{spawn_membership_task, spawn_outbox_task},
    runtime::{DataDirLock, RuntimeState},
    state::{AppState, ReadinessState},
    store::Store,
    telemetry::init_tracing,
};

pub async fn run() -> Result<(), String> {
    let config = Config::from_env().map_err(|error| format!("invalid configuration: {error}"))?;
    let telemetry = init_tracing(&config);

    config
        .ensure_directories()
        .await
        .map_err(|error| format!("failed to create directories: {error}"))?;

    let metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
    let data_dir_lock = DataDirLock::acquire(&config.data_dir).inspect_err(|_| {
        metrics.record_writer_lock_acquire_failure();
    })?;
    let extension = ExtensionEngine::from_env(metrics.clone())
        .await
        .map_err(|error| format!("failed to initialize extension engine: {error}"))?;
    let analytics =
        Analytics::from_config(config.analytics.as_ref(), &config.node_url, metrics.clone())
            .map_err(|error| format!("failed to initialize analytics: {error}"))?;
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
    let notify = Notify::new();

    let state = Arc::new(AppState {
        config,
        _data_dir_lock: data_dir_lock,
        store,
        io,
        memory,
        metrics,
        runtime: RuntimeState::new(),
        extension,
        analytics,
        client,
        notify,
        readiness: tokio::sync::Mutex::new(ReadinessState::new(Instant::now())),
    });
    state.sync_runtime_metrics().await;

    spawn_membership_task(state.clone());
    spawn_outbox_task(state.clone());
    spawn_snapshot_task(state.clone());
    spawn_runtime_metrics_task(state.clone());
    spawn_drain_signal_task(state.clone());

    let address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, state.config.port));
    let grpc_address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, state.config.grpc_port));
    info!("Kura service listening on {address}");
    info!("Kura REAPI service listening on {grpc_address}");
    let internal_address = SocketAddr::from((Ipv4Addr::UNSPECIFIED, state.config.internal_port));
    if state.config.peer_tls.is_some() {
        info!("Kura internal mTLS service listening on {internal_address}");
    } else {
        info!("Kura internal HTTP service listening on {internal_address}");
    }

    let grpc_listener = tokio::net::TcpListener::bind(grpc_address)
        .await
        .map_err(|error| format!("failed to bind gRPC listener: {error}"))?;
    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);
    let grpc_shutdown_rx = shutdown_rx.clone();
    let grpc_state = state.clone();
    let grpc_handle = tokio::spawn(async move {
        let grpc_shutdown = async move {
            let mut shutdown_rx = grpc_shutdown_rx;
            if *shutdown_rx.borrow() {
                return;
            }
            let _ = shutdown_rx.changed().await;
        };

        if let Err(error) = reapi::serve(grpc_listener, grpc_state, grpc_shutdown).await {
            tracing::error!("gRPC server failed: {error}");
        }
    });

    let internal_handle = if let Some(peer_tls) = state.config.peer_tls.clone() {
        let tls_config = build_internal_rustls_config(&peer_tls).await?;
        let internal_router = http::internal_router(state.clone());
        let mut internal_shutdown_rx = shutdown_rx.clone();
        let handle = Handle::new();
        let shutdown_handle = handle.clone();
        tokio::spawn(async move {
            if *internal_shutdown_rx.borrow() {
                shutdown_handle.graceful_shutdown(None);
                return;
            }
            let _ = internal_shutdown_rx.changed().await;
            shutdown_handle.graceful_shutdown(None);
        });
        Some(tokio::spawn(async move {
            if let Err(error) = axum_server::bind_rustls(internal_address, tls_config)
                .handle(handle)
                .serve(internal_router.into_make_service())
                .await
            {
                tracing::error!("internal mTLS server failed: {error}");
            }
        }))
    } else {
        let internal_listener = tokio::net::TcpListener::bind(internal_address)
            .await
            .map_err(|error| format!("failed to bind internal TCP listener: {error}"))?;
        let internal_router = http::internal_router(state.clone());
        let mut internal_shutdown_rx = shutdown_rx.clone();
        Some(tokio::spawn(async move {
            let internal_shutdown = async move {
                if *internal_shutdown_rx.borrow() {
                    return;
                }
                let _ = internal_shutdown_rx.changed().await;
            };

            if let Err(error) = axum::serve(internal_listener, internal_router)
                .with_graceful_shutdown(internal_shutdown)
                .await
            {
                tracing::error!("internal server failed: {error}");
            }
        }))
    };

    let router = http::public_router(state.clone());
    let public_handle = Handle::new();
    let public_shutdown_handle = public_handle.clone();
    let public_shutdown_state = state.clone();
    tokio::spawn(async move {
        shutdown_signal().await;
        let _ = public_shutdown_state.enter_draining();
        public_shutdown_state.sync_runtime_metrics().await;
        public_shutdown_handle.graceful_shutdown(None);
    });

    let mut public_server = axum_server::bind(address).handle(public_handle);
    public_server
        .http_builder()
        .http1()
        .keep_alive(true)
        .timer(TokioTimer::new())
        .header_read_timeout(Some(Duration::from_secs(30)));
    public_server
        .serve(router.into_make_service())
        .await
        .map_err(|error| format!("server error: {error}"))?;
    let _ = shutdown_tx.send(true);
    let _ = grpc_handle.await;
    if let Some(internal_handle) = internal_handle {
        let _ = internal_handle.await;
    }

    telemetry.shutdown();

    Ok(())
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
    tokio::spawn(async move {
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
                        let evicted = state.store.trim_manifest_cache_to(target_bytes, "pressure");
                        if evicted > 0 {
                            state.metrics.record_memory_action("manifest_cache_trim");
                        }
                        state
                            .metrics
                            .update_background_work_paused("outbox", state.memory.pause_outbox());
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
    });
}

fn spawn_runtime_metrics_task(state: Arc<AppState>) {
    tokio::spawn(async move {
        loop {
            state.sync_runtime_metrics().await;
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    });
}

#[cfg(unix)]
fn spawn_drain_signal_task(state: Arc<AppState>) {
    tokio::spawn(async move {
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
    });
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

#[cfg(test)]
mod tests {
    use tokio::{sync::oneshot, time::timeout};

    use super::*;

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
}
