//! The replica link (design §3): one task per same-region pulling peer that
//! snapshots the sibling's feed head, runs a horizon-bounded backward pass,
//! then reads the feed forward with long-polls, applying every page through
//! the backfill pass pipeline and advancing its cursor only when the page
//! is applied whole.

use std::{
    sync::{
        Arc,
        atomic::{AtomicU32, Ordering},
    },
    time::Instant,
};

use reqwest::StatusCode;
use tokio_util::sync::CancellationToken;
use tracing::{info, warn};

use crate::{
    backfill::{
        pass::{
            BackfillPassOutcome, BackfillPassTuning, PassSource, run_backfill_pass_with_tuning,
        },
        window::compute_window,
    },
    constants::BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET,
    http::{
        BackfillEntry, SYNC_GONE_AHEAD, SYNC_GONE_FLOOR, SYNC_GONE_INCARNATION, SyncForwardGone,
        SyncForwardHead, SyncForwardPage,
    },
    replication::read_bounded_body,
    state::SharedState,
    sync::{
        coordinator::{LinkPhase, LinkStatusCell, backoff, pass_backoff},
        feed::{SyncFeedKind, SyncPosition},
    },
    utils::{now_ms, url_encode},
};

const RESPONSE_LIMIT_BYTES: u64 = 32 * 1024 * 1024;

enum Forward {
    Page(SyncForwardPage),
    Gone(SyncForwardGone),
}

/// How long a forward read holds. Capped at the settle window, because the
/// response also carries the frontier this node's serving bound reads
/// (D-24) and a caught-up link learns it no other way: a committed row
/// still returns the instant it lands, so the cap only costs one idle
/// request per window on loopback and keeps the bound within one window of
/// now while the sibling is quiet.
fn forward_wait_secs(app: &SharedState) -> u64 {
    let refresh = app.config.sync_region_settle_ms.div_ceil(1_000).max(1);
    app.config.sync_long_poll_secs.min(refresh)
}

fn forward_url(app: &SharedState, peer: &str, after: Option<SyncPosition>) -> String {
    let mut url = format!(
        "{peer}/_internal/sync/forward?peer={}&region={}",
        url_encode(&app.config.node_url),
        url_encode(&app.config.region)
    );
    if let Some(after) = after {
        url.push_str("&after=");
        url.push_str(&after.encode());
        url.push_str(&format!("&wait={}", forward_wait_secs(app)));
    }
    url
}

async fn request_head(app: &SharedState, peer: &str) -> Result<SyncForwardHead, String> {
    let response = app
        .client()
        .get(forward_url(app, peer, None))
        .send()
        .await
        .map_err(|error| format!("sync head request failed: {error}"))?;
    if !response.status().is_success() {
        return Err(format!("sync head request answered {}", response.status()));
    }
    let bytes = read_bounded_body(response, RESPONSE_LIMIT_BYTES, "sync head").await?;
    serde_json::from_slice(&bytes).map_err(|error| format!("sync head decode failed: {error}"))
}

async fn request_forward(
    app: &SharedState,
    peer: &str,
    after: SyncPosition,
) -> Result<Forward, String> {
    let response = app
        .client()
        .get(forward_url(app, peer, Some(after)))
        .send()
        .await
        .map_err(|error| format!("sync forward request failed: {error}"))?;
    let status = response.status();
    let bytes = read_bounded_body(response, RESPONSE_LIMIT_BYTES, "sync forward").await?;
    if status == StatusCode::GONE {
        return serde_json::from_slice(&bytes)
            .map(Forward::Gone)
            .map_err(|error| format!("sync gone decode failed: {error}"));
    }
    if !status.is_success() {
        return Err(format!("sync forward request answered {status}"));
    }
    serde_json::from_slice(&bytes)
        .map(Forward::Page)
        .map_err(|error| format!("sync forward decode failed: {error}"))
}

fn tuning(app: &SharedState, source: PassSource) -> BackfillPassTuning {
    let mut tuning = BackfillPassTuning::from_config(&app.config);
    tuning.source = source;
    // The sibling link: what it delivers the sibling already holds, so it
    // earns no feed row, and it rides loopback, so the WAN limiter does not
    // apply (design §3.1, §4.8).
    tuning.feed_rows = false;
    tuning.bandwidth_shaped = false;
    tuning
}

/// Runs one pass through the shared claim set; the guard is released when
/// the pass future resolves.
async fn run_pass(
    app: &SharedState,
    peer: &str,
    cancel: &CancellationToken,
    source: PassSource,
    window_min: Option<u64>,
) -> BackfillPassOutcome {
    let window = crate::backfill::window::BackfillWindow {
        min_version_ms: window_min,
    };
    let guard = app.backfill.claims().register_pass();
    run_backfill_pass_with_tuning(app, peer, window, guard, cancel, tuning(app, source)).await
}

