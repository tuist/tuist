pub mod operation;
pub mod outbox_message;

use std::{
    collections::{BTreeMap, BTreeSet},
    net::{IpAddr, SocketAddr},
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use futures_util::stream::{self, StreamExt};
use reqwest::header::{CONTENT_TYPE, HeaderValue};
use serde::Deserialize;
use tokio::{
    io::AsyncWriteExt,
    time::{Instant, sleep},
};
use tokio_util::io::ReaderStream;
use tracing::{Instrument, field, warn};

use crate::{
    bandwidth::BandwidthLimiter,
    config::Config,
    constants::{
        MAX_INLINE_REPLICATION_BODY_BYTES, REPLICATION_RETRY_SECS, RESPONSE_STREAM_CHUNK_BYTES,
    },
    failpoints::FailpointName,
    state::SharedState,
    telemetry::{inject_current_trace_context, record_trace_context},
    utils::{replication_target_label, url_encode},
};

use self::{operation::ReplicationOperation, outbox_message::OutboxMessage};

// How much of a staged peer body may accumulate in the page cache before the
// writer drops what it has already written behind itself.
const PEER_BODY_CACHE_DROP_INTERVAL_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Deserialize)]
struct PeerStatusPayload {
    region: String,
    tenant_id: String,
    node_url: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct DiscoveryTarget {
    url: String,
    label: String,
    scope: DiscoveryScope,
    resolved: Option<ResolvedDiscoveryTarget>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum DiscoveryScope {
    Local,
    Global,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct ResolvedDiscoveryTarget {
    host: String,
    address: SocketAddr,
}

#[cfg(test)]
pub async fn enqueue_replication_for_artifact(
    state: &SharedState,
    manifest: &crate::artifact::manifest::ArtifactManifest,
) {
    for peer in replication_targets(state).await {
        if let Err(error) = state.store.enqueue(OutboxMessage {
            target: peer.clone(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: manifest.producer,
                namespace_id: manifest.namespace_id.clone(),
                key: manifest.key.clone(),
                content_type: manifest.content_type.clone(),
                artifact_id: manifest.artifact_id.clone(),
                version_ms: manifest.version_ms,
                inline: manifest.inline,
                branch: manifest.branch.clone(),
                trunk: None,
            },
        }) {
            warn!("failed to enqueue artifact replication for {peer}: {error}");
        }
    }
    state.notify.notify_one();
}

pub fn spawn_membership_task(state: SharedState) {
    spawn_supervised("membership", state, membership_task_loop);
}

pub fn spawn_outbox_task(state: SharedState) {
    spawn_supervised("outbox", state, outbox_task_loop);
}

pub(crate) fn spawn_supervised<F, Fut>(name: &'static str, state: SharedState, work: F)
where
    F: Fn(SharedState) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = ()> + Send + 'static,
{
    tokio::spawn(
        async move {
            loop {
                let task_state = state.clone();
                let handle = tokio::spawn(work(task_state).in_current_span());
                match handle.await {
                    Ok(()) => return,
                    Err(error) if error.is_panic() => {
                        state
                            .metrics
                            .record_memory_action(&format!("background_panic_{name}"));
                        warn!("background task '{name}' panicked: {error:?}; respawning in 1s");
                        sleep(Duration::from_secs(1)).await;
                    }
                    Err(error) => {
                        warn!("background task '{name}' aborted: {error:?}");
                        return;
                    }
                }
            }
        }
        .in_current_span(),
    );
}

async fn membership_task_loop(state: SharedState) {
    loop {
        let mut members = BTreeSet::new();
        let mut peer_nodes = BTreeMap::new();
        let targets = discovery_targets(&state.config, &state.dynamic_peers.load()).await;
        let mut peer_status_successes = 0_usize;
        let lookups = futures_util::future::join_all(targets.iter().map(|peer| {
            let client = match &peer.resolved {
                Some(resolved) => state
                    .peer_client_factory
                    .build_resolving(&resolved.host, resolved.address),
                None => Ok(state.client().as_ref().clone()),
            };
            let url = match peer.scope {
                DiscoveryScope::Local => format!("{}/_internal/status", peer.url),
                DiscoveryScope::Global => format!("{}/_internal/status?scope=global", peer.url),
            };
            let label = peer.label.clone();
            async move {
                let result = match client {
                    Ok(client) => client
                        .get(url)
                        .send()
                        .await
                        .map_err(|error| error.to_string()),
                    Err(error) => Err(error),
                };
                (label, result)
            }
        }))
        .await;
        for (peer, result) in lookups {
            match result {
                Ok(response) if response.status().is_success() => {
                    match response.json::<PeerStatusPayload>().await {
                        Ok(payload) => {
                            peer_status_successes += 1;
                            if payload.tenant_id != state.config.tenant_id
                                || is_self_or_own_gateway(
                                    &payload.node_url,
                                    &state.config.node_url,
                                    state.config.peer_gateway_url.as_deref(),
                                )
                            {
                                continue;
                            }
                            members.insert(payload.region.clone());
                            peer_nodes.insert(payload.node_url, payload.region);
                        }
                        Err(error) => warn!("failed to decode peer status from {peer}: {error}"),
                    }
                }
                Ok(response) => {
                    warn!("peer status check failed for {peer}: {}", response.status())
                }
                Err(error) => warn!("peer status request failed for {peer}: {error}"),
            }
        }

        let discovery_observed = targets.is_empty() || peer_status_successes > 0;
        // Peers we only know through discovery (in-cluster siblings found via
        // DNS, cross-region pods via the account peer Service) are
        // platform-managed like the static seeds: their absence usually means
        // unreachability, not departure, and unlike enrolled peers nothing
        // ever re-enrolls them. A re-join backfill only reaches back to the
        // backfill window, so anything older would be lost outright. Remember
        // them so outbox pruning never drops their messages.
        let configured_urls: BTreeSet<&str> = targets.iter().map(|t| t.url.as_str()).collect();
        let discovered_only: Vec<String> = peer_nodes
            .keys()
            .filter(|url| !configured_urls.contains(url.as_str()))
            .cloned()
            .collect();
        state.note_discovered_only_peers(discovered_only).await;
        let membership_update = state
            .apply_membership_view(members, peer_nodes, discovery_observed)
            .await;
        state
            .metrics
            .update_discovered_peer_nodes(membership_update.known_peer_count);
        state.backfill.evaluate(&state, &membership_update);
        state.maybe_mark_serving().await;
        sleep(Duration::from_secs(2)).await;
    }
}

async fn outbox_task_loop(state: SharedState) {
    loop {
        let notified = state.notify.notified();
        tokio::pin!(notified);

        // Replication delivery runs at every pressure tier. It is not
        // sheddable background work: the outbox is depth-capped
        // (`KURA_OUTBOX_MAX_DEPTH`) and `reserve_outbox_slots` fails a cache
        // write once that cap is reached, so a paused drain does not defer
        // work — it strands the queue and ends up rejecting writes. Both
        // write gates test only `pressure() == Critical` and test it *before*
        // outbox depth (`http::reject_overloaded_public_writes`,
        // `reapi::admission::reject_overloaded_grpc_writes`), so any pause
        // below Critical would hold the drain while writes keep arriving,
        // walking the queue straight into the cap; at Critical those gates
        // already refuse writes at the door, so the outbox is frozen rather
        // than growing — pausing there would strand whatever was queued and
        // buy nothing.
        //
        // The memory a pause could reclaim does not justify either case. The
        // loop is serial and node-wide, so exactly one delivery is in flight
        // regardless of peer count or backlog depth — a queued message costs
        // RocksDB, not RAM — and it takes no transient reservation. That one
        // delivery holds a single `SegmentReader` chunk (512 KiB) for a
        // segment-backed artifact, or the whole value for an inline one,
        // bounded by MAX_INLINE_REPLICATION_BODY_BYTES.
        //
        // Reported here rather than from the memory actuator so the sample
        // tracks a pass that is actually running.
        state.metrics.update_background_work_paused("outbox", false);
        if let Err(error) = process_outbox(&state).await {
            warn!("outbox processing failed: {error}");
        }

        tokio::select! {
            _ = &mut notified => {},
            _ = sleep(Duration::from_secs(REPLICATION_RETRY_SECS)) => {},
        }
    }
}

pub async fn replication_targets(state: &SharedState) -> Vec<String> {
    state.replication_targets().await
}

pub(crate) async fn read_bounded_body(
    response: reqwest::Response,
    max_bytes: u64,
    label: &str,
) -> Result<Vec<u8>, String> {
    if let Some(content_length) = response.content_length()
        && content_length > max_bytes
    {
        return Err(format!(
            "{label} response body declared {content_length} bytes, exceeds limit of {max_bytes}"
        ));
    }
    let mut buffer = Vec::new();
    let mut total: u64 = 0;
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|error| format!("{label} body stream failed: {error}"))?;
        total = total.saturating_add(chunk.len() as u64);
        if total > max_bytes {
            return Err(format!(
                "{label} response body exceeded limit of {max_bytes} bytes"
            ));
        }
        buffer.extend_from_slice(&chunk);
    }
    Ok(buffer)
}

/// Streams a peer response body to a staging file under the caller's byte
/// reservation, applying replication bandwidth shaping and dropping the staged
/// page cache behind the writer under memory pressure. Used by the backfill
/// pass driver for both batch and per-artifact downloads.
pub(crate) async fn stream_response_to_temp(
    state: &SharedState,
    response: reqwest::Response,
    path: &Path,
    staging_limit: u64,
) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "peer staging path is missing a parent directory".to_string())?;
    state.io.create_dir_all(parent).await?;
    // The staged file must not exceed the caller's `peer_staging_budget`
    // reservation: an inconsistent peer serving a body larger than its manifest
    // advertised is rejected here instead of overrunning the budget.
    let mut destination = Some(state.io.create_file(path).await?);
    let outcome = async {
        let mut stream = response.bytes_stream();
        let mut total: u64 = 0;
        let mut advised_through: u64 = 0;
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|error| format!("failed to stream peer body: {error:?}"))?;
            total = total.saturating_add(chunk.len() as u64);
            if total > staging_limit {
                return Err(format!(
                    "peer body response exceeded reserved {staging_limit} bytes"
                ));
            }
            if let Some(limiter) = state.replication_bandwidth_limiter.as_ref() {
                limiter.acquire(chunk.len()).await;
            }
            destination
                .as_mut()
                .expect("peer staging destination remains open while streaming")
                .write_all(&chunk)
                .await
                .map_err(|error| format!("failed to persist peer body: {error}"))?;
            if total.saturating_sub(advised_through) >= PEER_BODY_CACHE_DROP_INTERVAL_BYTES {
                // Drop-behind follows the cache-reclaim serving mode (raw
                // charge / working set), while the park follows admission
                // (the pressure tier). They were one predicate when both
                // keyed on the raw charge; keeping them fused would stop
                // dropping staged page cache on exactly the charge-full warm
                // nodes the mode exists for, now that admission no longer
                // closes there.
                if state.memory.should_reclaim_file_cache() {
                    let file = destination
                        .take()
                        .expect("peer staging destination remains open while streaming");
                    destination = match state
                        .io
                        .sync_drop_cache_and_reopen_append(
                            file,
                            path,
                            advised_through,
                            total - advised_through,
                        )
                        .await
                    {
                        Ok(file) => Some(file),
                        Err(error) => {
                            state
                                .metrics
                                .record_memory_action("peer_body_file_cache_drop_failed");
                            warn!("failed to release peer body file cache: {error}");
                            return Err(error);
                        }
                    };
                    advised_through = total;
                }
                state.memory.wait_for_background_headroom().await;
            }
        }
        destination
            .as_mut()
            .expect("peer staging destination remains open while streaming")
            .flush()
            .await
            .map_err(|error| format!("failed to flush peer body: {error}"))?;
        Ok::<(), String>(())
    }
    .await;

    // Drop the handle before asynchronous best-effort cleanup. The caller's
    // owned guard is the cancellation-safe fallback when the watchdog drops
    // this future at an await point.
    drop(destination.take());
    if outcome.is_err() {
        state.io.remove_file_if_exists(path).await;
    }
    outcome
}

