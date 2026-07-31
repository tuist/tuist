//! Per-peer backfill pass driver: one pass walks a peer's listing newest →
//! oldest inside its window while a concurrent fetcher composes byte/time
//! bounded bodies batches (one body request in flight per peer), routes
//! oversized entries to the per-artifact endpoint, and applies everything
//! through the unchanged live apply paths (R12). Scheduling — who spawns
//! passes, failure budgets, watermark persistence — is the lifecycle layer's
//! job (Unit 8); a pass only reports a rich [`BackfillPassOutcome`] for it to
//! consume.

use std::sync::{
    Mutex,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;

use reqwest::header::RETRY_AFTER;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    sync::mpsc,
    time::{Instant, sleep, sleep_until},
};
use tokio_util::sync::CancellationToken;

use crate::{
    artifact::producer::ArtifactProducer,
    backfill::{
        claims::{ClaimKey, ListDecision, PassClaimGuard},
        window::{BackfillWindow, capacity_complete},
    },
    config::Config,
    constants::{
        BACKFILL_BATCH_FLUSH_INTERVAL_MS, BACKFILL_BODIES_BATCH_BYTES, BACKFILL_FETCH_QUEUE_TUPLES,
        BACKFILL_RETRY_BACKOFF_BASE_MS, BACKFILL_RETRY_BACKOFF_MAX_MS, MAX_BACKFILL_BODIES_ENTRIES,
        MAX_BOOTSTRAP_PAGE_BYTES, MAX_BOOTSTRAP_PAGE_ITEMS, MAX_INLINE_REPLICATION_BODY_BYTES,
        MAX_REPLICATION_BODY_BYTES,
    },
    failpoints::FailpointName,
    file_cache::FileCachePolicy,
    http::{
        BACKFILL_ERROR_INDEX_BUILDING, BACKFILL_ERROR_PEER_BUSY,
        BACKFILL_ERROR_TMP_BUDGET_EXHAUSTED, BackfillBodiesRequest, BackfillBodyDisposition,
        BackfillBodyFramePrelude, BackfillEntriesPage, BackfillEntry, BackfillUnavailable,
        read_backfill_body_frame_prelude,
    },
    replication::{read_bounded_body, stream_response_to_temp},
    state::SharedState,
    store::StagedArtifactPath,
    utils::{BackfillRecordKind, TempFileCleanup, temp_file_path, url_encode},
};

/// Window applied while reading one full body frame from a bodies-response
/// spool or per-artifact stream; mirrors the bootstrap body-fetch memory
/// window (a reservation window, not the full object size, because a valid
/// artifact may be as large as the container).
const TRANSFER_MEMORY_WINDOW_BYTES: u64 = 16 * 1024 * 1024;

/// Per-entry allowance for frame overhead (header + record id + manifest
/// meta) when sizing the spool reservation of a batch response whose peer
/// declared no Content-Length.
const FRAME_OVERHEAD_ALLOWANCE_BYTES: u64 = 4 * 1024;

/// Ceiling for a typed 503 body read while classifying a peer response.
const UNAVAILABLE_BODY_CEILING_BYTES: u64 = 64 * 1024;

/// Why a completed pass stopped listing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackfillPassEnd {
    /// The cursor descended past the window's `min_version_ms`.
    WindowBound,
    /// The peer's listing ran out before the bound (unbounded window, or a
    /// peer holding nothing older than the bound).
    PeerExhausted,
}

/// Cumulative counters of one pass, returned with every outcome. The
/// lifecycle layer compares `retryable_wait` against its wall-clock cap for
/// the budget-exempt retry classes (index building, not-capable peers,
/// backpressure, peer tmp budget), which retry inside the pass without
/// failing it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct BackfillPassStats {
    pub pages_listed: u64,
    pub tuples_listed: u64,
    pub tuples_claimed: u64,
    pub tuples_waited: u64,
    pub tuples_present: u64,
    pub tuples_capacity_skipped: u64,
    pub bodies_applied: u64,
    pub bodies_absent: u64,
    /// Fetch-individually frames bounced out of a batch by the serving side
    /// (the defensive backstop; up-front routing uses listed sizes).
    pub bodies_rerouted_individual: u64,
    /// Per-artifact endpoint fetches (up-front oversized routing plus
    /// bounced frames).
    pub individual_fetches: u64,
    pub tombstones_applied: u64,
    pub bytes_applied: u64,
    /// Total time slept in budget-exempt retry backoffs.
    pub retryable_wait: Duration,
}

/// Terminal result of one pass.
///
/// Semantics the lifecycle layer must respect:
/// - `Completed` means the listing reached its end AND the pass's drain set
///   fully resolved — safe to advance the peer's watermark (from the wall
///   clock the caller captured at window computation, not anything in here).
/// - `Failed` is a hard error; claims were already released by the pass
///   guard. Budget-exempt retryable classes never surface here — they retry
///   inside the pass — so a `Failed` outcome is always budget-charged;
///   `stats.retryable_wait` still reports how much of the pass was spent in
///   exempt retries.
/// - `Cancelled` is the cooperative token path (peer loss): claims released,
///   no failure-budget charge, no watermark advance.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackfillPassOutcome {
    Completed {
        end: BackfillPassEnd,
        /// The marginal-trade capacity test fired during the pass: the
        /// segmented guarantee narrowed to the newest ring-worth while
        /// non-ring kinds still covered the full window.
        capacity_completed: bool,
        stats: BackfillPassStats,
    },
    Failed {
        error: String,
        stats: BackfillPassStats,
    },
    Cancelled {
        stats: BackfillPassStats,
    },
}

/// Pass knobs. Production passes take these from config and compiled
/// constants via [`BackfillPassTuning::from_config`]; tests shrink them.
#[derive(Clone, Debug)]
pub struct BackfillPassTuning {
    /// Batch byte threshold and up-front oversized cutoff
    /// (`KURA_BACKFILL_BATCH_BYTES`).
    pub batch_bytes: u64,
    pub flush_interval: Duration,
    pub retry_backoff_base: Duration,
    pub retry_backoff_max: Duration,
    pub page_limit: usize,
}

impl BackfillPassTuning {
    pub fn from_config(config: &Config) -> Self {
        Self {
            batch_bytes: config.backfill_batch_bytes,
            flush_interval: Duration::from_millis(BACKFILL_BATCH_FLUSH_INTERVAL_MS),
            retry_backoff_base: Duration::from_millis(BACKFILL_RETRY_BACKOFF_BASE_MS),
            retry_backoff_max: Duration::from_millis(BACKFILL_RETRY_BACKOFF_MAX_MS),
            page_limit: MAX_BOOTSTRAP_PAGE_ITEMS,
        }
    }
}

/// Runs one backfill pass over `peer`. The window and the claim guard come
/// from the caller (the lifecycle layer computes windows and registers passes
/// on the shared claim set); the guard is consumed so its `Drop` — the
/// structural claim release — happens before this future resolves, which is
/// what lets the caller serialize "claim release strictly precedes successor
/// re-claim" by awaiting the pass.
///
/// `cancel` is checked at every await point that can block (page fetches,
/// body requests, backoff sleeps, queue handoffs, per-frame applies).
#[allow(dead_code)] // consumed by the backfill lifecycle (Unit 8)
pub async fn run_backfill_pass(
    state: &SharedState,
    peer: &str,
    window: BackfillWindow,
    guard: PassClaimGuard,
    cancel: &CancellationToken,
) -> BackfillPassOutcome {
    let tuning = BackfillPassTuning::from_config(&state.config);
    run_backfill_pass_with_tuning(state, peer, window, guard, cancel, tuning).await
}

