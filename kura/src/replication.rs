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
        // Peers we only know through discovery (in-cluster siblings found via
        // DNS, cross-region pods via the account peer Service) are
        // platform-managed like the static seeds: their absence usually means
        // unreachability, not departure, and unlike enrolled peers nothing
        // ever tells them to re-bootstrap. Remember them so outbox pruning
        // never drops their messages.
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
    let Some(epoch) = state.note_bootstrap_started(&peer).await else {
        return;
    };

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
                    state.note_bootstrap_succeeded(&peer, epoch).await;
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
                        let applied = outcome.applied();
                        if applied {
                            // Tick progress as each artifact lands, not once per
                            // page: draining a single 256-manifest page can take
                            // longer than the no-progress window on a slow/cold
                            // link, and batching the bump to page end would let the
                            // watchdog cancel a bootstrap that is in fact applying.
                            progress.fetch_add(1, Ordering::Relaxed);
                        }
                        Ok(applied)
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
                Ok(true) => applied += 1,
                Ok(false) => {}
                Err(_) => failed += 1,
            }
        }

        ensure_cursor_advances(peer, after.as_deref(), &page)?;
        match page.next_after {
            Some(next_after) => after = Some(next_after),
            None => break,
        }
    }

    Ok((applied, failed))
}

/// Reject a peer that returns a stale or non-advancing manifest cursor. Without a
/// total-runtime cap on the bootstrap, a `next_after` that does not move past the
/// cursor we asked with — or a `Some(next_after)` on an empty page — would loop
/// this walk (holding the bootstrap task and its semaphore permit) forever, and
/// the per-page progress tick would keep the no-progress watchdog from ever
/// firing. A well-behaved peer always returns the last artifact_id it served,
/// which is strictly greater than the requested cursor.
fn ensure_cursor_advances(
    peer: &str,
    after: Option<&str>,
    page: &ManifestPage,
) -> Result<(), String> {
    let Some(next_after) = page.next_after.as_deref() else {
        return Ok(());
    };
    let advanced = after.is_none_or(|current| next_after > current);
    if page.manifests.is_empty() || !advanced {
        return Err(format!(
            "bootstrap from {peer} returned a non-advancing manifest cursor {next_after:?}; abandoning this attempt"
        ));
    }
    Ok(())
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
    // The loop runs every few seconds regardless of load; skip the target-set
    // rebuild (readiness lock + clones) when there is nothing to deliver.
    if state.store.next_outbox_message(None)?.is_none() {
        return Ok(());
    }

    let current_targets: BTreeSet<String> = state.replication_targets().await.into_iter().collect();
    // Discovery-only peers (in-cluster siblings, cross-region pods) are
    // treated like the static seeds: never pruned. Their absence usually
    // means a network flap, not departure, and nothing re-bootstraps them
    // afterwards, so dropping their messages would be silent
    // under-replication. The protection is process-scoped (the history is
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
        // which re-bootstraps the full dataset, so the dropped deltas are
        // recovered. An empty target set means the node has no peer view at
        // all (e.g. the control plane is unreachable), not that every peer
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
                        // A metadata-lane message enqueued mid-pass sorts
                        // before the cursor, so without this re-check it
                        // would wait out the rest of a bulk backlog (a cache
                        // populate parks the sibling's fresh action-cache
                        // entries for the ~30 minutes its blobs take to
                        // ship). Jump back only for a target that is not
                        // backed off, so a parked failing backlog does not
                        // get re-scanned after every delivery.
                        if let Some((head_key, head)) = state.store.next_outbox_message(None)?
                            && head_key.as_slice()
                                < crate::store::OUTBOX_BULK_LANE_PREFIX.as_bytes()
                            && after
                                .as_deref()
                                .is_some_and(|cursor| head_key.as_slice() < cursor)
                            && !state
                                .replication_target_backed_off(&head.target, Instant::now())
                                .await
                        {
                            after = None;
                        }
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
mod tests;