/// Whether a discovered peer's advertised `node_url` should be skipped because
/// it is this node itself or this node's own peer gateway.
///
/// When global discovery is fronted by a public peer gateway (the account peer
/// LoadBalancer), every same-account peer advertises that one gateway URL for
/// global scope. A node must not adopt its own gateway as a distinct peer, or
/// same-region traffic would hairpin out through the public endpoint and back
/// instead of staying in-cluster. An external peer (which has no gateway of its
/// own) still adopts the gateway URL and replicates through it.
fn is_self_or_own_gateway(node_url: &str, own_node_url: &str, own_gateway: Option<&str>) -> bool {
    node_url == own_node_url || own_gateway == Some(node_url)
}

async fn discovery_targets(config: &Config, dynamic_peers: &[String]) -> Vec<DiscoveryTarget> {
    let mut targets = config
        .peers
        .iter()
        .chain(dynamic_peers.iter())
        .cloned()
        .map(|peer| DiscoveryTarget {
            label: peer.clone(),
            url: peer,
            scope: DiscoveryScope::Local,
            resolved: None,
        })
        .collect::<BTreeSet<_>>();

    let Ok(node_url) = reqwest::Url::parse(&config.node_url) else {
        return targets.into_iter().collect();
    };
    let Some(port) = node_url.port_or_known_default() else {
        return targets.into_iter().collect();
    };
    let scheme = node_url.scheme().to_owned();
    if let Some(dns_name) = &config.discovery_dns_name {
        discover_dns_targets(&mut targets, dns_name, port, &scheme, DiscoveryScope::Local).await;
    }
    if let Some(dns_name) = &config.global_discovery_dns_name {
        discover_dns_targets(
            &mut targets,
            dns_name,
            port,
            &scheme,
            DiscoveryScope::Global,
        )
        .await;
    }

    targets.into_iter().collect()
}