pub async fn run_backfill_pass_with_tuning(
    state: &SharedState,
    peer: &str,
    window: BackfillWindow,
    guard: PassClaimGuard,
    cancel: &CancellationToken,
    tuning: BackfillPassTuning,
) -> BackfillPassOutcome {
    tracing::info!(
        peer,
        min_version_ms = window.min_version_ms,
        "backfill pass started"
    );
    let context = PassContext {
        state,
        peer,
        window,
        guard: &guard,
        cancel,
        tuning: &tuning,
        capacity_fired: AtomicBool::new(false),
        stats: Mutex::new(BackfillPassStats::default()),
        _gauges: BackfillPassGauges::new(state, peer),
    };

    let (queue_tx, queue_rx) = mpsc::channel(BACKFILL_FETCH_QUEUE_TUPLES);
    let result = tokio::try_join!(
        list_entries(&context, queue_tx),
        fetch_bodies(&context, queue_rx),
    );

    let capacity_completed = context.capacity_fired.load(Ordering::Relaxed);
    let stats = context.snapshot_stats();
    match result {
        Ok((end, ())) => {
            tracing::info!(
                peer,
                ?end,
                capacity_completed,
                pages = stats.pages_listed,
                listed = stats.tuples_listed,
                applied = stats.bodies_applied,
                absent = stats.bodies_absent,
                tombstones = stats.tombstones_applied,
                bytes = stats.bytes_applied,
                "backfill pass completed"
            );
            BackfillPassOutcome::Completed {
                end,
                capacity_completed,
                stats,
            }
        }
        Err(PassAbort::Cancelled) => {
            tracing::info!(peer, "backfill pass cancelled");
            BackfillPassOutcome::Cancelled { stats }
        }
        Err(PassAbort::Hard(error)) => {
            tracing::warn!(peer, error, "backfill pass failed");
            BackfillPassOutcome::Failed { error, stats }
        }
    }
}

/// Why a pass's task tree stopped early. `try_join!` propagates the first
/// abort and drops the sibling task, so a hard fetcher failure also stops
/// the listing walk (and vice versa); the guard's `Drop` in the caller
/// releases whatever claims remain either way.
#[derive(Debug)]
enum PassAbort {
    Cancelled,
    Hard(String),
}

struct PassContext<'a> {
    state: &'a SharedState,
    peer: &'a str,
    window: BackfillWindow,
    guard: &'a PassClaimGuard,
    cancel: &'a CancellationToken,
    tuning: &'a BackfillPassTuning,
    capacity_fired: AtomicBool,
    stats: Mutex<BackfillPassStats>,
    _gauges: BackfillPassGauges,
}

impl PassContext<'_> {
    /// Mutates the stats under the lock and refreshes the pass-progress
    /// gauges from the result, so progress is observable while the pass runs
    /// (the 2026-07-16 silence lesson).
    fn update_stats(&self, update: impl FnOnce(&mut BackfillPassStats)) {
        let mut stats = self.stats.lock().expect("backfill pass stats poisoned");
        update(&mut stats);
        let metrics = &self.state.metrics;
        metrics.set_backfill_pass_listed_tuples(self.peer, stats.tuples_listed);
        metrics.set_backfill_pass_resolved_tuples(
            self.peer,
            stats.bodies_applied + stats.bodies_absent + stats.tombstones_applied,
        );
    }

    fn snapshot_stats(&self) -> BackfillPassStats {
        self.stats
            .lock()
            .expect("backfill pass stats poisoned")
            .clone()
    }

    fn capacity_fired(&self) -> bool {
        self.capacity_fired.load(Ordering::Relaxed)
    }

    fn note_body(&self, outcome: &'static str) {
        self.state.metrics.record_backfill_body(outcome);
        self.update_stats(|stats| match outcome {
            "applied" => stats.bodies_applied += 1,
            "absent" => stats.bodies_absent += 1,
            _ => {}
        });
    }
}

/// Runs `future` unless the pass's cancellation token fires first.
async fn cancellable<T>(
    context: &PassContext<'_>,
    future: impl Future<Output = T>,
) -> Result<T, PassAbort> {
    tokio::select! {
        biased;
        _ = context.cancel.cancelled() => Err(PassAbort::Cancelled),
        value = future => Ok(value),
    }
}

/// A claimed tuple handed from the lister to the fetcher. `size` is the
/// listed size when the lister queued it; re-claims arrive sizeless and
/// compose as zero-byte entries — if one is actually oversized the serving
/// side bounces it as a fetch-individually frame (the defensive backstop).
struct QueuedFetch {
    key: ClaimKey,
    size: Option<u64>,
}

// ---- Listing walk ----------------------------------------------------------

async fn list_entries(
    context: &PassContext<'_>,
    queue: mpsc::Sender<QueuedFetch>,
) -> Result<BackfillPassEnd, PassAbort> {
    let mut after: Option<String> = None;
    loop {
        let page = fetch_listing_page(context, after.as_deref()).await?;
        context.state.metrics.record_backfill_listing_page();
        context.update_stats(|stats| stats.pages_listed += 1);
        for entry in &page.entries {
            if context.cancel.is_cancelled() {
                return Err(PassAbort::Cancelled);
            }
            if let Some(min_version_ms) = context.window.min_version_ms
                && entry.version_ms < min_version_ms
            {
                return Ok(BackfillPassEnd::WindowBound);
            }
            let Some(kind) = BackfillRecordKind::from_wire_name(&entry.record_kind) else {
                // A newer peer may list kinds this binary does not know;
                // skipping keeps the walk alive across one version skew.
                tracing::debug!(
                    peer = context.peer,
                    record_kind = entry.record_kind,
                    "skipping backfill entry of unknown kind"
                );
                continue;
            };
            list_entry(context, &queue, kind, entry).await?;
        }
        match page.next_after {
            Some(next) => after = Some(next),
            None => return Ok(BackfillPassEnd::PeerExhausted),
        }
    }
}

async fn list_entry(
    context: &PassContext<'_>,
    queue: &mpsc::Sender<QueuedFetch>,
    kind: BackfillRecordKind,
    entry: &BackfillEntry,
) -> Result<(), PassAbort> {
    context.update_stats(|stats| stats.tuples_listed += 1);

    // Evaluate the marginal trade as the cursor descends. Inputs are re-read
    // per segmented tuple: applies rotate segments underneath the pass.
    if kind == BackfillRecordKind::SegmentArtifact && !context.capacity_fired() {
        let inputs = context.state.store.backfill_capacity_inputs();
        if capacity_complete(
            inputs.segment_count,
            inputs.ring_total_segments,
            inputs.next_evictee_stat_ms,
            entry.version_ms,
        ) {
            // Synchronously strips held segmented claims that are not in an
            // in-flight batch; the fetcher drops the same tuples from its
            // composed batch before dispatching.
            context.guard.mark_capacity_complete();
            context.capacity_fired.store(true, Ordering::Relaxed);
            tracing::info!(
                peer = context.peer,
                cursor_version_ms = entry.version_ms,
                "backfill pass capacity-completed; segmented fetches stop, other kinds continue"
            );
        }
    }
    if context.capacity_fired() && kind == BackfillRecordKind::SegmentArtifact {
        let decision = context.guard.list(ClaimKey {
            kind,
            record_id: entry.record_id.clone(),
            version_ms: entry.version_ms,
        });
        debug_assert_eq!(decision, ListDecision::CapacitySkipped);
        context
            .state
            .metrics
            .record_backfill_listed_tuple("capacity_skipped");
        context.update_stats(|stats| stats.tuples_capacity_skipped += 1);
        return Ok(());
    }

    // Presence pre-check: locally covered tuples are never listed into the
    // claim set — a warm re-walk costs listing pages only.
    let covered = context
        .state
        .store
        .backfill_locally_covered(kind, &entry.record_id, entry.version_ms)
        .map_err(PassAbort::Hard)?;
    if covered {
        context
            .state
            .metrics
            .record_backfill_listed_tuple("present");
        context.update_stats(|stats| stats.tuples_present += 1);
        return Ok(());
    }

    let key = ClaimKey {
        kind,
        record_id: entry.record_id.clone(),
        version_ms: entry.version_ms,
    };
    match context.guard.list(key.clone()) {
        ListDecision::Claimed => {
            context
                .state
                .metrics
                .record_backfill_listed_tuple("claimed");
            context.update_stats(|stats| stats.tuples_claimed += 1);
            if kind == BackfillRecordKind::NamespaceTombstone {
                // Tombstones are metadata-only: applied straight from the
                // listing tuple, no body phase.
                apply_tombstone(context, &key).await
            } else {
                let item = QueuedFetch {
                    key,
                    size: entry.size,
                };
                cancellable(context, queue.send(item))
                    .await?
                    .map_err(|_| PassAbort::Hard("backfill fetch queue closed".to_owned()))
            }
        }
        ListDecision::Waiting => {
            context
                .state
                .metrics
                .record_backfill_listed_tuple("waiting");
            context.update_stats(|stats| stats.tuples_waited += 1);
            Ok(())
        }
        ListDecision::CapacitySkipped => {
            context
                .state
                .metrics
                .record_backfill_listed_tuple("capacity_skipped");
            context.update_stats(|stats| stats.tuples_capacity_skipped += 1);
            Ok(())
        }
    }
}

