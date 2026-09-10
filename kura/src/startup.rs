use std::{
    sync::{Arc, Mutex, Weak},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::{
    Router,
    extract::State,
    http::{StatusCode, header},
    response::{IntoResponse, Response},
    routing::get,
};
use hyper_util::rt::TokioIo;
use tokio::{
    net::TcpListener,
    sync::watch,
    task::{JoinHandle, JoinSet},
    time::Instant,
};
use tower::ServiceExt;
use tracing::Instrument;

use crate::{metrics::Metrics, runtime::RuntimeState, state::AppState};

const PROGRESS_TIMEOUT: Duration = Duration::from_secs(300);
// RocksDB open/replay is opaque to the application. Bound that phase
// separately rather than pretending a timer tick is recovery progress.
const STORE_OPEN_TIMEOUT: Duration = Duration::from_secs(900);
const MAX_BOOTSTRAP_CONNECTIONS: usize = 32;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Preparing = 0,
    OpeningStore = 1,
    CleaningSegments = 2,
    Configuring = 3,
    Complete = 4,
    Failed = 5,
}

#[derive(Debug)]
pub enum RecoveryError {
    Interrupted,
    Failed(String),
}

impl RecoveryError {
    pub fn context(self, context: &str) -> Self {
        match self {
            Self::Interrupted => Self::Interrupted,
            Self::Failed(error) => Self::Failed(format!("{context}: {error}")),
        }
    }
}

impl From<String> for RecoveryError {
    fn from(error: String) -> Self {
        Self::Failed(error)
    }
}

impl std::fmt::Display for RecoveryError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Interrupted => formatter.write_str("startup recovery interrupted by shutdown"),
            Self::Failed(error) => formatter.write_str(error),
        }
    }
}

pub struct Recovery {
    progress: Mutex<(Phase, Instant)>,
    metrics: Metrics,
    runtime: Arc<RuntimeState>,
}

impl Recovery {
    pub fn new(metrics: Metrics, runtime: Arc<RuntimeState>) -> Arc<Self> {
        let recovery = Arc::new(Self {
            progress: Mutex::new((Phase::Preparing, Instant::now())),
            metrics,
            runtime,
        });
        recovery.set_phase(Phase::Preparing);
        recovery
    }

    pub fn set_phase(&self, phase: Phase) {
        *self.progress.lock().expect("startup progress poisoned") = (phase, Instant::now());
        self.metrics.record_startup_phase(phase as i64);
        self.record_timestamp();
        tracing::info!(?phase, "startup recovery phase changed");
    }

    fn record_timestamp(&self) {
        self.metrics.record_startup_progress_timestamp(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64,
        );
    }

    pub fn check_running(&self) -> Result<(), RecoveryError> {
        if self.runtime.is_draining() {
            return Err(RecoveryError::Interrupted);
        }
        Ok(())
    }

    pub fn completed_work(&self, committed: bool) -> Result<(), RecoveryError> {
        let mut progress = self.progress.lock().expect("startup progress poisoned");
        if progress.0 != Phase::CleaningSegments {
            return Ok(());
        }
        progress.1 = Instant::now();
        self.record_timestamp();
        self.metrics.record_startup_work(committed);
        drop(progress);
        self.check_running()
    }

    fn healthy(&self) -> bool {
        let (phase, last_progress) = *self.progress.lock().expect("startup progress poisoned");
        // A requested drain is not a liveness failure. The signal handler
        // prevents activation and recovery stops at the next safe boundary.
        phase != Phase::Failed
            && (phase == Phase::Complete
                || last_progress.elapsed()
                    < if phase == Phase::OpeningStore {
                        STORE_OPEN_TIMEOUT
                    } else {
                        PROGRESS_TIMEOUT
                    })
    }
}

async fn up(State(recovery): State<Arc<Recovery>>) -> Response {
    let status = if recovery.healthy() {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };
    (status, "recovering\n").into_response()
}

async fn unavailable() -> impl IntoResponse {
    (
        StatusCode::SERVICE_UNAVAILABLE,
        "startup recovery in progress\n",
    )
}

fn router(recovery: Arc<Recovery>) -> Router {
    Router::new()
        .route("/up", get(up))
        .route("/ready", get(unavailable))
        .route(
            "/metrics",
            get(|State(recovery): State<Arc<Recovery>>| async move {
                (
                    [(
                        header::CONTENT_TYPE,
                        "application/openmetrics-text; version=1.0.0; charset=utf-8",
                    )],
                    recovery.metrics.render(),
                )
            }),
        )
        .fallback(unavailable)
        .with_state(recovery)
}