async fn discover_dns_targets(
    targets: &mut BTreeSet<DiscoveryTarget>,
    dns_name: &str,
    port: u16,
    scheme: &str,
    scope: DiscoveryScope,
) {
    match tokio::net::lookup_host((dns_name, port)).await {
        Ok(addresses) => {
            for address in addresses {
                if scheme == "https" {
                    let url = format!("{scheme}://{dns_name}:{port}");
                    targets.insert(DiscoveryTarget {
                        label: format!("{url}@{}", address.ip()),
                        url,
                        scope,
                        resolved: Some(ResolvedDiscoveryTarget {
                            host: dns_name.to_owned(),
                            address,
                        }),
                    });
                } else {
                    let url = format!("{scheme}://{}:{port}", format_ip_for_url(address.ip()));
                    targets.insert(DiscoveryTarget {
                        label: url.clone(),
                        url,
                        scope,
                        resolved: None,
                    });
                }
            }
        }
        Err(error) => warn!("dns discovery lookup failed for {dns_name}:{port}: {error}"),
    }
}

fn format_ip_for_url(ip: IpAddr) -> String {
    match ip {
        IpAddr::V4(ip) => ip.to_string(),
        IpAddr::V6(ip) => format!("[{ip}]"),
    }
}

// After a message is cleared, rewind the scan cursor to the outbox head if a
// higher-priority metadata-lane message was enqueued mid-pass and now sorts
// before it. Without this a fresh action-cache entry parks behind the rest of a
// bulk backlog (a cache populate can hold the sibling's entries for the ~30
// minutes its blobs take to ship). Jump back only for a target that is not
// backed off, so a parked failing backlog is not re-scanned after every clear.
async fn rewind_to_priority_head(
    state: &SharedState,
    after: &mut Option<Vec<u8>>,
) -> Result<(), String> {
    if let Some((head_key, head)) = state.store.next_outbox_message(None)?
        && head_key.as_slice() < crate::store::OUTBOX_BULK_LANE_PREFIX.as_bytes()
        && after
            .as_deref()
            .is_some_and(|cursor| head_key.as_slice() < cursor)
        && !state
            .replication_target_backed_off(&head.target, Instant::now())
            .await
    {
        *after = None;
    }
    Ok(())
}

pub async fn process_outbox(state: &SharedState) -> Result<(), String> {
    // The loop runs every few seconds regardless of load; skip the target-set
    // rebuild (readiness lock + clones) when there is nothing to deliver.
    if state.store.next_outbox_message(None)?.is_none() {
        return Ok(());
    }

    let current_targets: BTreeSet<String> = state.replication_targets().await.into_iter().collect();
    // Discovery-only peers (in-cluster siblings, cross-region pods) are
    // treated like the static seeds: never pruned. Their absence usually
    // means a network flap, not departure, and the re-join backfill only
    // reaches back to the backfill window, so dropping their messages would be
    // silent under-replication. The protection is process-scoped (the history is
    // in-memory): a genuinely removed pod is never rediscovered after the
    // observer's next restart, so its small frozen backlog — enqueues stop
    // within one membership tick of unreachability — is dropped after the
    // next deploy.
    let discovered_history = state.discovered_only_peer_history().await;
    // Pruning decides from process-scoped state (the dynamic view, the
    // discovered-only history) while the outbox is persistent, and the static
    // seeds keep the target set non-empty from the first pass — so a fresh
    // process must not prune until its view has actually arrived: the first
    // peers sync where one is configured, and one completed membership pass
    // so the discovered-only exemption has refilled. Deliveries proceed
    // regardless; only the destructive branch waits.
    let prune_ready =
        !state.runtime.peer_view_pending() && state.initial_discovery_completed().await;
    let mut dropped: BTreeMap<String, u64> = BTreeMap::new();

    let mut after = None::<Vec<u8>>;
    while let Some((message_key, message)) = state.store.next_outbox_message(after.as_deref())? {
        after = Some(message_key.clone());

        // Messages for a peer that left the mesh can never be delivered and
        // would otherwise accumulate until the outbox depth cap sheds writes.
        // The fetched peer view is authoritative and its removals are
        // deliberate (the control plane withholds a peer only after a full
        // staleness window of missed heartbeats), so messages for an absent
        // control-plane-managed target are dropped immediately; a departed
        // peer that later rejoins does so through a recovery re-enrollment,
        // which arms a pass per peer in view, and those reconcile back to the
        // backfill window — so the dropped deltas are recovered as long as the
        // absence fits inside it. An empty target set means the node has no
        // peer view at all (e.g. the control plane is unreachable), not that
        // every peer
        // left — never prune on it. The accepted trade-off: a mesh that
        // legitimately shrinks to zero peers keeps its queued messages until
        // a peer rejoins or the node restarts.
        if prune_ready
            && !current_targets.is_empty()
            && !current_targets.contains(&message.target)
            && !discovered_history.contains(&message.target)
        {
            state.store.delete_outbox_message(&message_key)?;
            state.metrics.record_replication(
                &message.target,
                message.operation.name(),
                "dropped_stale_target",
                Duration::ZERO,
            );
            *dropped.entry(message.target.clone()).or_insert(0) += 1;
            continue;
        }

        if state
            .replication_target_backed_off(&message.target, Instant::now())
            .await
        {
            continue;
        }

        let started_at = std::time::Instant::now();
        let operation_name = message.operation.name();
        let result = replicate_message(state, &message).await;

        match result {
            Ok(ReplicationOutcome::DroppedOversized) => {
                // The artifact was purged and can never replicate; drop the
                // message. Not a delivery and not a target failure, so leave the
                // target's success/backoff state untouched.
                state.metrics.record_replication(
                    &message.target,
                    operation_name,
                    "dropped_oversized",
                    started_at.elapsed(),
                );
                state.store.delete_outbox_message(&message_key)?;
                rewind_to_priority_head(state, &mut after).await?;
            }
            Ok(ReplicationOutcome::Delivered) => {
                state.note_replication_success(&message.target).await;
                match state
                    .store
                    .hit_failpoint(FailpointName::BeforeDeleteOutboxMessageAfterSuccess)
                    .await
                {
                    Ok(()) => {
                        state.metrics.record_replication(
                            &message.target,
                            operation_name,
                            "ok",
                            started_at.elapsed(),
                        );
                        state.store.delete_outbox_message(&message_key)?;
                        rewind_to_priority_head(state, &mut after).await?;
                    }
                    Err(error) => {
                        state.metrics.record_replication(
                            &message.target,
                            operation_name,
                            "error",
                            started_at.elapsed(),
                        );
                        warn!("replication to {} failed: {error}", message.target);
                    }
                }
            }
            Err(error) => {
                state
                    .note_replication_failure(&message.target, Instant::now())
                    .await;
                state.metrics.record_replication(
                    &message.target,
                    operation_name,
                    "error",
                    started_at.elapsed(),
                );
                warn!("replication to {} failed: {error}", message.target);
            }
        }
    }

    for (target, count) in dropped {
        warn!("dropped {count} outbox message(s) for {target}: no longer a replication target");
    }

    Ok(())
}

