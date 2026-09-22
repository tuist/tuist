//! Drain task that forwards analytics-outbox entries to the Tuist
//! server's webhook endpoints.
//!
//! Each pipeline ([`Pipeline::GradleCache`], [`Pipeline::XcodeCache`],
//! [`Pipeline::ReapiCache`]) runs its own drain loop. On each tick the
//! loop pulls a FIFO batch from the shared analytics-outbox column
//! family, POSTs the payload bytes to the pipeline's webhook, and
//! deletes the acknowledged keys on 2xx. Backoff on transient failures
//! and the two head-of-line quarantine signals surfaced by the store
//! ([`NextBatch::HeadTooLarge`] and [`NextBatch::HeadMalformed`]) are
//! handled here rather than pushed onto the caller: the invariant is
//! that a single unhappy row cannot block the pipeline forever.
//!
//! # Wire contract
//!
//! Each outbox entry's payload IS the POST body: opaque bytes the
//! producer already serialised. The forwarder appends the HMAC signature
//! and the cache-endpoint header the server expects, then delivers.
//! Because a batch may aggregate several entries at the store layer but
//! each entry is a self-contained webhook body, the forwarder POSTs one
//! entry per request rather than concatenating them. That keeps the
//! wire format identical to the pre-outbox in-memory path and lets the
//! server's existing dedup token stay meaningful on redelivery.
//!
//! # Quarantine (this PR)
//!
//! Both [`NextBatch::HeadTooLarge`] and [`NextBatch::HeadMalformed`]
//! delete the offending row after logging and metric bumps. A follow-up
//! PR will move the raw key and value into a dedicated quarantine
//! column family so operators can inspect and replay them. The public
//! interface of the loop is designed to make that swap invisible to
//! callers.
//!
//! # Rollout ordering
//!
//! The forwarder is wired into [`crate::app::run`] via
//! [`spawn_tasks`], but the producer has not yet been flipped to append
//! events to the outbox column family. The drain loops therefore idle
//! against an empty pipeline until the follow-up producer PR lands.
//! Landing the wiring first means the producer switch is a one-line
//! routing change rather than a scaffold-plus-routing change, and any
//! entries that end up in the outbox during a late rollout land in a
//! release that already drains them.
//!
//! # Bounds
//!
//! Kura is bound by memory, disk, CPU, and egress on every mesh node
//! (`kura/CLAUDE.md#resource-budgets`). The drain loop stays inside
//! all four at the shape it ships with:
//!
//! - **Memory.** One tick decodes at most `max_batch_entries` entries
//!   into `Vec<OutboxEntry>` before POSTing, bounded by
//!   `max_batch_bytes` (default 512 KiB). Across three pipelines the
//!   steady-state working set is ~1.5 MiB. Decoded entries drop at
//!   the end of the tick; `delivered_keys` never grows past
//!   `max_batch_entries`. Payload bytes are cloned once for
//!   [`reqwest::RequestBuilder::body`] and released with the response.
//!   No file-backed mmap and no per-request pool allocation, so this
//!   traffic does not surface in the pressure tier signal.
//! - **Disk.** Each successful drain issues one `WriteBatch` of `N`
//!   deletes through `write_batch_with_durability_off_runtime` with
//!   `ApplyDurability::Sync`. That is one fsync per batch, not per
//!   entry, and it runs on the store's blocking pool so it never parks
//!   a Tokio worker. Quarantine deletes are the same shape: one fsync
//!   per quarantined row.
//! - **CPU.** Per-entry work is HMAC-SHA256 over the payload plus one
//!   reqwest send. No JSON parse, no re-encode: the payload is opaque
//!   bytes the producer already serialised. Idle and failure sleeps
//!   are real timers, not spin loops; the failure backoff uses AWS-
//!   style full jitter capped at `failure_backoff_ms_max` so a fleet-
//!   wide outage cannot produce a synchronised retry storm.
//! - **Egress.** One POST per outbox entry, one request-body clone per
//!   POST, no per-entry reconnect (reqwest keepalive). The producer
//!   controls how many events land in each entry, so cross-pipeline
//!   parallelism (three drain tasks) plus intra-pipeline batching at
//!   the producer is what sets steady-state throughput. Egress is not
//!   shaped through [`crate::bandwidth::BandwidthLimiter`] because
//!   analytics traffic does not go over the peer path; the pre-outbox
//!   in-memory analytics runtime followed the same rule.
//!
//! # Cancellation
//!
//! `drain_pipeline` races the whole tick against the shared
//! [`CancellationToken`], so a shutdown fires within one poll pass
//! rather than waiting for a reqwest deadline. Dropping the tick
//! future cancels the in-flight POST cleanly and leaves the entry in
//! the outbox for redelivery on the next boot. That is safe because
//! the delete only runs after a 2xx response; a mid-flight POST that
//! races the cancel drops before it can ack anything.
//!
//! # Rollout skew
//!
//! No on-disk format changes here. The entry-schema types this module
//! depends on ([`crate::analytics_outbox`]) are the same ones a peer
//! at either side of a rolling deploy encodes and decodes, so a mixed-
//! version fleet still drains its outbox. The webhook wire contract
//! matches the pre-outbox in-memory path byte-for-byte, so a server
//! that has not rolled yet keeps accepting the same body shape and the
//! same headers.

