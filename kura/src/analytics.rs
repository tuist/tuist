use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use hmac::{Hmac, Mac};
use reqwest::{Client, StatusCode, header::CONTENT_TYPE};
use serde::Serialize;
use sha2::Sha256;
use tokio::{
    sync::mpsc,
    time::{Instant, MissedTickBehavior, interval},
};
use tracing::error;

use crate::{config::AnalyticsConfig, metrics::Metrics};

type HmacSha256 = Hmac<Sha256>;

const XCODE_WEBHOOK_PATH: &str = "/webhooks/cache";
const GRADLE_WEBHOOK_PATH: &str = "/webhooks/gradle-cache";

#[derive(Clone)]
pub struct Analytics {
    sender: mpsc::Sender<AnalyticsEvent>,
    pending: Arc<AtomicUsize>,
    queue_capacity: usize,
    metrics: Metrics,
}

#[derive(Clone, Debug)]
enum AnalyticsEvent {
    Xcode(XcodeAnalyticsEvent),
    Gradle(GradleAnalyticsEvent),
}

#[derive(Clone)]
struct AnalyticsRuntime {
    client: Client,
    config: AnalyticsConfig,
    cache_endpoint: String,
    metrics: Metrics,
    pending: Arc<AtomicUsize>,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
struct XcodeAnalyticsEvent {
    account_handle: String,
    project_handle: String,
    action: String,
    size: u64,
    cas_id: String,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
struct GradleAnalyticsEvent {
    account_handle: String,
    project_handle: String,
    action: String,
    size: u64,
    cache_key: String,
}

#[derive(Serialize)]
struct EventBatch<T> {
    events: Vec<T>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CircuitState {
    Closed,
    Open,
    HalfOpen,
}

#[derive(Clone, Copy, Debug)]
struct CircuitBreaker {
    state: CircuitState,
    consecutive_failures: usize,
    opened_until: Option<Instant>,
}

impl Analytics {
    pub fn from_config(
        analytics_config: Option<&AnalyticsConfig>,
        node_url: &str,
        metrics: Metrics,
    ) -> Result<Option<Self>, String> {
        let Some(config) = analytics_config.cloned() else {
            return Ok(None);
        };

        let client = Client::builder()
            .connect_timeout(Duration::from_millis(500))
            .timeout(Duration::from_millis(config.request_timeout_ms))
            .build()
            .map_err(|error| format!("failed to build analytics client: {error}"))?;
        let (sender, receiver) = mpsc::channel(config.queue_capacity);
        let pending = Arc::new(AtomicUsize::new(0));
        let runtime = AnalyticsRuntime {
            client,
            config: config.clone(),
            cache_endpoint: analytics_endpoint(node_url),
            metrics: metrics.clone(),
            pending: pending.clone(),
        };

        metrics.update_analytics_queue(config.queue_capacity, 0);
        tokio::spawn(async move {
            runtime.run(receiver).await;
        });

        Ok(Some(Self {
            sender,
            pending,
            queue_capacity: config.queue_capacity,
            metrics,
        }))
    }

    pub fn enqueue_xcode_download(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cas_id: &str,
        size: u64,
    ) {
        self.enqueue(AnalyticsEvent::Xcode(XcodeAnalyticsEvent {
            account_handle: tenant_id.to_owned(),
            project_handle: namespace_id.to_owned(),
            action: "download".into(),
            size,
            cas_id: cas_id.to_owned(),
        }));
    }

    pub fn enqueue_xcode_upload(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cas_id: &str,
        size: u64,
    ) {
        self.enqueue(AnalyticsEvent::Xcode(XcodeAnalyticsEvent {
            account_handle: tenant_id.to_owned(),
            project_handle: namespace_id.to_owned(),
            action: "upload".into(),
            size,
            cas_id: cas_id.to_owned(),
        }));
    }

    pub fn enqueue_gradle_download(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cache_key: &str,
        size: u64,
    ) {
        self.enqueue(AnalyticsEvent::Gradle(GradleAnalyticsEvent {
            account_handle: tenant_id.to_owned(),
            project_handle: namespace_id.to_owned(),
            action: "download".into(),
            size,
            cache_key: cache_key.to_owned(),
        }));
    }

    pub fn enqueue_gradle_upload(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cache_key: &str,
        size: u64,
    ) {
        self.enqueue(AnalyticsEvent::Gradle(GradleAnalyticsEvent {
            account_handle: tenant_id.to_owned(),
            project_handle: namespace_id.to_owned(),
            action: "upload".into(),
            size,
            cache_key: cache_key.to_owned(),
        }));
    }

