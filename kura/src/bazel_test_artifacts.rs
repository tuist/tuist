//! Best-effort delivery of Bazel's conventional test artifacts to Tuist.
//!
//! The Build Event Protocol handler only enqueues target metadata and artifact
//! digests. This worker reads and forwards the artifacts later, under a strict
//! size cap and a background memory reservation. Result admission never waits;
//! only the small invocation-completion marker applies bounded backpressure so
//! accepted results are processed in order.

use std::{sync::Arc, time::Duration};

use base64::{Engine, engine::general_purpose::STANDARD};
use hmac::{Hmac, Mac};
use reqwest::{Client, StatusCode, header::CONTENT_TYPE};
use serde::Serialize;
use sha2::Sha256;
use tokio::{sync::mpsc, time::sleep};
use tracing::{debug, warn};

use crate::{
    artifact::producer::ArtifactProducer, config::AnalyticsConfig, memory::MemoryController,
    metrics::Metrics, store::Store, utils::blob_key,
};

type HmacSha256 = Hmac<Sha256>;

const BAZEL_TEST_ARTIFACTS_WEBHOOK_PATH: &str = "/webhooks/bazel-test-artifacts";
/// Limits both local materialization and the webhook body. A JUnit report can
/// contain arbitrarily large failure output, so sending it is intentionally a
/// diagnostic best effort rather than a second artifact-transfer protocol.
pub const MAX_BAZEL_TEST_ARTIFACT_BYTES: u64 = 256 * 1024;
const DELIVERY_MEMORY_OVERHEAD_BYTES: u64 = 64 * 1024;
const DELIVERY_ATTEMPTS: usize = 5;
const MAX_BAZEL_TEST_ARTIFACT_QUEUE_DEPTH: usize = 64;

#[derive(Clone)]
pub struct BazelTestArtifactDelivery {
    sender: mpsc::Sender<DeliveryEvent>,
    metrics: Metrics,
}

#[derive(Clone, Debug)]
pub struct BazelTestResult {
    pub account_handle: String,
    pub project_handle: String,
    pub invocation_id: String,
    pub target_label: String,
    pub run: i32,
    pub shard: i32,
    pub attempt: i32,
    pub status: &'static str,
    pub duration_ms: u64,
    pub started_at_ms: u64,
    pub cached: bool,
    pub is_ci: bool,
    pub sequence_number: i64,
    pub artifacts: Vec<BazelTestArtifact>,
}

#[derive(Clone, Debug)]
pub struct BazelTestInvocationFinished {
    pub account_handle: String,
    pub project_handle: String,
    pub invocation_id: String,
}

#[derive(Clone, Debug)]
pub struct BazelTestSummary {
    pub account_handle: String,
    pub project_handle: String,
    pub invocation_id: String,
    pub target_label: String,
    pub status: &'static str,
    pub total_run_count: i32,
    pub total_num_cached: i32,
    pub duration_ms: u64,
    pub started_at_ms: u64,
    pub finished_at_ms: u64,
}

#[derive(Clone, Debug)]
pub struct BazelTestArtifact {
    pub artifact_kind: BazelTestArtifactKind,
    pub digest: String,
    pub size: u64,
}

#[derive(Clone, Debug)]
enum DeliveryEvent {
    TestResult(BazelTestResult),
    TestSummary(BazelTestSummary),
    InvocationFinished(BazelTestInvocationFinished),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BazelTestArtifactKind {
    Junit,
    Log,
}

impl BazelTestArtifactKind {
    pub fn from_output_path(path: &str) -> Option<Self> {
        match path.rsplit('/').next()? {
            "test.xml" => Some(Self::Junit),
            "test.log" => Some(Self::Log),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Junit => "junit",
            Self::Log => "log",
        }
    }
}

#[derive(Clone)]
struct Runtime {
    client: Client,
    config: AnalyticsConfig,
    cache_endpoint: String,
    store: Arc<Store>,
    memory: MemoryController,
    metrics: Metrics,
}

#[derive(Serialize)]
struct TestResultPayload<'a> {
    event_kind: &'static str,
    account_handle: &'a str,
    project_handle: &'a str,
    invocation_id: &'a str,
    target_label: &'a str,
    run: i32,
    shard: i32,
    attempt: i32,
    status: &'a str,
    duration_ms: u64,
    started_at_ms: u64,
    cached: bool,
    is_ci: bool,
    sequence_number: i64,
    artifacts: Vec<ArtifactPayload<'a>>,
}

