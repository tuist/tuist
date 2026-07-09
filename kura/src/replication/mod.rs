pub mod operation;
pub mod outbox_message;

use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    net::{IpAddr, SocketAddr},
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
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
use tracing::{Instrument, field, info, warn};

use crate::{
    artifact::manifest::ArtifactManifest,
    config::Config,
    constants::{
        BOOTSTRAP_DIGEST_DEFAULT_PREFIX_LEN, MAX_BOOTSTRAP_PAGE_BYTES,
        MAX_INLINE_REPLICATION_BODY_BYTES, MAX_REPLICATION_BODY_BYTES, REPLICATION_RETRY_SECS,
    },
    failpoints::FailpointName,
    state::SharedState,
    store::{
        ArtifactApplyOutcome, ManifestBucketDigest, ManifestDigest, ManifestPage,
        NamespaceTombstonePage,
    },
    telemetry::{inject_current_trace_context, record_trace_context},
    utils::{replication_target_label, temp_file_path, url_encode},
};

use self::{operation::ReplicationOperation, outbox_message::OutboxMessage};

const BOOTSTRAP_PAGE_LIMIT: usize = 256;

// Artifact bodies fetched from a peer concurrently within a bootstrap page. Caps
// open peer connections; staged bytes stay bounded by bootstrap_staging_budget.
const BOOTSTRAP_ARTIFACT_FETCH_CONCURRENCY: usize = 16;

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
pub async fn enqueue_replication_for_artifact(state: &SharedState, manifest: &ArtifactManifest) {
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

fn spawn_supervised<F, Fut>(name: &'static str, state: SharedState, work: F)
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
        let membership_update = state
            .apply_membership_view(members, peer_nodes, discovery_observed)
            .await;
        state
            .metrics
            .update_discovered_peer_nodes(membership_update.known_peer_count);
        for peer in state.peers_needing_bootstrap().await {
            maybe_spawn_bootstrap_task(state.clone(), peer).await;
        }
        state.maybe_mark_serving().await;
        sleep(Duration::from_secs(2)).await;
    }
}