async fn fetch_listing_page(
    context: &PassContext<'_>,
    after: Option<&str>,
) -> Result<BackfillEntriesPage, PassAbort> {
    let mut attempt = 0_u32;
    loop {
        let mut url = format!(
            "{}/_internal/backfill/entries?limit={}",
            context.peer, context.tuning.page_limit
        );
        if let Some(after) = after {
            url.push_str("&after=");
            url.push_str(&url_encode(after));
        }
        let started = Instant::now();
        let response = cancellable(context, context.state.client().get(&url).send())
            .await?
            .map_err(|error| {
                PassAbort::Hard(format!("backfill entries request failed: {error:?}"))
            })?;
        match classify_backfill_response(response, "backfill entries")
            .await
            .map_err(PassAbort::Hard)?
        {
            RequestDisposition::Success(response) => {
                let bytes =
                    read_bounded_body(response, MAX_BOOTSTRAP_PAGE_BYTES, "backfill entries")
                        .await
                        .map_err(PassAbort::Hard)?;
                let page: BackfillEntriesPage =
                    serde_json::from_slice(&bytes).map_err(|error| {
                        PassAbort::Hard(format!("failed to decode backfill entries page: {error}"))
                    })?;
                context.state.metrics.record_replication(
                    context.peer,
                    "backfill_entries",
                    "ok",
                    started.elapsed(),
                );
                return Ok(page);
            }
            RequestDisposition::Retry {
                class,
                retry_after_ms,
            } => {
                context.state.metrics.record_replication(
                    context.peer,
                    "backfill_entries",
                    class,
                    started.elapsed(),
                );
                retry_backoff(context, attempt, class, retry_after_ms).await?;
                attempt = attempt.saturating_add(1);
            }
        }
    }
}

// ---- Batch composition and fetching ----------------------------------------

#[derive(Default)]
struct BatchState {
    items: Vec<QueuedFetch>,
    bytes: u64,
    deadline: Option<Instant>,
}

async fn fetch_bodies(
    context: &PassContext<'_>,
    mut queue: mpsc::Receiver<QueuedFetch>,
) -> Result<(), PassAbort> {
    let mut batch = BatchState::default();
    let mut listing_done = false;
    loop {
        // Re-claim wins (batch failures elsewhere, absent scoping, holder
        // cancellation) arrive through the guard and are fetched through
        // THIS pass's peer.
        for key in context.guard.take_reclaimed() {
            admit(context, &mut batch, QueuedFetch { key, size: None }).await?;
        }

        let deadline_passed = batch
            .deadline
            .is_some_and(|deadline| Instant::now() >= deadline);
        if !batch.items.is_empty() && (deadline_passed || listing_done) {
            flush_batch(context, &mut batch).await?;
            continue;
        }

        if listing_done && batch.items.is_empty() {
            // Create the wakeup future before checking drain state, or the
            // resolution that empties the drain set can be missed.
            let changed = context.guard.changed();
            if context.guard.is_drained() {
                return Ok(());
            }
            cancellable(context, changed).await?;
            continue;
        }

        let changed = context.guard.changed();
        let flush_deadline = batch
            .deadline
            .unwrap_or_else(|| Instant::now() + Duration::from_secs(3600));
        tokio::select! {
            biased;
            _ = context.cancel.cancelled() => return Err(PassAbort::Cancelled),
            item = queue.recv() => match item {
                Some(item) => admit(context, &mut batch, item).await?,
                None => listing_done = true,
            },
            _ = sleep_until(flush_deadline), if batch.deadline.is_some() => {}
            _ = changed => {}
        }
    }
}

/// Routes one claimed tuple: tombstones apply directly, capacity-stripped
/// segmented claims are dropped (already resolved), oversized entries fetch
/// individually, and everything else composes byte-bounded into the batch.
async fn admit(
    context: &PassContext<'_>,
    batch: &mut BatchState,
    item: QueuedFetch,
) -> Result<(), PassAbort> {
    if item.key.kind == BackfillRecordKind::NamespaceTombstone {
        // Reclaimed tombstone (the lister applies its own claims inline).
        return apply_tombstone(context, &item.key).await;
    }
    if item.key.kind == BackfillRecordKind::SegmentArtifact && context.capacity_fired() {
        // The claim was stripped by mark_capacity_complete and resolved
        // capacity-skipped for this pass; nothing to fetch.
        return Ok(());
    }
    if item
        .size
        .is_some_and(|size| size > context.tuning.batch_bytes)
    {
        return fetch_individual(context, &item.key).await;
    }
    let size = item.size.unwrap_or(0);
    if !batch.items.is_empty() && batch.bytes.saturating_add(size) > context.tuning.batch_bytes {
        flush_batch(context, batch).await?;
    }
    if batch.items.is_empty() {
        batch.deadline = Some(Instant::now() + context.tuning.flush_interval);
    }
    batch.bytes = batch.bytes.saturating_add(size);
    batch.items.push(item);
    if batch.bytes >= context.tuning.batch_bytes || batch.items.len() >= MAX_BACKFILL_BODIES_ENTRIES
    {
        flush_batch(context, batch).await?;
    }
    Ok(())
}

async fn flush_batch(context: &PassContext<'_>, batch: &mut BatchState) -> Result<(), PassAbort> {
    let mut items = std::mem::take(&mut batch.items);
    batch.bytes = 0;
    batch.deadline = None;
    if context.capacity_fired() {
        // Composed-but-undispatched segmented claims were stripped (and
        // resolved for this pass) when capacity completion fired; dispatching
        // them would touch claims this pass no longer holds.
        items.retain(|item| item.key.kind != BackfillRecordKind::SegmentArtifact);
    }
    if items.is_empty() {
        return Ok(());
    }
    // In-flight marking happens before the request leaves: in-flight claims
    // are exempt from capacity stripping (their batch runs to completion).
    for item in &items {
        context.guard.mark_in_flight(&item.key);
    }
    let response = send_bodies_request(context, &items).await?;
    let spool = spool_batch_response(context, &items, response).await?;
    apply_spooled_batch(context, &items, &spool).await
}

async fn send_bodies_request(
    context: &PassContext<'_>,
    items: &[QueuedFetch],
) -> Result<reqwest::Response, PassAbort> {
    let request = BackfillBodiesRequest {
        entries: items
            .iter()
            .map(|item| BackfillEntry {
                record_kind: item.key.kind.as_str().to_owned(),
                record_id: item.key.record_id.clone(),
                version_ms: item.key.version_ms,
                size: None,
            })
            .collect(),
    };
    let body = serde_json::to_vec(&request)
        .map_err(|error| PassAbort::Hard(format!("failed to encode bodies request: {error}")))?;
    let url = format!("{}/_internal/backfill/bodies", context.peer);
    let mut attempt = 0_u32;
    loop {
        let started = Instant::now();
        let response = cancellable(
            context,
            context
                .state
                .client()
                .post(&url)
                .header(reqwest::header::CONTENT_TYPE, "application/json")
                .body(body.clone())
                .send(),
        )
        .await?
        .map_err(|error| PassAbort::Hard(format!("backfill bodies request failed: {error:?}")))?;
        match classify_backfill_response(response, "backfill bodies")
            .await
            .map_err(PassAbort::Hard)?
        {
            RequestDisposition::Success(response) => {
                context.state.metrics.record_replication(
                    context.peer,
                    "backfill_bodies",
                    "ok",
                    started.elapsed(),
                );
                return Ok(response);
            }
            RequestDisposition::Retry {
                class,
                retry_after_ms,
            } => {
                context.state.metrics.record_replication(
                    context.peer,
                    "backfill_bodies",
                    class,
                    started.elapsed(),
                );
                retry_backoff(context, attempt, class, retry_after_ms).await?;
                attempt = attempt.saturating_add(1);
            }
        }
    }
}

struct SpooledResponse {
    path: std::path::PathBuf,
    _cleanup: TempFileCleanup,
}