#[derive(Serialize)]
struct ArtifactPayload<'a> {
    artifact_kind: &'a str,
    digest: &'a str,
    content_base64: String,
}

#[derive(Serialize)]
struct InvocationFinishedPayload<'a> {
    event_kind: &'static str,
    account_handle: &'a str,
    project_handle: &'a str,
    invocation_id: &'a str,
}

#[derive(Serialize)]
struct TestSummaryPayload<'a> {
    event_kind: &'static str,
    account_handle: &'a str,
    project_handle: &'a str,
    invocation_id: &'a str,
    target_label: &'a str,
    status: &'a str,
    total_run_count: i32,
    total_num_cached: i32,
    duration_ms: u64,
    started_at_ms: u64,
    finished_at_ms: u64,
}

impl BazelTestArtifactDelivery {
    pub fn from_config(
        analytics_config: Option<&AnalyticsConfig>,
        node_url: &str,
        store: Arc<Store>,
        memory: MemoryController,
        metrics: Metrics,
    ) -> Result<Option<Self>, String> {
        let Some(config) = analytics_config.cloned() else {
            return Ok(None);
        };

        let client = Client::builder()
            .connect_timeout(Duration::from_millis(500))
            .timeout(Duration::from_millis(config.request_timeout_ms))
            .build()
            .map_err(|error| format!("failed to build Bazel test-artifact client: {error}"))?;
        let (sender, receiver) = mpsc::channel(
            config
                .queue_capacity
                .min(MAX_BAZEL_TEST_ARTIFACT_QUEUE_DEPTH),
        );
        let runtime = Runtime {
            client,
            config,
            cache_endpoint: cache_endpoint(node_url),
            store,
            memory,
            metrics: metrics.clone(),
        };

        tokio::spawn(async move {
            runtime.run(receiver).await;
        });

        Ok(Some(Self { sender, metrics }))
    }

    /// Queues metadata only. This deliberately never waits for I/O, memory, or
    /// webhook capacity on the build-event stream.
    pub fn enqueue_test_result(&self, test_result: BazelTestResult) {
        match self.sender.try_send(DeliveryEvent::TestResult(test_result)) {
            Ok(()) => {
                self.metrics
                    .record_analytics_event("bazel_test_artifact", "enqueued", 1);
            }
            Err(_) => {
                self.metrics
                    .record_analytics_event("bazel_test_artifact", "dropped", 1);
            }
        }
    }

    pub fn enqueue_test_summary(&self, test_summary: BazelTestSummary) {
        match self
            .sender
            .try_send(DeliveryEvent::TestSummary(test_summary))
        {
            Ok(()) => {
                self.metrics
                    .record_analytics_event("bazel_test_summary", "enqueued", 1);
            }
            Err(_) => {
                self.metrics
                    .record_analytics_event("bazel_test_summary", "dropped", 1);
            }
        }
    }

    /// Queues a completion marker behind every accepted result for the same
    /// invocation. Waiting for bounded queue capacity preserves ordering
    /// without allocating beyond the configured delivery budget.
    pub async fn enqueue_invocation_finished(&self, invocation: BazelTestInvocationFinished) {
        match self
            .sender
            .send(DeliveryEvent::InvocationFinished(invocation))
            .await
        {
            Ok(()) => {
                self.metrics.record_analytics_event(
                    "bazel_test_artifact_completion",
                    "enqueued",
                    1,
                );
            }
            Err(_) => {
                self.metrics
                    .record_analytics_event("bazel_test_artifact_completion", "dropped", 1);
            }
        }
    }
}

impl Runtime {
    async fn run(self, mut receiver: mpsc::Receiver<DeliveryEvent>) {
        while let Some(event) = receiver.recv().await {
            match event {
                DeliveryEvent::TestResult(test_result) => {
                    self.deliver_test_result(test_result).await;
                }
                DeliveryEvent::TestSummary(test_summary) => {
                    self.deliver_test_summary(test_summary).await;
                }
                DeliveryEvent::InvocationFinished(invocation) => {
                    self.deliver_invocation_finished(invocation).await;
                }
            }
        }
    }