/// What a page or snapshot says about the link's frontier: the instant
/// below which nothing more can arrive over it (D-24). A peer that sends
/// none is an older binary; the rows' own arrival stamps stand in, and when
/// there are none, its clock does — which leaves the settle-window exposure
/// D-6 already carried.
fn link_frontier(frontier_ms: u64, last_arrived_at_ms: Option<u64>, peer_now: u64) -> Option<u64> {
    match (frontier_ms, last_arrived_at_ms) {
        (0, Some(arrived_at_ms)) => Some(arrived_at_ms),
        (0, None) => Some(peer_now),
        (frontier_ms, _) => Some(frontier_ms),
    }
}

/// Snapshot the head, run the horizon-bounded backward pass, adopt the
/// watermark map, and take the cursor at the snapshot (design §3.1).
async fn bootstrap(
    app: &SharedState,
    peer: &str,
    cancel: &CancellationToken,
    status: &LinkStatusCell,
) -> Result<(SyncPosition, u64), String> {
    status.update(|status| status.phase = LinkPhase::Bootstrapping);
    let head = request_head(app, peer).await?;
    let incarnation = u64::from_str_radix(&head.incarnation, 16)
        .map_err(|error| format!("sync head incarnation is not hex: {error}"))?;
    let age_ordered_stats = app.store.backfill_age_ordered_stats();
    let ring_total_segments = app.store.backfill_capacity_inputs().ring_total_segments;
    let window = compute_window(
        &age_ordered_stats,
        ring_total_segments,
        app.config.backfill_margin_percent,
        None,
        now_ms(),
        &app.metrics,
    );
    info!(
        peer,
        head = head.head,
        min_version_ms = window.min_version_ms,
        "replica bootstrap: snapshot taken, backward pass starting"
    );
    match run_pass(
        app,
        peer,
        cancel,
        PassSource::PeerIndex,
        window.min_version_ms,
    )
    .await
    {
        BackfillPassOutcome::Completed { .. } => {}
        BackfillPassOutcome::Cancelled { .. } => return Err("cancelled".to_owned()),
        BackfillPassOutcome::Failed { error, .. } => {
            return Err(format!("backward pass failed: {error}"));
        }
    }
    for (region, watermark) in &head.watermarks {
        if region == &app.config.region {
            continue;
        }
        app.store.advance_sync_watermark(region, *watermark).await?;
    }
    let position = SyncPosition {
        incarnation,
        seq: head.head,
    };
    app.store.write_sync_cursor(peer, position)?;
    // The cursor sits at the snapshot, so the snapshot's frontier is this
    // link's: nothing allocated below it on the sibling is still to come.
    let frontier_ms = link_frontier(head.frontier_ms, None, head.now).unwrap_or_default();
    Ok((position, frontier_ms))
}

/// Applies one forward page whole: records through a pass, then watermark
/// advances in commit order (design §4.3). Returns whether every entry
/// resolved, in which case the cursor may advance.
async fn apply_page(
    app: &SharedState,
    peer: &str,
    cancel: &CancellationToken,
    page: &SyncForwardPage,
) -> Result<bool, String> {
    let mut entries = Vec::new();
    let mut watermarks = Vec::new();
    for entry in &page.entries {
        match SyncFeedKind::from_wire_name(&entry.kind) {
            Some(SyncFeedKind::Record(_)) => entries.push(BackfillEntry {
                record_kind: entry.kind.clone(),
                record_id: entry.record_id.clone(),
                version_ms: entry.version_ms,
                size: entry.size,
            }),
            Some(SyncFeedKind::Watermark) => {
                watermarks.push((entry.record_id.clone(), entry.version_ms));
            }
            None => {
                // A newer sibling may write kinds this binary does not know;
                // skipping keeps the link alive across one version skew.
                warn!(peer, kind = entry.kind, "skipping feed row of unknown kind");
            }
        }
    }
    if !entries.is_empty() {
        match run_pass(app, peer, cancel, PassSource::Entries(entries), None).await {
            BackfillPassOutcome::Completed { .. } => {}
            BackfillPassOutcome::Cancelled { .. } => return Err("cancelled".to_owned()),
            BackfillPassOutcome::Failed { error, .. } => {
                warn!(
                    peer,
                    error, "forward page apply failed; the page is retried whole"
                );
                return Ok(false);
            }
        }
    }
    for (region, watermark) in watermarks {
        if region == app.config.region {
            continue;
        }
        app.store.advance_sync_watermark(&region, watermark).await?;
    }
    Ok(true)
}