use std::{sync::Arc, time::Duration};

use rand::Rng as _;
use reqwest::{Client, StatusCode, header::CONTENT_TYPE};
use tokio::time::{Instant, sleep};
use tokio_util::sync::CancellationToken;
use tracing::{error, info, warn};

use crate::{
    analytics::{
        classify_reqwest_error, error_cause_chain, error_result_label, sign, status_result_label,
    },
    analytics_outbox::{DecodeError, NextBatch, OutboxEntry, Pipeline},
    metrics::Metrics,
    store::Store,
};

/// Webhook paths served by the Tuist server. Kept in sync with the
/// per-pipeline consts in [`crate::analytics`] so a rename in one place
/// forces the same rename here.
const XCODE_WEBHOOK_PATH: &str = "/webhooks/cache";
const GRADLE_WEBHOOK_PATH: &str = "/webhooks/gradle-cache";
const REAPI_CACHE_WEBHOOK_PATH: &str = "/webhooks/reapi-cache";

/// HMAC signature header the server verifies on every webhook POST.
const HMAC_SIGNATURE_HEADER: &str = "x-cache-signature";
/// Node identifier the server uses to attribute the batch back to a
/// specific mesh peer for observability.
const CACHE_ENDPOINT_HEADER: &str = "x-cache-endpoint";

/// Runtime knobs for one drain loop. Cloned per pipeline task at spawn
/// time so each pipeline can be tuned independently in follow-up PRs
/// without changing this signature.
#[derive(Clone, Debug)]
pub struct ForwarderConfig {
    /// Absolute base URL for the Tuist server (e.g.
    /// `http://tuist-tuist-server.tuist.svc.cluster.local.:80`).
    pub server_url: String,
    /// HMAC signing secret shared with the server.
    pub signing_key: String,
    /// The `x-cache-endpoint` value the server uses to attribute batches
    /// to this mesh peer.
    pub cache_endpoint: String,
    /// Maximum entries pulled from RocksDB in one drain tick. The batch
    /// respects both this cap and `max_batch_bytes`, whichever is
    /// exhausted first.
    pub max_batch_entries: usize,
    /// Byte budget the drain tick will respect. When the head entry
    /// alone exceeds this, the loop hits the
    /// [`NextBatch::HeadTooLarge`] path, not a permanent 413 retry.
    pub max_batch_bytes: usize,
    /// Delay when the pipeline is empty. Kept short enough that a burst
    /// of appends does not sit in RocksDB for perceptible latency; kept
    /// non-zero so an empty pipeline does not busy-spin.
    pub idle_backoff_ms: u64,
    /// Base delay for retries after a transient failure. Actual sleep
    /// is `base * 2^attempt` with full jitter, capped at
    /// `failure_backoff_ms_max`. AWS-style full jitter beats
    /// exponential-only under fleet-wide correlated outages.
    pub failure_backoff_ms_base: u64,
    /// Ceiling for the jittered retry backoff.
    pub failure_backoff_ms_max: u64,
}