enum ReplicationOutcome {
    Delivered,
    // A legacy oversized inline artifact that no peer can accept inline (every
    // receiver bounds the inline body by MAX_INLINE_REPLICATION_BODY_BYTES).
    // The local copy was purged and the poison outbox message must be dropped.
    DroppedOversized,
}

/// The instant an upload last made forward progress, as milliseconds since the
/// attempt began. Held as an atomic rather than a `Mutex<Instant>` so the
/// per-chunk marking stays lock-free and cannot panic on a poisoned lock.
struct UploadProgress {
    started: Instant,
    last_progress_ms: AtomicU64,
}

impl UploadProgress {
    fn new() -> Self {
        Self {
            started: Instant::now(),
            last_progress_ms: AtomicU64::new(0),
        }
    }

    /// Re-arm the stall window. Called for each body chunk the stream yields,
    /// and once more when the stream terminates.
    fn mark(&self) {
        let elapsed = u64::try_from(self.started.elapsed().as_millis()).unwrap_or(u64::MAX);
        self.last_progress_ms.store(elapsed, Ordering::Relaxed);
    }

    fn idle(&self) -> Duration {
        let last = Duration::from_millis(self.last_progress_ms.load(Ordering::Relaxed));
        self.started.elapsed().saturating_sub(last)
    }
}

/// The request body of an artifact upload: the artifact's bytes, throttled by
/// the shared replication limiter, marking `progress` for every chunk and once
/// more when the stream terminates.
///
/// Chunks are 512 KiB rather than `ReaderStream`'s 4 KiB default. A multi-GB
/// artifact would otherwise take a bandwidth reservation hundreds of thousands
/// of times, and the limiter is shared, so 4 KiB slivers queue behind other
/// callers' 512 KiB reservations.
///
/// The terminating mark is what gives the wait for the response a whole stall
/// window instead of the last chunk's remainder: the receiver copies the staged
/// body into a segment and fsyncs it under the node-wide segment write lock
/// before it answers, and that tail scales with the artifact, not the network.
fn upload_body_stream<R>(
    reader: R,
    bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
    progress: Arc<UploadProgress>,
) -> impl futures_util::Stream<Item = std::io::Result<bytes::Bytes>> + Send + 'static
where
    R: tokio::io::AsyncRead + Send + Unpin + 'static,
{
    let end_progress = progress.clone();
    ReaderStream::with_capacity(reader, RESPONSE_STREAM_CHUNK_BYTES)
        .then(move |item| {
            let bandwidth_limiter = bandwidth_limiter.clone();
            let progress = progress.clone();
            async move {
                if let (Some(limiter), Ok(chunk)) = (bandwidth_limiter.as_ref(), item.as_ref()) {
                    limiter.acquire(chunk.len()).await;
                }
                progress.mark();
                item
            }
        })
        .chain(
            stream::once(async move { end_progress.mark() })
                .filter_map(|()| std::future::ready(None)),
        )
}

/// Resolves once the upload has made no forward progress for `stall`.
///
/// This is deliberately not an interval-sampling watchdog, which fires anywhere
/// between one and two intervals after the last progress. That imprecision is
/// fine for a background catch-up pass with its own retry loop. Here it is the
/// *only* deadline on the attempt, and the drain is serial and
/// node-wide, so a doubled window would double how long one stuck peer blocks
/// every other peer's replication. Sleeping to the exact deadline keeps that
/// cost fixed, and still wakes an active transfer at most once per window.
async fn upload_stalled(progress: &UploadProgress, stall: Duration) {
    loop {
        let idle = progress.idle();
        if idle >= stall {
            return;
        }
        sleep(stall - idle).await;
    }
}