    fn enqueue(&self, event: AnalyticsEvent) {
        match self.sender.try_send(event) {
            Ok(()) => {
                let depth = self.pending.fetch_add(1, Ordering::Relaxed) + 1;
                self.metrics.record_analytics_event("queue", "enqueued", 1);
                self.metrics
                    .update_analytics_queue(self.queue_capacity, depth);
            }
            Err(_) => {
                self.metrics.record_analytics_event("queue", "dropped", 1);
            }
        }
    }
}

impl AnalyticsRuntime {
    async fn run(self, mut receiver: mpsc::Receiver<AnalyticsEvent>) {
        let mut ticker = interval(Duration::from_millis(self.config.batch_timeout_ms));
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);

        let mut xcode_batch = Vec::with_capacity(self.config.batch_size);
        let mut gradle_batch = Vec::with_capacity(self.config.batch_size);
        let mut xcode_breaker = CircuitBreaker::new();
        let mut gradle_breaker = CircuitBreaker::new();

        self.metrics
            .update_analytics_circuit_state("xcode", xcode_breaker.state.code());
        self.metrics
            .update_analytics_circuit_state("gradle", gradle_breaker.state.code());

        loop {
            tokio::select! {
                maybe_event = receiver.recv() => {
                    let Some(event) = maybe_event else {
                        self.flush_xcode(&mut xcode_batch, &mut xcode_breaker).await;
                        self.flush_gradle(&mut gradle_batch, &mut gradle_breaker).await;
                        break;
                    };

                    let depth = self.pending.fetch_sub(1, Ordering::Relaxed).saturating_sub(1);
                    self.metrics
                        .update_analytics_queue(self.config.queue_capacity, depth);

                    match event {
                        AnalyticsEvent::Xcode(event) => {
                            xcode_batch.push(event);
                            if xcode_batch.len() >= self.config.batch_size {
                                self.flush_xcode(&mut xcode_batch, &mut xcode_breaker).await;
                            }
                        }
                        AnalyticsEvent::Gradle(event) => {
                            gradle_batch.push(event);
                            if gradle_batch.len() >= self.config.batch_size {
                                self.flush_gradle(&mut gradle_batch, &mut gradle_breaker).await;
                            }
                        }
                    }
                }
                _ = ticker.tick() => {
                    self.flush_xcode(&mut xcode_batch, &mut xcode_breaker).await;
                    self.flush_gradle(&mut gradle_batch, &mut gradle_breaker).await;
                }
            }
        }
    }

    async fn flush_xcode(
        &self,
        batch: &mut Vec<XcodeAnalyticsEvent>,
        breaker: &mut CircuitBreaker,
    ) {
        if batch.is_empty() {
            return;
        }

        let count = batch.len() as u64;
        let events = std::mem::take(batch);
        self.flush(
            "xcode",
            XCODE_WEBHOOK_PATH,
            &EventBatch { events },
            count,
            breaker,
            |count, result| self.metrics.record_analytics_event("xcode", result, count),
        )
        .await;
    }

    async fn flush_gradle(
        &self,
        batch: &mut Vec<GradleAnalyticsEvent>,
        breaker: &mut CircuitBreaker,
    ) {
        if batch.is_empty() {
            return;
        }

        let count = batch.len() as u64;
        let events = std::mem::take(batch);
        self.flush(
            "gradle",
            GRADLE_WEBHOOK_PATH,
            &EventBatch { events },
            count,
            breaker,
            |count, result| self.metrics.record_analytics_event("gradle", result, count),
        )
        .await;
    }

    async fn flush<T, F>(
        &self,
        pipeline: &str,
        path: &str,
        batch: &T,
        count: u64,
        breaker: &mut CircuitBreaker,
        event_result: F,
    ) where
        T: Serialize,
        F: FnOnce(u64, &str),
    {
        let encoded = match serde_json::to_vec(batch) {
            Ok(encoded) => encoded,
            Err(error) => {
                error!("failed to encode {pipeline} analytics batch: {error}");
                event_result(count, "encode_error");
                self.metrics
                    .record_analytics_batch(pipeline, "encode_error", Duration::default());
                return;
            }
        };

        let now = Instant::now();
        if !breaker.allow_request(
            now,
            Duration::from_millis(self.config.circuit_breaker_open_ms),
        ) {
            event_result(count, "circuit_open");
            self.metrics
                .record_analytics_batch(pipeline, "circuit_open", Duration::default());
            return;
        }

        let url = format!("{}{}", self.config.server_url, path);
        let signature = sign(&self.config.signing_key, &encoded);
        let start = now;

        let result = self
            .client
            .post(url)
            .header(CONTENT_TYPE, "application/json")
            .header("x-cache-signature", signature)
            .header("x-cache-endpoint", &self.cache_endpoint)
            .body(encoded)
            .send()
            .await;
        let duration = start.elapsed();

        match result {
            Ok(response) if response.status().is_success() => {
                event_result(count, "sent");
                self.metrics
                    .record_analytics_batch(pipeline, "ok", duration);
                self.record_breaker_transition(pipeline, breaker.on_success());
            }
            Ok(response) => {
                self.record_breaker_transition(
                    pipeline,
                    breaker.on_failure(
                        Instant::now(),
                        self.config.circuit_breaker_failure_threshold,
                        Duration::from_millis(self.config.circuit_breaker_open_ms),
                    ),
                );
                record_delivery_failure(
                    pipeline,
                    response.status(),
                    duration,
                    count,
                    &self.metrics,
                    event_result,
                );
            }
            Err(error) => {
                error!("failed to send {pipeline} analytics batch: {error}");
                event_result(count, "delivery_error");
                self.metrics
                    .record_analytics_batch(pipeline, "error", duration);
                self.record_breaker_transition(
                    pipeline,
                    breaker.on_failure(
                        Instant::now(),
                        self.config.circuit_breaker_failure_threshold,
                        Duration::from_millis(self.config.circuit_breaker_open_ms),
                    ),
                );
            }
        }
    }