impl ForwarderConfig {
    /// Bounded defaults. Chosen to drain a typical steady-state pipeline
    /// (a few entries per second) without adding a scrape's worth of
    /// idle load; a follow-up PR exposes these through
    /// [`crate::config::AnalyticsConfig`] once the producer is routing
    /// through the outbox.
    #[must_use]
    pub fn defaults(server_url: String, signing_key: String, cache_endpoint: String) -> Self {
        Self {
            server_url,
            signing_key,
            cache_endpoint,
            max_batch_entries: 64,
            max_batch_bytes: 512 * 1024,
            idle_backoff_ms: 500,
            failure_backoff_ms_base: 250,
            failure_backoff_ms_max: 30_000,
        }
    }
}

/// Result label a drain tick reports to
/// [`Metrics::record_analytics_batch`]. Kept a bounded `&'static str`
/// so Prometheus label cardinality on the reused `result` column stays
/// finite. Every constant here is a live emit path — the idle tick and
/// a circuit-breaker path both exist upstream in [`crate::analytics`]
/// but the forwarder does not report either; the idle case is silent
/// (a scrape sees the depth gauge instead) and a circuit breaker is
/// deferred to the follow-up PR that ships end-to-end backpressure.
mod result_label {
    pub const OK: &str = "outbox_forward_ok";
    pub const HEAD_TOO_LARGE: &str = "outbox_head_too_large";
    pub const HEAD_MALFORMED: &str = "outbox_head_malformed";
    pub const DELETE_FAILED: &str = "outbox_delete_failed";
    pub const READ_FAILED: &str = "outbox_read_failed";
}

/// Wire the forwarder into [`crate::app::run`]. No-op when analytics is
/// disabled. Each pipeline runs through [`crate::replication::spawn_supervised`]
/// so a panic in one drain loop respawns after a 1 s backoff and bumps
/// the `background_panic_analytics_forwarder_*` metric, matching how
/// every other long-lived background task in this crate is supervised.
///
/// The tasks live until the process exits; the store is durable, so an
/// interrupted drain resumes on the next boot. The pattern matches
/// [`crate::usage::Usage::spawn_tasks`], which follows the same "run
/// until the runtime drops" contract.
pub fn spawn_tasks(state: &crate::state::SharedState) {
    if state.config.analytics.is_none() {
        return;
    }

    for pipeline in Pipeline::ALL {
        let name: &'static str = match pipeline {
            Pipeline::GradleCache => "analytics_forwarder_gradle_cache",
            Pipeline::XcodeCache => "analytics_forwarder_xcode_cache",
            Pipeline::ReapiCache => "analytics_forwarder_reapi_cache",
        };
        crate::replication::spawn_supervised(name, state.clone(), move |state| {
            // Every field is rebuilt per (re)spawn: on a panic, the
            // supervisor restarts the closure, and picking up a fresh
            // `state.client` snapshot means a TLS/cert rotation between
            // panic and respawn is not stuck on the old handle.
            let store = Arc::clone(&state.store);
            let client = (**state.client.load()).clone();
            let metrics = state.metrics.clone();
            let analytics_config = state
                .config
                .analytics
                .as_ref()
                .expect("spawn_tasks pre-checked analytics is Some");
            let config = ForwarderConfig::defaults(
                analytics_config.server_url.clone(),
                analytics_config.signing_key.clone(),
                crate::analytics::analytics_endpoint(&state.config.node_url),
            );
            // No shared cancellation token: each supervised body owns
            // its own so a panic-driven restart cannot inherit a fired
            // token from a previous iteration. The store's durability
            // is what makes the "drop on process exit" contract safe.
            let cancel = CancellationToken::new();
            drain_pipeline(store, client, config, metrics, pipeline, cancel)
        });
    }
}