/// Spools a bodies response to a temp file under the tmp budget before any
/// frame is applied, so applies run against disk, not the socket.
async fn spool_batch_response(
    context: &PassContext<'_>,
    items: &[QueuedFetch],
    response: reqwest::Response,
) -> Result<SpooledResponse, PassAbort> {
    let sanity_limit = BACKFILL_BODIES_BATCH_BYTES
        .saturating_add((items.len() as u64).saturating_mul(FRAME_OVERHEAD_ALLOWANCE_BYTES));
    let limit = match response.content_length() {
        Some(declared) if declared > sanity_limit => {
            return Err(PassAbort::Hard(format!(
                "backfill bodies response declared {declared} bytes, exceeds {sanity_limit}"
            )));
        }
        Some(declared) => declared.max(1),
        None => sanity_limit,
    };
    let state = context.state;
    // The waiting reservation serializes bounded staging like bootstrap; the
    // disk reservation enforces the local tmp ceiling.
    let _staging_reservation =
        cancellable(context, state.bootstrap_staging_budget.reserve(limit)).await?;
    let disk_reservation = state
        .tmp_staging_budget
        .try_reserve(limit)
        .map_err(PassAbort::Hard)?;
    let _memory_reservation = cancellable(
        context,
        state
            .memory
            .reserve_background_transient(limit.clamp(1, TRANSFER_MEMORY_WINDOW_BYTES)),
    )
    .await?
    .map_err(|()| PassAbort::Hard("backfill memory admission closed".to_owned()))?;

    let directory = state.config.tmp_dir.join("backfill");
    state
        .io
        .create_dir_all(&directory)
        .await
        .map_err(PassAbort::Hard)?;
    let path = temp_file_path(&directory, "fetch");
    let cleanup = TempFileCleanup::new(path.clone(), disk_reservation);
    cancellable(
        context,
        stream_response_to_temp(state, response, &path, limit),
    )
    .await?
    .map_err(PassAbort::Hard)?;
    Ok(SpooledResponse {
        path,
        _cleanup: cleanup,
    })
}

/// Iterates the spooled frames in lockstep with the requested tuples (the
/// serving side answers one frame per requested tuple, in order) and applies
/// them. Applies happen under the FRAME's version/kind/meta; claim resolution
/// uses the LISTED key.
async fn apply_spooled_batch(
    context: &PassContext<'_>,
    items: &[QueuedFetch],
    spool: &SpooledResponse,
) -> Result<(), PassAbort> {
    context
        .state
        .store
        .hit_failpoint(FailpointName::AfterBackfillBodiesSpoolBeforeApply)
        .await
        .map_err(PassAbort::Hard)?;
    let file = context
        .state
        .io
        .open_file(&spool.path)
        .await
        .map_err(PassAbort::Hard)?;
    let mut reader = tokio::io::BufReader::new(file);
    for item in items {
        if context.cancel.is_cancelled() {
            return Err(PassAbort::Cancelled);
        }
        let prelude = read_backfill_body_frame_prelude(&mut reader, BACKFILL_BODIES_BATCH_BYTES)
            .await
            .map_err(PassAbort::Hard)?
            .ok_or_else(|| {
                PassAbort::Hard(
                    "backfill bodies response ended before every requested tuple resolved"
                        .to_owned(),
                )
            })?;
        if prelude.record_id != item.key.record_id {
            return Err(PassAbort::Hard(format!(
                "backfill bodies frame for {} arrived out of order (expected {})",
                prelude.record_id, item.key.record_id
            )));
        }
        match prelude.disposition {
            BackfillBodyDisposition::Absent => {
                context.guard.resolve_absent(&item.key);
                context.note_body("absent");
            }
            BackfillBodyDisposition::FetchIndividually => {
                context.update_stats(|stats| stats.bodies_rerouted_individual += 1);
                fetch_individual(context, &item.key).await?;
            }
            BackfillBodyDisposition::Present => {
                match apply_present_frame(context, &prelude, &mut reader).await? {
                    PresentApply::Applied => {
                        context.guard.resolve_applied(&item.key);
                        context
                            .state
                            .metrics
                            .record_backfill_applied_bytes(prelude.body_len);
                        context.update_stats(|stats| {
                            stats.bytes_applied += prelude.body_len;
                        });
                        context.note_body("applied");
                    }
                    PresentApply::SkippedUnusable => {
                        // Unusable through this peer (e.g. an inline body over
                        // the replication bound): per-peer absent lets waiters
                        // try their own peers instead of wedging the pass.
                        context.guard.resolve_absent(&item.key);
                        context.note_body("absent");
                    }
                }
            }
        }
    }
    // A well-formed response carries exactly one frame per requested tuple.
    if read_backfill_body_frame_prelude(&mut reader, BACKFILL_BODIES_BATCH_BYTES)
        .await
        .map_err(PassAbort::Hard)?
        .is_some()
    {
        return Err(PassAbort::Hard(
            "backfill bodies response carried more frames than requested tuples".to_owned(),
        ));
    }
    Ok(())
}

enum PresentApply {
    Applied,
    SkippedUnusable,
}

/// Applies one `Present` frame whose body follows on `reader` through the
/// unchanged live apply paths (R12). Any LWW verdict — applied, equal, stale,
/// tombstoned — counts as a successful resolution: the record is locally
/// converged either way.
async fn apply_present_frame<R>(
    context: &PassContext<'_>,
    prelude: &BackfillBodyFramePrelude,
    reader: &mut R,
) -> Result<PresentApply, PassAbort>
where
    R: tokio::io::AsyncRead + Unpin,
{
    let meta = prelude
        .meta
        .as_ref()
        .ok_or_else(|| PassAbort::Hard("present frame without manifest meta".to_owned()))?;
    let Some(producer) = ArtifactProducer::from_str(&meta.producer) else {
        return Err(PassAbort::Hard(format!(
            "present frame carries unknown producer {}",
            meta.producer
        )));
    };
    let state = context.state;
    match prelude.kind {
        BackfillRecordKind::NamespaceTombstone => Err(PassAbort::Hard(
            "present frame carries a tombstone kind".to_owned(),
        )),
        BackfillRecordKind::InlineArtifact => {
            if prelude.body_len > MAX_INLINE_REPLICATION_BODY_BYTES {
                tracing::warn!(
                    record_id = prelude.record_id,
                    body_len = prelude.body_len,
                    "skipping backfill inline body over the replication bound"
                );
                let mut sink = tokio::io::sink();
                tokio::io::copy(&mut reader.take(prelude.body_len), &mut sink)
                    .await
                    .map_err(|error| {
                        PassAbort::Hard(format!("failed to discard oversized inline body: {error}"))
                    })?;
                return Ok(PresentApply::SkippedUnusable);
            }
            let mut body = vec![0_u8; prelude.body_len as usize];
            reader.read_exact(&mut body).await.map_err(|error| {
                PassAbort::Hard(format!("failed to read backfill inline body: {error}"))
            })?;
            state
                .store
                .apply_replicated_inline_artifact_from_bytes(
                    producer,
                    &meta.namespace_id,
                    &meta.key,
                    &meta.content_type,
                    &body,
                    prelude.version_ms,
                    meta.branch.as_deref(),
                    None,
                )
                .await
                .map_err(PassAbort::Hard)?;
            Ok(PresentApply::Applied)
        }
        BackfillRecordKind::SegmentArtifact => {
            let reservation = state
                .tmp_staging_budget
                .try_reserve(prelude.body_len.max(1))
                .map_err(PassAbort::Hard)?;
            let directory = state.config.tmp_dir.join("backfill");
            state
                .io
                .create_dir_all(&directory)
                .await
                .map_err(PassAbort::Hard)?;
            let path = temp_file_path(&directory, "apply");
            let mut cleanup = TempFileCleanup::new(path.clone(), reservation);
            let mut file = state.io.create_file(&path).await.map_err(PassAbort::Hard)?;
            let copied = tokio::io::copy(&mut reader.take(prelude.body_len), &mut file)
                .await
                .map_err(|error| {
                    PassAbort::Hard(format!("failed to stage backfill body: {error}"))
                })?;
            if copied != prelude.body_len {
                return Err(PassAbort::Hard(format!(
                    "backfill body for {} yielded {copied} bytes, expected {}",
                    prelude.record_id, prelude.body_len
                )));
            }
            file.flush().await.map_err(|error| {
                PassAbort::Hard(format!("failed to flush backfill body: {error}"))
            })?;
            drop(file);
            let result = state
                .store
                .apply_replicated_artifact_from_path(
                    producer,
                    &meta.namespace_id,
                    &meta.key,
                    &meta.content_type,
                    StagedArtifactPath::new(&path, FileCachePolicy::Bounded),
                    prelude.version_ms,
                )
                .await;
            cleanup.remove_and_disarm(&state.io).await;
            result.map_err(PassAbort::Hard)?;
            Ok(PresentApply::Applied)
        }
    }
}