async fn outbox_task_loop(state: SharedState) {
    loop {
        let notified = state.notify.notified();
        tokio::pin!(notified);

        let pause_outbox = state.memory.pause_outbox();
        state
            .metrics
            .update_background_work_paused("outbox", pause_outbox);
        if !pause_outbox && let Err(error) = process_outbox(&state).await {
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

async fn maybe_spawn_bootstrap_task(state: SharedState, peer: String) {
    if !state.note_bootstrap_started(&peer).await {
        return;
    }

    let semaphore = state.bootstrap_semaphore.clone();
    tokio::spawn(
        async move {
            let _permit = match semaphore.acquire_owned().await {
                Ok(permit) => permit,
                Err(_) => {
                    state.note_bootstrap_failed(&peer).await;
                    return;
                }
            };
            let started_at = std::time::Instant::now();
            let no_progress_timeout = Duration::from_millis(state.config.bootstrap_timeout_ms);
            let result =
                bootstrap_from_peer_with_watchdog(&state, &peer, no_progress_timeout).await;
            match result {
                Ok(stats) => {
                    state.note_bootstrap_succeeded(&peer).await;
                    state.metrics.record_bootstrap_run(
                        "ok",
                        started_at.elapsed(),
                        stats.tombstones_applied,
                        stats.artifacts_applied,
                    );
                    state.maybe_mark_serving().await;
                }
                Err(error) => {
                    warn!("bootstrap from {peer} failed: {error}");
                    state
                        .metrics
                        .record_bootstrap_run("error", started_at.elapsed(), 0, 0);
                    state.note_bootstrap_failed(&peer).await;
                }
            }
        }
        .in_current_span(),
    );
}

/// Run a per-peer bootstrap under a *no-progress* watchdog. A single wall-clock
/// cap on the whole bootstrap can never let a large cold pull finish — the walk
/// is killed and restarts from scratch every window, so a node whose backlog
/// exceeds one window's worth of transfer stays `NotReady` forever. Instead the
/// bootstrap runs until it completes or genuinely stalls: every fetched page and
/// applied artifact bumps a progress counter, and the watchdog only abandons the
/// bootstrap after `no_progress_timeout` elapses with *no* forward progress. A
/// steadily-progressing multi-hour pull now converges; a truly stuck one is
/// still abandoned and retried.
async fn bootstrap_from_peer_with_watchdog(
    state: &SharedState,
    peer: &str,
    no_progress_timeout: Duration,
) -> Result<BootstrapStats, String> {
    let progress = AtomicU64::new(0);
    tokio::select! {
        result = bootstrap_from_peer(state, peer, &progress) => result,
        () = bootstrap_no_progress_watchdog(&progress, no_progress_timeout) => Err(format!(
            "bootstrap from {peer} made no progress for {} ms; abandoning this attempt",
            no_progress_timeout.as_millis()
        )),
    }
}

/// Resolve once the `progress` counter has failed to advance across a full
/// `interval`. Callers select this against the bootstrap future, so it acts as a
/// stall detector rather than a total-runtime cap.
async fn bootstrap_no_progress_watchdog(progress: &AtomicU64, interval: Duration) {
    let mut last = progress.load(Ordering::Relaxed);
    loop {
        sleep(interval).await;
        let current = progress.load(Ordering::Relaxed);
        if current == last {
            return;
        }
        last = current;
    }
}

async fn bootstrap_from_peer(
    state: &SharedState,
    peer: &str,
    progress: &AtomicU64,
) -> Result<BootstrapStats, String> {
    let tombstones_applied =
        bootstrap_namespace_tombstones_from_peer(state, peer, progress).await?;
    let artifacts_applied = bootstrap_manifests_from_peer(state, peer, progress).await?;
    Ok(BootstrapStats {
        tombstones_applied,
        artifacts_applied,
    })
}

async fn bootstrap_namespace_tombstones_from_peer(
    state: &SharedState,
    peer: &str,
    progress: &AtomicU64,
) -> Result<u64, String> {
    let mut after = None;
    let mut applied = 0_u64;

    loop {
        let page = fetch_bootstrap_tombstones_page(state, peer, after.as_deref()).await?;
        progress.fetch_add(1, Ordering::Relaxed);
        for tombstone in &page.tombstones {
            let outcome = state
                .store
                .apply_replicated_namespace_delete(&tombstone.namespace_id, tombstone.version_ms)
                .await
                .inspect_err(|_| {
                    state.metrics.record_replication_apply(
                        "bootstrap",
                        "namespace_delete",
                        "error",
                    );
                })?;
            state.metrics.record_replication_apply(
                "bootstrap",
                "namespace_delete",
                outcome.as_str(),
            );
            if outcome.applied() {
                applied += 1;
            }
        }

        match page.next_after {
            Some(next_after) => after = Some(next_after),
            None => return Ok(applied),
        }
    }
}

async fn bootstrap_manifests_from_peer(
    state: &SharedState,
    peer: &str,
    progress: &AtomicU64,
) -> Result<u64, String> {
    let prefix_len = BOOTSTRAP_DIGEST_DEFAULT_PREFIX_LEN;
    let mut applied = 0_u64;
    let mut failed = 0_u64;

    // Range-based anti-entropy: exchange per-bucket digests and walk only the
    // buckets whose contents differ. For a mostly-in-sync pair this collapses a
    // full O(peer dataset) page walk into one digest exchange plus a handful of
    // small range walks, so the joining node reconciles the delta in seconds
    // instead of re-walking every manifest each retry until the bootstrap
    // timeout fires.
    match fetch_bootstrap_digest(state, peer, prefix_len).await? {
        Some(peer_digest) => {
            progress.fetch_add(1, Ordering::Relaxed);
            let local_digest = state.store.manifests_digest(prefix_len)?;
            let divergent = divergent_prefixes(&local_digest, &peer_digest.buckets);
            let walked = divergent.len() as u64;
            let matched = (peer_digest.buckets.len() as u64).saturating_sub(walked);
            state
                .metrics
                .record_bootstrap_digest_reconcile(matched, walked);
            info!(
                "bootstrap from {peer}: {walked}/{} manifest buckets diverged, {matched} matched and skipped",
                peer_digest.buckets.len()
            );
            for prefix in divergent {
                let (range_applied, range_failed) =
                    bootstrap_manifest_range_from_peer(state, peer, Some(&prefix), progress)
                        .await?;
                applied += range_applied;
                failed += range_failed;
            }
        }
        None => {
            // Peer predates the digest endpoint (one-version-skew during a
            // rollout, or a mixed-version mesh): fall back to a full keyspace
            // walk, exactly as before.
            let (range_applied, range_failed) =
                bootstrap_manifest_range_from_peer(state, peer, None, progress).await?;
            applied += range_applied;
            failed += range_failed;
        }
    }

    // Surfaced as a failed bootstrap so the peer is retried, but only after this
    // pass has applied everything it could — that forward progress is what lets
    // a mutually-bootstrapping mesh converge instead of deadlocking. A peer is
    // marked bootstrapped (and the node allowed to serve) only on a fully clean
    // pass, so readiness still implies complete data.
    if failed > 0 {
        return Err(format!(
            "bootstrap from {peer} incomplete: {failed} artifact(s) failed this pass, {applied} applied; will retry"
        ));
    }

    Ok(applied)
}

/// Diff a local digest against a peer's, returning the peer bucket prefixes we
/// must enumerate to pull the peer's data. A bucket is divergent when the peer
/// has it and our `(count, hash)` for that prefix doesn't match exactly
/// (including buckets we lack entirely). Buckets only *we* hold are ignored:
/// bootstrap pulls from the peer, so there is nothing to fetch there.
fn divergent_prefixes(
    local: &[ManifestBucketDigest],
    peer: &[ManifestBucketDigest],
) -> Vec<String> {
    let local_by_prefix: HashMap<&str, (u64, &str)> = local
        .iter()
        .map(|bucket| (bucket.prefix.as_str(), (bucket.count, bucket.hash.as_str())))
        .collect();

    peer.iter()
        .filter(|bucket| {
            local_by_prefix.get(bucket.prefix.as_str())
                != Some(&(bucket.count, bucket.hash.as_str()))
        })
        .map(|bucket| bucket.prefix.clone())
        .collect()
}

/// Walk the peer's manifest keyspace (optionally scoped to a single digest
/// bucket prefix), pre-checking and fetching each artifact. Returns
/// `(applied, failed)` for the caller to aggregate across ranges.
async fn bootstrap_manifest_range_from_peer(
    state: &SharedState,
    peer: &str,
    prefix: Option<&str>,
    progress: &AtomicU64,
) -> Result<(u64, u64), String> {
    let mut after = None;
    let mut applied = 0_u64;
    let mut failed = 0_u64;

    loop {
        let page = fetch_bootstrap_manifests_page(state, peer, after.as_deref(), prefix).await?;
        // Fetching a page is forward progress even when it applies nothing (a
        // warm re-walk or an already-present range), so the no-progress watchdog
        // never abandons a bootstrap that is still advancing through the walk.
        progress.fetch_add(1, Ordering::Relaxed);
        state
            .store
            .hit_failpoint(FailpointName::AfterBootstrapManifestPageFetchBeforeApply)
            .await?;

        // Cheap local pre-check first: skip artifacts we already hold without a
        // network fetch, and propagate a real store error instead of masking it as
        // a per-artifact fetch failure below.
        let mut to_fetch = Vec::new();
        for manifest in &page.manifests {
            let outcome = state.store.artifact_apply_outcome(
                manifest.producer,
                &manifest.namespace_id,
                &manifest.key,
                manifest.version_ms,
            )?;
            if outcome.applied() {
                to_fetch.push(manifest.clone());
            } else {
                state
                    .metrics
                    .record_replication_apply("bootstrap", "artifact", outcome.as_str());
            }
        }

        // Fetch the page's artifacts concurrently. A fresh node bootstraps the
        // whole dataset over the WAN, where one serial stream leaves the link idle
        // between requests and can't finish a large cache inside the bootstrap
        // timeout. Concurrency caps open connections; staged bytes stay bounded by
        // the bootstrap_staging_budget each fetch reserves against, and the
        // segment-append lock still serializes the on-disk write, so only the
        // network transfers overlap.
        let outcomes: Vec<Result<bool, String>> = stream::iter(to_fetch)
            .map(|manifest| async move {
                // A single artifact failing must not abort the whole peer
                // bootstrap. Aborting strands every later artifact behind the first
                // gap, and when peers bootstrap from each other simultaneously
                // (e.g. a full-mesh restart) each one serves still-incomplete data,
                // so every bootstrap breaks at its first gap and the mesh deadlocks
                // with none reaching a serving state. Record the failure, keep
                // going so we still apply the artifacts we can fetch this pass, and
                // report partial completion at the end so the peer is retried —
                // already-applied artifacts are skipped on the retry, so successive
                // passes converge as data propagates outward from the data-bearing
                // replicas.
                match bootstrap_artifact_from_peer(state, peer, &manifest).await {
                    Ok(outcome) => {
                        state.metrics.record_replication_apply(
                            "bootstrap",
                            "artifact",
                            outcome.as_str(),
                        );
                        Ok(outcome.applied())
                    }
                    Err(error) => {
                        state
                            .metrics
                            .record_replication_apply("bootstrap", "artifact", "error");
                        warn!("bootstrap artifact from {peer} failed, continuing: {error}");
                        Err(error)
                    }
                }
            })
            .buffer_unordered(BOOTSTRAP_ARTIFACT_FETCH_CONCURRENCY)
            .collect()
            .await;

        for outcome in outcomes {
            match outcome {
                Ok(true) => {
                    applied += 1;
                    progress.fetch_add(1, Ordering::Relaxed);
                }
                Ok(false) => {}
                Err(_) => failed += 1,
            }
        }

        match page.next_after {
            Some(next_after) => after = Some(next_after),
            None => break,
        }
    }

    Ok((applied, failed))
}

async fn bootstrap_artifact_from_peer(
    state: &SharedState,
    peer: &str,
    manifest: &ArtifactManifest,
) -> Result<ArtifactApplyOutcome, String> {
    // Single-flight the body download across peers. A fresh node bootstraps from
    // every peer concurrently, and the mesh is near-fully overlapping, so absent
    // this gate each peer-task would pull the same artifact and the node would
    // transfer the whole dataset once per peer. Hold a per-artifact gate across
    // the fetch+apply and re-check presence after acquiring it: the first
    // peer-task to claim a key downloads it, and the rest observe it already
    // applied and skip the network entirely. On failure the owner releases the
    // gate with the key still absent, so the next waiter re-checks, sees the gap,
    // and fetches it from its own peer — the dedup self-heals instead of
    // stranding the artifact. The gate is bootstrap-scoped so it never blocks the
    // live-replication apply path; the store's per-key apply lock remains the
    // last-line write-dedup.
    let _fetch_guard = state
        .bootstrap_fetch_lock(&manifest.artifact_id)
        .lock()
        .await;
    let recheck = state.store.artifact_apply_outcome(
        manifest.producer,
        &manifest.namespace_id,
        &manifest.key,
        manifest.version_ms,
    )?;
    if !recheck.applied() {
        return Ok(recheck);
    }

    let url = format!(
        "{peer}/_internal/bootstrap/artifacts/{}",
        url_encode(&manifest.artifact_id)
    );
    let response = state
        .client()
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("bootstrap artifact request failed: {error:?}"))?;
    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(ArtifactApplyOutcome::IgnoredStale);
    }
    let response = response
        .error_for_status()
        .map_err(|error| format!("bootstrap artifact response failed: {error}"))?;

    if manifest.inline {
        let bytes = read_bounded_body(
            response,
            MAX_INLINE_REPLICATION_BODY_BYTES,
            "bootstrap inline artifact",
        )
        .await?;
        state
            .store
            .hit_failpoint(FailpointName::AfterBootstrapArtifactFetchBeforePersist)
            .await?;
        return state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                manifest.producer,
                &manifest.namespace_id,
                &manifest.key,
                &manifest.content_type,
                bytes.as_ref(),
                manifest.version_ms,
            )
            .await;
    }

    let declared_bytes = response.content_length();
    if let Some(declared) = declared_bytes
        && declared > MAX_REPLICATION_BODY_BYTES
    {
        return Err(format!(
            "bootstrap artifact response declared {declared} bytes, exceeds limit of {MAX_REPLICATION_BODY_BYTES}"
        ));
    }
    // Reserve for the larger of the manifest size and the peer's declared body
    // so an inconsistent peer can't stage more bytes than we accounted for.
    let reserved_bytes = manifest
        .size
        .max(declared_bytes.unwrap_or(0))
        .min(MAX_REPLICATION_BODY_BYTES);
    // reserve() waits when the budget is full, so peak concurrent staging never
    // exceeds it however large the account is. A whole-dir hard check here is
    // wrong: when bootstrap legitimately fills the budget it would reject the
    // next artifact and fail the whole bootstrap, reintroducing the stall this
    // reservation exists to prevent. (The node is out of the Service while
    // bootstrapping, so non-bootstrap tmp occupants are negligible.)
    let _staging_reservation = state.bootstrap_staging_budget.reserve(reserved_bytes).await;
    let temp_path = temp_file_path(&state.config.tmp_dir.join("bootstrap"), "bootstrap");
    stream_response_to_temp(state, response, &temp_path, reserved_bytes).await?;
    state
        .store
        .hit_failpoint(FailpointName::AfterBootstrapArtifactFetchBeforePersist)
        .await?;
    state
        .store
        .apply_replicated_artifact_from_path(
            manifest.producer,
            &manifest.namespace_id,
            &manifest.key,
            &manifest.content_type,
            &temp_path,
            manifest.version_ms,
        )
        .await
}