    async fn deliver_test_result(&self, test_result: BazelTestResult) {
        // Hold the reservation until the raw bytes, base64 payload, serialized
        // request, and retry clone have all been released. The largest live
        // representation is bounded by the artifact size plus four expanded
        // or serialized copies.
        let artifact_bytes = test_result
            .artifacts
            .iter()
            .map(|artifact| artifact.size)
            .sum::<u64>();
        let reservation_bytes = artifact_bytes
            .saturating_mul(5)
            .saturating_add(DELIVERY_MEMORY_OVERHEAD_BYTES);
        let _reservation = match self
            .memory
            .reserve_background_transient(reservation_bytes)
            .await
        {
            Ok(reservation) => reservation,
            Err(()) => {
                self.metrics
                    .record_analytics_event("bazel_test_artifact", "memory_rejected", 1);
                return;
            }
        };

        let mut artifacts = Vec::with_capacity(test_result.artifacts.len());
        for artifact in &test_result.artifacts {
            let Some(bytes) = self
                .read_artifact(&test_result.project_handle, artifact)
                .await
            else {
                continue;
            };
            artifacts.push(ArtifactPayload {
                artifact_kind: artifact.artifact_kind.as_str(),
                digest: &artifact.digest,
                content_base64: STANDARD.encode(bytes),
            });
        }

        let payload = TestResultPayload {
            event_kind: "test_result",
            account_handle: &test_result.account_handle,
            project_handle: &test_result.project_handle,
            invocation_id: &test_result.invocation_id,
            target_label: &test_result.target_label,
            run: test_result.run,
            shard: test_result.shard,
            attempt: test_result.attempt,
            status: test_result.status,
            duration_ms: test_result.duration_ms,
            started_at_ms: test_result.started_at_ms,
            cached: test_result.cached,
            is_ci: test_result.is_ci,
            sequence_number: test_result.sequence_number,
            artifacts,
        };
        let body = match serde_json::to_vec(&payload) {
            Ok(body) => body,
            Err(error) => {
                warn!("failed to encode Bazel test artifact webhook payload: {error}");
                self.metrics
                    .record_analytics_event("bazel_test_artifact", "encode_error", 1);
                return;
            }
        };

        self.post(body).await;
    }

    async fn deliver_test_summary(&self, test_summary: BazelTestSummary) {
        let payload = TestSummaryPayload {
            event_kind: "test_summary",
            account_handle: &test_summary.account_handle,
            project_handle: &test_summary.project_handle,
            invocation_id: &test_summary.invocation_id,
            target_label: &test_summary.target_label,
            status: test_summary.status,
            total_run_count: test_summary.total_run_count,
            total_num_cached: test_summary.total_num_cached,
            duration_ms: test_summary.duration_ms,
            started_at_ms: test_summary.started_at_ms,
            finished_at_ms: test_summary.finished_at_ms,
        };
        let body = match serde_json::to_vec(&payload) {
            Ok(body) => body,
            Err(error) => {
                warn!("failed to encode Bazel test summary payload: {error}");
                self.metrics
                    .record_analytics_event("bazel_test_summary", "encode_error", 1);
                return;
            }
        };

        self.post(body).await;
    }

    async fn deliver_invocation_finished(&self, invocation: BazelTestInvocationFinished) {
        let payload = InvocationFinishedPayload {
            event_kind: "invocation_finished",
            account_handle: &invocation.account_handle,
            project_handle: &invocation.project_handle,
            invocation_id: &invocation.invocation_id,
        };
        let body = match serde_json::to_vec(&payload) {
            Ok(body) => body,
            Err(error) => {
                warn!("failed to encode Bazel test artifact completion payload: {error}");
                self.metrics.record_analytics_event(
                    "bazel_test_artifact_completion",
                    "encode_error",
                    1,
                );
                return;
            }
        };

        self.post(body).await;
    }

