use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use hmac::{Hmac, Mac};
use reqwest::{Client, StatusCode, header::CONTENT_TYPE};
use serde::{Serialize, Serializer, ser::SerializeStruct};
use sha2::Sha256;
use tokio::{
    sync::mpsc,
    time::{Instant, MissedTickBehavior, interval},
};
use tracing::error;
use uuid::Uuid;

use crate::{
    config::AnalyticsConfig,
    metrics::{AnalyticsQueueMetrics, Metrics},
};

type HmacSha256 = Hmac<Sha256>;

const XCODE_WEBHOOK_PATH: &str = "/webhooks/cache";
const GRADLE_WEBHOOK_PATH: &str = "/webhooks/gradle-cache";
const REAPI_CACHE_WEBHOOK_PATH: &str = "/webhooks/reapi-cache";
const BAZEL_INVOCATIONS_WEBHOOK_PATH: &str = "/webhooks/bazel-invocations";
const MAX_BAZEL_INVOCATION_BATCH_SIZE: usize = 32;

#[derive(Clone)]
pub struct Analytics {
    sender: mpsc::Sender<AnalyticsEvent>,
    bazel_sender: mpsc::Sender<BazelInvocationAnalyticsEvent>,
    pending: Arc<AtomicUsize>,
    queue_capacity: usize,
    metrics: Metrics,
    queue_metrics: Arc<AnalyticsQueueMetrics>,
}

#[derive(Clone, Debug)]
enum AnalyticsEvent {
    Xcode(XcodeAnalyticsEvent),
    Gradle(GradleAnalyticsEvent),
    ReapiCache(ReapiCacheAnalyticsEvent),
}

#[derive(Clone)]
struct AnalyticsRuntime {
    client: Client,
    config: AnalyticsConfig,
    cache_endpoint: String,
    metrics: Metrics,
    queue_metrics: Arc<AnalyticsQueueMetrics>,
    pending: Arc<AtomicUsize>,
}