// ---- Individual (oversized) fetch ------------------------------------------

/// Fetches one claimed tuple through the per-artifact endpoint: the up-front
/// route for entries whose listed size exceeds the batch threshold, and the
/// re-route for fetch-individually frames. Runs inline in the fetcher, so it
/// shares the one-request-in-flight bound with batch fetches.
async fn fetch_individual(context: &PassContext<'_>, key: &ClaimKey) -> Result<(), PassAbort> {
    context.guard.mark_in_flight(key);
    context.update_stats(|stats| stats.individual_fetches += 1);
    let url = format!(
        "{}/_internal/backfill/artifacts/{}",
        context.peer,
        url_encode(&key.record_id)
    );
    let mut attempt = 0_u32;
    loop {
        let started = Instant::now();
        let response = cancellable(context, context.state.client().get(&url).send())
            .await?
            .map_err(|error| {
                PassAbort::Hard(format!("backfill artifact request failed: {error:?}"))
            })?;
        // Unlike the listing/bodies routes, a 404 here is the record being
        // gone, not a pre-AB peer: the pass only reaches this endpoint after
        // the same peer served backfill listings.
        if response.status() == reqwest::StatusCode::NOT_FOUND {
            context.state.metrics.record_replication(
                context.peer,
                "backfill_artifact",
                "absent",
                started.elapsed(),
            );
            context.guard.resolve_absent(key);
            context.note_body("absent");
            return Ok(());
        }
        match classify_backfill_response(response, "backfill artifact")
            .await
            .map_err(PassAbort::Hard)?
        {
            RequestDisposition::Success(response) => {
                context.state.metrics.record_replication(
                    context.peer,
                    "backfill_artifact",
                    "ok",
                    started.elapsed(),
                );
                return apply_individual_response(context, key, response).await;
            }
            RequestDisposition::Retry {
                class,
                retry_after_ms,
            } => {
                context.state.metrics.record_replication(
                    context.peer,
                    "backfill_artifact",
                    class,
                    started.elapsed(),
                );
                retry_backoff(context, attempt, class, retry_after_ms).await?;
                attempt = attempt.saturating_add(1);
            }
        }
    }
}

async fn apply_individual_response(
    context: &PassContext<'_>,
    key: &ClaimKey,
    response: reqwest::Response,
) -> Result<(), PassAbort> {
    let sanity_limit = MAX_REPLICATION_BODY_BYTES.saturating_add(FRAME_OVERHEAD_ALLOWANCE_BYTES);
    let limit = match response.content_length() {
        Some(declared) if declared > sanity_limit => {
            return Err(PassAbort::Hard(format!(
                "backfill artifact response declared {declared} bytes, exceeds {sanity_limit}"
            )));
        }
        Some(declared) => declared.max(1),
        None => sanity_limit,
    };
    let state = context.state;
    let _staging_reservation =
        cancellable(context, state.bootstrap_staging_budget.reserve(limit)).await?;
    let disk_reservation = state
        .tmp_staging_budget
        .try_reserve(limit)
        .map_err(PassAbort::Hard)?;
    let _memory_reservation = cancellable(
        context,
        state
            .memory
            .reserve_background_transient(limit.clamp(1, TRANSFER_MEMORY_WINDOW_BYTES)),
    )
    .await?
    .map_err(|()| PassAbort::Hard("backfill memory admission closed".to_owned()))?;

    let directory = state.config.tmp_dir.join("backfill");
    state
        .io
        .create_dir_all(&directory)
        .await
        .map_err(PassAbort::Hard)?;
    let path = temp_file_path(&directory, "artifact");
    let _cleanup = TempFileCleanup::new(path.clone(), disk_reservation);
    cancellable(
        context,
        stream_response_to_temp(state, response, &path, limit),
    )
    .await?
    .map_err(PassAbort::Hard)?;

    let file = state.io.open_file(&path).await.map_err(PassAbort::Hard)?;
    let mut reader = tokio::io::BufReader::new(file);
    let prelude = read_backfill_body_frame_prelude(&mut reader, MAX_REPLICATION_BODY_BYTES)
        .await
        .map_err(PassAbort::Hard)?
        .ok_or_else(|| PassAbort::Hard("empty backfill artifact response".to_owned()))?;
    if prelude.record_id != key.record_id {
        return Err(PassAbort::Hard(format!(
            "backfill artifact response answered for {} (requested {})",
            prelude.record_id, key.record_id
        )));
    }
    match prelude.disposition {
        BackfillBodyDisposition::Absent => {
            context.guard.resolve_absent(key);
            context.note_body("absent");
            Ok(())
        }
        BackfillBodyDisposition::FetchIndividually => Err(PassAbort::Hard(
            "backfill artifact response bounced a fetch-individually frame".to_owned(),
        )),
        BackfillBodyDisposition::Present => {
            match apply_present_frame(context, &prelude, &mut reader).await? {
                PresentApply::Applied => {
                    context.guard.resolve_applied(key);
                    context
                        .state
                        .metrics
                        .record_backfill_applied_bytes(prelude.body_len);
                    context.update_stats(|stats| stats.bytes_applied += prelude.body_len);
                    context.note_body("applied");
                }
                PresentApply::SkippedUnusable => {
                    context.guard.resolve_absent(key);
                    context.note_body("absent");
                }
            }
            Ok(())
        }
    }
}

// ---- Shared helpers --------------------------------------------------------

async fn apply_tombstone(context: &PassContext<'_>, key: &ClaimKey) -> Result<(), PassAbort> {
    context
        .state
        .store
        .apply_replicated_namespace_delete(&key.record_id, key.version_ms)
        .await
        .map_err(PassAbort::Hard)?;
    context.guard.resolve_applied(key);
    context.state.metrics.record_backfill_body("tombstone");
    context.update_stats(|stats| stats.tombstones_applied += 1);
    Ok(())
}

enum RequestDisposition {
    Success(reqwest::Response),
    /// Budget-exempt retryable class: the pass backs off and retries without
    /// failing; the lifecycle layer sees only the accumulated
    /// `retryable_wait` (its wall-clock cap input), never a failure.
    Retry {
        class: &'static str,
        retry_after_ms: u64,
    },
}

async fn classify_backfill_response(
    response: reqwest::Response,
    label: &str,
) -> Result<RequestDisposition, String> {
    let status = response.status();
    if status.is_success() {
        return Ok(RequestDisposition::Success(response));
    }
    let retry_after_ms = response
        .headers()
        .get(RETRY_AFTER)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u64>().ok())
        .map(|seconds| seconds.saturating_mul(1_000));
    if status == reqwest::StatusCode::NOT_FOUND {
        // A peer without the backfill routes (pre-AB, e.g. a self-hosted
        // laggard): the not-capable class, retried without budget charge.
        return Ok(RequestDisposition::Retry {
            class: "not_capable",
            retry_after_ms: 0,
        });
    }
    if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
        return Ok(RequestDisposition::Retry {
            class: "backpressure",
            retry_after_ms: retry_after_ms.unwrap_or(0),
        });
    }
    if status == reqwest::StatusCode::SERVICE_UNAVAILABLE {
        let body = read_bounded_body(response, UNAVAILABLE_BODY_CEILING_BYTES, label)
            .await
            .unwrap_or_default();
        if let Ok(unavailable) = serde_json::from_slice::<BackfillUnavailable>(&body) {
            let class = if unavailable.error == BACKFILL_ERROR_INDEX_BUILDING {
                Some("index_building")
            } else if unavailable.error == BACKFILL_ERROR_PEER_BUSY {
                Some("peer_busy")
            } else if unavailable.error == BACKFILL_ERROR_TMP_BUDGET_EXHAUSTED {
                Some("tmp_budget_exhausted")
            } else if retry_after_ms.is_some() {
                Some("backpressure")
            } else {
                None
            };
            if let Some(class) = class {
                return Ok(RequestDisposition::Retry {
                    class,
                    retry_after_ms: retry_after_ms.unwrap_or(0),
                });
            }
            return Err(format!("{label} unavailable: {}", unavailable.message));
        }
        if retry_after_ms.is_some() {
            return Ok(RequestDisposition::Retry {
                class: "backpressure",
                retry_after_ms: retry_after_ms.unwrap_or(0),
            });
        }
        return Err(format!("{label} failed with status {status}"));
    }
    Err(format!("{label} failed with status {status}"))
}