async fn stream_response_to_temp(
    state: &SharedState,
    response: reqwest::Response,
    path: &Path,
    staging_limit: u64,
) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "bootstrap temp path is missing a parent directory".to_string())?;
    state.io.create_dir_all(parent).await?;
    // The staged file must not exceed the caller's `bootstrap_staging_budget`
    // reservation: an inconsistent peer serving a body larger than its manifest
    // advertised is rejected here instead of overrunning the budget.
    let mut destination = state.io.create_file(path).await?;
    let dest = &mut destination;
    let outcome = async move {
        let mut stream = response.bytes_stream();
        let mut total: u64 = 0;
        while let Some(chunk) = stream.next().await {
            let chunk =
                chunk.map_err(|error| format!("failed to stream bootstrap body: {error:?}"))?;
            total = total.saturating_add(chunk.len() as u64);
            if total > staging_limit {
                return Err(format!(
                    "bootstrap artifact response exceeded reserved {staging_limit} bytes"
                ));
            }
            if let Some(limiter) = state.replication_bandwidth_limiter.as_ref() {
                limiter.acquire(chunk.len()).await;
            }
            dest.write_all(&chunk)
                .await
                .map_err(|error| format!("failed to persist bootstrap body: {error}"))?;
        }
        dest.flush()
            .await
            .map_err(|error| format!("failed to flush bootstrap body: {error}"))?;
        Ok::<(), String>(())
    }
    .await;

    // Drop the handle, then remove the partially-staged file on any failure. A
    // peer serving incomplete data or a dropped connection (the bootstrap deadlock
    // case) would otherwise leave one temp file per attempt; a retrying bootstrap
    // accumulates them until the data disk fills and RocksDB can no longer open,
    // wedging the pod out-of-space.
    drop(destination);
    if outcome.is_err() {
        state.io.remove_file_if_exists(path).await;
    }
    outcome
}

async fn fetch_bootstrap_manifests_page(
    state: &SharedState,
    peer: &str,
    after: Option<&str>,
    prefix: Option<&str>,
) -> Result<ManifestPage, String> {
    let mut url = format!("{peer}/_internal/bootstrap/manifests?limit={BOOTSTRAP_PAGE_LIMIT}");
    if let Some(after) = after {
        url.push_str("&after=");
        url.push_str(&url_encode(after));
    }
    if let Some(prefix) = prefix {
        url.push_str("&prefix=");
        url.push_str(&url_encode(prefix));
    }

    let response = state
        .client()
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("bootstrap manifest request failed: {error}"))?
        .error_for_status()
        .map_err(|error| format!("bootstrap manifest response failed: {error}"))?;
    let bytes = read_bounded_body(response, MAX_BOOTSTRAP_PAGE_BYTES, "bootstrap manifest").await?;
    serde_json::from_slice(&bytes)
        .map_err(|error| format!("failed to decode bootstrap manifest page: {error}"))
}

/// Fetch the peer's per-bucket manifest digest for range-based anti-entropy.
/// Returns `Ok(None)` when the peer does not implement the endpoint (older
/// version → 404), which the caller treats as "fall back to a full walk". Any
/// other transport or decode failure is a hard error so the bootstrap is
/// retried rather than silently degrading to a full walk on a flaky link.
async fn fetch_bootstrap_digest(
    state: &SharedState,
    peer: &str,
    prefix_len: usize,
) -> Result<Option<ManifestDigest>, String> {
    let url = format!("{peer}/_internal/bootstrap/digest?prefix_len={prefix_len}");
    let response = state
        .client()
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("bootstrap digest request failed: {error}"))?;
    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(None);
    }
    let response = response
        .error_for_status()
        .map_err(|error| format!("bootstrap digest response failed: {error}"))?;
    let bytes = read_bounded_body(response, MAX_BOOTSTRAP_PAGE_BYTES, "bootstrap digest").await?;
    let digest: ManifestDigest = serde_json::from_slice(&bytes)
        .map_err(|error| format!("failed to decode bootstrap digest: {error}"))?;
    // A peer that answered with a different partitioning than we asked for can't
    // be diffed against our local digest; fall back to a full walk rather than
    // mis-diffing incompatible buckets.
    if digest.prefix_len != prefix_len {
        return Ok(None);
    }
    Ok(Some(digest))
}