async fn replicate_message(
    state: &SharedState,
    message: &OutboxMessage,
) -> Result<ReplicationOutcome, String> {
    match &message.operation {
        ReplicationOperation::UpsertArtifact {
            producer,
            namespace_id,
            key,
            content_type,
            artifact_id,
            version_ms,
            inline,
            branch,
            trunk,
        } => {
            let manifest = match state.store.manifest(artifact_id)? {
                Some(manifest) => manifest,
                None => return Ok(ReplicationOutcome::Delivered),
            };

            // Legacy entries stored before the write-side cap can exceed the
            // inline ceiling. They 413 on every inline push (poison message)
            // and wedge a fresh peer's backfill, so purge the local copy and
            // drop the message instead of retrying forever. A re-run re-uploads
            // and the write cap cleanly rejects it, so it never comes back.
            if manifest.inline && manifest.size > MAX_INLINE_REPLICATION_BODY_BYTES {
                state
                    .store
                    .delete_artifact_metadata(std::slice::from_ref(&manifest))?;
                warn!(
                    "purged oversized inline artifact {} ({} bytes > {} limit); dropping replication to {}",
                    manifest.key, manifest.size, MAX_INLINE_REPLICATION_BODY_BYTES, message.target
                );
                return Ok(ReplicationOutcome::DroppedOversized);
            }

            let file = state
                .store
                .open_artifact_reader(&manifest)
                .await
                .map_err(|error| {
                    format!("failed to open local artifact for replication: {error}")
                })?;

            let mut url = format!(
                "{}/_internal/replicate/artifact?producer={}&inline={}&namespace_id={}&key={}&content_type={}&version_ms={}",
                message.target,
                producer.as_str(),
                inline,
                url_encode(namespace_id),
                url_encode(key),
                url_encode(content_type),
                version_ms,
            );
            // Appended only when tagged, so an untagged publish puts the exact
            // URL today's nodes send. An old peer ignores query params it does
            // not read, which leaves it applying the entry untagged — its
            // behavior before this field existed.
            if let Some(branch) = branch {
                url.push_str("&branch=");
                url.push_str(&url_encode(branch));
            }
            if let Some(trunk) = trunk {
                url.push_str("&trunk=");
                url.push_str(&url_encode(trunk));
            }
            let url = url;
            let size = manifest.size;
            let bandwidth_limiter = state.replication_bandwidth_limiter.clone();
            let upload_stall = Duration::from_millis(state.config.replication_upload_stall_ms);
            let upload_progress = std::sync::Arc::new(UploadProgress::new());
            let body_stream = upload_body_stream(file, bandwidth_limiter, upload_progress.clone());
            let body = reqwest::Body::wrap_stream(body_stream);
            let request_span = tracing::info_span!(
                "replication.request",
                otel.name = "PUT /_internal/replicate/artifact",
                otel.kind = "client",
                kura.operation = "upsert_artifact",
                http.request.method = "PUT",
                url.full = %url,
                peer.service = %replication_target_label(&message.target),
                http.response.status_code = field::Empty,
                otel.status_code = field::Empty,
                trace_id = field::Empty,
                span_id = field::Empty,
            );
            record_trace_context(&request_span);
            let response_span = request_span.clone();

            async {
                let mut headers = reqwest::header::HeaderMap::new();
                inject_current_trace_context(&mut headers);
                headers.insert(
                    CONTENT_TYPE,
                    HeaderValue::from_static("application/octet-stream"),
                );

                let send = state
                    .upload_client()
                    .put(&url)
                    .headers(headers)
                    .body(body)
                    .send();
                // The upload client has no read timeout (the response side is
                // silent until the body completes), so the stall watchdog is
                // the attempt's only deadline; dropping the send future on
                // stall tears the connection down. `biased` polls the response
                // first so a reply landing on the deadline is never discarded
                // in favour of the watchdog: the watchdog is a fallback, not a
                // competitor, and losing that race costs a full re-upload.
                let response = tokio::select! {
                    biased;
                    response = send => response.map_err(|error| {
                        format!("artifact replication request failed ({size} bytes): {error:?}")
                    })?,
                    () = upload_stalled(&upload_progress, upload_stall) => {
                        return Err(format!(
                            "artifact replication upload stalled: no body progress for {}ms ({size} bytes)",
                            upload_stall.as_millis()
                        ));
                    }
                };
                response_span.record("http.response.status_code", response.status().as_u16());
                if response.status().is_server_error() {
                    response_span.record("otel.status_code", "ERROR");
                }
                response
                    .error_for_status()
                    .map(|_| ReplicationOutcome::Delivered)
                    .map_err(|error| {
                        format!("artifact replication response failed ({size} bytes): {error}")
                    })
            }
            .instrument(request_span)
            .await
        }
        ReplicationOperation::DeleteNamespace {
            namespace_id,
            version_ms,
        } => {
            let url = format!(
                "{}/_internal/replicate/namespace?namespace_id={}&version_ms={}",
                message.target,
                url_encode(namespace_id),
                version_ms,
            );
            let request_span = tracing::info_span!(
                "replication.request",
                otel.name = "DELETE /_internal/replicate/namespace",
                otel.kind = "client",
                kura.operation = "delete_namespace",
                http.request.method = "DELETE",
                url.full = %url,
                peer.service = %replication_target_label(&message.target),
                http.response.status_code = field::Empty,
                otel.status_code = field::Empty,
                trace_id = field::Empty,
                span_id = field::Empty,
            );
            record_trace_context(&request_span);
            let response_span = request_span.clone();

            async {
                let mut headers = reqwest::header::HeaderMap::new();
                inject_current_trace_context(&mut headers);
                let response = state
                    .client()
                    .delete(&url)
                    .headers(headers)
                    .send()
                    .await
                    .map_err(|error| format!("namespace replication request failed: {error}"))?;
                response_span.record("http.response.status_code", response.status().as_u16());
                if response.status().is_server_error() {
                    response_span.record("otel.status_code", "ERROR");
                }
                response
                    .error_for_status()
                    .map(|_| ReplicationOutcome::Delivered)
                    .map_err(|error| format!("namespace replication response failed: {error}"))
            }
            .instrument(request_span)
            .await
        }
    }
}

#[cfg(test)]
mod tests {
    use axum::{
        Router,
        http::StatusCode,
        routing::{get, put},
    };
    use tokio::net::TcpListener;

    use super::*;
    use crate::{
        artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
        constants::DEFAULT_REPLICATION_UPLOAD_STALL_MS,
        failpoints::{FailpointAction, FailpointName},
        http::router,
        memory::MemoryPressure,
        test_support::{TestContext, test_context},
    };

    #[tokio::test(start_paused = true)]
    async fn upload_stall_watchdog_fires_only_without_body_progress() {
        let stall = Duration::from_millis(DEFAULT_REPLICATION_UPLOAD_STALL_MS);
        let progress = UploadProgress::new();

        // Poll first, so the watchdog is armed against the *original* deadline
        // and has to observe the later progress to survive. Without this the
        // test passes against a watchdog that ignores `progress` entirely.
        let watchdog = upload_stalled(&progress, stall);
        tokio::pin!(watchdog);
        assert!(
            futures_util::poll!(watchdog.as_mut()).is_pending(),
            "the watchdog must not fire before the window elapses"
        );

        // Progress just short of the deadline pushes it out by a full window.
        tokio::time::advance(stall - Duration::from_millis(1)).await;
        progress.mark();
        assert!(
            futures_util::poll!(watchdog.as_mut()).is_pending(),
            "the watchdog must not fire while the upload is still progressing"
        );

        // Past the original deadline, but not past the re-armed one.
        tokio::time::advance(stall - Duration::from_millis(1)).await;
        assert!(
            futures_util::poll!(watchdog.as_mut()).is_pending(),
            "progress must reset the stall window, not merely delay the first check"
        );

        // A full window with no further progress trips it.
        tokio::time::advance(Duration::from_millis(1)).await;
        watchdog.await;
    }

    // The response wait is the part of the attempt where the receiver copies
    // the body into a segment and fsyncs it, so it needs a window of its own
    // rather than the remainder of the last chunk's.
    #[tokio::test(start_paused = true)]
    async fn the_end_of_the_body_stream_re_arms_the_stall_window() {
        let stall = Duration::from_millis(DEFAULT_REPLICATION_UPLOAD_STALL_MS);
        let directory = tempfile::tempdir().expect("temp dir should create");
        let path = directory.path().join("artifact");
        tokio::fs::write(&path, b"payload")
            .await
            .expect("artifact should write");
        let file = tokio::fs::File::open(&path)
            .await
            .expect("artifact should open");

        let progress = Arc::new(UploadProgress::new());
        let stream = upload_body_stream(file, None, progress.clone());
        tokio::pin!(stream);

        // Drain the body, then spend almost a whole window producing nothing —
        // exactly what the receiver's commit looks like from the sender's side.
        while stream.next().await.is_some() {
            tokio::time::advance(stall - Duration::from_millis(1)).await;
        }
        assert!(
            progress.idle() < stall,
            "the end of the body stream must re-arm the stall window"
        );

        tokio::time::advance(stall - Duration::from_millis(1)).await;
        assert!(
            progress.idle() < stall,
            "the response wait must get a whole window, not the last chunk's remainder"
        );
    }

    #[test]
    fn skips_self_and_own_gateway_but_adopts_other_peers() {
        let own = "https://kura-eu-0.kura-eu-headless.kura.svc.cluster.local:7443";
        let gateway = "https://peer.tuist-eu-1.kura.tuist.dev:7443";

        // Our own in-cluster URL and our own gateway are both skipped.
        assert!(is_self_or_own_gateway(own, own, Some(gateway)));
        assert!(is_self_or_own_gateway(gateway, own, Some(gateway)));

        // A different peer (another instance, or a self-hosted node) is adopted.
        assert!(!is_self_or_own_gateway(
            "https://kura-eu-1.kura-eu-headless.kura.svc.cluster.local:7443",
            own,
            Some(gateway),
        ));

        // With no gateway of our own, an external node adopting the managed
        // gateway URL must not skip it.
        assert!(!is_self_or_own_gateway(gateway, own, None));
    }