/// Drain loop body. Exposed for tests so the loop can be run against a
/// controlled [`CancellationToken`] and a fake server.
pub async fn drain_pipeline(
    store: Arc<Store>,
    client: Client,
    config: ForwarderConfig,
    metrics: Metrics,
    pipeline: Pipeline,
    cancel: CancellationToken,
) {
    info!(
        pipeline = pipeline.as_label(),
        "analytics outbox forwarder starting",
    );
    let mut consecutive_failures: u32 = 0;
    loop {
        if cancel.is_cancelled() {
            info!(
                pipeline = pipeline.as_label(),
                "analytics outbox forwarder cancelled",
            );
            return;
        }

        // Race the whole tick against cancellation so a mid-POST
        // shutdown does not have to wait for the reqwest future to
        // return on its own. Dropping the tick future cancels the
        // in-flight reqwest cleanly and leaves the entry in the outbox
        // for redelivery on the next boot, which is safe because the
        // ack delete only runs after a 2xx response. The store's
        // durability guarantees do the rest.
        let outcome = tokio::select! {
            biased;
            () = cancel.cancelled() => {
                info!(
                    pipeline = pipeline.as_label(),
                    "analytics outbox forwarder cancelled mid-tick",
                );
                return;
            }
            outcome = tick(&store, &client, &config, &metrics, pipeline) => outcome,
        };

        match outcome {
            TickOutcome::Delivered { .. } => {
                consecutive_failures = 0;
            }
            TickOutcome::Idle => {
                consecutive_failures = 0;
                if sleep_with_cancel(Duration::from_millis(config.idle_backoff_ms), &cancel).await {
                    return;
                }
            }
            TickOutcome::Quarantined { .. } => {
                consecutive_failures = 0;
            }
            TickOutcome::Failure => {
                let delay = jittered_backoff(
                    consecutive_failures,
                    config.failure_backoff_ms_base,
                    config.failure_backoff_ms_max,
                );
                consecutive_failures = consecutive_failures.saturating_add(1);
                if sleep_with_cancel(delay, &cancel).await {
                    return;
                }
            }
        }
    }
}

/// One drain-loop iteration. Broken out so tests can call it directly.
pub async fn tick(
    store: &Store,
    client: &Client,
    config: &ForwarderConfig,
    metrics: &Metrics,
    pipeline: Pipeline,
) -> TickOutcome {
    let batch = match store.next_analytics_outbox_batch(
        pipeline,
        config.max_batch_entries,
        config.max_batch_bytes,
    ) {
        Ok(batch) => batch,
        Err(error) => {
            error!(
                pipeline = pipeline.as_label(),
                error = %error,
                "failed to read analytics outbox batch",
            );
            metrics.record_analytics_batch(
                pipeline.as_label(),
                result_label::READ_FAILED,
                Duration::default(),
            );
            return TickOutcome::Failure;
        }
    };

    match batch {
        NextBatch::Batch(entries) if entries.is_empty() => TickOutcome::Idle,
        NextBatch::Batch(entries) => {
            forward_batch(store, client, config, metrics, pipeline, entries).await
        }
        NextBatch::HeadTooLarge { entry, size_bytes } => {
            quarantine_oversized(store, metrics, pipeline, entry, size_bytes).await
        }
        NextBatch::HeadMalformed { key, value, error } => {
            quarantine_malformed(store, metrics, pipeline, key, value, error).await
        }
    }
}

async fn forward_batch(
    store: &Store,
    client: &Client,
    config: &ForwarderConfig,
    metrics: &Metrics,
    pipeline: Pipeline,
    entries: Vec<OutboxEntry>,
) -> TickOutcome {
    let mut delivered_keys: Vec<Vec<u8>> = Vec::with_capacity(entries.len());
    let mut had_failure = false;

    for entry in entries {
        let start = Instant::now();
        match post_entry(client, config, pipeline, &entry).await {
            PostOutcome::Success => {
                metrics.record_analytics_batch(
                    pipeline.as_label(),
                    result_label::OK,
                    start.elapsed(),
                );
                delivered_keys.push(entry.key);
            }
            PostOutcome::StatusError { status } => {
                metrics.record_analytics_batch(
                    pipeline.as_label(),
                    status_result_label(status),
                    start.elapsed(),
                );
                error!(
                    pipeline = pipeline.as_label(),
                    status = status.as_u16(),
                    "analytics outbox forwarder received an error status",
                );
                had_failure = true;
                break;
            }
            PostOutcome::TransportError { kind, cause } => {
                metrics.record_analytics_batch(
                    pipeline.as_label(),
                    error_result_label(kind),
                    start.elapsed(),
                );
                error!(
                    pipeline = pipeline.as_label(),
                    kind, "analytics outbox forwarder transport error: {cause}",
                );
                had_failure = true;
                break;
            }
        }
    }

    if !delivered_keys.is_empty()
        && let Err(error) = store.delete_analytics_outbox_entries(&delivered_keys).await
    {
        error!(
            pipeline = pipeline.as_label(),
            error = %error,
            acked = delivered_keys.len(),
            "failed to delete acknowledged analytics outbox entries; will be redelivered",
        );
        metrics.record_analytics_batch(
            pipeline.as_label(),
            result_label::DELETE_FAILED,
            Duration::default(),
        );
        return TickOutcome::Failure;
    }

    if had_failure {
        TickOutcome::Failure
    } else {
        TickOutcome::Delivered {
            entries: delivered_keys.len(),
        }
    }
}