async fn fetch_bootstrap_tombstones_page(
    state: &SharedState,
    peer: &str,
    after: Option<&str>,
) -> Result<NamespaceTombstonePage, String> {
    let mut url =
        format!("{peer}/_internal/bootstrap/namespace_tombstones?limit={BOOTSTRAP_PAGE_LIMIT}");
    if let Some(after) = after {
        url.push_str("&after=");
        url.push_str(&url_encode(after));
    }

    let response = state
        .client()
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("bootstrap tombstone request failed: {error}"))?
        .error_for_status()
        .map_err(|error| format!("bootstrap tombstone response failed: {error}"))?;
    let bytes =
        read_bounded_body(response, MAX_BOOTSTRAP_PAGE_BYTES, "bootstrap tombstone").await?;
    serde_json::from_slice(&bytes)
        .map_err(|error| format!("failed to decode bootstrap tombstone page: {error}"))
}

async fn read_bounded_body(
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

#[derive(Debug)]
struct BootstrapStats {
    tombstones_applied: u64,
    artifacts_applied: u64,
}

pub async fn process_outbox(state: &SharedState) -> Result<(), String> {
    let mut after = None::<Vec<u8>>;
    while let Some((message_key, message)) = state.store.next_outbox_message(after.as_deref())? {
        after = Some(message_key.clone());

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
            Ok(()) => {
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

    Ok(())
}

async fn replicate_message(state: &SharedState, message: &OutboxMessage) -> Result<(), String> {
    match &message.operation {
        ReplicationOperation::UpsertArtifact {
            producer,
            namespace_id,
            key,
            content_type,
            artifact_id,
            version_ms,
            inline,
        } => {
            let manifest = match state.store.manifest(artifact_id)? {
                Some(manifest) => manifest,
                None => return Ok(()),
            };

            let file = state
                .store
                .open_artifact_reader(&manifest)
                .await
                .map_err(|error| {
                    format!("failed to open local artifact for replication: {error}")
                })?;

            let url = format!(
                "{}/_internal/replicate/artifact?producer={}&inline={}&namespace_id={}&key={}&content_type={}&version_ms={}",
                message.target,
                producer.as_str(),
                inline,
                url_encode(namespace_id),
                url_encode(key),
                url_encode(content_type),
                version_ms,
            );
            let bandwidth_limiter = state.replication_bandwidth_limiter.clone();
            let body_stream = ReaderStream::new(file).then(move |item| {
                let bandwidth_limiter = bandwidth_limiter.clone();
                async move {
                    if let (Some(limiter), Ok(chunk)) = (bandwidth_limiter.as_ref(), item.as_ref())
                    {
                        limiter.acquire(chunk.len()).await;
                    }
                    item
                }
            });
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

                let response = state
                    .client()
                    .put(&url)
                    .headers(headers)
                    .body(body)
                    .send()
                    .await
                    .map_err(|error| format!("artifact replication request failed: {error:?}"))?;
                response_span.record("http.response.status_code", response.status().as_u16());
                if response.status().is_server_error() {
                    response_span.record("otel.status_code", "ERROR");
                }
                response
                    .error_for_status()
                    .map(|_| ())
                    .map_err(|error| format!("artifact replication response failed: {error}"))
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
                    .map(|_| ())
                    .map_err(|error| format!("namespace replication response failed: {error}"))
            }
            .instrument(request_span)
            .await
        }
    }
}

#[cfg(test)]
mod tests {
    use axum::{Json, Router, extract::Path as AxumPath, http::StatusCode, routing::get};
    use tokio::net::TcpListener;

    use super::*;
    use crate::{
        artifact::producer::ArtifactProducer,
        failpoints::{FailpointAction, FailpointName},
        http::router,
        test_support::{TestContext, test_context},
        utils::artifact_storage_id,
    };

    fn bucket(prefix: &str, count: u64, hash: &str) -> ManifestBucketDigest {
        ManifestBucketDigest {
            prefix: prefix.to_string(),
            count,
            hash: hash.to_string(),
        }
    }

    #[test]
    fn divergent_prefixes_are_empty_when_digests_match() {
        let local = vec![bucket("00a", 3, "h1"), bucket("0f2", 1, "h2")];
        let peer = local.clone();
        assert!(
            divergent_prefixes(&local, &peer).is_empty(),
            "matching digests must walk zero ranges"
        );
    }

    #[test]
    fn divergent_prefixes_flags_changed_and_peer_only_but_not_local_only() {
        let local = vec![
            bucket("00a", 3, "match"),
            bucket("0f2", 1, "old"),
            bucket("aaa", 5, "local-only"),
        ];
        let peer = vec![
            bucket("00a", 3, "match"),
            bucket("0f2", 1, "new"),
            bucket("bbb", 2, "peer-only"),
        ];
        let mut divergent = divergent_prefixes(&local, &peer);
        divergent.sort();
        assert_eq!(
            divergent,
            vec!["0f2".to_string(), "bbb".to_string()],
            "walk changed and peer-only buckets; ignore matched and local-only"
        );
    }

    #[test]
    fn divergent_prefixes_flags_count_mismatch_with_colliding_hash() {
        let local = vec![bucket("00a", 3, "h")];
        let peer = vec![bucket("00a", 4, "h")];
        assert_eq!(
            divergent_prefixes(&local, &peer),
            vec!["00a".to_string()],
            "count is a discriminator even when the hash matches"
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

    fn bootstrap_test_manifest(
        producer: ArtifactProducer,
        inline: bool,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        size: u64,
        version_ms: u64,
    ) -> ArtifactManifest {
        ArtifactManifest {
            artifact_id: artifact_storage_id(producer, "test-tenant", namespace_id, key),
            producer,
            namespace_id: namespace_id.to_owned(),
            key: key.to_owned(),
            content_type: content_type.to_owned(),
            inline,
            blob_path: None,
            segment_id: None,
            segment_offset: None,
            size,
            version_ms,
            created_at_ms: version_ms,
        }
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
                    artifact_id: local
                        .state
                        .store
                        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                        .await
                        .expect("artifact fetch should succeed")
                        .expect("artifact should exist")
                        .artifact_id,
                    version_ms: local
                        .state
                        .store
                        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                        .await
                        .expect("artifact fetch should succeed")
                        .expect("artifact should exist")
                        .version_ms,
                    inline: false,
                },
            })
            .expect("upsert should enqueue");

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
    async fn bootstrap_respects_local_newer_winner() {
        let remote = test_context(|_| {}).await;
        let remote_manifest = remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"remote-v1",
            )
            .await
            .expect("remote artifact should persist");
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        let local = test_context(|_| {}).await;
        local
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"local-v2",
                remote_manifest.version_ms + 100,
            )
            .await
            .expect("local newer artifact should apply");

        let outcome = bootstrap_artifact_from_peer(&local.state, &remote_url, &remote_manifest)
            .await
            .expect("bootstrap should complete");
        assert_eq!(outcome, ArtifactApplyOutcome::IgnoredStale);

        let manifest = local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should remain");
        let mut reader = local
            .state
            .store
            .open_artifact_reader(&manifest)
            .await
            .expect("artifact reader should open");
        let mut bytes = Vec::new();
        use tokio::io::AsyncReadExt;
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("artifact bytes should read");
        assert_eq!(bytes, b"local-v2");
    }

    #[tokio::test]
    async fn bootstrap_continues_past_a_failing_artifact_and_reports_partial() {
        use axum::{
            body::Body,
            extract::Request,
            middleware::{self, Next},
            response::Response,
        };

        let remote = test_context(|_| {}).await;
        remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "good",
                "application/octet-stream",
                b"good-data",
            )
            .await
            .expect("good artifact should persist");
        let bad = remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "bad",
                "application/octet-stream",
                b"bad-data",
            )
            .await
            .expect("bad artifact should persist");

        // Serve the real bootstrap endpoints, but 500 the "bad" artifact the way
        // a peer that hasn't finished bootstrapping it yet would.
        let poison_path = format!(
            "/_internal/bootstrap/artifacts/{}",
            url_encode(&bad.artifact_id)
        );
        let app = router(remote.state.clone()).layer(middleware::from_fn(
            move |request: Request, next: Next| {
                let poison_path = poison_path.clone();
                async move {
                    if request.uri().path() == poison_path {
                        return Response::builder()
                            .status(StatusCode::INTERNAL_SERVER_ERROR)
                            .body(Body::from("incomplete"))
                            .unwrap();
                    }
                    next.run(request).await
                }
            },
        ));
        let (remote_url, _server) = spawn_server(app).await;

        let local = test_context(|_| {}).await;
        let result =
            bootstrap_manifests_from_peer(&local.state, &remote_url, &AtomicU64::new(0)).await;

        // The peer bootstrap surfaces failure so it gets retried ...
        assert!(
            result.is_err(),
            "a failed artifact must surface as a retryable bootstrap failure"
        );
        // ... but the good artifact was still applied — forward progress, not an
        // abort at the first failure (which is what deadlocks a mutually
        // bootstrapping mesh).
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "good")
                .await
                .expect("good fetch should succeed")
                .is_some(),
            "the good artifact must apply even though another failed"
        );
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "bad")
                .await
                .expect("bad fetch should succeed")
                .is_none(),
            "the failed artifact must not be applied"
        );
    }

    #[tokio::test]
    async fn bootstrap_tombstones_prevent_stale_manifest_resurrection() {
        let stale_manifest = bootstrap_test_manifest(
            ArtifactProducer::Xcode,
            true,
            "ios",
            "cas-1",
            "application/json",
            br#"{"value":"stale"}"#.len() as u64,
            100,
        );
        let tombstones = NamespaceTombstonePage {
            tombstones: vec![crate::store::NamespaceTombstoneRecord {
                namespace_id: "ios".into(),
                version_ms: 200,
            }],
            next_after: None,
        };
        let manifests = ManifestPage {
            manifests: vec![stale_manifest.clone()],
            next_after: None,
        };
        let artifact_payload = br#"{"value":"stale"}"#.to_vec();
        let app = Router::new()
            .route(
                "/_internal/bootstrap/namespace_tombstones",
                get({
                    let tombstones = tombstones.clone();
                    move || {
                        let tombstones = tombstones.clone();
                        async move { Json(tombstones) }
                    }
                }),
            )
            .route(
                "/_internal/bootstrap/manifests",
                get({
                    let manifests = manifests.clone();
                    move || {
                        let manifests = manifests.clone();
                        async move { Json(manifests) }
                    }
                }),
            )
            .route(
                "/_internal/bootstrap/artifacts/{artifact_id}",
                get(move |AxumPath(_artifact_id): AxumPath<String>| {
                    let artifact_payload = artifact_payload.clone();
                    async move { (StatusCode::OK, artifact_payload) }
                }),
            );
        let (remote_url, _server) = spawn_server(app).await;
        let local = test_context(|_| {}).await;

        let stats = bootstrap_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
            .await
            .expect("bootstrap should complete");
        assert_eq!(stats.tombstones_applied, 1);
        assert_eq!(stats.artifacts_applied, 0);
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn bootstrap_stale_manifest_then_tombstone_converges_to_delete() {
        let stale_manifest = bootstrap_test_manifest(
            ArtifactProducer::Xcode,
            true,
            "ios",
            "cas-1",
            "application/json",
            br#"{"value":"stale"}"#.len() as u64,
            100,
        );
        let tombstones = NamespaceTombstonePage {
            tombstones: vec![crate::store::NamespaceTombstoneRecord {
                namespace_id: "ios".into(),
                version_ms: 200,
            }],
            next_after: None,
        };
        let artifact_payload = br#"{"value":"stale"}"#.to_vec();
        let app = Router::new()
            .route(
                "/_internal/bootstrap/namespace_tombstones",
                get({
                    let tombstones = tombstones.clone();
                    move || {
                        let tombstones = tombstones.clone();
                        async move { Json(tombstones) }
                    }
                }),
            )
            .route(
                "/_internal/bootstrap/artifacts/{artifact_id}",
                get(move |AxumPath(_artifact_id): AxumPath<String>| {
                    let artifact_payload = artifact_payload.clone();
                    async move { (StatusCode::OK, artifact_payload) }
                }),
            );
        let (remote_url, _server) = spawn_server(app).await;
        let local = test_context(|_| {}).await;

        let outcome = bootstrap_artifact_from_peer(&local.state, &remote_url, &stale_manifest)
            .await
            .expect("artifact bootstrap should complete");
        assert_eq!(outcome, ArtifactApplyOutcome::Applied);
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
                .await
                .expect("artifact fetch should succeed")
                .is_some()
        );

        let applied =
            bootstrap_namespace_tombstones_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
                .await
                .expect("tombstone bootstrap should complete");
        assert_eq!(applied, 1);
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn bootstrap_fetch_failpoint_prevents_partial_visibility() {
        let remote = test_context(|_| {}).await;
        let remote_manifest = remote
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
            .expect("remote artifact should persist");
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;
        let local = test_context(|_| {}).await;
        local.state.store.failpoints().set_once(
            FailpointName::AfterBootstrapArtifactFetchBeforePersist,
            FailpointAction::Error("bootstrap interrupted".into()),
        );

        let error = bootstrap_artifact_from_peer(&local.state, &remote_url, &remote_manifest)
            .await
            .expect_err("bootstrap should fail before persist");
        assert!(error.contains("bootstrap interrupted"));
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn bootstrap_skips_all_ranges_when_digests_match() {
        let remote = test_context(|_| {}).await;
        let remote_manifest = remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("remote artifact should persist");
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        // Local already holds the identical artifact (same id and version_ms), so
        // the digest exchange must match every bucket.
        let local = test_context(|_| {}).await;
        local
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
                remote_manifest.version_ms,
            )
            .await
            .expect("local applies the identical replicated artifact");

        // Arm the page-walk failpoint: a matching digest must skip every bucket,
        // so no manifest page is ever fetched and this never fires. If the digest
        // path regressed into a full walk, this would error the bootstrap.
        local.state.store.failpoints().set_once(
            FailpointName::AfterBootstrapManifestPageFetchBeforeApply,
            FailpointAction::Error("no range should be walked for an in-sync pair".into()),
        );

        let applied = bootstrap_manifests_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
            .await
            .expect("bootstrap should succeed without walking any range");
        assert_eq!(applied, 0, "an in-sync pair applies nothing");
    }

    #[tokio::test]
    async fn bootstrap_falls_back_to_full_walk_when_peer_lacks_digest_endpoint() {
        use axum::{
            extract::Request,
            middleware::{self, Next},
            response::IntoResponse,
        };

        let remote = test_context(|_| {}).await;
        remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("remote artifact should persist");

        // Model a peer one version behind, before the digest endpoint existed: it
        // 404s the digest so the joining node must fall back to the full walk.
        async fn deny_digest(request: Request, next: Next) -> axum::response::Response {
            if request.uri().path() == "/_internal/bootstrap/digest" {
                return StatusCode::NOT_FOUND.into_response();
            }
            next.run(request).await
        }
        let peer_router = router(remote.state.clone()).layer(middleware::from_fn(deny_digest));
        let (remote_url, _server) = spawn_server(peer_router).await;

        let local = test_context(|_| {}).await;
        let applied = bootstrap_manifests_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
            .await
            .expect("bootstrap should fall back to a full walk");
        assert_eq!(
            applied, 1,
            "the peer's artifact should replicate via the fallback walk"
        );
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
                .await
                .expect("artifact fetch should succeed")
                .is_some()
        );
    }

    #[tokio::test]
    async fn range_digest_reconciles_a_mostly_in_sync_pair_by_walking_only_the_delta() {
        use std::sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        };

        use axum::{
            extract::Request,
            middleware::{self, Next},
            response::IntoResponse,
        };

        // Reproduces the production wedge: a large peer dataset that the joining
        // node already holds almost all of. Prod is ~1.4M artifacts / 4096
        // buckets, ~99% in sync; a thousand here spans many buckets and forces
        // the legacy full walk into several pages while staying fast.
        const TOTAL: usize = 1024;
        const MISSING: usize = 2;

        let remote = test_context(|_| {}).await;
        let mut keys = Vec::with_capacity(TOTAL);
        for i in 0..TOTAL {
            let key = format!("artifact-{i:05}");
            remote
                .state
                .store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    &key,
                    "application/octet-stream",
                    b"payload",
                    100,
                )
                .await
                .expect("remote applies artifact");
            keys.push(key);
        }

        // Build a fresh local that already holds all but the first MISSING keys
        // (identical id + version_ms, exactly as a replicated peer would), i.e.
        // ~99% in sync.
        async fn build_local_holding_all_but_missing(keys: &[String]) -> TestContext {
            let local = test_context(|_| {}).await;
            for key in &keys[MISSING..] {
                local
                    .state
                    .store
                    .apply_replicated_inline_artifact_from_bytes(
                        ArtifactProducer::Xcode,
                        "ios",
                        key,
                        "application/octet-stream",
                        b"payload",
                        100,
                    )
                    .await
                    .expect("local applies artifact");
            }
            local
        }

        // --- New path: peer serves the digest endpoint ---
        let digest_pages = Arc::new(AtomicUsize::new(0));
        let dp = digest_pages.clone();
        let digest_router = router(remote.state.clone()).layer(middleware::from_fn(
            move |request: Request, next: Next| {
                let dp = dp.clone();
                async move {
                    if request.uri().path() == "/_internal/bootstrap/manifests" {
                        dp.fetch_add(1, Ordering::SeqCst);
                    }
                    next.run(request).await
                }
            },
        ));
        let (digest_url, _digest_server) = spawn_server(digest_router).await;

        let local_new = build_local_holding_all_but_missing(&keys).await;
        let applied_new =
            bootstrap_manifests_from_peer(&local_new.state, &digest_url, &AtomicU64::new(0))
                .await
                .expect("digest-path bootstrap converges");
        assert_eq!(applied_new, MISSING as u64, "only the delta is applied");
        for key in &keys[..MISSING] {
            assert!(
                local_new
                    .state
                    .store
                    .fetch_artifact(ArtifactProducer::Xcode, "ios", key)
                    .await
                    .expect("fetch")
                    .is_some(),
                "the missing artifact must be pulled"
            );
        }

        // O(delta) proof, independent of dataset size: the digest matched almost
        // every bucket and only the diverging ones were walked.
        let rendered = local_new.state.metrics.render();
        let bucket_counter = |result: &str| -> u64 {
            rendered
                .lines()
                .find(|line| {
                    line.starts_with("kura_bootstrap_digest_buckets_total")
                        && line.contains(&format!("result=\"{result}\""))
                })
                .and_then(|line| line.rsplit(' ').next())
                .and_then(|value| value.trim().parse::<u64>().ok())
                .unwrap_or(0)
        };
        let matched = bucket_counter("matched");
        let walked = bucket_counter("walked");
        assert!(
            walked >= 1 && walked <= MISSING as u64,
            "walked ~= delta, got {walked}"
        );
        assert!(
            matched >= 100,
            "matched must dwarf walked (skipped ~all buckets), got matched={matched} walked={walked}"
        );
        let digest_page_count = digest_pages.load(Ordering::SeqCst);
        assert!(
            digest_page_count <= MISSING,
            "digest path walks only diverging buckets, got {digest_page_count} pages"
        );

        // --- Old path (A/B control): identical peer, but the digest endpoint
        // 404s so the joining node takes the legacy full walk. Same ~99%-in-sync
        // local, yet it must page the entire keyspace to apply the same delta. ---
        let full_pages = Arc::new(AtomicUsize::new(0));
        let fp = full_pages.clone();
        let fallback_router = router(remote.state.clone()).layer(middleware::from_fn(
            move |request: Request, next: Next| {
                let fp = fp.clone();
                async move {
                    let path = request.uri().path().to_owned();
                    if path == "/_internal/bootstrap/digest" {
                        return StatusCode::NOT_FOUND.into_response();
                    }
                    if path == "/_internal/bootstrap/manifests" {
                        fp.fetch_add(1, Ordering::SeqCst);
                    }
                    next.run(request).await
                }
            },
        ));
        let (fallback_url, _fallback_server) = spawn_server(fallback_router).await;

        let local_old = build_local_holding_all_but_missing(&keys).await;
        let applied_old =
            bootstrap_manifests_from_peer(&local_old.state, &fallback_url, &AtomicU64::new(0))
                .await
                .expect("fallback bootstrap converges");
        assert_eq!(
            applied_old, MISSING as u64,
            "fallback applies the same delta"
        );

        let full_page_count = full_pages.load(Ordering::SeqCst);
        let expected_full_walk = TOTAL.div_ceil(BOOTSTRAP_PAGE_LIMIT);
        assert_eq!(
            full_page_count, expected_full_walk,
            "legacy walk pages the entire keyspace"
        );
        assert!(
            digest_page_count < full_page_count,
            "range digest walks fewer pages than the full walk ({digest_page_count} < {full_page_count}); at prod scale (1.4M) the full walk is ~5652 pages while the digest path stays == delta"
        );
    }

    #[tokio::test]
    async fn bootstrap_completes_a_slow_but_progressing_pull() {
        use axum::{
            extract::Request,
            middleware::{self, Next},
            response::IntoResponse,
        };

        // A dataset whose full pull takes far longer than one watchdog window.
        let remote = test_context(|_| {}).await;
        for i in 0..800 {
            let key = format!("artifact-{i:05}");
            remote
                .state
                .store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    &key,
                    "application/octet-stream",
                    b"payload",
                    100,
                )
                .await
                .expect("remote applies artifact");
        }

        // Peer takes the linear full walk (digest 404s) and delays every manifest
        // page, so wall-clock runtime spans many windows while each step lands
        // well inside one.
        async fn slow_manifests(request: Request, next: Next) -> axum::response::Response {
            let path = request.uri().path().to_owned();
            if path == "/_internal/bootstrap/digest" {
                return StatusCode::NOT_FOUND.into_response();
            }
            if path == "/_internal/bootstrap/manifests" {
                sleep(Duration::from_millis(120)).await;
            }
            next.run(request).await
        }
        let peer = router(remote.state.clone()).layer(middleware::from_fn(slow_manifests));
        let (peer_url, _server) = spawn_server(peer).await;

        // A single wall-clock cap of 300ms — the old behavior — would kill this
        // multi-second pull mid-walk and restart it forever. The no-progress
        // watchdog lets it run to completion because every page and artifact is
        // forward progress.
        let local = test_context(|_| {}).await;
        let stats =
            bootstrap_from_peer_with_watchdog(&local.state, &peer_url, Duration::from_millis(300))
                .await
                .expect("a steadily-progressing bootstrap must complete, not time out");
        assert_eq!(
            stats.artifacts_applied, 800,
            "the whole dataset must be pulled despite the runtime exceeding many windows"
        );
    }

    #[tokio::test]
    async fn bootstrap_is_abandoned_when_it_stops_making_progress() {
        use axum::{
            extract::Request,
            middleware::{self, Next},
            response::IntoResponse,
        };

        let remote = test_context(|_| {}).await;
        remote
            .state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
                100,
            )
            .await
            .expect("remote applies artifact");

        // The peer hangs indefinitely on manifest pages: once the walk reaches
        // manifests the bootstrap makes no further progress.
        async fn hang_manifests(request: Request, next: Next) -> axum::response::Response {
            let path = request.uri().path().to_owned();
            if path == "/_internal/bootstrap/digest" {
                return StatusCode::NOT_FOUND.into_response();
            }
            if path == "/_internal/bootstrap/manifests" {
                sleep(Duration::from_secs(30)).await;
            }
            next.run(request).await
        }
        let peer = router(remote.state.clone()).layer(middleware::from_fn(hang_manifests));
        let (peer_url, _server) = spawn_server(peer).await;

        let local = test_context(|_| {}).await;
        let error =
            bootstrap_from_peer_with_watchdog(&local.state, &peer_url, Duration::from_millis(150))
                .await
                .expect_err("a stalled bootstrap must be abandoned, not hang forever");
        assert!(
            error.contains("made no progress"),
            "unexpected error: {error}"
        );
    }

    #[tokio::test]
    async fn bootstrap_succeeds_when_total_artifacts_exceed_tmp_budget() {
        // A large account whose cached artifacts dwarf the tmp budget must still
        // bootstrap from a single peer: peak tmp staging is bounded by the
        // per-artifact reservation, so the budget is never exhausted regardless
        // of total account size.
        let artifact_bytes = vec![7_u8; 256 * 1024];
        let artifact_count = 24_usize;
        let tmp_budget = (artifact_bytes.len() as u64) * 2;

        let remote = test_context(|_| {}).await;
        for index in 0..artifact_count {
            remote
                .state
                .store
                .persist_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    &format!("artifact-{index}"),
                    "application/octet-stream",
                    &artifact_bytes,
                )
                .await
                .expect("remote artifact should persist");
        }
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        let local = test_context(move |config| {
            config.tmp_dir_max_bytes = tmp_budget;
        })
        .await;
        assert!(
            (artifact_bytes.len() as u64) * (artifact_count as u64) > tmp_budget,
            "test should stage far more than the tmp budget allows at once"
        );

        let stats = bootstrap_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
            .await
            .expect("bootstrap should converge under a fixed tmp budget");
        assert_eq!(stats.artifacts_applied, artifact_count as u64);

        for index in 0..artifact_count {
            let manifest = local
                .state
                .store
                .fetch_artifact(
                    ArtifactProducer::Gradle,
                    "ios",
                    &format!("artifact-{index}"),
                )
                .await
                .expect("artifact fetch should succeed")
                .expect("every bootstrapped artifact should be present");
            assert_eq!(manifest.size, artifact_bytes.len() as u64);
        }

        // The reservation is fully released once bootstrap drains.
        let drained = local
            .state
            .bootstrap_staging_budget
            .reserve(tmp_budget)
            .await;
        drop(drained);
    }

    #[tokio::test]
    async fn concurrent_peer_bootstraps_converge_and_bound_peak_tmp() {
        // Reproduces the production failure mode: many peers bootstrap
        // concurrently into the shared tmp dir while their network fetches are
        // slow, so each holds a partially-written temp file open at the same
        // time. The peer streams every body in small chunks with a delay between
        // them, so absent the reservation all stagers would pass the racy
        // point-in-time capacity check at once and pile far more than the budget
        // into the tmp dir. The reservation bounds how many stage concurrently,
        // so peak tmp usage stays within the budget while every artifact still
        // applies. A watcher samples the on-disk tmp size throughout.
        let peer_count = 8_usize;
        let artifact_len = 256 * 1024_usize;
        let tmp_budget = (artifact_len as u64) * 2;
        let chunk = vec![3_u8; 32 * 1024];
        let chunks_per_artifact = artifact_len / chunk.len();

        let app = Router::new().route(
            "/_internal/bootstrap/artifacts/{artifact_id}",
            get({
                let chunk = chunk.clone();
                move |AxumPath(_artifact_id): AxumPath<String>| {
                    let chunk = chunk.clone();
                    async move {
                        let stream =
                            futures_util::stream::iter(0..chunks_per_artifact).then(move |_| {
                                let chunk = chunk.clone();
                                async move {
                                    sleep(Duration::from_millis(5)).await;
                                    Ok::<_, std::io::Error>(chunk)
                                }
                            });
                        axum::body::Body::from_stream(stream)
                    }
                }
            }),
        );
        let (remote_url, _server) = spawn_server(app).await;

        let local = test_context(move |config| {
            config.tmp_dir_max_bytes = tmp_budget;
        })
        .await;
        let tmp_dir = local.state.config.tmp_dir.clone();

        let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let peak = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
        let watcher = {
            let tmp_dir = tmp_dir.clone();
            let stop = stop.clone();
            let peak = peak.clone();
            tokio::spawn(async move {
                while !stop.load(std::sync::atomic::Ordering::Relaxed) {
                    let staged = crate::utils::directory_size_bytes(&tmp_dir);
                    peak.fetch_max(staged, std::sync::atomic::Ordering::Relaxed);
                    sleep(Duration::from_millis(1)).await;
                }
            })
        };

        let tasks: Vec<_> = (0..peer_count)
            .map(|index| {
                let manifest = bootstrap_test_manifest(
                    ArtifactProducer::Gradle,
                    false,
                    "ios",
                    &format!("artifact-{index}"),
                    "application/octet-stream",
                    artifact_len as u64,
                    100 + index as u64,
                );
                let state = local.state.clone();
                let remote_url = remote_url.clone();
                tokio::spawn(async move {
                    bootstrap_artifact_from_peer(&state, &remote_url, &manifest).await
                })
            })
            .collect();

        for task in tasks {
            let outcome = task
                .await
                .expect("bootstrap task should not panic")
                .expect("concurrent bootstrap staging should stay within the budget");
            assert_eq!(outcome, ArtifactApplyOutcome::Applied);
        }

        stop.store(true, std::sync::atomic::Ordering::Relaxed);
        watcher.await.expect("watcher task should finish");

        let observed_peak = peak.load(std::sync::atomic::Ordering::Relaxed);
        assert!(
            observed_peak <= tmp_budget,
            "peak staged tmp bytes {observed_peak} exceeded budget {tmp_budget}"
        );

        for index in 0..peer_count {
            assert!(
                local
                    .state
                    .store
                    .fetch_artifact(
                        ArtifactProducer::Gradle,
                        "ios",
                        &format!("artifact-{index}")
                    )
                    .await
                    .expect("artifact fetch should succeed")
                    .is_some(),
                "every concurrently bootstrapped artifact should be present"
            );
        }
    }

    #[tokio::test]
    async fn concurrent_cross_peer_bootstrap_fetches_and_writes_each_artifact_once() {
        // A fresh node bootstraps the SAME artifacts from several peers at once:
        // every peer serves an identical manifest page (same ids and versions)
        // and identical bodies, as the near-fully-overlapping mesh does. The
        // per-artifact fetch gate single-flights each key, so exactly one peer
        // downloads each body and writes it once. Two invariants are asserted
        // together: the segment store holds ~1x the dataset (not peer_count x —
        // the production ENOSPC), and the peers serve each artifact body once
        // total (not once per peer — the redundant WAN transfer). A sleep
        // failpoint between the durable append and the metadata commit holds the
        // gate's owner busy so waiters genuinely contend; without the gate they
        // would all fetch, and without the apply lock they would all write.
        use std::collections::HashMap;
        use std::sync::atomic::{AtomicU64, Ordering};

        use crate::failpoints::{FailpointAction, FailpointName};

        let peer_count = 4_usize;
        let artifact_count = 6_usize;
        let artifact_len = 128 * 1024_usize;
        let dataset_bytes = (artifact_count * artifact_len) as u64;

        let mut manifests = Vec::new();
        let mut bodies = HashMap::new();
        for index in 0..artifact_count {
            let manifest = bootstrap_test_manifest(
                ArtifactProducer::Gradle,
                false,
                "ios",
                &format!("artifact-{index}"),
                "application/octet-stream",
                artifact_len as u64,
                100 + index as u64,
            );
            bodies.insert(
                manifest.artifact_id.clone(),
                vec![index as u8; artifact_len],
            );
            manifests.push(manifest);
        }
        let manifest_page = ManifestPage {
            manifests,
            next_after: None,
        };
        let bodies = std::sync::Arc::new(bodies);
        // Shared across every peer router: counts total artifact-body requests so
        // the test can assert the fetch was single-flighted across peers.
        let body_requests = std::sync::Arc::new(AtomicU64::new(0));

        let mut peer_urls = Vec::new();
        let mut servers = Vec::new();
        for _ in 0..peer_count {
            let manifest_page = manifest_page.clone();
            let bodies = bodies.clone();
            let body_requests = body_requests.clone();
            let app = Router::new()
                .route(
                    "/_internal/bootstrap/namespace_tombstones",
                    get(|| async {
                        Json(NamespaceTombstonePage {
                            tombstones: Vec::new(),
                            next_after: None,
                        })
                    }),
                )
                .route(
                    "/_internal/bootstrap/manifests",
                    get(move || {
                        let manifest_page = manifest_page.clone();
                        async move { Json(manifest_page) }
                    }),
                )
                .route(
                    "/_internal/bootstrap/artifacts/{artifact_id}",
                    get(move |AxumPath(artifact_id): AxumPath<String>| {
                        let bodies = bodies.clone();
                        let body_requests = body_requests.clone();
                        async move {
                            body_requests.fetch_add(1, Ordering::Relaxed);
                            match bodies.get(&artifact_id) {
                                Some(body) => (StatusCode::OK, body.clone()),
                                None => (StatusCode::NOT_FOUND, Vec::new()),
                            }
                        }
                    }),
                );
            let (url, server) = spawn_server(app).await;
            peer_urls.push(url);
            servers.push(server);
        }

        let local = test_context(|_| {}).await;
        local.state.store.failpoints().set_always(
            FailpointName::AfterArtifactBytesDurableBeforeMetadata,
            FailpointAction::Sleep(Duration::from_millis(150)),
        );

        let tasks: Vec<_> = peer_urls
            .iter()
            .map(|peer| {
                let state = local.state.clone();
                let peer = peer.clone();
                tokio::spawn(
                    async move { bootstrap_from_peer(&state, &peer, &AtomicU64::new(0)).await },
                )
            })
            .collect();
        for task in tasks {
            task.await
                .expect("bootstrap task should not panic")
                .expect("each concurrent peer bootstrap should converge");
        }

        // Written once: the segment store holds ~1x the dataset, not peer_count x.
        let segments_bytes =
            crate::utils::directory_size_bytes(&local.state.config.data_dir.join("segments"));
        assert!(
            segments_bytes <= dataset_bytes + artifact_len as u64,
            "segment store held {segments_bytes} bytes, expected ~{dataset_bytes} (1x the \
             dataset); cross-peer bootstrap amplified on-disk data"
        );

        // Fetched once: the peers served each body a single time across the whole
        // mesh, not once per peer.
        let observed_requests = body_requests.load(Ordering::Relaxed);
        assert_eq!(
            observed_requests, artifact_count as u64,
            "expected {artifact_count} artifact-body requests (one per key); observed \
             {observed_requests} — the cross-peer fetch was not single-flighted"
        );

        for index in 0..artifact_count {
            assert!(
                local
                    .state
                    .store
                    .fetch_artifact(
                        ArtifactProducer::Gradle,
                        "ios",
                        &format!("artifact-{index}")
                    )
                    .await
                    .expect("artifact fetch should succeed")
                    .is_some(),
                "every concurrently bootstrapped artifact should be present"
            );
        }
    }

    #[tokio::test]
    async fn bootstrap_rejects_body_larger_than_reserved() {
        // An inconsistent peer streams a chunked body larger than its manifest
        // advertised (no Content-Length). The staged file is capped at the
        // reservation, so it is rejected instead of overrunning the tmp budget.
        let declared_len = 64 * 1024_u64;
        let chunk = vec![7_u8; declared_len as usize];
        let app = Router::new().route(
            "/_internal/bootstrap/artifacts/{artifact_id}",
            get({
                let chunk = chunk.clone();
                move |AxumPath(_artifact_id): AxumPath<String>| {
                    let chunk = chunk.clone();
                    async move {
                        let stream = futures_util::stream::iter(0..4).then(move |_| {
                            let chunk = chunk.clone();
                            async move { Ok::<_, std::io::Error>(chunk) }
                        });
                        axum::body::Body::from_stream(stream)
                    }
                }
            }),
        );
        let (remote_url, _server) = spawn_server(app).await;

        let local = test_context(|_config| {}).await;
        let manifest = bootstrap_test_manifest(
            ArtifactProducer::Gradle,
            false,
            "ios",
            "oversized",
            "application/octet-stream",
            declared_len,
            100,
        );

        let error = bootstrap_artifact_from_peer(&local.state, &remote_url, &manifest)
            .await
            .expect_err("a body larger than the manifest must be rejected");
        assert!(
            error.contains("exceeded reserved"),
            "expected a reservation-overflow rejection, got: {error}"
        );
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "oversized")
                .await
                .expect("artifact fetch should succeed")
                .is_none(),
            "the rejected artifact must not be persisted"
        );
    }
}