    fn record_breaker_transition(
        &self,
        pipeline: &str,
        transition: Option<(CircuitState, CircuitState)>,
    ) {
        let Some((from, to)) = transition else {
            return;
        };

        self.metrics
            .record_analytics_circuit_transition(pipeline, from.as_str(), to.as_str());
        self.metrics
            .update_analytics_circuit_state(pipeline, to.code());
    }
}

fn record_delivery_failure<F>(
    pipeline: &str,
    status: StatusCode,
    duration: Duration,
    count: u64,
    metrics: &Metrics,
    event_result: F,
) where
    F: FnOnce(u64, &str),
{
    error!("failed to send {pipeline} analytics batch with status {status}");
    event_result(count, "delivery_error");
    metrics.record_analytics_batch(pipeline, "error", duration);
}

fn sign(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .expect("analytics signing key should be accepted by HMAC");
    mac.update(body);
    hex::encode(mac.finalize().into_bytes())
}

fn analytics_endpoint(node_url: &str) -> String {
    let Some(url) = reqwest::Url::parse(node_url).ok() else {
        return node_url.to_owned();
    };

    let Some(host) = url.host_str() else {
        return node_url.to_owned();
    };

    match url.port() {
        Some(port) => format!("{host}:{port}"),
        None => host.to_owned(),
    }
}

impl CircuitBreaker {
    fn new() -> Self {
        Self {
            state: CircuitState::Closed,
            consecutive_failures: 0,
            opened_until: None,
        }
    }

    fn allow_request(&mut self, now: Instant, open_duration: Duration) -> bool {
        match self.state {
            CircuitState::Closed | CircuitState::HalfOpen => true,
            CircuitState::Open => {
                if self
                    .opened_until
                    .is_some_and(|opened_until| now >= opened_until)
                {
                    self.state = CircuitState::HalfOpen;
                    self.opened_until = Some(now + open_duration);
                    true
                } else {
                    false
                }
            }
        }
    }

    fn on_success(&mut self) -> Option<(CircuitState, CircuitState)> {
        let previous = self.state;
        self.state = CircuitState::Closed;
        self.consecutive_failures = 0;
        self.opened_until = None;

        if previous == CircuitState::Closed {
            None
        } else {
            Some((previous, CircuitState::Closed))
        }
    }

    fn on_failure(
        &mut self,
        now: Instant,
        failure_threshold: usize,
        open_duration: Duration,
    ) -> Option<(CircuitState, CircuitState)> {
        match self.state {
            CircuitState::Closed => {
                self.consecutive_failures += 1;
                if self.consecutive_failures >= failure_threshold {
                    self.consecutive_failures = 0;
                    self.opened_until = Some(now + open_duration);
                    self.state = CircuitState::Open;
                    Some((CircuitState::Closed, CircuitState::Open))
                } else {
                    None
                }
            }
            CircuitState::HalfOpen => {
                self.consecutive_failures = 0;
                self.opened_until = Some(now + open_duration);
                self.state = CircuitState::Open;
                Some((CircuitState::HalfOpen, CircuitState::Open))
            }
            CircuitState::Open => {
                self.opened_until = Some(now + open_duration);
                None
            }
        }
    }
}

impl CircuitState {
    fn as_str(self) -> &'static str {
        match self {
            CircuitState::Closed => "closed",
            CircuitState::Open => "open",
            CircuitState::HalfOpen => "half_open",
        }
    }

    fn code(self) -> i64 {
        match self {
            CircuitState::Closed => 0,
            CircuitState::Open => 1,
            CircuitState::HalfOpen => 2,
        }
    }
}

#[cfg(test)]
mod tests;