async fn post_entry(
    client: &Client,
    config: &ForwarderConfig,
    pipeline: Pipeline,
    entry: &OutboxEntry,
) -> PostOutcome {
    let url = format!("{}{}", config.server_url, webhook_path(pipeline));
    let signature = sign(&config.signing_key, &entry.payload);
    let response = client
        .post(url)
        .header(CONTENT_TYPE, content_type_header(entry))
        .header(HMAC_SIGNATURE_HEADER, signature)
        .header(CACHE_ENDPOINT_HEADER, &config.cache_endpoint)
        .body(entry.payload.clone())
        .send()
        .await;

    match response {
        Ok(response) if response.status().is_success() => PostOutcome::Success,
        Ok(response) => PostOutcome::StatusError {
            status: response.status(),
        },
        Err(error) => {
            let cause = error_cause_chain(&error);
            PostOutcome::TransportError {
                kind: classify_reqwest_error(&error),
                cause,
            }
        }
    }
}

async fn quarantine_oversized(
    store: &Store,
    metrics: &Metrics,
    pipeline: Pipeline,
    entry: OutboxEntry,
    size_bytes: usize,
) -> TickOutcome {
    warn!(
        pipeline = pipeline.as_label(),
        size_bytes,
        event_id = %entry.event_id,
        "analytics outbox head exceeds configured byte budget; quarantining",
    );
    metrics.record_analytics_batch(
        pipeline.as_label(),
        result_label::HEAD_TOO_LARGE,
        Duration::default(),
    );
    match store
        .delete_analytics_outbox_entries(std::slice::from_ref(&entry.key))
        .await
    {
        Ok(()) => TickOutcome::Quarantined {
            reason: "oversized",
        },
        Err(error) => {
            error!(
                pipeline = pipeline.as_label(),
                error = %error,
                "failed to delete oversized analytics outbox entry; will retry",
            );
            metrics.record_analytics_batch(
                pipeline.as_label(),
                result_label::DELETE_FAILED,
                Duration::default(),
            );
            TickOutcome::Failure
        }
    }
}

async fn quarantine_malformed(
    store: &Store,
    metrics: &Metrics,
    pipeline: Pipeline,
    key: Vec<u8>,
    value: Vec<u8>,
    error: DecodeError,
) -> TickOutcome {
    warn!(
        pipeline = pipeline.as_label(),
        value_bytes = value.len(),
        ?error,
        "analytics outbox head does not decode; quarantining",
    );
    metrics.record_analytics_batch(
        pipeline.as_label(),
        result_label::HEAD_MALFORMED,
        Duration::default(),
    );
    match store.delete_analytics_outbox_entries(&[key]).await {
        Ok(()) => TickOutcome::Quarantined {
            reason: "malformed",
        },
        Err(delete_error) => {
            error!(
                pipeline = pipeline.as_label(),
                error = %delete_error,
                "failed to delete malformed analytics outbox entry; will retry",
            );
            metrics.record_analytics_batch(
                pipeline.as_label(),
                result_label::DELETE_FAILED,
                Duration::default(),
            );
            TickOutcome::Failure
        }
    }
}

#[must_use]
fn webhook_path(pipeline: Pipeline) -> &'static str {
    match pipeline {
        Pipeline::GradleCache => GRADLE_WEBHOOK_PATH,
        Pipeline::XcodeCache => XCODE_WEBHOOK_PATH,
        Pipeline::ReapiCache => REAPI_CACHE_WEBHOOK_PATH,
    }
}