// event_id + observed_at_ms are minted by the producer and carried through
// the pipeline unchanged. The server preserves them on insert so a retried
// batch collapses on the ClickHouse side instead of double-counting. These
// two fields are prerequisites for the durable outbox we're building next
// (see /engineering/specs/94 discussion): without them, a redelivered batch
// after a WAN blip would insert duplicate rows and corrupt cache-usage
// dashboards. Additive on the wire, so a server that has not rolled yet
// keeps working.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
struct XcodeAnalyticsEvent {
    event_id: Uuid,
    account_handle: String,
    project_handle: String,
    action: String,
    size: u64,
    cas_id: String,
    observed_at_ms: u64,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
struct GradleAnalyticsEvent {
    event_id: Uuid,
    account_handle: String,
    project_handle: String,
    action: String,
    size: u64,
    cache_key: String,
    observed_at_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReapiCacheAnalyticsContext {
    pub account_handle: String,
    pub project_handle: String,
    pub client_kind: &'static str,
    pub invocation_id: String,
    pub action_mnemonic: String,
    pub target_label: String,
    pub configuration_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReapiCacheAnalyticsEvent {
    // See the same note on Xcode/Gradle: the producer mints event_id and the
    // server preserves it on insert so a retried batch dedupes at the
    // ClickHouse layer.
    pub event_id: Uuid,
    pub context: Arc<ReapiCacheAnalyticsContext>,
    pub operation: &'static str,
    pub outcome: &'static str,
    pub action_digest: String,
    pub size: u64,
    pub duration_us: u64,
    pub observed_at_ms: u64,
}

impl Serialize for ReapiCacheAnalyticsEvent {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut event = serializer.serialize_struct("ReapiCacheAnalyticsEvent", 15)?;
        event.serialize_field("event_id", &self.event_id)?;
        event.serialize_field("account_handle", &self.context.account_handle)?;
        event.serialize_field("project_handle", &self.context.project_handle)?;
        event.serialize_field("client_kind", self.context.client_kind)?;
        event.serialize_field("operation", self.operation)?;
        event.serialize_field("outcome", self.outcome)?;
        event.serialize_field("action_digest", &self.action_digest)?;
        event.serialize_field("size", &self.size)?;
        // Microseconds are the real measurement: Kura answers most action-cache
        // lookups in well under a millisecond, so a millisecond field rounds
        // almost every observation to zero and makes latency and throughput
        // uncomputable. `duration_ms` stays on the wire so a server that has
        // not rolled yet keeps working, and can be dropped once it has.
        event.serialize_field("duration_us", &self.duration_us)?;
        event.serialize_field("duration_ms", &(self.duration_us / 1_000))?;
        event.serialize_field("observed_at_ms", &self.observed_at_ms)?;
        event.serialize_field("invocation_id", &self.context.invocation_id)?;
        event.serialize_field("action_mnemonic", &self.context.action_mnemonic)?;
        event.serialize_field("target_label", &self.context.target_label)?;
        event.serialize_field("configuration_id", &self.context.configuration_id)?;
        event.end()
    }
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct BazelInvocationAnalyticsEvent {
    pub account_handle: String,
    pub project_handle: String,
    pub invocation_id: String,
    pub command: String,
    pub target_patterns: Vec<String>,
    pub git_branch: String,
    pub git_commit_sha: String,
    pub is_ci: bool,
    pub custom_values: BTreeMap<String, String>,
    pub bazel_version: String,
    pub cpu_time_ms: u64,
    pub actions_created: u64,
    pub actions_executed: u64,
    pub targets_configured: u64,
    pub packages_loaded: u64,
    pub build_timeline_duration_ms: u64,
    pub build_timeline_lanes: Vec<String>,
    pub build_timeline_span_lanes: Vec<u8>,
    pub build_timeline_span_start_ms: Vec<u64>,
    pub build_timeline_span_durations_ms: Vec<u64>,
    pub build_timeline_span_categories: Vec<String>,
    pub build_timeline_span_descriptions: Vec<String>,
    pub critical_path_duration_ms: u64,
    pub critical_path_action_descriptions: Vec<String>,
    pub critical_path_action_durations_ms: Vec<u64>,
    pub logs: Vec<BazelInvocationLogAnalyticsEvent>,
    pub status: String,
    pub exit_code: i32,
    pub started_at_ms: u64,
    pub finished_at_ms: u64,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct BazelInvocationLogAnalyticsEvent {
    pub sequence_number: u64,
    pub stream: &'static str,
    pub message: String,
    pub observed_at_ms: u64,
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

        let client = crate::control_plane_http::analytics_client_builder(config.request_timeout_ms)
            .build()
            .map_err(|error| format!("failed to build analytics client: {error}"))?;
        let (sender, receiver) = mpsc::channel(config.queue_capacity);
        let (bazel_sender, bazel_receiver) = mpsc::channel(config.queue_capacity);
        let pending = Arc::new(AtomicUsize::new(0));
        let queue_metrics = metrics.analytics_queue_metrics();
        let runtime = AnalyticsRuntime {
            client,
            config: config.clone(),
            cache_endpoint: analytics_endpoint(node_url),
            metrics: metrics.clone(),
            queue_metrics: queue_metrics.clone(),
            pending: pending.clone(),
        };

        queue_metrics.update(config.queue_capacity, 0);
        let bazel_runtime = runtime.clone();
        tokio::spawn(async move {
            runtime.run(receiver).await;
        });
        tokio::spawn(async move {
            bazel_runtime.run_bazel_invocations(bazel_receiver).await;
        });

        Ok(Some(Self {
            sender,
            bazel_sender,
            pending,
            queue_capacity: config.queue_capacity,
            metrics,
            queue_metrics,
        }))
    }

    pub fn enqueue_xcode_download(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cas_id: &str,
        size: u64,
    ) {
        self.enqueue(|| {
            AnalyticsEvent::Xcode(XcodeAnalyticsEvent {
                event_id: Uuid::now_v7(),
                account_handle: tenant_id.to_owned(),
                project_handle: namespace_id.to_owned(),
                action: "download".into(),
                size,
                cas_id: cas_id.to_owned(),
                observed_at_ms: observed_at_ms_now(),
            })
        });
    }

    pub fn enqueue_xcode_upload(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cas_id: &str,
        size: u64,
    ) {
        self.enqueue(|| {
            AnalyticsEvent::Xcode(XcodeAnalyticsEvent {
                event_id: Uuid::now_v7(),
                account_handle: tenant_id.to_owned(),
                project_handle: namespace_id.to_owned(),
                action: "upload".into(),
                size,
                cas_id: cas_id.to_owned(),
                observed_at_ms: observed_at_ms_now(),
            })
        });
    }

    pub fn enqueue_gradle_download(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cache_key: &str,
        size: u64,
    ) {
        self.enqueue(|| {
            AnalyticsEvent::Gradle(GradleAnalyticsEvent {
                event_id: Uuid::now_v7(),
                account_handle: tenant_id.to_owned(),
                project_handle: namespace_id.to_owned(),
                action: "download".into(),
                size,
                cache_key: cache_key.to_owned(),
                observed_at_ms: observed_at_ms_now(),
            })
        });
    }

    pub fn enqueue_gradle_upload(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        cache_key: &str,
        size: u64,
    ) {
        self.enqueue(|| {
            AnalyticsEvent::Gradle(GradleAnalyticsEvent {
                event_id: Uuid::now_v7(),
                account_handle: tenant_id.to_owned(),
                project_handle: namespace_id.to_owned(),
                action: "upload".into(),
                size,
                cache_key: cache_key.to_owned(),
                observed_at_ms: observed_at_ms_now(),
            })
        });
    }

    pub fn enqueue_reapi_cache_event(&self, event: impl FnOnce() -> ReapiCacheAnalyticsEvent) {
        self.enqueue(|| AnalyticsEvent::ReapiCache(event()));
    }

    pub fn enqueue_bazel_invocation_event(&self, event: BazelInvocationAnalyticsEvent) {
        match self.bazel_sender.try_send(event) {
            Ok(()) => self
                .metrics
                .record_analytics_event("bazel_invocations", "enqueued", 1),
            Err(_) => self
                .metrics
                .record_analytics_event("bazel_invocations", "dropped", 1),
        }
    }

    fn enqueue(&self, event: impl FnOnce() -> AnalyticsEvent) {
        let Ok(permit) = self.sender.try_reserve() else {
            self.queue_metrics.record_dropped();
            return;
        };
        let event = event();
        let depth = self.pending.fetch_add(1, Ordering::Relaxed) + 1;
        self.queue_metrics
            .record_enqueued(self.queue_capacity, depth);
        permit.send(event);
    }
}

impl AnalyticsRuntime {
    async fn run_bazel_invocations(
        self,
        mut receiver: mpsc::Receiver<BazelInvocationAnalyticsEvent>,
    ) {
        let mut ticker = interval(Duration::from_millis(self.config.batch_timeout_ms));
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
        let batch_size = self.config.batch_size.min(MAX_BAZEL_INVOCATION_BATCH_SIZE);
        let mut batch = Vec::with_capacity(batch_size);
        let mut breaker = CircuitBreaker::new();

        self.metrics
            .update_analytics_circuit_state("bazel_invocations", breaker.state.code());

        loop {
            tokio::select! {
                event = receiver.recv() => {
                    let Some(event) = event else {
                        self.flush_bazel_invocations(&mut batch, &mut breaker).await;
                        break;
                    };
                    batch.push(event);
                    if batch.len() >= batch_size {
                        self.flush_bazel_invocations(&mut batch, &mut breaker).await;
                    }
                }
                _ = ticker.tick() => self.flush_bazel_invocations(&mut batch, &mut breaker).await,
            }
        }
    }

    async fn run(self, mut receiver: mpsc::Receiver<AnalyticsEvent>) {
        let mut ticker = interval(Duration::from_millis(self.config.batch_timeout_ms));
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);

        let mut xcode_batch = Vec::with_capacity(self.config.batch_size);
        let mut gradle_batch = Vec::with_capacity(self.config.batch_size);
        let mut reapi_cache_batch = Vec::with_capacity(self.config.batch_size);
        let mut xcode_breaker = CircuitBreaker::new();
        let mut gradle_breaker = CircuitBreaker::new();
        let mut reapi_cache_breaker = CircuitBreaker::new();

        self.metrics
            .update_analytics_circuit_state("xcode", xcode_breaker.state.code());
        self.metrics
            .update_analytics_circuit_state("gradle", gradle_breaker.state.code());
        self.metrics
            .update_analytics_circuit_state("reapi_cache", reapi_cache_breaker.state.code());

        loop {
            tokio::select! {
                maybe_event = receiver.recv() => {
                    let Some(event) = maybe_event else {
                        self.flush_xcode(&mut xcode_batch, &mut xcode_breaker).await;
                        self.flush_gradle(&mut gradle_batch, &mut gradle_breaker).await;
                        self.flush_reapi_cache(&mut reapi_cache_batch, &mut reapi_cache_breaker).await;
                        break;
                    };

                    let depth = self.pending.fetch_sub(1, Ordering::Relaxed).saturating_sub(1);
                    self.queue_metrics.update(self.config.queue_capacity, depth);

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
                        AnalyticsEvent::ReapiCache(event) => {
                            reapi_cache_batch.push(event);
                            if reapi_cache_batch.len() >= self.config.batch_size {
                                self.flush_reapi_cache(&mut reapi_cache_batch, &mut reapi_cache_breaker).await;
                            }
                        }
                    }
                }
                _ = ticker.tick() => {
                    self.flush_xcode(&mut xcode_batch, &mut xcode_breaker).await;
                    self.flush_gradle(&mut gradle_batch, &mut gradle_breaker).await;
                    self.flush_reapi_cache(&mut reapi_cache_batch, &mut reapi_cache_breaker).await;
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

    async fn flush_reapi_cache(
        &self,
        batch: &mut Vec<ReapiCacheAnalyticsEvent>,
        breaker: &mut CircuitBreaker,
    ) {
        if batch.is_empty() {
            return;
        }

        let count = batch.len() as u64;
        let events = std::mem::take(batch);
        self.flush(
            "reapi_cache",
            REAPI_CACHE_WEBHOOK_PATH,
            &EventBatch { events },
            count,
            breaker,
            |count, result| {
                self.metrics
                    .record_analytics_event("reapi_cache", result, count)
            },
        )
        .await;
    }

    async fn flush_bazel_invocations(
        &self,
        batch: &mut Vec<BazelInvocationAnalyticsEvent>,
        breaker: &mut CircuitBreaker,
    ) {
        if batch.is_empty() {
            return;
        }

        let count = batch.len() as u64;
        let events = std::mem::take(batch);
        self.flush(
            "bazel_invocations",
            BAZEL_INVOCATIONS_WEBHOOK_PATH,
            &EventBatch { events },
            count,
            breaker,
            |count, result| {
                self.metrics
                    .record_analytics_event("bazel_invocations", result, count)
            },
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
                let kind = classify_reqwest_error(&error);
                let chain = error_cause_chain(&error);
                error!(pipeline, kind, "failed to send analytics batch: {chain}");
                event_result(count, "delivery_error");
                self.metrics
                    .record_analytics_batch(pipeline, error_result_label(kind), duration);
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
    let label = status_result_label(status);
    error!(
        pipeline,
        kind = label,
        status = status.as_u16(),
        "failed to send analytics batch"
    );
    event_result(count, "delivery_error");
    metrics.record_analytics_batch(pipeline, label, duration);
}

/// Classify a reqwest transport error so operators can tell a connect-time
/// failure apart from a stalled-in-flight request without reading the log
/// message. The set is intentionally small and bounded to keep Prometheus
/// label cardinality on `kura_analytics_batches_total{result=...}` finite.
///
/// Precedence matters. In reqwest 0.13.x a TCP connect that exceeds the
/// client's `connect_timeout` produces an error where both `is_connect()`
/// and `is_timeout()` return true; a request that connects but exceeds
/// the client's overall `timeout` returns `is_timeout()` alone. Checking
/// `is_connect()` first therefore keeps `connect` and `timeout` as
/// separate signals, which is the whole point of this metric split.
///
/// A note on the remaining buckets:
/// - `body` fires for reqwest's body-side error kind (typically response
///   body read failures). Outbound writes on the `Vec<u8>` body path
///   here usually surface as `request` (or `timeout` if the overall
///   budget expired), not `body`.
/// - `decode` fires when a JSON/text decode of the response fails; this
///   client only reads status, so it should stay empty.
/// - `request` is the catch-all for everything that connected but
///   otherwise misbehaved.
fn classify_reqwest_error(error: &reqwest::Error) -> &'static str {
    if error.is_connect() {
        "connect"
    } else if error.is_timeout() {
        "timeout"
    } else if error.is_body() {
        "body"
    } else if error.is_decode() {
        "decode"
    } else if error.is_request() {
        "request"
    } else {
        "other"
    }
}

fn error_result_label(kind: &str) -> &'static str {
    // Return a `&'static str` so the metrics label is stable and never
    // interpolated with user data.
    match kind {
        "timeout" => "error_timeout",
        "connect" => "error_connect",
        "body" => "error_body",
        "decode" => "error_decode",
        "request" => "error_request",
        _ => "error_other",
    }
}

fn status_result_label(status: StatusCode) -> &'static str {
    if status.is_client_error() {
        "error_status_4xx"
    } else if status.is_server_error() {
        "error_status_5xx"
    } else {
        "error_status_other"
    }
}

/// Walk the error's `source` chain and join every layer's `Display` output
/// with " -> ". reqwest's top-level message is `error sending request for
/// url (...)`; the real cause (connection reset, DNS failure, TLS
/// handshake, ...) lives further down and is what tells the operator what
/// actually went wrong.
fn error_cause_chain(error: &(dyn std::error::Error + 'static)) -> String {
    use std::fmt::Write as _;
    let mut out = error.to_string();
    let mut cause = error.source();
    while let Some(source) = cause {
        let _ = write!(out, " -> {source}");
        cause = source.source();
    }
    out
}

fn sign(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .expect("analytics signing key should be accepted by HMAC");
    mac.update(body);
    hex::encode(mac.finalize().into_bytes())
}

// Milliseconds since the Unix epoch. Saturates at u64::MAX on the impossibly
// distant future; returns 0 on a system clock that predates the epoch, which
// only happens on a misconfigured test machine.
fn observed_at_ms_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| u64::try_from(elapsed.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
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
mod tests {
    use std::{
        collections::BTreeMap,
        sync::{Arc, Mutex},
    };

    use axum::{
        Router, body::Bytes, extract::Request, http::StatusCode, response::IntoResponse,
        routing::post,
    };
    use http_body_util::BodyExt;
    use serde_json::Value;
    use tokio::time::{Duration, Instant, sleep, timeout};

    use crate::{config::AnalyticsConfig, metrics::Metrics};

    use super::{
        Analytics, BazelInvocationAnalyticsEvent, BazelInvocationLogAnalyticsEvent, CircuitBreaker,
        CircuitState, GRADLE_WEBHOOK_PATH, ReapiCacheAnalyticsEvent, analytics_endpoint,
        classify_reqwest_error, error_cause_chain, error_result_label, sign, status_result_label,
    };

    #[derive(Clone, Debug)]
    struct CapturedRequest {
        path: String,
        headers: Vec<(String, String)>,
        body: Vec<u8>,
    }

    #[tokio::test]
    async fn batches_and_signs_xcode_gradle_reapi_cache_and_bazel_invocation_events() {
        let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
        let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
        let analytics = Analytics::from_config(
            Some(&AnalyticsConfig {
                server_url: base_url,
                signing_key: "secret-key".into(),
                batch_size: 1,
                batch_timeout_ms: 5_000,
                queue_capacity: 8,
                request_timeout_ms: 5_000,
                circuit_breaker_failure_threshold: 2,
                circuit_breaker_open_ms: 5_000,
            }),
            "https://cache-us-east-3.example.com:7443",
            Metrics::new("us-east".into(), "tenant".into()),
        )
        .expect("analytics should initialize")
        .expect("analytics should be enabled");

        analytics.enqueue_xcode_upload("acme", "ios", "cas-1", 42);
        analytics.enqueue_gradle_download("acme", "android", "gradle-key", 64);
        analytics.enqueue_reapi_cache_event(|| ReapiCacheAnalyticsEvent {
            event_id: uuid::Uuid::now_v7(),
            context: Arc::new(super::ReapiCacheAnalyticsContext {
                account_handle: "acme".into(),
                project_handle: "bazel".into(),
                client_kind: "bazel",
                invocation_id: "invocation-1".into(),
                action_mnemonic: "SwiftCompile".into(),
                target_label: "//app:app".into(),
                configuration_id: "config-1".into(),
            }),
            operation: "action_cache",
            outcome: "hit",
            action_digest: "digest-1".into(),
            size: 128,
            duration_us: 9_400,
            observed_at_ms: 1_700_000_000_123,
        });
        analytics.enqueue_bazel_invocation_event(BazelInvocationAnalyticsEvent {
            account_handle: "acme".into(),
            project_handle: "bazel".into(),
            invocation_id: "invocation-1".into(),
            command: "test".into(),
            target_patterns: vec!["//...".into()],
            git_branch: "main".into(),
            git_commit_sha: "abc123".into(),
            is_ci: true,
            custom_values: BTreeMap::from([
                ("environment".into(), "local".into()),
                ("runner".into(), "linux-arm64".into()),
            ]),
            bazel_version: "9.1.0".into(),
            cpu_time_ms: 1_250,
            actions_created: 11,
            actions_executed: 10,
            targets_configured: 4,
            packages_loaded: 2,
            build_timeline_duration_ms: 15_000,
            build_timeline_lanes: vec!["Execution lane 1".into()],
            build_timeline_span_lanes: vec![0],
            build_timeline_span_start_ms: vec![500],
            build_timeline_span_durations_ms: vec![1_000],
            build_timeline_span_categories: vec!["execution".into()],
            build_timeline_span_descriptions: vec!["Compile //app:app".into()],
            critical_path_duration_ms: 1_000,
            critical_path_action_descriptions: vec!["Compile //app:app".into()],
            critical_path_action_durations_ms: vec![1_000],
            logs: vec![BazelInvocationLogAnalyticsEvent {
                sequence_number: 6,
                stream: "stderr",
                message: "build failed".into(),
                observed_at_ms: 1_700_000_014_000,
            }],
            status: "success".into(),
            exit_code: 0,
            started_at_ms: 1_700_000_000_000,
            finished_at_ms: 1_700_000_015_000,
        });

        timeout(Duration::from_secs(2), async {
            loop {
                if captured.lock().expect("captured requests lock").len() >= 4 {
                    break;
                }
                sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("analytics batches should be delivered");

        let requests = captured.lock().expect("captured requests lock");
        assert_eq!(requests.len(), 4);

        let xcode = requests
            .iter()
            .find(|request| request.path == "/webhooks/cache")
            .expect("xcode analytics request should be present");
        assert_signed(xcode, "secret-key", "cache-us-east-3.example.com:7443");
        let mut xcode_body: Value =
            serde_json::from_slice(&xcode.body).expect("xcode payload should decode");
        assert_event_id_is_uuidv7(&mut xcode_body["events"][0]);
        assert_observed_at_is_recent(&mut xcode_body["events"][0]);
        assert_eq!(
            xcode_body,
            serde_json::json!({
                "events": [{
                    "account_handle": "acme",
                    "project_handle": "ios",
                    "action": "upload",
                    "size": 42,
                    "cas_id": "cas-1"
                }]
            })
        );

        let gradle = requests
            .iter()
            .find(|request| request.path == "/webhooks/gradle-cache")
            .expect("gradle analytics request should be present");
        assert_signed(gradle, "secret-key", "cache-us-east-3.example.com:7443");
        let mut gradle_body: Value =
            serde_json::from_slice(&gradle.body).expect("gradle payload should decode");
        assert_event_id_is_uuidv7(&mut gradle_body["events"][0]);
        assert_observed_at_is_recent(&mut gradle_body["events"][0]);
        assert_eq!(
            gradle_body,
            serde_json::json!({
                "events": [{
                    "account_handle": "acme",
                    "project_handle": "android",
                    "action": "download",
                    "size": 64,
                    "cache_key": "gradle-key"
                }]
            })
        );

        let reapi_cache = requests
            .iter()
            .find(|request| request.path == "/webhooks/reapi-cache")
            .expect("REAPI cache analytics request should be present");
        assert_signed(
            reapi_cache,
            "secret-key",
            "cache-us-east-3.example.com:7443",
        );
        let mut reapi_cache_body: Value =
            serde_json::from_slice(&reapi_cache.body).expect("REAPI cache payload should decode");
        assert_event_id_is_uuidv7(&mut reapi_cache_body["events"][0]);
        assert_eq!(
            reapi_cache_body,
            serde_json::json!({
                "events": [{
                    "account_handle": "acme",
                    "project_handle": "bazel",
                    "client_kind": "bazel",
                    "operation": "action_cache",
                    "outcome": "hit",
                    "action_digest": "digest-1",
                    "size": 128,
                    "duration_us": 9400,
                    "duration_ms": 9,
                    "observed_at_ms": 1700000000123u64,
                    "invocation_id": "invocation-1",
                    "action_mnemonic": "SwiftCompile",
                    "target_label": "//app:app",
                    "configuration_id": "config-1"
                }]
            })
        );

        let bazel_invocations = requests
            .iter()
            .find(|request| request.path == "/webhooks/bazel-invocations")
            .expect("Bazel invocation analytics request should be present");
        assert_signed(
            bazel_invocations,
            "secret-key",
            "cache-us-east-3.example.com:7443",
        );
        let bazel_invocations_body: Value = serde_json::from_slice(&bazel_invocations.body)
            .expect("Bazel invocation payload should decode");
        assert_eq!(
            bazel_invocations_body,
            serde_json::json!({
                "events": [{
                    "account_handle": "acme",
                    "project_handle": "bazel",
                    "invocation_id": "invocation-1",
                    "command": "test",
                    "status": "success",
                    "exit_code": 0,
                    "target_patterns": ["//..."],
                    "is_ci": true,
                    "git_branch": "main",
                    "git_commit_sha": "abc123",
                    "custom_values": {
                        "environment": "local",
                        "runner": "linux-arm64"
                    },
                    "bazel_version": "9.1.0",
                    "cpu_time_ms": 1_250,
                    "actions_created": 11,
                    "actions_executed": 10,
                    "targets_configured": 4,
                    "packages_loaded": 2,
                    "build_timeline_duration_ms": 15_000,
                    "build_timeline_lanes": ["Execution lane 1"],
                    "build_timeline_span_lanes": [0],
                    "build_timeline_span_start_ms": [500],
                    "build_timeline_span_durations_ms": [1_000],
                    "build_timeline_span_categories": ["execution"],
                    "build_timeline_span_descriptions": ["Compile //app:app"],
                    "critical_path_duration_ms": 1_000,
                    "critical_path_action_descriptions": ["Compile //app:app"],
                    "critical_path_action_durations_ms": [1_000],
                    "logs": [{
                        "sequence_number": 6,
                        "stream": "stderr",
                        "message": "build failed",
                        "observed_at_ms": 1_700_000_014_000u64
                    }],
                    "started_at_ms": 1_700_000_000_000u64,
                    "finished_at_ms": 1_700_000_015_000u64
                }]
            })
        );
    }

    #[tokio::test]
    async fn caps_bazel_invocation_batches_independently_of_the_general_batch_size() {
        let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
        let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
        let analytics = Analytics::from_config(
            Some(&AnalyticsConfig {
                server_url: base_url,
                signing_key: "secret-key".into(),
                batch_size: 100,
                batch_timeout_ms: 50,
                queue_capacity: 100,
                request_timeout_ms: 5_000,
                circuit_breaker_failure_threshold: 2,
                circuit_breaker_open_ms: 5_000,
            }),
            "https://cache-us-east-3.example.com:7443",
            Metrics::new("us-east".into(), "tenant".into()),
        )
        .expect("analytics should initialize")
        .expect("analytics should be enabled");

        for index in 0..33 {
            analytics.enqueue_bazel_invocation_event(empty_bazel_invocation_event(index));
        }

        timeout(Duration::from_secs(2), async {
            loop {
                if captured.lock().expect("captured requests lock").len() == 2 {
                    break;
                }
                sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("Bazel invocation batches should be delivered");

        let requests = captured.lock().expect("captured requests lock");
        let batch_sizes = requests
            .iter()
            .map(|request| {
                let body: Value = serde_json::from_slice(&request.body)
                    .expect("Bazel invocation payload should decode");
                body["events"]
                    .as_array()
                    .expect("Bazel invocation payload should contain events")
                    .len()
            })
            .collect::<Vec<_>>();

        assert_eq!(batch_sizes, vec![32, 1]);
    }

    #[tokio::test]
    async fn sends_content_addressable_storage_cache_events() {
        let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
        let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
        let analytics = Analytics::from_config(
            Some(&AnalyticsConfig {
                server_url: base_url,
                signing_key: "secret-key".into(),
                batch_size: 1,
                batch_timeout_ms: 5_000,
                queue_capacity: 8,
                request_timeout_ms: 5_000,
                circuit_breaker_failure_threshold: 2,
                circuit_breaker_open_ms: 5_000,
            }),
            "https://cache-us-east-3.example.com:7443",
            Metrics::new("us-east".into(), "tenant".into()),
        )
        .expect("analytics should initialize")
        .expect("analytics should be enabled");

        analytics.enqueue_reapi_cache_event(|| ReapiCacheAnalyticsEvent {
            event_id: uuid::Uuid::now_v7(),
            context: Arc::new(super::ReapiCacheAnalyticsContext {
                account_handle: "acme".into(),
                project_handle: "bazel".into(),
                client_kind: "bazel",
                invocation_id: "invocation-1".into(),
                action_mnemonic: "".into(),
                target_label: "".into(),
                configuration_id: "".into(),
            }),
            operation: "cas",
            outcome: "write",
            action_digest: "content-digest".into(),
            size: 4_096,
            duration_us: 14_500,
            observed_at_ms: 1_700_000_000_456,
        });

        timeout(Duration::from_secs(2), async {
            loop {
                if captured.lock().expect("captured requests lock").len() == 1 {
                    break;
                }
                sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("analytics batch should be delivered");

        let requests = captured.lock().expect("captured requests lock");
        let reapi_cache = requests
            .iter()
            .find(|request| request.path == "/webhooks/reapi-cache")
            .expect("Remote Execution API cache analytics request should be present");

        assert_signed(
            reapi_cache,
            "secret-key",
            "cache-us-east-3.example.com:7443",
        );

        let mut body: Value =
            serde_json::from_slice(&reapi_cache.body).expect("cache payload should decode");
        assert_event_id_is_uuidv7(&mut body["events"][0]);
        assert_eq!(
            body,
            serde_json::json!({
                "events": [{
                    "account_handle": "acme",
                    "project_handle": "bazel",
                    "client_kind": "bazel",
                    "operation": "cas",
                    "outcome": "write",
                    "action_digest": "content-digest",
                    "size": 4096,
                    "duration_us": 14500,
                    "duration_ms": 14,
                    "observed_at_ms": 1700000000456u64,
                    "invocation_id": "invocation-1",
                    "action_mnemonic": "",
                    "target_label": "",
                    "configuration_id": ""
                }]
            })
        );
    }

    #[tokio::test]
    async fn circuit_breaker_stops_delivery_after_repeated_failures() {
        let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
        let (base_url, _handle) =
            spawn_capture_server_with_status(captured.clone(), StatusCode::INTERNAL_SERVER_ERROR)
                .await;
        let analytics = Analytics::from_config(
            Some(&AnalyticsConfig {
                server_url: base_url,
                signing_key: "secret-key".into(),
                batch_size: 1,
                batch_timeout_ms: 5_000,
                queue_capacity: 8,
                request_timeout_ms: 1_000,
                circuit_breaker_failure_threshold: 2,
                circuit_breaker_open_ms: 60_000,
            }),
            "https://cache-us-east-3.example.com:7443",
            Metrics::new("us-east".into(), "tenant".into()),
        )
        .expect("analytics should initialize")
        .expect("analytics should be enabled");

        analytics.enqueue_xcode_upload("acme", "ios", "cas-1", 1);
        analytics.enqueue_xcode_upload("acme", "ios", "cas-2", 1);
        analytics.enqueue_xcode_upload("acme", "ios", "cas-3", 1);
        analytics.enqueue_xcode_upload("acme", "ios", "cas-4", 1);

        timeout(Duration::from_secs(2), async {
            loop {
                if analytics.pending.load(std::sync::atomic::Ordering::Relaxed) == 0 {
                    break;
                }
                sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("analytics queue should drain");

        let requests = captured.lock().expect("captured requests lock");
        assert_eq!(
            requests.len(),
            2,
            "only the first two failures should reach the upstream before the breaker opens"
        );
    }

    #[test]
    fn derives_cache_endpoint_header_from_node_url() {
        assert_eq!(
            analytics_endpoint("https://cache-eu.example.com:7443"),
            "cache-eu.example.com:7443"
        );
        assert_eq!(
            analytics_endpoint("https://cache-eu.example.com"),
            "cache-eu.example.com"
        );
    }

    #[test]
    fn keeps_an_absolute_host_absolute() {
        // The chart renders the analytics URL in absolute form so a node does
        // not expand a cluster-local name against every search domain first.
        // That only helps if the trailing dot survives to the resolver.
        let url = reqwest::Url::parse(&format!(
            "{}{}",
            "http://tuist-tuist-server.tuist.svc.cluster.local.:80", GRADLE_WEBHOOK_PATH
        ))
        .expect("an absolute host must parse");

        assert_eq!(
            url.host_str(),
            Some("tuist-tuist-server.tuist.svc.cluster.local.")
        );
    }

    #[tokio::test]
    async fn classifies_connect_timeout_separately_from_full_request_timeout() {
        // 240.0.0.1/4 is IANA-reserved and unroutable, so a TCP connect to
        // it never completes. A tiny connect_timeout forces the client to
        // return the connect-timeout branch of `reqwest::Error`, which in
        // reqwest 0.13.x is `is_connect() == true && is_timeout() == true`.
        // The classifier's precedence must return `connect` here.
        let client = reqwest::Client::builder()
            .connect_timeout(Duration::from_millis(20))
            .timeout(Duration::from_secs(30))
            .build()
            .expect("client should build");
        let error = client
            .post("http://240.0.0.1:9/webhooks/gradle-cache")
            .body(Vec::<u8>::new())
            .send()
            .await
            .expect_err("connect to unroutable address should fail");
        assert_eq!(
            classify_reqwest_error(&error),
            "connect",
            "a connect-timeout must classify as connect, not timeout; \
             precedence order in classify_reqwest_error is load-bearing"
        );

        // A listener that accepts but never reads triggers reqwest's overall
        // request timeout (not the connect timeout). `is_connect()` is
        // false here, so the classifier falls through to `timeout`.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("listener should bind");
        let addr = listener.local_addr().expect("listener has an address");
        let accept_task = tokio::spawn(async move {
            // Accept once and hold the socket so the client hangs on the
            // full-request timeout rather than on connect.
            let (socket, _) = listener.accept().await.expect("accept");
            tokio::time::sleep(Duration::from_secs(5)).await;
            drop(socket);
        });
        let client = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_millis(200))
            .build()
            .expect("client should build");
        let error = client
            .post(format!("http://{addr}/webhooks/gradle-cache"))
            .body(Vec::<u8>::new())
            .send()
            .await
            .expect_err("request beyond overall timeout should fail");
        assert_eq!(
            classify_reqwest_error(&error),
            "timeout",
            "a full-request timeout must classify as timeout, not connect"
        );
        accept_task.abort();
    }

    #[test]
    fn error_result_labels_are_stable_and_bounded() {
        for kind in [
            "timeout", "connect", "body", "decode", "request", "other", "made-up",
        ] {
            let label = error_result_label(kind);
            assert!(
                label.starts_with("error_"),
                "label {label} should carry the `error_` prefix so Prometheus can regex it"
            );
        }
        assert_eq!(error_result_label("timeout"), "error_timeout");
        assert_eq!(error_result_label("connect"), "error_connect");
        assert_eq!(error_result_label("something-new"), "error_other");
    }

    #[test]
    fn status_result_labels_split_by_class() {
        assert_eq!(
            status_result_label(StatusCode::BAD_REQUEST),
            "error_status_4xx"
        );
        assert_eq!(
            status_result_label(StatusCode::INTERNAL_SERVER_ERROR),
            "error_status_5xx"
        );
        assert_eq!(
            status_result_label(StatusCode::PERMANENT_REDIRECT),
            "error_status_other"
        );
    }

    #[test]
    fn cause_chain_joins_every_source() {
        use std::fmt;

        #[derive(Debug)]
        struct Layer {
            message: &'static str,
            source: Option<Box<dyn std::error::Error + 'static>>,
        }
        impl fmt::Display for Layer {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.message)
            }
        }
        impl std::error::Error for Layer {
            fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
                self.source.as_deref()
            }
        }

        let leaf = Layer {
            message: "connection reset by peer",
            source: None,
        };
        let middle = Layer {
            message: "tcp connect failed",
            source: Some(Box::new(leaf)),
        };
        let top = Layer {
            message: "error sending request",
            source: Some(Box::new(middle)),
        };

        assert_eq!(
            error_cause_chain(&top),
            "error sending request -> tcp connect failed -> connection reset by peer"
        );
    }

    #[test]
    fn circuit_breaker_opens_and_recovers() {
        let mut breaker = CircuitBreaker::new();
        let open_duration = Duration::from_secs(30);
        let now = Instant::now();

        assert!(breaker.allow_request(now, open_duration));
        assert_eq!(breaker.on_failure(now, 2, open_duration), None);
        assert_eq!(breaker.state, CircuitState::Closed);

        assert!(breaker.allow_request(now, open_duration));
        assert_eq!(
            breaker.on_failure(now, 2, open_duration),
            Some((CircuitState::Closed, CircuitState::Open))
        );
        assert_eq!(breaker.state, CircuitState::Open);
        assert!(!breaker.allow_request(now + Duration::from_secs(5), open_duration));

        assert!(breaker.allow_request(now + open_duration, open_duration));
        assert_eq!(breaker.state, CircuitState::HalfOpen);
        assert_eq!(
            breaker.on_success(),
            Some((CircuitState::HalfOpen, CircuitState::Closed))
        );
        assert_eq!(breaker.state, CircuitState::Closed);
    }

    fn assert_signed(request: &CapturedRequest, secret: &str, endpoint: &str) {
        let signature = request
            .headers
            .iter()
            .find(|(key, _)| key == "x-cache-signature")
            .map(|(_, value)| value.as_str())
            .expect("signature header should be present");
        assert_eq!(signature, sign(secret, &request.body));

        let cache_endpoint = request
            .headers
            .iter()
            .find(|(key, _)| key == "x-cache-endpoint")
            .map(|(_, value)| value.as_str())
            .expect("cache endpoint header should be present");
        assert_eq!(cache_endpoint, endpoint);
    }

    // Assert the event's `event_id` field is a well-formed UUIDv7, then remove
    // it from the value so the caller can compare the rest of the payload
    // against a fixed fixture. UUIDv7 embeds a millisecond timestamp in the
    // top 48 bits; checking the version keeps the test honest that we're not
    // shipping v4 or a nil UUID.
    fn assert_event_id_is_uuidv7(event: &mut Value) {
        let object = event
            .as_object_mut()
            .expect("event should decode to a JSON object");
        let raw = object
            .remove("event_id")
            .expect("event should carry an `event_id` field");
        let text = raw.as_str().expect("`event_id` should be a JSON string");
        let parsed = uuid::Uuid::parse_str(text).expect("`event_id` should parse as a UUID");
        assert_eq!(
            parsed.get_version_num(),
            7,
            "`event_id` should be a UUIDv7, got {parsed}",
        );
    }

    // Same shape as `assert_event_id_is_uuidv7`: pull `observed_at_ms` off the
    // event, sanity-check it's inside a plausible modern-epoch window, and
    // remove it so a fixture comparison can proceed. The check window is
    // deliberately wide (10^12 to 10^14) so time-skewed CI does not flake.
    fn assert_observed_at_is_recent(event: &mut Value) {
        let object = event
            .as_object_mut()
            .expect("event should decode to a JSON object");
        let raw = object
            .remove("observed_at_ms")
            .expect("event should carry an `observed_at_ms` field");
        let value = raw
            .as_u64()
            .expect("`observed_at_ms` should be a non-negative integer");
        assert!(
            (1_000_000_000_000..100_000_000_000_000).contains(&value),
            "`observed_at_ms` outside a plausible modern-epoch range: {value}",
        );
    }

    fn empty_bazel_invocation_event(index: usize) -> BazelInvocationAnalyticsEvent {
        BazelInvocationAnalyticsEvent {
            account_handle: "acme".into(),
            project_handle: "bazel".into(),
            invocation_id: format!("invocation-{index}"),
            command: "build".into(),
            target_patterns: Vec::new(),
            git_branch: String::new(),
            git_commit_sha: String::new(),
            is_ci: false,
            custom_values: BTreeMap::new(),
            bazel_version: String::new(),
            cpu_time_ms: 0,
            actions_created: 0,
            actions_executed: 0,
            targets_configured: 0,
            packages_loaded: 0,
            build_timeline_duration_ms: 0,
            build_timeline_lanes: Vec::new(),
            build_timeline_span_lanes: Vec::new(),
            build_timeline_span_start_ms: Vec::new(),
            build_timeline_span_durations_ms: Vec::new(),
            build_timeline_span_categories: Vec::new(),
            build_timeline_span_descriptions: Vec::new(),
            critical_path_duration_ms: 0,
            critical_path_action_descriptions: Vec::new(),
            critical_path_action_durations_ms: Vec::new(),
            logs: Vec::new(),
            status: "success".into(),
            exit_code: 0,
            started_at_ms: 0,
            finished_at_ms: 0,
        }
    }

    async fn spawn_capture_server(
        captured: Arc<Mutex<Vec<CapturedRequest>>>,
    ) -> (String, tokio::task::JoinHandle<()>) {
        spawn_capture_server_with_status(captured, StatusCode::ACCEPTED).await
    }

    async fn spawn_capture_server_with_status(
        captured: Arc<Mutex<Vec<CapturedRequest>>>,
        status: StatusCode,
    ) -> (String, tokio::task::JoinHandle<()>) {
        let router = Router::new()
            .route(
                "/webhooks/cache",
                post({
                    let captured = captured.clone();
                    move |request| capture_request(captured.clone(), request, status)
                }),
            )
            .route(
                "/webhooks/gradle-cache",
                post({
                    let captured = captured.clone();
                    move |request| capture_request(captured.clone(), request, status)
                }),
            );
        let router = router.route(
            "/webhooks/reapi-cache",
            post({
                let captured = captured.clone();
                move |request| capture_request(captured.clone(), request, status)
            }),
        );
        let router = router.route(
            "/webhooks/bazel-invocations",
            post({
                let captured = captured.clone();
                move |request| capture_request(captured.clone(), request, status)
            }),
        );

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("test listener should bind");
        let address = listener
            .local_addr()
            .expect("test listener should expose local address");
        let handle = tokio::spawn(async move {
            axum::serve(listener, router)
                .await
                .expect("capture server should run");
        });

        (format!("http://{}", address), handle)
    }

    async fn capture_request(
        captured: Arc<Mutex<Vec<CapturedRequest>>>,
        request: Request,
        status: StatusCode,
    ) -> impl IntoResponse {
        let (parts, body) = request.into_parts();
        let body = body
            .collect()
            .await
            .expect("request body should collect")
            .to_bytes();
        let headers = parts
            .headers
            .iter()
            .map(|(key, value)| {
                (
                    key.as_str().to_owned(),
                    value.to_str().unwrap_or_default().to_owned(),
                )
            })
            .collect::<Vec<_>>();
        captured
            .lock()
            .expect("captured requests lock")
            .push(CapturedRequest {
                path: parts.uri.path().to_owned(),
                headers,
                body: Bytes::copy_from_slice(&body).to_vec(),
            });
        status
    }
}