pub struct Bootstrap {
    pub recovery: Arc<Recovery>,
    stop: watch::Sender<bool>,
    listener: Option<JoinHandle<TcpListener>>,
    signals: JoinHandle<()>,
    termination: watch::Receiver<bool>,
    signal_state: Arc<Mutex<Weak<AppState>>>,
}

impl Bootstrap {
    pub async fn start(
        address: std::net::SocketAddr,
        metrics: Metrics,
        runtime: Arc<RuntimeState>,
    ) -> Result<Self, String> {
        let recovery = Recovery::new(metrics, runtime.clone());
        // Register the streams synchronously before starting any recovery,
        // including before the spawned signal task gets its first poll.
        let signal_state = Arc::new(Mutex::new(Weak::new()));
        let (signals, termination) = signals(runtime, signal_state.clone())?;
        let listener = match TcpListener::bind(address).await {
            Ok(listener) => listener,
            Err(error) => {
                signals.abort();
                return Err(format!("failed to bind startup HTTP listener: {error}"));
            }
        };
        let (stop, stop_rx) = watch::channel(false);
        let listener =
            tokio::spawn(serve(listener, router(recovery.clone()), stop_rx).in_current_span());
        Ok(Self {
            recovery,
            stop,
            listener: Some(listener),
            signals,
            termination,
            signal_state,
        })
    }

    pub fn attach_state(&self, state: &Arc<AppState>) {
        *self.signal_state.lock().expect("signal state poisoned") = Arc::downgrade(state);
    }

    pub fn termination(&self) -> watch::Receiver<bool> {
        self.termination.clone()
    }

    pub async fn take_listener(&mut self) -> Result<TcpListener, RecoveryError> {
        self.recovery.check_running()?;
        self.stop.send_replace(true);
        self.listener
            .take()
            .ok_or_else(|| "startup listener already transferred".to_owned())?
            .await
            .map_err(|error| RecoveryError::Failed(format!("startup listener failed: {error}")))
    }
}

impl Drop for Bootstrap {
    fn drop(&mut self) {
        if let Some(listener) = &self.listener {
            listener.abort();
        }
        self.signals.abort();
    }
}

async fn serve(
    listener: TcpListener,
    router: Router,
    mut stop: watch::Receiver<bool>,
) -> TcpListener {
    let mut connections = JoinSet::new();
    loop {
        tokio::select! {
            biased;
            _ = stop.changed() => break,
            Some(_) = connections.join_next(), if !connections.is_empty() => {},
            accepted = listener.accept(), if connections.len() < MAX_BOOTSTRAP_CONNECTIONS => {
                let Ok((stream, _)) = accepted else { continue };
                let router = router.clone();
                connections.spawn(async move {
                    let service = hyper::service::service_fn(move |request| {
                        router.clone().oneshot(request.map(axum::body::Body::new))
                    });
                    // No bootstrap keep-alives survive activation. The same
                    // bound socket transfers to the ordinary accelerated server.
                    let _ = tokio::time::timeout(Duration::from_secs(5),
                        hyper::server::conn::http1::Builder::new()
                            .keep_alive(false)
                            .max_buf_size(16 * 1024)
                            .serve_connection(TokioIo::new(stream), service)
                    ).await;
                });
            }
        }
    }
    connections.shutdown().await;
    listener
}

async fn request_drain(runtime: &RuntimeState, state: &Mutex<Weak<AppState>>) {
    if !runtime.request_drain() {
        return;
    }
    let state = state.lock().expect("signal state poisoned").upgrade();
    if let Some(state) = state {
        state.store.sync_feed().notify_commit();
        tokio::spawn(async move {
            state.sync_runtime_metrics().await;
        });
    }
}