    async fn spawn_server(app: Router) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("failed to bind test listener");
        let address = listener
            .local_addr()
            .expect("failed to read listener address");
        let handle = tokio::spawn(async move {
            axum::serve(listener, app)
                .await
                .expect("test server should run");
        });
        (format!("http://{address}"), handle)
    }

    #[tokio::test]
    async fn peer_body_larger_than_its_reservation_is_rejected_mid_stream() {
        // The guard the backfill pass relies on: an inconsistent peer streams
        // a chunked body larger than the manifest it listed, so the receiver
        // has reserved less than the peer sends. The staged file is capped at
        // the reservation and the transfer fails there, instead of overrunning
        // the staging budget and the tmp-dir ceiling. Both call sites derive
        // the reservation from the peer's declared size
        // (`spool_batch_response`, `apply_individual_response`), so a
        // regression here surfaces as ENOSPC rather than a failed pass.
        let chunk = vec![7_u8; 16 * 1024];
        let app = Router::new().route(
            "/body",
            get({
                let chunk = chunk.clone();
                move || {
                    let chunk = chunk.clone();
                    async move {
                        let stream = futures_util::stream::iter(0..8).then(move |_| {
                            let chunk = chunk.clone();
                            async move { Ok::<_, std::io::Error>(chunk) }
                        });
                        axum::body::Body::from_stream(stream)
                    }
                }
            }),
        );
        let (peer_url, _server) = spawn_server(app).await;

        let ctx = test_context(|_config| {}).await;
        let reserved = 32 * 1024_u64;
        let response = reqwest::get(format!("{peer_url}/body"))
            .await
            .expect("peer body request should succeed");
        let path = ctx.state.config.tmp_dir.join("backfill").join("overrun");

        let error = stream_response_to_temp(&ctx.state, response, &path, reserved)
            .await
            .expect_err("a body larger than the reservation must be rejected");
        assert!(
            error.contains("exceeded reserved"),
            "expected a reservation-overflow rejection, got: {error}"
        );

        assert!(
            tokio::fs::metadata(&path).await.is_err(),
            "the partial staging file must be removed, not left charging the tmp budget"
        );
    }

    #[tokio::test]
    async fn enqueue_replication_skips_current_node() {
        let ctx = test_context(|config| {
            config.node_url = "http://127.0.0.1:4100".into();
            config.peers = vec![
                "http://127.0.0.1:4100".into(),
                "http://127.0.0.1:4101".into(),
            ];
        })
        .await;
        let manifest = ctx
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "namespace",
                "artifact",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("artifact should persist");

        enqueue_replication_for_artifact(&ctx.state, &manifest).await;

        let queued = ctx
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert_eq!(queued.len(), 1);
        assert_eq!(queued[0].1.target, "http://127.0.0.1:4101");
    }

    #[tokio::test]
    async fn discover_targets_keeps_dns_names_for_https_peers() {
        let ctx = test_context(|config| {
            config.node_url = "https://kura-us.kura.internal:7443".into();
            config.peers = vec!["https://seed.kura.internal:7443".into()];
            config.discovery_dns_name = Some("localhost".into());
            config.global_discovery_dns_name = Some("localhost".into());
        })
        .await;

        let targets = discovery_targets(&ctx.state.config, &ctx.state.dynamic_peers.load()).await;

        assert!(targets.iter().any(|target| {
            target.url == "https://seed.kura.internal:7443" && target.resolved.is_none()
        }));
        assert!(targets.iter().any(|target| {
            target.url == "https://localhost:7443"
                && target.scope == DiscoveryScope::Local
                && target.resolved.is_some()
        }));
        assert!(targets.iter().any(|target| {
            target.url == "https://localhost:7443"
                && target.scope == DiscoveryScope::Global
                && target.resolved.is_some()
        }));
        assert!(!targets.iter().any(|target| {
            target.url.starts_with("https://127.") || target.url.starts_with("https://[::1]")
        }));
    }

    #[tokio::test]
    async fn process_outbox_replicates_artifacts_and_namespace_deletes() {
        let remote = test_context(|_| {}).await;
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        let local = test_context(|_| {}).await;
        persist_and_enqueue_upsert(&local, remote_url.clone()).await;

        local
            .state
            .store
            .enqueue(OutboxMessage {
                target: remote_url,
                operation: ReplicationOperation::DeleteNamespace {
                    namespace_id: "android".into(),
                    version_ms: 123,
                },
            })
            .expect("delete should enqueue");

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        let replicated = remote
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("replicated artifact should exist");
        let mut reader = remote
            .state
            .store
            .open_artifact_reader(&replicated)
            .await
            .expect("replicated artifact reader should open");
        let mut bytes = Vec::new();
        use tokio::io::AsyncReadExt;
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("replicated bytes should read");
        assert_eq!(bytes, b"payload");

        let queued = local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert!(
            queued.is_empty(),
            "successful replication should clear outbox"
        );
    }

    // The bug this path exists to fix: the receiver stays silent while it
    // consumes and commits the body, so any deadline that keys on response
    // silence eventually strands the artifact. Here the receiver answers only
    // after a delay, and the upload still has to be delivered.
    //
    // The delay is short. Reproducing the original 30s ceiling would add 30s of
    // wall clock to every run, and paused time is not safe in this test —
    // real sockets make the runtime look idle while bytes sit in a kernel
    // buffer, so the clock can jump to the watchdog deadline mid-transfer. The
    // 30s claim is pinned instead by
    // `upload_client_has_no_read_timeout_and_download_client_keeps_one`.
    #[tokio::test]
    async fn artifact_upload_survives_a_receiver_that_delays_its_response() {
        let local = test_context(|_| {}).await;
        // The harness caps its clients at 5s; production's upload client has no
        // total timeout at all, which is what this path depends on.
        local.state.upload_client.store(std::sync::Arc::new(
            crate::peer_tls::PeerClientFactory::plain()
                .build_upload()
                .expect("upload client should build"),
        ));

        let receiver = Router::new().route(
            "/_internal/replicate/artifact",
            put(|body: axum::body::Bytes| async move {
                assert_eq!(body.as_ref(), b"payload", "receiver should get whole body");
                sleep(Duration::from_millis(250)).await;
                StatusCode::NO_CONTENT
            }),
        );
        let (target, _server) = spawn_server(receiver).await;
        persist_and_enqueue_upsert(&local, target).await;

        process_outbox(&local.state)
            .await
            .expect("a delayed response must not fail the upload");

        let queued = local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert!(
            queued.is_empty(),
            "a delivered upload must clear the outbox instead of retrying forever"
        );
    }

    /// Persists a segment-backed artifact on `context` and queues its upsert
    /// for `target`, returning the enqueued manifest.
    async fn persist_and_enqueue_upsert(context: &TestContext, target: String) -> ArtifactManifest {
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");
        let manifest = context
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should exist");

        context
            .state
            .store
            .enqueue(OutboxMessage {
                target,
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Gradle,
                    namespace_id: "ios".into(),
                    key: "artifact".into(),
                    content_type: "application/octet-stream".into(),
                    artifact_id: manifest.artifact_id.clone(),
                    version_ms: manifest.version_ms,
                    inline: false,
                    branch: None,
                    trunk: None,
                },
            })
            .expect("upsert should enqueue");

        manifest
    }

    /// The artifact `persist_and_enqueue_upsert` replicates, as seen by a peer.
    async fn replicated_artifact(context: &TestContext) -> Option<ArtifactManifest> {
        context
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
    }

    fn stale_target_message(target: &str) -> OutboxMessage {
        OutboxMessage {
            target: target.into(),
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "ios".into(),
                version_ms: 1,
            },
        }
    }

    /// Replication is not sheddable under memory pressure. The outbox is
    /// depth-capped and a full outbox rejects cache writes, so pausing the
    /// drain trades one in-flight delivery's buffer for rejected writes and a
    /// node that stays divergent from its peers.
    #[tokio::test]
    async fn process_outbox_delivers_under_critical_memory_pressure() {
        let remote = test_context(|_| {}).await;
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        let local = test_context(|_| {}).await;
        persist_and_enqueue_upsert(&local, remote_url).await;

        local
            .state
            .memory
            .observe(local.state.config.memory_hard_limit_bytes);
        assert_eq!(local.state.memory.pressure(), MemoryPressure::Critical);

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed under critical pressure");

        assert!(
            replicated_artifact(&remote).await.is_some(),
            "critical pressure must not stop replication"
        );
        assert!(
            local
                .state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .is_empty(),
            "a delivered message must leave the durable outbox"
        );
    }

    /// The mesh-wide case: the receiver is also shedding, so
    /// `reject_overloaded_internal_writes` 503s the delivery at the far end.
    /// Draining unconditionally must not turn that into data loss — the
    /// message stays queued and is retried on the normal cadence.
    #[tokio::test]
    async fn a_peer_shedding_replication_keeps_the_message_queued_for_retry() {
        let remote = test_context(|_| {}).await;
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;
        remote
            .state
            .memory
            .observe(remote.state.config.memory_hard_limit_bytes);
        assert_eq!(remote.state.memory.pressure(), MemoryPressure::Critical);

        let local = test_context(|_| {}).await;
        persist_and_enqueue_upsert(&local, remote_url).await;

        process_outbox(&local.state)
            .await
            .expect("a refused delivery must not fail the pass");

        assert_eq!(
            local
                .state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .len(),
            1,
            "a delivery the peer refused must stay queued for retry"
        );
        assert!(
            replicated_artifact(&remote).await.is_none(),
            "the shedding peer must not have stored the artifact"
        );
    }

    async fn complete_initial_discovery(state: &SharedState) {
        state
            .apply_membership_view(
                std::collections::BTreeSet::new(),
                std::collections::BTreeMap::new(),
                true,
            )
            .await;
    }

    #[tokio::test]
    async fn process_outbox_drops_messages_for_targets_that_left_the_mesh() {
        let local = test_context(|config| {
            config.peers = vec!["https://live-peer.test:7443".into()];
        })
        .await;
        complete_initial_discovery(&local.state).await;
        local
            .state
            .store
            .enqueue(stale_target_message("https://gone-peer.test:7443"))
            .expect("enqueue should succeed");

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        let queued = local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert!(
            queued.is_empty(),
            "messages for a target that left the mesh should be dropped"
        );
    }

    #[tokio::test]
    async fn process_outbox_defers_pruning_until_a_membership_pass_completes() {
        // The outbox is persistent while every pruning protection is
        // process-scoped: a fresh process restarting with a backlog must not
        // prune before its first membership pass, or messages for live peers
        // whose exemptions have not refilled yet would be destroyed.
        let local = test_context(|config| {
            config.peers = vec!["https://live-peer.test:7443".into()];
        })
        .await;
        local
            .state
            .store
            .enqueue(stale_target_message("https://gone-peer.test:7443"))
            .expect("enqueue should succeed");

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");
        assert_eq!(
            local.state.store.outbox_messages().expect("load").len(),
            1,
            "nothing may be pruned before the first completed membership pass"
        );

        complete_initial_discovery(&local.state).await;
        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");
        assert!(
            local
                .state
                .store
                .outbox_messages()
                .expect("load")
                .is_empty(),
            "pruning should proceed once the peer view has arrived"
        );
    }

    #[tokio::test]
    async fn process_outbox_defers_pruning_while_the_first_peers_sync_is_pending() {
        let local = test_context(|config| {
            config.peers = vec!["https://live-peer.test:7443".into()];
        })
        .await;
        local.state.runtime.require_peer_view();
        complete_initial_discovery(&local.state).await;
        local
            .state
            .store
            .enqueue(stale_target_message("https://gone-peer.test:7443"))
            .expect("enqueue should succeed");

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");
        assert_eq!(
            local.state.store.outbox_messages().expect("load").len(),
            1,
            "nothing may be pruned while the first peers sync is pending"
        );

        local.state.runtime.mark_peer_view_ready();
        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");
        assert!(
            local
                .state
                .store
                .outbox_messages()
                .expect("load")
                .is_empty(),
            "pruning should proceed once the sync has landed"
        );
    }

    #[tokio::test]
    async fn process_outbox_drops_messages_for_boot_time_peers_that_left_the_mesh() {
        // The static seed is managed/stable peers only, so a self-hosted peer
        // present at boot lives in the dynamic view — its departure arrives
        // via a later heartbeat and must be prunable without a restart.
        let local = test_context(|_| {}).await;
        complete_initial_discovery(&local.state).await;
        local.state.dynamic_peers.store(std::sync::Arc::new(vec![
            "https://gone-peer.test:7443".to_string(),
            "https://live-peer.test:7443".to_string(),
        ]));
        local
            .state
            .store
            .enqueue(stale_target_message("https://gone-peer.test:7443"))
            .expect("enqueue should succeed");

        // The next heartbeat's peer view no longer contains the departed peer.
        local.state.dynamic_peers.store(std::sync::Arc::new(vec![
            "https://live-peer.test:7443".to_string(),
        ]));

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        let queued = local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert!(
            queued.is_empty(),
            "boot-time peers must be prunable once the dynamic view drops them"
        );
    }

    #[tokio::test]
    async fn process_outbox_never_drops_messages_for_discovered_peers() {
        // An in-cluster sibling known only through discovery flaps out of the
        // membership view. Unlike an enrolled peer, nothing re-enrolls it after
        // the flap, so its messages must never be dropped.
        let local = test_context(|_| {}).await;
        local.state.dynamic_peers.store(std::sync::Arc::new(vec![
            "https://live-peer.test:7443".to_string(),
        ]));
        local
            .state
            .note_discovered_only_peers(vec!["https://sibling-0.test:7443".to_string()])
            .await;
        local
            .state
            .store
            .enqueue(stale_target_message("https://sibling-0.test:7443"))
            .expect("enqueue should succeed");

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        let queued = local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert_eq!(
            queued.len(),
            1,
            "a discovered sibling's flap must not destroy its queued messages"
        );
    }

    #[tokio::test]
    async fn process_outbox_never_drops_when_the_node_has_no_peer_view() {
        // The default test config's only peer is the node itself, so the
        // current target set is empty — the control-plane-unreachable shape.
        let local = test_context(|_| {}).await;
        local
            .state
            .store
            .enqueue(stale_target_message("https://gone-peer.test:7443"))
            .expect("enqueue should succeed");

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        let queued = local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert_eq!(
            queued.len(),
            1,
            "an empty peer view must never be treated as every peer having left"
        );
    }

    #[tokio::test]
    async fn process_outbox_backs_off_unreachable_target() {
        let local = test_context(|_| {}).await;
        let unreachable = "http://127.0.0.1:1".to_string();
        local
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");
        let artifact = local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should exist");
        local
            .state
            .store
            .enqueue(OutboxMessage {
                target: unreachable.clone(),
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Gradle,
                    namespace_id: "ios".into(),
                    key: "artifact".into(),
                    content_type: "application/octet-stream".into(),
                    artifact_id: artifact.artifact_id,
                    version_ms: artifact.version_ms,
                    inline: false,
                    branch: None,
                    trunk: None,
                },
            })
            .expect("upsert should enqueue");

        assert!(
            !local
                .state
                .replication_target_backed_off(&unreachable, Instant::now())
                .await
        );

        process_outbox(&local.state)
            .await
            .expect("outbox processing should not error on a failed peer");

        assert!(
            local
                .state
                .replication_target_backed_off(&unreachable, Instant::now())
                .await,
            "a failed replication target should be backed off"
        );
        assert_eq!(
            local
                .state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .len(),
            1,
            "a failed message must stay in the outbox"
        );
    }

    #[tokio::test]
    async fn process_outbox_skips_backed_off_target() {
        let remote = test_context(|_| {}).await;
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        let local = test_context(|_| {}).await;
        local
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");
        let artifact = local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should exist");
        local
            .state
            .store
            .enqueue(OutboxMessage {
                target: remote_url.clone(),
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Gradle,
                    namespace_id: "ios".into(),
                    key: "artifact".into(),
                    content_type: "application/octet-stream".into(),
                    artifact_id: artifact.artifact_id,
                    version_ms: artifact.version_ms,
                    inline: false,
                    branch: None,
                    trunk: None,
                },
            })
            .expect("upsert should enqueue");

        local
            .state
            .note_replication_failure(&remote_url, Instant::now())
            .await;

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        assert!(
            remote
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                .await
                .expect("artifact fetch should succeed")
                .is_none(),
            "a backed-off target must not be contacted"
        );
        assert_eq!(
            local
                .state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .len(),
            1,
            "a skipped message must remain in the outbox"
        );

        local.state.note_replication_success(&remote_url).await;

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        assert!(
            remote
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                .await
                .expect("artifact fetch should succeed")
                .is_some(),
            "after backoff clears, replication should proceed"
        );
        assert!(
            local
                .state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .is_empty(),
            "successful replication should clear the outbox"
        );
    }

    #[tokio::test]
    async fn process_outbox_retries_after_success_before_outbox_delete() {
        let remote = test_context(|_| {}).await;
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;
        let local = test_context(|_| {}).await;

        let manifest = local
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");

        local
            .state
            .store
            .enqueue(OutboxMessage {
                target: remote_url,
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Gradle,
                    namespace_id: "ios".into(),
                    key: "artifact".into(),
                    content_type: "application/octet-stream".into(),
                    artifact_id: manifest.artifact_id.clone(),
                    version_ms: manifest.version_ms,
                    inline: false,
                    branch: None,
                    trunk: None,
                },
            })
            .expect("outbox message should enqueue");

        local.state.store.failpoints().set_once(
            FailpointName::BeforeDeleteOutboxMessageAfterSuccess,
            FailpointAction::Error("delete interrupted".into()),
        );

        process_outbox(&local.state)
            .await
            .expect("outbox processing should complete");

        assert_eq!(
            local
                .state
                .store
                .outbox_message_count()
                .expect("outbox count should load"),
            1
        );

        process_outbox(&local.state)
            .await
            .expect("outbox retry should complete");

        assert_eq!(
            local
                .state
                .store
                .outbox_message_count()
                .expect("outbox count should load"),
            0
        );
        let replicated = remote
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("replicated artifact should exist");
        let mut reader = remote
            .state
            .store
            .open_artifact_reader(&replicated)
            .await
            .expect("artifact reader should open");
        let mut bytes = Vec::new();
        use tokio::io::AsyncReadExt;
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("artifact bytes should read");
        assert_eq!(bytes, b"payload");
    }

    #[tokio::test]
    async fn replicating_an_oversized_inline_artifact_purges_it_and_drops_the_message() {
        let ctx = test_context(|_| {}).await;
        let manifest = ctx
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "tuist",
                "action_cache/dead/1",
                "application/x-protobuf",
                &vec![0u8; MAX_INLINE_REPLICATION_BODY_BYTES as usize + 1],
            )
            .await
            .expect("oversized inline artifact should persist");

        let message = OutboxMessage {
            target: "https://unused.invalid:7443".to_owned(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: manifest.producer,
                namespace_id: manifest.namespace_id.clone(),
                key: manifest.key.clone(),
                content_type: manifest.content_type.clone(),
                artifact_id: manifest.artifact_id.clone(),
                version_ms: manifest.version_ms,
                inline: manifest.inline,
                branch: None,
                trunk: None,
            },
        };

        // Resolves without a network call — the oversized entry is purged and
        // the message dropped before any send is attempted.
        let outcome = replicate_message(&ctx.state, &message)
            .await
            .expect("oversized inline replication should resolve");
        assert!(matches!(outcome, ReplicationOutcome::DroppedOversized));

        assert!(
            ctx.state
                .store
                .manifest(&manifest.artifact_id)
                .expect("manifest lookup should succeed")
                .is_none(),
            "the oversized inline manifest must be purged"
        );
        assert!(
            ctx.state
                .store
                .fetch_inline_artifact_bytes(
                    ArtifactProducer::Reapi,
                    "tuist",
                    "action_cache/dead/1"
                )
                .expect("inline lookup should succeed")
                .is_none(),
            "the oversized inline bytes must be reclaimed"
        );
    }
}