pub async fn run(
    app: SharedState,
    peer: String,
    cancel: CancellationToken,
    status: Arc<LinkStatusCell>,
    bootstrap_failures: Arc<AtomicU32>,
) {
    let mut request_failures = 0_u32;
    let mut cursor: Option<SyncPosition> = match app.store.sync_cursor(&peer) {
        Ok(cursor) => cursor,
        Err(error) => {
            warn!(peer, error, "unreadable sync cursor; bootstrapping");
            None
        }
    };
    loop {
        if cancel.is_cancelled() {
            return;
        }
        let position = match cursor {
            Some(position) => position,
            None => {
                let outcome = tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return,
                    outcome = bootstrap(&app, &peer, &cancel, &status) => outcome,
                };
                match outcome {
                    Ok((position, frontier_ms)) => {
                        bootstrap_failures.store(0, Ordering::Relaxed);
                        cursor = Some(position);
                        // The cursor sits at the snapshot head, so it is
                        // within one page of the sibling by construction
                        // (design §3.6): settled from here on.
                        status.update(|status| {
                            status.settled = true;
                            status.frontier_ms = frontier_ms;
                        });
                        position
                    }
                    Err(error) => {
                        if error == "cancelled" {
                            return;
                        }
                        let failures = bootstrap_failures
                            .fetch_add(1, Ordering::Relaxed)
                            .saturating_add(1);
                        app.metrics.record_backfill_pass_event("failed");
                        if failures >= BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET {
                            // Ready-but-cold, as the backfill cycle already
                            // allows; retries continue in the background.
                            status.update(|status| status.settled = true);
                        }
                        status.update(|status| status.phase = LinkPhase::Retrying);
                        warn!(peer, error, "replica bootstrap failed; retrying");
                        tokio::select! {
                            biased;
                            _ = cancel.cancelled() => return,
                            _ = tokio::time::sleep(pass_backoff(failures)) => {}
                        }
                        continue;
                    }
                }
            }
        };

        status.update(|status| status.phase = LinkPhase::Forward);
        let response = tokio::select! {
            biased;
            _ = cancel.cancelled() => return,
            response = request_forward(&app, &peer, position) => response,
        };
        match response {
            Ok(Forward::Page(page)) => {
                request_failures = 0;
                let applied = tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return,
                    applied = apply_page(&app, &peer, &cancel, &page) => applied,
                };
                match applied {
                    Ok(true) => {
                        let next = SyncPosition {
                            incarnation: position.incarnation,
                            seq: page.next,
                        };
                        if next != position
                            && let Err(error) = app.store.write_sync_cursor(&peer, next)
                        {
                            warn!(peer, error, "failed to persist the sync cursor");
                        }
                        cursor = Some(next);
                        let lag_seconds = page.entries.last().map_or(0, |entry| {
                            now_ms().saturating_sub(entry.arrived_at_ms) / 1000
                        });
                        let lag_entries = page.head.saturating_sub(page.next);
                        app.metrics
                            .set_sync_forward_cursor_lag(&peer, lag_entries, lag_seconds);
                        // Caught up: nothing below the sibling's frontier is
                        // still to come. Behind: the rows above the cursor
                        // were stamped at or after the last one applied, so
                        // that stamp bounds them (D-24).
                        let frontier_ms = if page.next == page.head {
                            link_frontier(
                                page.frontier_ms,
                                page.entries.last().map(|entry| entry.arrived_at_ms),
                                page.now,
                            )
                        } else {
                            page.entries.last().map(|entry| entry.arrived_at_ms)
                        };
                        status.update(|status| {
                            status.settled = true;
                            status.last_success = Some(Instant::now());
                            status.lag_entries = lag_entries;
                            if let Some(frontier_ms) = frontier_ms {
                                status.frontier_ms = frontier_ms;
                            }
                        });
                    }
                    Ok(false) => {
                        request_failures = request_failures.saturating_add(1);
                        status.update(|status| status.phase = LinkPhase::Retrying);
                        tokio::select! {
                            biased;
                            _ = cancel.cancelled() => return,
                            _ = tokio::time::sleep(backoff(request_failures)) => {}
                        }
                    }
                    Err(error) => {
                        if error == "cancelled" {
                            return;
                        }
                        warn!(peer, error, "forward page apply errored");
                        request_failures = request_failures.saturating_add(1);
                        tokio::select! {
                            biased;
                            _ = cancel.cancelled() => return,
                            _ = tokio::time::sleep(backoff(request_failures)) => {}
                        }
                    }
                }
            }
            Ok(Forward::Gone(gone)) => {
                let reason = match gone.error.as_str() {
                    SYNC_GONE_INCARNATION => "incarnation",
                    SYNC_GONE_AHEAD => "ahead",
                    SYNC_GONE_FLOOR => "floor",
                    _ => "floor",
                };
                app.metrics.record_sync_forward_fell_behind(reason);
                warn!(
                    peer,
                    reason,
                    floor = gone.floor,
                    head = gone.head,
                    "fell off the sibling's feed; re-bootstrapping"
                );
                if let Err(error) = app.store.clear_sync_cursor(&peer) {
                    warn!(peer, error, "failed to clear the sync cursor");
                }
                app.metrics.clear_sync_forward_cursor_lag(&peer);
                cursor = None;
            }
            Err(error) => {
                request_failures = request_failures.saturating_add(1);
                status.update(|status| status.phase = LinkPhase::Retrying);
                app.metrics.note_peer_connection_failure();
                warn!(peer, error, "forward read failed");
                tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(backoff(request_failures)) => {}
                }
            }
        }
    }
}