#[must_use]
fn content_type_header(entry: &OutboxEntry) -> &'static str {
    match entry.content_type {
        crate::analytics_outbox::ContentType::Json => "application/json",
        crate::analytics_outbox::ContentType::OtlpProtobuf => "application/x-protobuf",
    }
}

/// AWS-style full jitter: sleep in `[0, base * 2^attempt]`, capped at
/// `max_ms`. Full jitter avoids the retry-thundering-herd shape that
/// exponential-only backoff produces under a correlated fleet-wide
/// outage.
#[must_use]
fn jittered_backoff(attempt: u32, base_ms: u64, max_ms: u64) -> Duration {
    let exponent = attempt.min(20);
    let raw = base_ms.saturating_mul(1_u64 << exponent);
    let ceiling = raw.min(max_ms).max(1);
    let jittered = rand::rng().random_range(0..=ceiling);
    Duration::from_millis(jittered)
}

/// Sleep for `duration`, returning `true` if the cancellation token
/// fired first so the caller can exit its loop.
async fn sleep_with_cancel(duration: Duration, cancel: &CancellationToken) -> bool {
    tokio::select! {
        () = sleep(duration) => false,
        () = cancel.cancelled() => true,
    }
}

/// Outcome of one drain-loop iteration. Distinguished so the loop can
/// pick the appropriate sleep and so tests can assert the exact path.
#[derive(Debug, PartialEq, Eq)]
pub enum TickOutcome {
    /// One or more entries were POSTed and their keys removed.
    Delivered { entries: usize },
    /// The pipeline was empty; sleep on the idle timer.
    Idle,
    /// A head-of-line entry was quarantined (dropped for now,
    /// dedicated CF later).
    Quarantined { reason: &'static str },
    /// A transient failure; back off with jitter and retry.
    Failure,
}

#[derive(Debug)]
enum PostOutcome {
    Success,
    StatusError { status: StatusCode },
    TransportError { kind: &'static str, cause: String },
}

impl Pipeline {
    /// Every pipeline the forwarder drains. Kept next to the module so
    /// the drain-loop spawn logic does not have to enumerate variants
    /// inline.
    const ALL: [Pipeline; 3] = [
        Pipeline::GradleCache,
        Pipeline::XcodeCache,
        Pipeline::ReapiCache,
    ];
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analytics_outbox::{ContentType, encode_value};
    use crate::test_support::test_context;
    use std::net::SocketAddr;
    use std::sync::Mutex;
    use tokio::net::TcpListener;
    use uuid::Uuid;

    /// A minimal HTTP capture server that answers every POST with a
    /// configurable status code and records the received bodies. We do
    /// not need reqwest client behaviours around chunked encoding or
    /// h2, so a hand-rolled Hyper server keeps the test self-contained.
    struct CaptureServer {
        addr: SocketAddr,
        received: Arc<Mutex<Vec<Vec<u8>>>>,
        _shutdown: tokio::sync::oneshot::Sender<()>,
    }

    impl CaptureServer {
        async fn start(status: StatusCode) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
            let addr = listener.local_addr().expect("addr");
            let received: Arc<Mutex<Vec<Vec<u8>>>> = Arc::new(Mutex::new(Vec::new()));
            let (tx, mut rx) = tokio::sync::oneshot::channel::<()>();
            let received_clone = Arc::clone(&received);
            tokio::spawn(async move {
                loop {
                    tokio::select! {
                        result = listener.accept() => match result {
                            Ok((mut socket, _)) => {
                                let received_clone = Arc::clone(&received_clone);
                                tokio::spawn(async move {
                                    use tokio::io::{AsyncReadExt, AsyncWriteExt};
                                    let mut buffer = Vec::new();
                                    // Read until we have headers + body. For the
                                    // small POSTs the forwarder makes this is a
                                    // single read.
                                    let mut chunk = [0_u8; 8192];
                                    while let Ok(n) = socket.read(&mut chunk).await {
                                        if n == 0 { break; }
                                        buffer.extend_from_slice(&chunk[..n]);
                                        if let Some(body_start) = find_body_start(&buffer) {
                                            let content_length = parse_content_length(&buffer[..body_start]);
                                            let have = buffer.len() - body_start;
                                            if have >= content_length {
                                                let body = buffer[body_start..body_start + content_length].to_vec();
                                                received_clone.lock().expect("lock").push(body);
                                                let response = format!(
                                                    "HTTP/1.1 {} {}\r\ncontent-length: 0\r\n\r\n",
                                                    status.as_u16(),
                                                    status.canonical_reason().unwrap_or(""),
                                                );
                                                let _ = socket.write_all(response.as_bytes()).await;
                                                let _ = socket.shutdown().await;
                                                return;
                                            }
                                        }
                                    }
                                });
                            }
                            Err(_) => return,
                        },
                        _ = &mut rx => return,
                    }
                }
            });
            let _shutdown = tx;
            Self {
                addr,
                received,
                _shutdown,
            }
        }