    async fn post(&self, body: Vec<u8>) {
        for attempt in 0..DELIVERY_ATTEMPTS {
            let started_at = std::time::Instant::now();
            let response = self
                .client
                .post(format!(
                    "{}{}",
                    self.config.server_url, BAZEL_TEST_ARTIFACTS_WEBHOOK_PATH
                ))
                .header(CONTENT_TYPE, "application/json")
                .header("x-cache-signature", sign(&self.config.signing_key, &body))
                .header("x-cache-endpoint", &self.cache_endpoint)
                .body(body.clone())
                .send()
                .await;

            match response {
                Ok(response) if response.status().is_success() => {
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "sent", 1);
                    self.metrics.record_analytics_batch(
                        "bazel_test_artifact",
                        "ok",
                        started_at.elapsed(),
                    );
                    return;
                }
                Ok(response)
                    if should_retry(response.status()) && attempt + 1 < DELIVERY_ATTEMPTS =>
                {
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "retry", 1);
                    sleep(retry_delay(attempt)).await;
                }
                Ok(response) => {
                    debug!(status = %response.status(), "Bazel test artifact delivery was not accepted");
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "delivery_error", 1);
                    self.metrics.record_analytics_batch(
                        "bazel_test_artifact",
                        "error",
                        started_at.elapsed(),
                    );
                    return;
                }
                Err(error) if attempt + 1 < DELIVERY_ATTEMPTS => {
                    debug!("Bazel test artifact delivery attempt failed: {error}");
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "retry", 1);
                    sleep(retry_delay(attempt)).await;
                }
                Err(error) => {
                    debug!("Bazel test artifact delivery failed: {error}");
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "delivery_error", 1);
                    self.metrics.record_analytics_batch(
                        "bazel_test_artifact",
                        "error",
                        started_at.elapsed(),
                    );
                    return;
                }
            }
        }
    }

    async fn read_artifact(
        &self,
        project_handle: &str,
        artifact: &BazelTestArtifact,
    ) -> Option<Vec<u8>> {
        let key = blob_key(&format!("{}/{}", artifact.digest, artifact.size));
        let manifest =
            match self
                .store
                .manifest_for_key(ArtifactProducer::Reapi, project_handle, &key)
            {
                Ok(Some(manifest)) if manifest.size == artifact.size => manifest,
                Ok(Some(_)) => {
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "size_mismatch", 1);
                    return None;
                }
                Ok(None) => {
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "missing", 1);
                    return None;
                }
                Err(error) => {
                    warn!("failed to resolve Bazel test artifact manifest: {error}");
                    self.metrics
                        .record_analytics_event("bazel_test_artifact", "read_error", 1);
                    return None;
                }
            };

        match self
            .store
            .read_artifact_bytes_tolerating_promotion(&manifest)
            .await
        {
            Ok(Some(bytes)) if bytes.len() as u64 == artifact.size => Some(bytes),
            Ok(Some(_)) => {
                self.metrics
                    .record_analytics_event("bazel_test_artifact", "size_mismatch", 1);
                None
            }
            Ok(None) => {
                self.metrics
                    .record_analytics_event("bazel_test_artifact", "missing", 1);
                None
            }
            Err(error) => {
                warn!("failed to read Bazel test artifact: {error}");
                self.metrics
                    .record_analytics_event("bazel_test_artifact", "read_error", 1);
                None
            }
        }
    }
}

fn cache_endpoint(node_url: &str) -> String {
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

fn sign(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .expect("analytics signing key should be accepted by HMAC");
    mac.update(body);
    hex::encode(mac.finalize().into_bytes())
}

fn should_retry(status: StatusCode) -> bool {
    status == StatusCode::CONFLICT
        || status == StatusCode::TOO_MANY_REQUESTS
        || status.is_server_error()
}

fn retry_delay(attempt: usize) -> Duration {
    Duration::from_millis(100 * (1_u64 << attempt.min(4)))
}

#[cfg(test)]
mod tests {
    use super::{BazelTestArtifactKind, MAX_BAZEL_TEST_ARTIFACT_BYTES, retry_delay, should_retry};

    #[test]
    fn recognizes_only_conventional_test_output_names() {
        assert_eq!(
            BazelTestArtifactKind::from_output_path("bazel-out/testlogs/app/test.xml"),
            Some(BazelTestArtifactKind::Junit)
        );
        assert_eq!(
            BazelTestArtifactKind::from_output_path("bazel-out/testlogs/app/test.log"),
            Some(BazelTestArtifactKind::Log)
        );
        assert_eq!(
            BazelTestArtifactKind::from_output_path("test.xml.bak"),
            None
        );
        assert_eq!(BazelTestArtifactKind::from_output_path("result.xml"), None);
    }

    #[test]
    fn retries_only_transient_control_plane_responses() {
        assert!(should_retry(reqwest::StatusCode::CONFLICT));
        assert!(should_retry(reqwest::StatusCode::TOO_MANY_REQUESTS));
        assert!(should_retry(reqwest::StatusCode::BAD_GATEWAY));
        assert!(!should_retry(reqwest::StatusCode::BAD_REQUEST));
        assert_eq!(retry_delay(0).as_millis(), 100);
        assert_eq!(retry_delay(4).as_millis(), 1_600);
        assert_eq!(MAX_BAZEL_TEST_ARTIFACT_BYTES, 256 * 1024);
    }
}