fn signals(
    runtime: Arc<RuntimeState>,
    state: Arc<Mutex<Weak<AppState>>>,
) -> Result<(JoinHandle<()>, watch::Receiver<bool>), String> {
    let (termination, receiver) = watch::channel(false);
    #[cfg(unix)]
    {
        use tokio::signal::unix::{SignalKind, signal};
        let mut drain = signal(SignalKind::user_defined1()).map_err(|e| e.to_string())?;
        let mut term = signal(SignalKind::terminate()).map_err(|e| e.to_string())?;
        let mut interrupt = signal(SignalKind::interrupt()).map_err(|e| e.to_string())?;
        let task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = drain.recv() => {
                        request_drain(&runtime, &state).await;
                        tracing::info!("received SIGUSR1, entering draining state");
                    }
                    _ = term.recv() => break,
                    _ = interrupt.recv() => break,
                }
            }
            request_drain(&runtime, &state).await;
            termination.send_replace(true);
        });
        Ok((task, receiver))
    }
    #[cfg(not(unix))]
    {
        let task = tokio::spawn(async move {
            let _ = tokio::signal::ctrl_c().await;
            request_drain(&runtime, &state).await;
            termination.send_replace(true);
        });
        Ok((task, receiver))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::Request;

    fn recovery() -> Arc<Recovery> {
        Recovery::new(
            Metrics::new("local".into(), "test".into()),
            RuntimeState::new(),
        )
    }

    #[tokio::test(start_paused = true)]
    async fn progress_allows_recovery_beyond_the_old_startup_deadline() {
        let recovery = recovery();
        recovery.set_phase(Phase::CleaningSegments);
        for _ in 0..10 {
            tokio::time::advance(Duration::from_secs(60)).await;
            recovery.completed_work(true).unwrap();
            assert!(recovery.healthy());
        }
        let app = router(recovery.clone());
        for uri in ["/ready", "/cache/artifact", "/_internal/replicate/artifact"] {
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri(uri)
                        .body(axum::body::Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        }
        tokio::time::advance(PROGRESS_TIMEOUT).await;
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/up")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test(start_paused = true)]
    async fn opaque_open_is_bounded_and_failure_never_reports_healthy() {
        let recovery = recovery();
        recovery.set_phase(Phase::OpeningStore);
        tokio::time::advance(STORE_OPEN_TIMEOUT).await;
        assert!(!recovery.healthy());
        recovery.set_phase(Phase::Failed);
        assert!(!recovery.healthy());
    }

    #[tokio::test]
    async fn drain_prevents_activation() {
        let recovery = recovery();
        recovery.set_phase(Phase::CleaningSegments);
        recovery.runtime.request_drain();
        assert!(recovery.check_running().is_err());
        assert!(recovery.completed_work(true).is_err());
    }

    #[tokio::test]
    async fn listener_handoff_keeps_the_bound_socket() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let (stop, receiver) = watch::channel(false);
        let serving = tokio::spawn(serve(listener, router(recovery()), receiver));
        let client = reqwest::Client::new();
        assert_eq!(
            client
                .get(format!("http://{address}/up"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::OK
        );
        stop.send_replace(true);
        let listener = serving.await.unwrap();
        assert_eq!(listener.local_addr().unwrap(), address);
        assert!(TcpListener::bind(address).await.is_err());
        let serving = tokio::spawn(async move {
            axum::serve(
                listener,
                Router::new().route("/up", get(|| async { "serving" })),
            )
            .await
            .unwrap();
        });
        assert_eq!(
            client
                .get(format!("http://{address}/up"))
                .send()
                .await
                .unwrap()
                .text()
                .await
                .unwrap(),
            "serving"
        );
        serving.abort();
    }
    // Exercise process-wide handlers only in a child, so parallel tests never
    // receive one another's Unix signals.
    #[cfg(unix)]
    #[tokio::test]
    async fn bootstrap_signal_child() {
        let Ok(marker) = std::env::var("KURA_TEST_STARTUP_SIGNAL_MARKER") else {
            return;
        };
        let runtime = RuntimeState::new();
        let bootstrap = Bootstrap::start(
            "127.0.0.1:0".parse().unwrap(),
            Metrics::new("local".into(), "test".into()),
            runtime.clone(),
        )
        .await
        .unwrap();
        bootstrap.recovery.set_phase(Phase::CleaningSegments);
        std::fs::write(marker, b"ready").unwrap();
        tokio::time::timeout(Duration::from_secs(10), async {
            while !runtime.is_draining() {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        assert!(bootstrap.recovery.check_running().is_err());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn startup_signals_are_handled_before_the_store_exists() {
        for signal in [libc::SIGUSR1, libc::SIGTERM, libc::SIGINT] {
            let directory = tempfile::tempdir().unwrap();
            let marker = directory.path().join("ready");
            let mut child = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "startup::tests::bootstrap_signal_child",
                    "--nocapture",
                ])
                .env("KURA_TEST_STARTUP_SIGNAL_MARKER", &marker)
                .spawn()
                .unwrap();
            let deadline = Instant::now() + Duration::from_secs(15);
            while !marker.exists() && Instant::now() < deadline {
                if let Some(status) = child.try_wait().unwrap() {
                    panic!("signal child exited early: {status}");
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            if !marker.exists() {
                let _ = child.kill();
                let _ = child.wait();
                panic!("signal child did not start");
            }
            assert_eq!(unsafe { libc::kill(child.id() as libc::pid_t, signal) }, 0);
            let status = child.wait().unwrap();
            assert!(
                status.success(),
                "startup signal {signal} killed the process: {status}"
            );
        }
    }
}