async fn retry_backoff(
    context: &PassContext<'_>,
    attempt: u32,
    class: &'static str,
    retry_after_ms: u64,
) -> Result<(), PassAbort> {
    let base_ms = context.tuning.retry_backoff_base.as_millis() as u64;
    let max_ms = context.tuning.retry_backoff_max.as_millis() as u64;
    let exponential_ms = base_ms.saturating_mul(1_u64 << attempt.min(4)).min(max_ms);
    let delay = Duration::from_millis(exponential_ms.max(retry_after_ms.min(max_ms)));
    context.state.metrics.record_backfill_retry_backoff(class);
    context.update_stats(|stats| stats.retryable_wait += delay);
    cancellable(context, sleep(delay)).await
}

/// Zeroes the pass-progress gauges when the pass ends on any path (the
/// bootstrap-pass Drop-guard convention): a finished or abandoned pass must
/// not read as a live wedge.
struct BackfillPassGauges {
    metrics: crate::metrics::Metrics,
    peer: String,
}

impl BackfillPassGauges {
    fn new(state: &SharedState, peer: &str) -> Self {
        Self {
            metrics: state.metrics.clone(),
            peer: peer.to_owned(),
        }
    }
}

impl Drop for BackfillPassGauges {
    fn drop(&mut self) {
        self.metrics.clear_backfill_pass_progress(&self.peer);
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering as AtomicOrdering},
    };

    use axum::{
        Router,
        extract::Request,
        middleware::{self, Next},
        response::IntoResponse,
    };
    use reqwest::StatusCode;
    use tokio::net::TcpListener;

    use super::*;
    use crate::{
        artifact::manifest::ArtifactManifest,
        backfill::claims::ClaimSet,
        failpoints::FailpointAction,
        http::router,
        segment::{reference::SegmentReference, state::SegmentState},
        test_support::{TestContext, test_context},
    };

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

    fn tuning() -> BackfillPassTuning {
        BackfillPassTuning {
            batch_bytes: BACKFILL_BODIES_BATCH_BYTES,
            flush_interval: Duration::from_millis(200),
            retry_backoff_base: Duration::from_millis(10),
            retry_backoff_max: Duration::from_millis(40),
            page_limit: MAX_BOOTSTRAP_PAGE_ITEMS,
        }
    }

    fn unbounded_window() -> BackfillWindow {
        BackfillWindow {
            min_version_ms: None,
        }
    }

    async fn run_pass(
        local: &TestContext,
        peer_url: &str,
        tuning: BackfillPassTuning,
    ) -> (BackfillPassOutcome, Arc<ClaimSet>) {
        let claim_set = ClaimSet::new();
        let guard = claim_set.register_pass();
        let cancel = CancellationToken::new();
        let outcome = run_backfill_pass_with_tuning(
            &local.state,
            peer_url,
            unbounded_window(),
            guard,
            &cancel,
            tuning,
        )
        .await;
        (outcome, claim_set)
    }

    async fn seed_segmented(context: &TestContext, key: &str, body: &[u8], version_ms: u64) {
        context
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                key,
                "application/octet-stream",
                body,
                version_ms,
            )
            .await
            .expect("segmented artifact should apply");
    }

    async fn seed_inline(context: &TestContext, key: &str, body: &[u8], version_ms: u64) {
        context
            .state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                key,
                "application/octet-stream",
                body,
                version_ms,
                None,
                None,
            )
            .await
            .expect("inline artifact should apply");
    }

    async fn seed_tombstone(context: &TestContext, namespace_id: &str, version_ms: u64) {
        context
            .state
            .store
            .apply_replicated_namespace_delete(namespace_id, version_ms)
            .await
            .expect("tombstone should apply");
    }

    fn build_index(context: &TestContext) {
        context
            .state
            .store
            .run_backfill_index_build()
            .expect("index build should run");
    }

    async fn fetch_manifest(
        context: &TestContext,
        producer: ArtifactProducer,
        key: &str,
    ) -> Option<ArtifactManifest> {
        context
            .state
            .store
            .fetch_artifact(producer, "ios", key)
            .await
            .expect("artifact fetch should succeed")
    }

    async fn read_body(context: &TestContext, manifest: &ArtifactManifest) -> Vec<u8> {
        let mut reader = context
            .state
            .store
            .open_artifact_reader(manifest)
            .await
            .expect("artifact reader should open");
        let mut bytes = Vec::new();
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("artifact bytes should read");
        bytes
    }

    /// Wraps the peer router counting bodies and per-artifact requests, and
    /// tracking the maximum number of concurrently in-flight bodies requests.
    fn counting_router(
        context: &TestContext,
        bodies: Arc<AtomicUsize>,
        artifacts: Arc<AtomicUsize>,
        max_inflight_bodies: Arc<AtomicUsize>,
    ) -> Router {
        let inflight = Arc::new(AtomicUsize::new(0));
        router(context.state.clone()).layer(middleware::from_fn(
            move |request: Request, next: Next| {
                let bodies = bodies.clone();
                let artifacts = artifacts.clone();
                let inflight = inflight.clone();
                let max_inflight = max_inflight_bodies.clone();
                async move {
                    let path = request.uri().path().to_owned();
                    let is_bodies = path == "/_internal/backfill/bodies";
                    if is_bodies {
                        bodies.fetch_add(1, AtomicOrdering::SeqCst);
                        let now = inflight.fetch_add(1, AtomicOrdering::SeqCst) + 1;
                        max_inflight.fetch_max(now, AtomicOrdering::SeqCst);
                    }
                    if path.starts_with("/_internal/backfill/artifacts/") {
                        artifacts.fetch_add(1, AtomicOrdering::SeqCst);
                    }
                    let response = next.run(request).await;
                    if is_bodies {
                        inflight.fetch_sub(1, AtomicOrdering::SeqCst);
                    }
                    response
                }
            },
        ))
    }

    #[tokio::test]
    async fn cold_requester_converges_and_preserves_origin_versions() {
        let peer = test_context(|_| {}).await;
        seed_segmented(&peer, "seg-a", b"segment-body-a", 1_000).await;
        seed_inline(&peer, "inl-b", b"inline-body-b", 900).await;
        seed_tombstone(&peer, "legacy-ns", 800).await;
        build_index(&peer);
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        let (outcome, claim_set) = run_pass(&local, &peer_url, tuning()).await;

        let BackfillPassOutcome::Completed {
            end,
            capacity_completed,
            stats,
        } = outcome
        else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(end, BackfillPassEnd::PeerExhausted);
        assert!(!capacity_completed);
        assert_eq!(stats.bodies_applied, 2);
        assert_eq!(stats.tombstones_applied, 1);
        assert_eq!(stats.tuples_listed, 3);
        assert!(claim_set.is_empty());

        let segmented = fetch_manifest(&local, ArtifactProducer::Gradle, "seg-a")
            .await
            .expect("segmented artifact should land");
        assert_eq!(segmented.version_ms, 1_000);
        assert_eq!(read_body(&local, &segmented).await, b"segment-body-a");

        let inline = fetch_manifest(&local, ArtifactProducer::Xcode, "inl-b")
            .await
            .expect("inline artifact should land");
        assert_eq!(inline.version_ms, 900);
        assert_eq!(read_body(&local, &inline).await, b"inline-body-b");

        assert!(
            local
                .state
                .store
                .backfill_locally_covered(BackfillRecordKind::NamespaceTombstone, "legacy-ns", 800)
                .expect("tombstone check should succeed"),
            "tombstone should be applied locally"
        );
    }

    #[tokio::test]
    async fn warm_rewalk_transfers_listing_pages_only() {
        let peer = test_context(|_| {}).await;
        seed_segmented(&peer, "seg-a", b"segment-body-a", 1_000).await;
        seed_inline(&peer, "inl-b", b"inline-body-b", 900).await;
        seed_tombstone(&peer, "legacy-ns", 800).await;
        build_index(&peer);
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        let (first, _) = run_pass(&local, &peer_url, tuning()).await;
        assert!(matches!(first, BackfillPassOutcome::Completed { .. }));

        // Second pass against a counting server: the presence pre-check must
        // short-circuit every tuple — listing pages are the only traffic.
        let bodies = Arc::new(AtomicUsize::new(0));
        let artifacts = Arc::new(AtomicUsize::new(0));
        let max_inflight = Arc::new(AtomicUsize::new(0));
        let counted = counting_router(&peer, bodies.clone(), artifacts.clone(), max_inflight);
        let (counted_url, _counted_server) = spawn_server(counted).await;
        let (second, claim_set) = run_pass(&local, &counted_url, tuning()).await;

        let BackfillPassOutcome::Completed { stats, .. } = second else {
            panic!("expected completion, got {second:?}");
        };
        assert_eq!(bodies.load(AtomicOrdering::SeqCst), 0, "zero body requests");
        assert_eq!(artifacts.load(AtomicOrdering::SeqCst), 0);
        assert_eq!(stats.tuples_present, 3);
        assert_eq!(stats.bodies_applied, 0);
        assert_eq!(stats.tombstones_applied, 0);
        assert!(claim_set.is_empty());
    }

    #[tokio::test]
    async fn stale_local_version_is_refetched_and_lww_refreshed() {
        let peer = test_context(|_| {}).await;
        seed_segmented(&peer, "seg-a", b"new-body", 1_000).await;
        build_index(&peer);
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        seed_segmented(&local, "seg-a", b"old-body", 500).await;

        let (outcome, _) = run_pass(&local, &peer_url, tuning()).await;
        let BackfillPassOutcome::Completed { stats, .. } = outcome else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(stats.bodies_applied, 1);
        assert_eq!(stats.tuples_present, 0);

        let manifest = fetch_manifest(&local, ArtifactProducer::Gradle, "seg-a")
            .await
            .expect("artifact should remain");
        assert_eq!(manifest.version_ms, 1_000);
        assert_eq!(read_body(&local, &manifest).await, b"new-body");
    }

    #[tokio::test]
    async fn batch_hard_failure_fails_the_pass_and_releases_claims() {
        let peer = test_context(|_| {}).await;
        seed_inline(&peer, "inl-a", b"inline-body", 900).await;
        build_index(&peer);
        let failing = router(peer.state.clone()).layer(middleware::from_fn(
            |request: Request, next: Next| async move {
                if request.uri().path() == "/_internal/backfill/bodies" {
                    return StatusCode::INTERNAL_SERVER_ERROR.into_response();
                }
                next.run(request).await
            },
        ));
        let (peer_url, _server) = spawn_server(failing).await;

        let local = test_context(|_| {}).await;
        let (outcome, claim_set) = run_pass(&local, &peer_url, tuning()).await;

        let BackfillPassOutcome::Failed { error, .. } = outcome else {
            panic!("expected failure, got {outcome:?}");
        };
        assert!(error.contains("500"), "unexpected error: {error}");
        assert!(claim_set.is_empty(), "guard drop must release all claims");
        assert!(
            fetch_manifest(&local, ArtifactProducer::Xcode, "inl-a")
                .await
                .is_none()
        );
    }

    #[tokio::test]
    async fn absent_bodies_resolve_and_the_pass_completes() {
        let peer = test_context(|_| {}).await;
        seed_inline(&peer, "inl-a", b"inline-body", 500).await;
        build_index(&peer);
        // A dangling index row (build/live race shape): listed, but nothing
        // resolves behind it. The serving side frames it absent (R13).
        let dangling_id = "d".repeat(64);
        peer.state
            .store
            .insert_backfill_index_row_for_testing(
                700,
                BackfillRecordKind::InlineArtifact,
                &dangling_id,
                Some(10),
            )
            .expect("dangling row should insert");
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        let (outcome, claim_set) = run_pass(&local, &peer_url, tuning()).await;

        let BackfillPassOutcome::Completed { stats, .. } = outcome else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(stats.bodies_absent, 1);
        assert_eq!(stats.bodies_applied, 1);
        assert!(claim_set.is_empty());
        assert!(
            fetch_manifest(&local, ArtifactProducer::Xcode, "inl-a")
                .await
                .is_some()
        );
    }

    #[tokio::test]
    async fn oversized_entries_route_to_the_per_artifact_endpoint_up_front() {
        let peer = test_context(|_| {}).await;
        let big_body = vec![0xAB_u8; 4_096];
        seed_segmented(&peer, "big", &big_body, 1_000).await;
        seed_inline(&peer, "small", b"tiny", 900).await;
        build_index(&peer);

        let bodies = Arc::new(AtomicUsize::new(0));
        let artifacts = Arc::new(AtomicUsize::new(0));
        let max_inflight = Arc::new(AtomicUsize::new(0));
        let counted = counting_router(&peer, bodies.clone(), artifacts.clone(), max_inflight);
        let (peer_url, _server) = spawn_server(counted).await;

        let local = test_context(|_| {}).await;
        let mut small_batches = tuning();
        small_batches.batch_bytes = 1_024;
        let (outcome, claim_set) = run_pass(&local, &peer_url, small_batches).await;

        let BackfillPassOutcome::Completed { stats, .. } = outcome else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(artifacts.load(AtomicOrdering::SeqCst), 1);
        assert_eq!(bodies.load(AtomicOrdering::SeqCst), 1);
        assert_eq!(stats.individual_fetches, 1);
        assert_eq!(stats.bodies_applied, 2);
        assert!(claim_set.is_empty());

        let big = fetch_manifest(&local, ArtifactProducer::Gradle, "big")
            .await
            .expect("oversized artifact should land");
        assert_eq!(big.version_ms, 1_000);
        assert_eq!(read_body(&local, &big).await, big_body);
        assert!(
            fetch_manifest(&local, ArtifactProducer::Xcode, "small")
                .await
                .is_some()
        );
    }

    #[tokio::test]
    async fn flush_triggers_on_byte_threshold_with_one_body_request_in_flight() {
        let peer = test_context(|_| {}).await;
        for index in 0..6_u64 {
            seed_inline(&peer, &format!("k{index}"), &[0x42_u8; 40], 1_000 + index).await;
        }
        build_index(&peer);

        let bodies = Arc::new(AtomicUsize::new(0));
        let artifacts = Arc::new(AtomicUsize::new(0));
        let max_inflight = Arc::new(AtomicUsize::new(0));
        let counted = counting_router(
            &peer,
            bodies.clone(),
            artifacts.clone(),
            max_inflight.clone(),
        );
        let (peer_url, _server) = spawn_server(counted).await;

        let local = test_context(|_| {}).await;
        let mut byte_bounded = tuning();
        byte_bounded.batch_bytes = 100;
        // A large interval so the byte threshold is the only flush trigger.
        byte_bounded.flush_interval = Duration::from_secs(10);
        let (outcome, _) = run_pass(&local, &peer_url, byte_bounded).await;

        let BackfillPassOutcome::Completed { stats, .. } = outcome else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(stats.bodies_applied, 6);
        // 40-byte entries against a 100-byte bound compose two per batch.
        assert_eq!(bodies.load(AtomicOrdering::SeqCst), 3);
        assert_eq!(max_inflight.load(AtomicOrdering::SeqCst), 1);
    }

    #[tokio::test]
    async fn flush_triggers_on_time_while_listing_is_still_running() {
        let peer = test_context(|_| {}).await;
        for index in 0..3_u64 {
            seed_inline(&peer, &format!("k{index}"), b"tick", 1_000 + index).await;
        }
        build_index(&peer);

        let bodies = Arc::new(AtomicUsize::new(0));
        let artifacts = Arc::new(AtomicUsize::new(0));
        let max_inflight = Arc::new(AtomicUsize::new(0));
        let counted = counting_router(
            &peer,
            bodies.clone(),
            artifacts.clone(),
            max_inflight.clone(),
        );
        // Slow every listing page so the flush interval elapses between
        // pages; the timer, not the byte bound or listing completion, must
        // dispatch each claimed tuple.
        let slowed = counted.layer(middleware::from_fn(
            |request: Request, next: Next| async move {
                if request.uri().path() == "/_internal/backfill/entries" {
                    sleep(Duration::from_millis(300)).await;
                }
                next.run(request).await
            },
        ));
        let (peer_url, _server) = spawn_server(slowed).await;

        let local = test_context(|_| {}).await;
        let mut timed = tuning();
        timed.page_limit = 1;
        timed.flush_interval = Duration::from_millis(100);
        let (outcome, _) = run_pass(&local, &peer_url, timed).await;

        let BackfillPassOutcome::Completed { stats, .. } = outcome else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(stats.bodies_applied, 3);
        // Each tuple flushed by the timer before the next page arrived.
        assert_eq!(bodies.load(AtomicOrdering::SeqCst), 3);
        assert_eq!(max_inflight.load(AtomicOrdering::SeqCst), 1);
    }

    #[tokio::test]
    async fn capacity_completion_stops_segmented_fetches_and_other_kinds_continue() {
        let peer = test_context(|_| {}).await;
        seed_segmented(&peer, "newer", b"newer-body", 1_000).await;
        seed_segmented(&peer, "older", b"older-body", 400).await;
        seed_inline(&peer, "inl", b"inline-body", 300).await;
        seed_tombstone(&peer, "dead-ns", 250).await;
        build_index(&peer);
        // Slow listing pages (one entry each) with a short flush interval:
        // the newer segmented tuple is dispatched and applied before the
        // cursor reaches the older tuple that turns the marginal trade.
        // Segmented claims still composed when the trade turns are stripped
        // and resolve capacity-skipped by design.
        let slowed = router(peer.state.clone()).layer(middleware::from_fn(
            |request: Request, next: Next| async move {
                if request.uri().path() == "/_internal/backfill/entries" {
                    sleep(Duration::from_millis(300)).await;
                }
                next.run(request).await
            },
        ));
        let (peer_url, _server) = spawn_server(slowed).await;

        // A tiny configured capacity resolves to the legacy 1:2:2 floor of 5
        // segments; fabricate a full ring whose next evictee holds data newer
        // than the older peer entry, so the marginal trade fires mid-pass.
        let local = test_context(|config| {
            config.cas_capacity_bytes = Some(1);
        })
        .await;
        let mut ring = SegmentState::default();
        for (band, id, created_at_ms, stat) in [
            ("old", "evictee", 1, 500_u64),
            ("current", "c1", 2, 600),
            ("current", "c2", 3, 650),
            ("new", "n1", 4, 700),
            ("new", "n2", 5, 750),
        ] {
            let mut reference = SegmentReference::new(id.into(), created_at_ms);
            reference.max_version_ms = Some(stat);
            match band {
                "old" => ring.old.push(reference),
                "current" => ring.current.push(reference),
                _ => ring.new.push(reference),
            }
        }
        local
            .state
            .store
            .install_segment_state_for_testing(ring)
            .await
            .expect("ring state should install");

        let mut paced = tuning();
        paced.page_limit = 1;
        paced.flush_interval = Duration::from_millis(50);
        let (outcome, claim_set) = run_pass(&local, &peer_url, paced).await;

        let BackfillPassOutcome::Completed {
            end,
            capacity_completed,
            stats,
        } = outcome
        else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(end, BackfillPassEnd::PeerExhausted);
        assert!(capacity_completed);
        assert_eq!(stats.tuples_capacity_skipped, 1);
        assert!(claim_set.is_empty());

        // The newer segmented entry (fetched before the trade turned) landed;
        // the older one was capacity-skipped.
        assert!(
            fetch_manifest(&local, ArtifactProducer::Gradle, "newer")
                .await
                .is_some()
        );
        assert!(
            fetch_manifest(&local, ArtifactProducer::Gradle, "older")
                .await
                .is_none()
        );
        // Non-ring kinds continued past capacity completion to the bound.
        assert!(
            fetch_manifest(&local, ArtifactProducer::Xcode, "inl")
                .await
                .is_some()
        );
        assert!(
            local
                .state
                .store
                .backfill_locally_covered(BackfillRecordKind::NamespaceTombstone, "dead-ns", 250)
                .expect("tombstone check should succeed")
        );
    }

    #[tokio::test]
    async fn crash_between_listing_and_apply_replays_without_loss_or_double_apply() {
        let peer = test_context(|_| {}).await;
        seed_segmented(&peer, "seg-a", b"segment-body", 1_000).await;
        seed_inline(&peer, "inl-b", b"inline-body", 900).await;
        build_index(&peer);
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        local.state.store.failpoints().set_once(
            FailpointName::AfterBackfillBodiesSpoolBeforeApply,
            FailpointAction::Error("backfill interrupted".into()),
        );

        let (first, first_set) = run_pass(&local, &peer_url, tuning()).await;
        let BackfillPassOutcome::Failed { error, .. } = first else {
            panic!("expected failure, got {first:?}");
        };
        assert!(error.contains("backfill interrupted"), "{error}");
        assert!(first_set.is_empty(), "claims released on failure");
        assert!(
            fetch_manifest(&local, ArtifactProducer::Gradle, "seg-a")
                .await
                .is_none(),
            "nothing applied before the crash point"
        );

        // Restart shape: a fresh pass re-lists and converges.
        let (second, _) = run_pass(&local, &peer_url, tuning()).await;
        let BackfillPassOutcome::Completed { stats, .. } = second else {
            panic!("expected completion, got {second:?}");
        };
        assert_eq!(stats.bodies_applied, 2);
        let manifest = fetch_manifest(&local, ArtifactProducer::Gradle, "seg-a")
            .await
            .expect("segmented artifact should land");
        assert_eq!(manifest.version_ms, 1_000);

        // A replayed walk transfers nothing and double-applies nothing (LWW
        // absorbs replays; the presence pre-check spares the transfer).
        let (third, _) = run_pass(&local, &peer_url, tuning()).await;
        let BackfillPassOutcome::Completed { stats, .. } = third else {
            panic!("expected completion, got {third:?}");
        };
        assert_eq!(stats.bodies_applied, 0);
        assert_eq!(stats.tuples_present, 2);
    }

    #[tokio::test]
    async fn index_building_peer_is_retried_without_failing_the_pass() {
        let peer = test_context(|_| {}).await;
        seed_inline(&peer, "inl-a", b"inline-body", 900).await;
        // No index build yet: the listing endpoint answers 503 index_building
        // until the delayed build lands.
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;
        let peer_state = peer.state.clone();
        let builder = tokio::spawn(async move {
            sleep(Duration::from_millis(150)).await;
            peer_state
                .store
                .run_backfill_index_build()
                .expect("index build should run");
        });

        let local = test_context(|_| {}).await;
        let (outcome, _) = run_pass(&local, &peer_url, tuning()).await;
        builder.await.expect("builder task should finish");

        let BackfillPassOutcome::Completed { stats, .. } = outcome else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(stats.bodies_applied, 1);
        assert!(stats.retryable_wait > Duration::ZERO);
    }

    #[tokio::test]
    async fn cancellation_yields_a_cancelled_outcome_and_releases_claims() {
        let peer = test_context(|_| {}).await;
        seed_inline(&peer, "inl-a", b"inline-body", 900).await;
        build_index(&peer);
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        let claim_set = ClaimSet::new();
        let guard = claim_set.register_pass();
        let cancel = CancellationToken::new();
        cancel.cancel();
        let outcome = run_backfill_pass_with_tuning(
            &local.state,
            &peer_url,
            unbounded_window(),
            guard,
            &cancel,
            tuning(),
        )
        .await;
        assert!(matches!(outcome, BackfillPassOutcome::Cancelled { .. }));
        assert!(claim_set.is_empty());
    }

    #[tokio::test]
    async fn window_bound_stops_the_listing_walk() {
        let peer = test_context(|_| {}).await;
        seed_inline(&peer, "young", b"young-body", 1_000).await;
        seed_inline(&peer, "old", b"old-body", 400).await;
        build_index(&peer);
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        let claim_set = ClaimSet::new();
        let guard = claim_set.register_pass();
        let cancel = CancellationToken::new();
        let outcome = run_backfill_pass_with_tuning(
            &local.state,
            &peer_url,
            BackfillWindow {
                min_version_ms: Some(500),
            },
            guard,
            &cancel,
            tuning(),
        )
        .await;

        let BackfillPassOutcome::Completed { end, stats, .. } = outcome else {
            panic!("expected completion, got {outcome:?}");
        };
        assert_eq!(end, BackfillPassEnd::WindowBound);
        assert_eq!(stats.bodies_applied, 1);
        assert!(
            fetch_manifest(&local, ArtifactProducer::Xcode, "young")
                .await
                .is_some()
        );
        assert!(
            fetch_manifest(&local, ArtifactProducer::Xcode, "old")
                .await
                .is_none()
        );
    }
}