        fn base_url(&self) -> String {
            format!("http://{}", self.addr)
        }

        fn received(&self) -> Vec<Vec<u8>> {
            self.received.lock().expect("lock").clone()
        }
    }

    fn find_body_start(buffer: &[u8]) -> Option<usize> {
        buffer
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .map(|p| p + 4)
    }

    fn parse_content_length(headers: &[u8]) -> usize {
        let s = std::str::from_utf8(headers).unwrap_or("");
        for line in s.split("\r\n") {
            if let Some(rest) = line.to_ascii_lowercase().strip_prefix("content-length:")
                && let Ok(n) = rest.trim().parse::<usize>()
            {
                return n;
            }
        }
        0
    }

    fn config(server_url: String) -> ForwarderConfig {
        ForwarderConfig {
            server_url,
            signing_key: "test-secret".to_owned(),
            cache_endpoint: "test-node".to_owned(),
            max_batch_entries: 16,
            max_batch_bytes: 64 * 1024,
            idle_backoff_ms: 10,
            failure_backoff_ms_base: 5,
            failure_backoff_ms_max: 50,
        }
    }

    #[tokio::test]
    async fn tick_delivers_and_deletes_the_head_entry() {
        let ctx = test_context(|_| {}).await;
        let store = Arc::clone(&ctx.state.store);
        let payload = br#"{"events":[{"n":1}]}"#.to_vec();
        let value = encode_value(0, 1, ContentType::Json, &payload).expect("payload encodes");
        store
            .append_analytics_outbox_entry(Pipeline::GradleCache, 1, Uuid::from_u128(1), &value)
            .await
            .expect("append");

        let server = CaptureServer::start(StatusCode::OK).await;
        let client = Client::new();
        let metrics = ctx.state.metrics.clone();
        let config = config(server.base_url());

        let outcome = tick(&store, &client, &config, &metrics, Pipeline::GradleCache).await;
        assert_eq!(outcome, TickOutcome::Delivered { entries: 1 });

        let received = server.received();
        assert_eq!(received.len(), 1);
        assert_eq!(received[0], payload);

        assert_eq!(store.analytics_outbox_entry_count().expect("count"), 0);
    }

    #[tokio::test]
    async fn tick_quarantines_a_head_that_exceeds_the_byte_budget() {
        let ctx = test_context(|_| {}).await;
        let store = Arc::clone(&ctx.state.store);
        let payload = vec![b'x'; 4_096];
        let value = encode_value(0, 1, ContentType::Json, &payload).expect("payload encodes");
        store
            .append_analytics_outbox_entry(Pipeline::XcodeCache, 1, Uuid::from_u128(1), &value)
            .await
            .expect("append");

        let client = Client::new();
        let metrics = ctx.state.metrics.clone();
        let mut config = config("http://127.0.0.1:1".to_owned());
        config.max_batch_bytes = 128;

        let outcome = tick(&store, &client, &config, &metrics, Pipeline::XcodeCache).await;
        assert_eq!(
            outcome,
            TickOutcome::Quarantined {
                reason: "oversized"
            }
        );
        assert_eq!(
            store.analytics_outbox_entry_count().expect("count"),
            0,
            "oversized head must be deleted so the pipeline can drain the next entry",
        );
    }

