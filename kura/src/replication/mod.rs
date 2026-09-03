pub mod operation;
pub mod outbox_message;

use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    net::{IpAddr, SocketAddr},
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use futures_util::stream::{self, FuturesUnordered, StreamExt};
use reqwest::header::{CONTENT_TYPE, HeaderValue};
use serde::Deserialize;
use tokio::{
    io::AsyncWriteExt,
    time::{Instant, sleep},
};
use tracing::{Instrument, field, warn};

use crate::{
    bandwidth::BandwidthLimiter,
    config::Config,
    constants::{
        MAX_INLINE_REPLICATION_BODY_BYTES, OUTBOX_MAX_INFLIGHT, REPLICATION_BATCH_MAX_BYTES,
        REPLICATION_BATCH_MAX_ITEMS, REPLICATION_BATCH_MAX_ROUNDS, REPLICATION_RETRY_SECS,
        RESPONSE_STREAM_CHUNK_BYTES,
    },
    failpoints::FailpointName,
    http::{ReplicateBatchItemMeta, ReplicateBatchOutcomes, encode_replicate_batch_frame},
    state::SharedState,
    store::{ArtifactReader, OUTBOX_BULK_LANE_PREFIX},
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
        // pass keeps at most `OUTBOX_MAX_INFLIGHT` deliveries in flight
        // node-wide, regardless of peer count or backlog depth — a queued
        // message costs RocksDB, not RAM — and takes no transient reservation.
        // Each delivery holds a single `SegmentReader` chunk (512 KiB) for a
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

/// A batched delivery's verdict.
enum BatchOutcome {
    /// The peer answered. One flag per message in the batch, in order: true
    /// means the peer is done with it (applied, or ignored as not newer) and
    /// the outbox message may be cleared.
    Resolved(Vec<bool>),
    /// The peer does not serve the batch route, so this target stays on the
    /// per-message path.
    Unsupported,
}

/// Whether a message can ride a batch. Only the metadata lane's inline
/// artifacts qualify: a segment-backed body streams and wants overlap rather
/// than company, and namespace deletes are ordering-sensitive enough that they
/// keep their own request.
fn batchable_inline_upsert(message: &OutboxMessage) -> bool {
    matches!(
        &message.operation,
        ReplicationOperation::UpsertArtifact { inline: true, .. }
    )
}

/// Ships as many of `items` as fit one request to `target`.
///
/// Items the local node can no longer produce (manifest or inline bytes gone)
/// resolve without being sent, matching the per-message path, which treats a
/// missing manifest as delivered. Oversized inline bodies are left out
/// entirely so the per-message path can purge them, which is the only place
/// that logic lives.
async fn replicate_batch(
    state: &SharedState,
    target: &str,
    items: &[(Vec<u8>, OutboxMessage)],
) -> Result<BatchOutcome, String> {
    let mut resolved = vec![false; items.len()];
    let mut sent_indices = Vec::new();
    let mut body = Vec::new();

    for (index, (_message_key, message)) in items.iter().enumerate() {
        let ReplicationOperation::UpsertArtifact {
            producer,
            namespace_id,
            key,
            content_type,
            artifact_id,
            version_ms,
            branch,
            trunk,
            ..
        } = &message.operation
        else {
            continue;
        };
        let Some(manifest) = state.store.manifest(artifact_id)? else {
            resolved[index] = true;
            continue;
        };
        if manifest.size > MAX_INLINE_REPLICATION_BODY_BYTES {
            continue;
        }
        let Some(bytes) = state.store.inline_bytes(artifact_id)? else {
            resolved[index] = true;
            continue;
        };

        let meta = ReplicateBatchItemMeta {
            producer: producer.as_str().to_owned(),
            namespace_id: namespace_id.clone(),
            key: key.clone(),
            content_type: content_type.clone(),
            version_ms: *version_ms,
            branch: branch.clone(),
            trunk: trunk.clone(),
        };
        let meta_bytes = serde_json::to_vec(&meta)
            .map_err(|error| format!("failed to encode replication batch meta: {error}"))?;
        let frame = encode_replicate_batch_frame(&meta_bytes, &bytes)?;
        // Stopping here rather than dropping the item leaves the remainder
        // queued for the next round, so an unusually large run of inline
        // bodies costs another request instead of an unbounded one.
        if !body.is_empty() && (body.len() + frame.len()) as u64 > REPLICATION_BATCH_MAX_BYTES {
            break;
        }
        body.extend_from_slice(&frame);
        sent_indices.push(index);
    }

    if sent_indices.is_empty() {
        return Ok(BatchOutcome::Resolved(resolved));
    }

    let url = format!("{target}/_internal/replicate/artifacts");
    let request_span = tracing::info_span!(
        "replication.request",
        otel.name = "PUT /_internal/replicate/artifacts",
        otel.kind = "client",
        kura.operation = "upsert_artifact_batch",
        http.request.method = "PUT",
        url.full = %url,
        peer.service = %replication_target_label(target),
        kura.batch_items = sent_indices.len(),
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

        // Charged before the send, the same budget the per-message path meters
        // its body stream against. Batching made this the dominant replication
        // path, so skipping it would let peer sync ignore the adaptive backoff
        // that yields bandwidth to public cache traffic.
        if let Some(limiter) = state.replication_bandwidth_limiter.as_ref() {
            limiter.acquire(body.len()).await;
        }

        let response = state
            .client()
            .put(&url)
            .headers(headers)
            .body(body)
            .send()
            .await
            .map_err(|error| format!("batched artifact replication request failed: {error:?}"))?;

        response_span.record("http.response.status_code", response.status().as_u16());
        // A peer that predates this route answers 404, and one that has the
        // path but not the method answers 405. Neither is a failure of the
        // messages: they go back through the per-message route.
        if matches!(
            response.status(),
            reqwest::StatusCode::NOT_FOUND | reqwest::StatusCode::METHOD_NOT_ALLOWED
        ) {
            return Ok(BatchOutcome::Unsupported);
        }
        if response.status().is_server_error() {
            response_span.record("otel.status_code", "ERROR");
        }
        let response = response
            .error_for_status()
            .map_err(|error| format!("batched artifact replication rejected: {error:?}"))?;
        let outcomes: ReplicateBatchOutcomes = response
            .json()
            .await
            .map_err(|error| format!("failed to decode replication batch outcomes: {error:?}"))?;
        if outcomes.outcomes.len() != sent_indices.len() {
            return Err(format!(
                "peer answered {} outcomes for {} batched items",
                outcomes.outcomes.len(),
                sent_indices.len()
            ));
        }
        for (index, outcome) in sent_indices.iter().zip(outcomes.outcomes) {
            resolved[*index] = outcome != "error";
        }
        Ok(BatchOutcome::Resolved(resolved))
    }
    .instrument(request_span)
    .await
}

/// Drains the metadata lane in per-target batches before the per-message pass.
///
/// The lane carries inline artifacts of a few KiB, so one request per message
/// spends a whole round trip on less than an MTU of payload and the drain is
/// bound by messages rather than bytes. Outbox keys are `{lane}-{time}-{uuid}`
/// with no target in them, so messages for different peers interleave and a
/// contiguous run is almost always length one; the scan therefore buckets by
/// target across a window instead of grouping neighbours.
///
/// Anything this does not take (bulk bodies, namespace deletes, backed-off or
/// departed targets, peers without the route) is left untouched for
/// `process_outbox`, which remains the complete path.
async fn drain_metadata_batches(
    state: &SharedState,
    current_targets: &BTreeSet<String>,
) -> Result<(), String> {
    for _round in 0..REPLICATION_BATCH_MAX_ROUNDS {
        let mut buckets: BTreeMap<String, Vec<(Vec<u8>, OutboxMessage)>> = BTreeMap::new();
        let mut after: Option<Vec<u8>> = None;
        let mut scanned = 0usize;
        let scan_cap = REPLICATION_BATCH_MAX_ITEMS.saturating_mul(4);

        while let Some((message_key, message)) =
            state.store.next_outbox_message(after.as_deref())?
        {
            if message_key.as_slice() >= OUTBOX_BULK_LANE_PREFIX.as_bytes() {
                break;
            }
            after = Some(message_key.clone());
            scanned += 1;
            if scanned >= scan_cap {
                break;
            }
            if !batchable_inline_upsert(&message)
                || !current_targets.contains(&message.target)
                || state.replication_batch_unsupported(&message.target).await
                || state
                    .replication_target_backed_off(&message.target, Instant::now())
                    .await
            {
                continue;
            }
            let bucket = buckets.entry(message.target.clone()).or_default();
            if bucket.len() < REPLICATION_BATCH_MAX_ITEMS {
                bucket.push((message_key, message));
            }
        }

        // A batch of one saves no round trip, so it goes through the
        // per-message path with everything else this pass skipped.
        buckets.retain(|_, items| items.len() > 1);
        if buckets.is_empty() {
            return Ok(());
        }

        // Bounded by the same ceiling as the per-message drain rather than by
        // the bucket count: a scan window can hold hundreds of targets, and
        // each delivery materializes its body before its first network await,
        // so an unbounded fan-out is both a connection and a memory spike.
        let results = stream::iter(buckets.into_iter().map(|(target, items)| async move {
            let started_at = std::time::Instant::now();
            let outcome = replicate_batch(state, &target, &items).await;
            (target, items, outcome, started_at.elapsed())
        }))
        .buffer_unordered(OUTBOX_MAX_INFLIGHT)
        .collect::<Vec<_>>()
        .await;

        let mut progressed = false;
        for (target, items, outcome, elapsed) in results {
            match outcome {
                Ok(BatchOutcome::Unsupported) => {
                    state.note_replication_batch_unsupported(&target).await;
                }
                Ok(BatchOutcome::Resolved(resolved)) => {
                    state.note_replication_success(&target).await;
                    // One batch is one replication request, so it records one
                    // observation however many messages it carried.
                    state
                        .metrics
                        .record_replication(&target, "upsert_artifact", "ok", elapsed);
                    for ((message_key, _message), done) in items.iter().zip(resolved) {
                        if done {
                            state.store.delete_outbox_message(message_key)?;
                            progressed = true;
                        }
                    }
                }
                Err(error) => {
                    state
                        .note_replication_failure(&target, Instant::now())
                        .await;
                    state
                        .metrics
                        .record_replication(&target, "upsert_artifact", "error", elapsed);
                    warn!("batched replication to {target} failed: {error}");
                }
            }
        }

        // Every batch failed or resolved nothing; retrying the same scan would
        // spin. The per-message pass and the next tick take it from here.
        if !progressed {
            return Ok(());
        }
    }

    Ok(())
}

// Next message at or after the cursor that is not already in flight. The scan
// rewinds to the head whenever a priority-lane message arrives, so it re-reaches
// keys the pipeline is still delivering; skipping them keeps one message to one
// delivery. The skip run is bounded by the in-flight limit.
fn next_undispatched_message(
    state: &SharedState,
    after: Option<&[u8]>,
    inflight_keys: &HashSet<Vec<u8>>,
) -> Result<Option<(Vec<u8>, OutboxMessage)>, String> {
    let mut cursor = after.map(<[u8]>::to_vec);
    loop {
        let Some((message_key, message)) = state.store.next_outbox_message(cursor.as_deref())?
        else {
            return Ok(None);
        };
        if !inflight_keys.contains(&message_key) {
            return Ok(Some((message_key, message)));
        }
        cursor = Some(message_key);
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

    // The metadata lane goes first and goes batched. It carries the small
    // inline artifacts, which is where per-message round trips dominate; what
    // it leaves behind (bulk bodies, namespace deletes, targets it could not
    // batch to) falls through to the per-message pass below.
    drain_metadata_batches(state, &current_targets).await?;

    // Deliveries are pipelined: up to `OUTBOX_MAX_INFLIGHT` are dispatched
    // before the first completion is awaited. Awaiting each message in turn
    // pinned a node's throughput to one delivery per round trip, which for a
    // write-primary whose peers sit on another continent lands below the rate
    // its own tenants write at. The queue then grows to `outbox_max_depth` and
    // the depth gate starts refusing those writes, which the cache client does
    // not retry.
    //
    // Out-of-order delivery is safe by construction: the apply side is
    // last-writer-wins on `version_ms` (`Store::artifact_apply_outcome`), so a
    // message landing after a newer one for the same key is ignored rather than
    // resurrecting stale bytes.
    let mut inflight = FuturesUnordered::new();
    // Dispatched but unresolved keys. `rewind_to_priority_head` sends the scan
    // back to the head mid-pass, so without this the same message could be
    // dispatched twice concurrently and then deleted twice.
    let mut inflight_keys: HashSet<Vec<u8>> = HashSet::new();
    // Targets whose backoff has already been advanced during this pass. The
    // pipeline dispatches a whole wave before it sees any result, so an
    // unreachable peer returns one failure per in-flight message rather than
    // one per attempt. Counting each of those would drive the exponential
    // backoff to its ceiling on a single blip — eight failures reach the 60s
    // clamp, where one attempt should have paused for two — and a peer that
    // blinked would then be parked long enough to rebuild the backlog this
    // pipelining exists to drain. One step per target per wave keeps the
    // escalation on the same cadence as the serial drain: one per pass.
    let mut backed_off_this_pass: HashSet<String> = HashSet::new();
    let mut after = None::<Vec<u8>>;

    loop {
        while inflight.len() < OUTBOX_MAX_INFLIGHT {
            let Some((message_key, message)) =
                next_undispatched_message(state, after.as_deref(), &inflight_keys)?
            else {
                break;
            };
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

            inflight_keys.insert(message_key.clone());
            inflight.push(async move {
                let started_at = std::time::Instant::now();
                let result = replicate_message(state, &message).await;
                (message_key, message, result, started_at.elapsed())
            });
        }

        // Nothing dispatched and nothing left to dispatch: the outbox is drained
        // for this pass.
        let Some((message_key, message, result, elapsed)) = inflight.next().await else {
            break;
        };
        inflight_keys.remove(&message_key);
        let operation_name = message.operation.name();

        match result {
            Ok(ReplicationOutcome::DroppedOversized) => {
                // The artifact was purged and can never replicate; drop the
                // message. Not a delivery and not a target failure, so leave the
                // target's success/backoff state untouched.
                state.metrics.record_replication(
                    &message.target,
                    operation_name,
                    "dropped_oversized",
                    elapsed,
                );
                state.store.delete_outbox_message(&message_key)?;
                rewind_to_priority_head(state, &mut after).await?;
            }
            Ok(ReplicationOutcome::Delivered) => {
                state.note_replication_success(&message.target).await;
                backed_off_this_pass.remove(&message.target);
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
                            elapsed,
                        );
                        state.store.delete_outbox_message(&message_key)?;
                        rewind_to_priority_head(state, &mut after).await?;
                    }
                    Err(error) => {
                        state.metrics.record_replication(
                            &message.target,
                            operation_name,
                            "error",
                            elapsed,
                        );
                        warn!("replication to {} failed: {error}", message.target);
                    }
                }
            }
            Err(error) => {
                if backed_off_this_pass.insert(message.target.clone()) {
                    state
                        .note_replication_failure(&message.target, Instant::now())
                        .await;
                }
                state
                    .metrics
                    .record_replication(&message.target, operation_name, "error", elapsed);
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
/// Chunks are 512 KiB. A multi-GB artifact would otherwise take a bandwidth
/// reservation hundreds of thousands of times, and the limiter is shared, so
/// small slivers queue behind other callers' 512 KiB reservations. The owned
/// segment-read allocation becomes the request-body chunk without an
/// intermediate asynchronous-reader copy.
///
/// The terminating mark is what gives the wait for the response a whole stall
/// window instead of the last chunk's remainder: the receiver copies the staged
/// body into a segment and fsyncs it under the node-wide segment write lock
/// before it answers, and that tail scales with the artifact, not the network.
fn upload_body_stream(
    reader: ArtifactReader,
    bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
    progress: Arc<UploadProgress>,
) -> impl futures_util::Stream<Item = std::io::Result<bytes::Bytes>> + Send + 'static {
    let end_progress = progress.clone();
    reader
        .into_bytes_stream(RESPONSE_STREAM_CHUNK_BYTES)
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

#[cfg(test)]
fn copying_upload_body_stream<R>(
    reader: R,
    bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
    progress: Arc<UploadProgress>,
) -> impl futures_util::Stream<Item = std::io::Result<bytes::Bytes>> + Send + 'static
where
    R: tokio::io::AsyncRead + Send + Unpin + 'static,
{
    let end_progress = progress.clone();
    tokio_util::io::ReaderStream::with_capacity(reader, RESPONSE_STREAM_CHUNK_BYTES)
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
        let reader = ArtifactReader::Inline {
            bytes: bytes::Bytes::from_static(b"payload"),
            offset: 0,
        };

        let progress = Arc::new(UploadProgress::new());
        let stream = upload_body_stream(reader, None, progress.clone());
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

    #[tokio::test]
    #[ignore = "performance benchmark run manually"]
    async fn replication_upload_owned_chunk_benchmark() {
        const SAMPLE_BYTES: u64 = 512 * 1_024 * 1_024;
        const SAMPLE_COUNT: usize = 8;

        async fn measure<S>(stream: S) -> Duration
        where
            S: futures_util::Stream<Item = std::io::Result<bytes::Bytes>>,
        {
            tokio::pin!(stream);
            let started_at = Instant::now();
            let mut read_bytes = 0_u64;
            while let Some(chunk) = stream.next().await {
                let chunk = chunk.expect("benchmark upload chunk");
                std::hint::black_box(chunk.as_ptr());
                read_bytes = read_bytes.saturating_add(chunk.len() as u64);
            }
            assert_eq!(read_bytes, SAMPLE_BYTES);
            started_at.elapsed()
        }

        let context = test_context(|config| {
            config.file_descriptor_pool_size = 4;
        })
        .await;
        let path = context
            .state
            .config
            .tmp_dir
            .join("replication-upload-stream-benchmark");
        let file = std::fs::File::create(&path).expect("create sparse benchmark file");
        file.set_len(SAMPLE_BYTES)
            .expect("size sparse benchmark file");
        drop(file);
        let handle = Arc::new(
            context
                .state
                .io
                .open_persistent_read_file(&path)
                .await
                .expect("open benchmark file"),
        );
        let reader = || {
            ArtifactReader::FileRange(crate::segment::reader::SegmentReader::new(
                handle.clone(),
                0,
                SAMPLE_BYTES,
            ))
        };

        let mut speedups = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut baseline_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut candidate_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        for sample in 0..SAMPLE_COUNT {
            let baseline =
                copying_upload_body_stream(reader(), None, Arc::new(UploadProgress::new()));
            let candidate = upload_body_stream(reader(), None, Arc::new(UploadProgress::new()));
            let (baseline_elapsed, candidate_elapsed) = if sample % 2 == 0 {
                (measure(baseline).await, measure(candidate).await)
            } else {
                let candidate_elapsed = measure(candidate).await;
                let baseline_elapsed = measure(baseline).await;
                (baseline_elapsed, candidate_elapsed)
            };
            if sample > 0 {
                let mebibytes = SAMPLE_BYTES as f64 / (1_024.0 * 1_024.0);
                baseline_throughputs.push(mebibytes / baseline_elapsed.as_secs_f64());
                candidate_throughputs.push(mebibytes / candidate_elapsed.as_secs_f64());
                speedups.push(baseline_elapsed.as_secs_f64() / candidate_elapsed.as_secs_f64());
            }
        }
        speedups.sort_by(f64::total_cmp);
        baseline_throughputs.sort_by(f64::total_cmp);
        candidate_throughputs.sort_by(f64::total_cmp);
        println!(
            "METRIC replication_upload_stream_speedup_ratio={:.6}",
            speedups[speedups.len() / 2]
        );
        println!(
            "METRIC baseline_mebibytes_per_second={:.3}",
            baseline_throughputs[baseline_throughputs.len() / 2]
        );
        println!(
            "METRIC candidate_mebibytes_per_second={:.3}",
            candidate_throughputs[candidate_throughputs.len() / 2]
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
    async fn a_wave_of_failures_to_one_target_advances_its_backoff_once() {
        // The pipeline dispatches a whole wave before it observes any result,
        // so an unreachable peer answers one failure per in-flight message
        // rather than one per attempt. Counting each of those would run the
        // exponential backoff to its 60s ceiling on a single blip, parking a
        // peer that merely blinked for long enough to rebuild a backlog. The
        // wave must move the backoff one step, to the initial two seconds.
        let local = test_context(|_| {}).await;
        let unreachable = "http://127.0.0.1:1".to_string();

        for index in 0..8 {
            let key = format!("artifact-{index}");
            local
                .state
                .store
                .persist_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    &key,
                    "application/octet-stream",
                    b"payload",
                )
                .await
                .expect("artifact should persist");
            let artifact = local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", &key)
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
                        key,
                        content_type: "application/octet-stream".into(),
                        artifact_id: artifact.artifact_id,
                        version_ms: artifact.version_ms,
                        inline: false,
                        branch: None,
                        trunk: None,
                    },
                })
                .expect("upsert should enqueue");
        }

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
        assert!(
            !local
                .state
                .replication_target_backed_off(
                    &unreachable,
                    Instant::now() + Duration::from_secs(5)
                )
                .await,
            "one wave of failures escalated the backoff past its first step; \
             the whole wave is one attempt, not one attempt per message"
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

    #[tokio::test]
    async fn outbox_deliveries_overlap_across_messages() {
        // The drain used to await each delivery before dispatching the next,
        // which pinned throughput to one message per round trip however much
        // bandwidth the node had. The peer here holds every request open for a
        // fixed delay and records how many were open at once: a serial drain
        // can never record more than one.
        const MESSAGES: usize = 16;

        let open = Arc::new(AtomicU64::new(0));
        let peak = Arc::new(AtomicU64::new(0));
        let app = Router::new().route(
            "/_internal/replicate/artifact",
            put({
                let open = open.clone();
                let peak = peak.clone();
                move || {
                    let open = open.clone();
                    let peak = peak.clone();
                    async move {
                        let now = open.fetch_add(1, Ordering::SeqCst) + 1;
                        peak.fetch_max(now, Ordering::SeqCst);
                        sleep(Duration::from_millis(150)).await;
                        open.fetch_sub(1, Ordering::SeqCst);
                        StatusCode::NO_CONTENT
                    }
                }
            }),
        );
        let (peer_url, _server) = spawn_server(app).await;

        let ctx = test_context({
            let peer_url = peer_url.clone();
            move |config| {
                config.peers = vec![peer_url.clone()];
            }
        })
        .await;

        for index in 0..MESSAGES {
            let manifest = ctx
                .state
                .store
                .persist_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "namespace",
                    &format!("artifact-{index}"),
                    "application/octet-stream",
                    b"hello",
                )
                .await
                .expect("artifact should persist");
            enqueue_replication_for_artifact(&ctx.state, &manifest).await;
        }

        process_outbox(&ctx.state)
            .await
            .expect("outbox should drain");

        assert!(
            ctx.state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .is_empty(),
            "every delivered message must be cleared from the outbox"
        );
        let peak = peak.load(Ordering::SeqCst);
        assert!(
            peak > 1,
            "deliveries never overlapped (peak in flight was {peak}); the drain is still serial"
        );
        assert!(
            peak <= OUTBOX_MAX_INFLIGHT as u64,
            "peak in flight was {peak}, above the {OUTBOX_MAX_INFLIGHT} the drain admits"
        );
    }

    #[tokio::test]
    async fn next_undispatched_message_skips_keys_already_in_flight() {
        // `rewind_to_priority_head` sends the scan back to the head mid-pass,
        // so it re-reaches keys the pipeline is still delivering. Handing one
        // out twice would replicate it twice and delete it twice.
        let ctx = test_context(|config| {
            config.peers = vec!["http://127.0.0.1:4101".into()];
        })
        .await;

        for index in 0..2 {
            let manifest = ctx
                .state
                .store
                .persist_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "namespace",
                    &format!("artifact-{index}"),
                    "application/octet-stream",
                    b"hello",
                )
                .await
                .expect("artifact should persist");
            enqueue_replication_for_artifact(&ctx.state, &manifest).await;
        }

        let queued = ctx
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert_eq!(queued.len(), 2);
        let head_key = queued[0].0.clone();

        let mut inflight_keys = HashSet::new();
        inflight_keys.insert(head_key.clone());

        let (next_key, _message) = next_undispatched_message(&ctx.state, None, &inflight_keys)
            .expect("scan should succeed")
            .expect("the second message should still be dispatchable");
        assert_ne!(
            next_key, head_key,
            "a message already in flight must not be handed out again"
        );
    }

    /// Peer that serves the batch route, recording how many requests it took
    /// and how many items each carried.
    fn batching_peer(
        requests: Arc<AtomicU64>,
        items_seen: Arc<AtomicU64>,
        fail_first_item: bool,
    ) -> Router {
        Router::new().route(
            "/_internal/replicate/artifacts",
            put(move |body: axum::body::Bytes| {
                let requests = requests.clone();
                let items_seen = items_seen.clone();
                async move {
                    requests.fetch_add(1, Ordering::SeqCst);
                    let frames = crate::http::decode_replicate_batch_frames(&body)
                        .expect("batch body should decode");
                    items_seen.fetch_add(frames.len() as u64, Ordering::SeqCst);
                    let outcomes = frames
                        .iter()
                        .enumerate()
                        .map(|(index, _)| {
                            if fail_first_item && index == 0 {
                                "error".to_owned()
                            } else {
                                "applied".to_owned()
                            }
                        })
                        .collect();
                    axum::Json(crate::http::ReplicateBatchOutcomes { outcomes })
                }
            }),
        )
    }

    async fn enqueue_inline_artifacts(ctx: &TestContext, peer_url: &str, count: usize) {
        for index in 0..count {
            ctx.state
                .store
                .persist_inline_artifact_from_bytes_and_enqueue(
                    ArtifactProducer::Xcode,
                    "namespace",
                    &format!("entry-{index}"),
                    "application/octet-stream",
                    b"action-cache-entry",
                    std::slice::from_ref(&peer_url.to_owned()),
                    None,
                    None,
                )
                .await
                .expect("inline artifact should persist");
        }
    }

    #[tokio::test]
    async fn metadata_lane_ships_as_one_batched_request() {
        // The lane carries inline artifacts of a few KiB, so one request per
        // message spends a whole round trip on less than an MTU of payload.
        // Sixteen messages must cost one request, not sixteen.
        let requests = Arc::new(AtomicU64::new(0));
        let items_seen = Arc::new(AtomicU64::new(0));
        let (peer_url, _server) =
            spawn_server(batching_peer(requests.clone(), items_seen.clone(), false)).await;

        let ctx = test_context({
            let peer_url = peer_url.clone();
            move |config| {
                config.peers = vec![peer_url.clone()];
            }
        })
        .await;
        enqueue_inline_artifacts(&ctx, &peer_url, 16).await;

        process_outbox(&ctx.state)
            .await
            .expect("outbox should drain");

        assert_eq!(
            items_seen.load(Ordering::SeqCst),
            16,
            "every queued message should have been delivered"
        );
        assert_eq!(
            requests.load(Ordering::SeqCst),
            1,
            "sixteen inline messages should cost one request, not one each"
        );
        assert!(
            ctx.state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .is_empty(),
            "delivered messages must be cleared"
        );
    }

    #[tokio::test]
    async fn a_peer_without_the_batch_route_falls_back_to_per_message() {
        // Mixed-version meshes are the normal state mid-rollout: a peer that
        // predates the batch route answers 404, and its messages must still
        // drain through the per-artifact route rather than wedging.
        let singles = Arc::new(AtomicU64::new(0));
        let app = Router::new().route(
            "/_internal/replicate/artifact",
            put({
                let singles = singles.clone();
                move || {
                    let singles = singles.clone();
                    async move {
                        singles.fetch_add(1, Ordering::SeqCst);
                        StatusCode::NO_CONTENT
                    }
                }
            }),
        );
        let (peer_url, _server) = spawn_server(app).await;

        let ctx = test_context({
            let peer_url = peer_url.clone();
            move |config| {
                config.peers = vec![peer_url.clone()];
            }
        })
        .await;
        enqueue_inline_artifacts(&ctx, &peer_url, 4).await;

        process_outbox(&ctx.state)
            .await
            .expect("outbox should drain against a peer without the batch route");

        assert_eq!(
            singles.load(Ordering::SeqCst),
            4,
            "each message should have gone through the per-artifact route"
        );
        assert!(
            ctx.state.replication_batch_unsupported(&peer_url).await,
            "the peer should be remembered as batch-less so later passes skip the probe"
        );
        assert!(
            ctx.state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .is_empty(),
            "the fallback must still clear delivered messages"
        );
    }

    #[tokio::test]
    async fn a_failed_item_stays_queued_while_its_batch_mates_clear() {
        // Per-item outcomes are the point of the response shape: one poison
        // item must not strand everything batched with it, and must not be
        // dropped either.
        let requests = Arc::new(AtomicU64::new(0));
        let items_seen = Arc::new(AtomicU64::new(0));
        let (peer_url, _server) =
            spawn_server(batching_peer(requests.clone(), items_seen.clone(), true)).await;

        let ctx = test_context({
            let peer_url = peer_url.clone();
            move |config| {
                config.peers = vec![peer_url.clone()];
            }
        })
        .await;
        enqueue_inline_artifacts(&ctx, &peer_url, 5).await;

        process_outbox(&ctx.state)
            .await
            .expect("outbox should drain");

        let queued = ctx
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert_eq!(
            queued.len(),
            1,
            "only the item the peer rejected should remain queued"
        );
    }

    #[tokio::test]
    async fn a_namespace_delete_ships_in_the_same_pass_as_batched_messages() {
        // The batch pre-pass restarts its scan at the outbox head after every
        // round, and namespace deletes are never batchable. Without a bound on
        // rounds, a target with a steady supply of batchable pairs keeps the
        // pass inside the pre-pass and the per-message drain - the only thing
        // that ships deletes, and the only path a peer without the batch route
        // has - never runs.
        let batches = Arc::new(AtomicU64::new(0));
        let deletes = Arc::new(AtomicU64::new(0));
        let app = Router::new()
            .route(
                "/_internal/replicate/artifacts",
                put({
                    let batches = batches.clone();
                    move |body: axum::body::Bytes| {
                        let batches = batches.clone();
                        async move {
                            batches.fetch_add(1, Ordering::SeqCst);
                            let frames = crate::http::decode_replicate_batch_frames(&body)
                                .expect("batch body should decode");
                            let outcomes = frames
                                .iter()
                                .map(|_| "applied".to_owned())
                                .collect::<Vec<_>>();
                            axum::Json(crate::http::ReplicateBatchOutcomes { outcomes })
                        }
                    }
                }),
            )
            .route(
                "/_internal/replicate/namespace",
                axum::routing::delete({
                    let deletes = deletes.clone();
                    move || {
                        let deletes = deletes.clone();
                        async move {
                            deletes.fetch_add(1, Ordering::SeqCst);
                            StatusCode::NO_CONTENT
                        }
                    }
                }),
            );
        let (peer_url, _server) = spawn_server(app).await;

        let ctx = test_context({
            let peer_url = peer_url.clone();
            move |config| {
                config.peers = vec![peer_url.clone()];
            }
        })
        .await;
        enqueue_inline_artifacts(&ctx, &peer_url, 6).await;
        ctx.state
            .store
            .enqueue(OutboxMessage {
                target: peer_url.clone(),
                operation: ReplicationOperation::DeleteNamespace {
                    namespace_id: "namespace".into(),
                    version_ms: 900,
                },
            })
            .expect("delete should enqueue");

        process_outbox(&ctx.state)
            .await
            .expect("outbox should drain");

        assert!(
            batches.load(Ordering::SeqCst) >= 1,
            "the inline messages should still have gone out batched"
        );
        assert_eq!(
            deletes.load(Ordering::SeqCst),
            1,
            "the namespace delete must not be starved behind the batch pre-pass"
        );
        assert!(
            ctx.state
                .store
                .outbox_messages()
                .expect("outbox should load")
                .is_empty(),
            "both lanes should have drained in one pass"
        );
    }
}