    #[tokio::test]
    async fn tick_quarantines_a_malformed_head() {
        let ctx = test_context(|_| {}).await;
        let store = Arc::clone(&ctx.state.store);
        let mut value = encode_value(0, 1, ContentType::Json, b"payload").expect("payload encodes");
        // Corrupt the schema version byte so the store returns
        // HeadMalformed. The forwarder must delete the row rather than
        // spinning forever.
        value[0] = 99;
        store
            .append_analytics_outbox_entry(Pipeline::ReapiCache, 1, Uuid::from_u128(1), &value)
            .await
            .expect("append");

        let client = Client::new();
        let metrics = ctx.state.metrics.clone();
        let config = config("http://127.0.0.1:1".to_owned());

        let outcome = tick(&store, &client, &config, &metrics, Pipeline::ReapiCache).await;
        assert_eq!(
            outcome,
            TickOutcome::Quarantined {
                reason: "malformed"
            }
        );
        assert_eq!(store.analytics_outbox_entry_count().expect("count"), 0);
    }

    #[tokio::test]
    async fn tick_reports_idle_for_an_empty_pipeline() {
        let ctx = test_context(|_| {}).await;
        let store = Arc::clone(&ctx.state.store);
        let client = Client::new();
        let metrics = ctx.state.metrics.clone();
        let config = config("http://127.0.0.1:1".to_owned());

        let outcome = tick(&store, &client, &config, &metrics, Pipeline::ReapiCache).await;
        assert_eq!(outcome, TickOutcome::Idle);
    }

    #[tokio::test]
    async fn tick_reports_failure_when_the_server_returns_5xx_and_leaves_the_entry() {
        let ctx = test_context(|_| {}).await;
        let store = Arc::clone(&ctx.state.store);
        let payload = br#"{"events":[]}"#.to_vec();
        let value = encode_value(0, 1, ContentType::Json, &payload).expect("payload encodes");
        store
            .append_analytics_outbox_entry(Pipeline::GradleCache, 1, Uuid::from_u128(1), &value)
            .await
            .expect("append");

        let server = CaptureServer::start(StatusCode::INTERNAL_SERVER_ERROR).await;
        let client = Client::new();
        let metrics = ctx.state.metrics.clone();
        let config = config(server.base_url());

        let outcome = tick(&store, &client, &config, &metrics, Pipeline::GradleCache).await;
        assert_eq!(outcome, TickOutcome::Failure);
        assert_eq!(
            store.analytics_outbox_entry_count().expect("count"),
            1,
            "a 5xx response must leave the entry in place for the next drain attempt",
        );
    }

    #[test]
    fn jittered_backoff_stays_within_the_ceiling() {
        for attempt in 0..8 {
            let delay = jittered_backoff(attempt, 10, 200);
            assert!(delay <= Duration::from_millis(200));
        }
    }

    #[tokio::test(flavor = "current_thread", start_paused = true)]
    async fn drain_pipeline_returns_promptly_on_cancellation() {
        // Bounded-design invariant: shutdown must not have to wait for a
        // POST timeout. `drain_pipeline` races the whole tick against
        // cancellation, so firing the cancel token has to unwind within
        // one poll pass even on an empty pipeline that is sleeping on
        // the idle timer.
        let ctx = test_context(|_| {}).await;
        let store = Arc::clone(&ctx.state.store);
        let client = Client::new();
        let metrics = ctx.state.metrics.clone();
        let mut cfg = config("http://127.0.0.1:1".to_owned());
        cfg.idle_backoff_ms = 60_000;
        let cancel = CancellationToken::new();

        let cancel_child = cancel.clone();
        let handle = tokio::spawn(async move {
            drain_pipeline(
                store,
                client,
                cfg,
                metrics,
                Pipeline::GradleCache,
                cancel_child,
            )
            .await;
        });

        // Give the task one poll pass to reach the idle sleep, then
        // cancel. Paused time means the idle timer will not fire; the
        // task can only exit through the cancellation branch.
        tokio::task::yield_now().await;
        cancel.cancel();
        tokio::time::timeout(Duration::from_secs(1), handle)
            .await
            .expect("drain_pipeline must return promptly on cancellation")
            .expect("task should not panic");
    }
}
