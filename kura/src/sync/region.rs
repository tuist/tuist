//! The region link (design §4): one task per remote gateway, run only while
//! this node holds its region's gateway role. A buffered backward pass on
//! start, then ascending origin-filtered forward reads from the per-origin
//! watermark, long-polling when caught up.

use std::{
    sync::{
        Arc,
        atomic::{AtomicU32, Ordering},
    },
    time::Instant,
};

use tokio_util::sync::CancellationToken;
use tracing::{info, warn};

use crate::{
    backfill::{
        pass::{
            BackfillPassOutcome, BackfillPassTuning, PassSource, run_backfill_pass_with_tuning,
        },
        window::{BackfillWindow, compute_window},
    },
    constants::{BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET, MAX_PEER_PAGE_BYTES},
    http::BackfillEntriesPage,
    replication::read_bounded_body,
    state::SharedState,
    sync::coordinator::{LinkPhase, LinkStatusCell, backoff, pass_backoff},
    utils::{BackfillRecordKind, now_ms, url_encode},
};

fn tuning(app: &SharedState, source: PassSource) -> BackfillPassTuning {
    let mut tuning = BackfillPassTuning::from_config(&app.config);
    tuning.source = source;
    tuning.feed_rows = true;
    tuning.bandwidth_shaped = true;
    tuning
}

async fn run_pass(
    app: &SharedState,
    peer: &str,
    cancel: &CancellationToken,
    source: PassSource,
    window: BackfillWindow,
) -> BackfillPassOutcome {
    let guard = app.backfill.claims().register_pass();
    run_backfill_pass_with_tuning(app, peer, window, guard, cancel, tuning(app, source)).await
}

/// One listing page, ascending. `after` is the page cursor of the previous
/// page (the full key); `None` resumes from the watermark.
async fn request_page(
    app: &SharedState,
    peer: &str,
    region: &str,
    from_version_ms: u64,
    after: Option<&str>,
    wait: bool,
) -> Result<BackfillEntriesPage, String> {
    let mut url = format!(
        "{peer}/_internal/backfill/entries?order=asc&from_version_ms={from_version_ms}&origin_region={}&limit={}",
        url_encode(region),
        crate::constants::MAX_PEER_PAGE_ITEMS
    );
    if let Some(after) = after {
        url.push_str("&after=");
        url.push_str(&url_encode(after));
    }
    if wait {
        url.push_str(&format!("&wait={}", app.config.sync_long_poll_secs));
    }
    let response = app
        .client()
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("region listing request failed: {error}"))?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!("region listing answered {status}"));
    }
    let bytes = read_bounded_body(response, MAX_PEER_PAGE_BYTES, "region listing").await?;
    serde_json::from_slice(&bytes).map_err(|error| format!("region listing decode failed: {error}"))
}

/// The watermark to read from: the persisted one, else the highest legacy
/// `backfill/wm/` row among the region's nodes (implementation decision
/// D-4), else nothing.
fn seed_watermark(app: &SharedState, region: &str) -> Result<Option<u64>, String> {
    if let Some(watermark) = app.store.sync_watermark(region)? {
        return Ok(Some(watermark));
    }
    let mut seed = None;
    for view in app.peer_views.load().iter() {
        if view.region == region
            && let Some(legacy) = app.store.backfill_watermark(&view.url)?
        {
            seed = Some(seed.map_or(legacy, |current: u64| current.max(legacy)));
        }
    }
    Ok(seed)
}

/// The buffered backward pass (design §4.4): `min = horizon.max(watermark −
/// buffer)`. On completion the watermark advances to the peer's clock at
/// pass start less the buffer (implementation decision D-12).
async fn backward_pass(
    app: &SharedState,
    peer: &str,
    region: &str,
    cancel: &CancellationToken,
    status: &LinkStatusCell,
) -> Result<(), String> {
    status.update(|status| status.phase = LinkPhase::Bootstrapping);
    let started = Instant::now();
    let probe = request_page(app, peer, region, 0, None, false).await?;
    let peer_now = probe.now;
    if let Some(peer_now) = peer_now {
        let skew = peer_now as i64 - now_ms() as i64;
        app.metrics.set_peer_clock_skew(peer, skew / 1000);
    }
    let watermark = seed_watermark(app, region)?;
    let buffered =
        watermark.map(|watermark| watermark.saturating_sub(app.config.sync_pass_start_buffer_ms));
    let window = compute_window(
        &app.store.backfill_age_ordered_stats(),
        app.store.backfill_capacity_inputs().ring_total_segments,
        app.config.backfill_margin_percent,
        buffered,
        now_ms(),
        &app.metrics,
    );
    info!(
        peer,
        region,
        watermark,
        min_version_ms = window.min_version_ms,
        "region backward pass starting"
    );
    match run_pass(app, peer, cancel, PassSource::PeerIndex, window).await {
        BackfillPassOutcome::Completed { stats, .. } => {
            app.metrics
                .record_region_sync_bytes(region, stats.bytes_applied);
            app.metrics
                .set_region_sync_last_cycle_duration(region, started.elapsed());
        }
        BackfillPassOutcome::Cancelled { .. } => return Err("cancelled".to_owned()),
        BackfillPassOutcome::Failed { error, .. } => {
            return Err(format!("backward pass failed: {error}"));
        }
    }
    if let Some(peer_now) = peer_now {
        app.store
            .advance_sync_watermark(
                region,
                peer_now.saturating_sub(app.config.sync_pass_start_buffer_ms),
            )
            .await?;
    }
    Ok(())
}

pub async fn run(
    app: SharedState,
    peer: String,
    region: String,
    cancel: CancellationToken,
    status: Arc<LinkStatusCell>,
    pass_failures: Arc<AtomicU32>,
) {
    loop {
        let outcome = tokio::select! {
            biased;
            _ = cancel.cancelled() => return,
            outcome = backward_pass(&app, &peer, &region, &cancel, &status) => outcome,
        };
        match outcome {
            Ok(()) => {
                pass_failures.store(0, Ordering::Relaxed);
                status.update(|status| {
                    status.settled = true;
                    status.last_success = Some(Instant::now());
                });
                break;
            }
            Err(error) => {
                if error == "cancelled" {
                    return;
                }
                let failures = pass_failures
                    .fetch_add(1, Ordering::Relaxed)
                    .saturating_add(1);
                app.metrics.record_backfill_pass_event("failed");
                if failures >= BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET {
                    status.update(|status| status.settled = true);
                }
                status.update(|status| status.phase = LinkPhase::Retrying);
                warn!(peer, region, error, "region backward pass failed; retrying");
                tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(pass_backoff(failures)) => {}
                }
            }
        }
    }

    status.update(|status| status.phase = LinkPhase::Forward);
    let mut after: Option<String> = None;
    let mut failures = 0_u32;
    loop {
        if cancel.is_cancelled() {
            return;
        }
        let from_version_ms = match app.store.sync_watermark(&region) {
            Ok(Some(watermark)) => watermark,
            Ok(None) => 0,
            Err(error) => {
                warn!(peer, region, error, "unreadable region watermark");
                0
            }
        };
        let response = tokio::select! {
            biased;
            _ = cancel.cancelled() => return,
            response = request_page(&app, &peer, &region, from_version_ms, after.as_deref(), true) => response,
        };
        let page = match response {
            Ok(page) => page,
            Err(error) => {
                failures = failures.saturating_add(1);
                app.metrics.note_peer_connection_failure();
                status.update(|status| status.phase = LinkPhase::Retrying);
                warn!(peer, region, error, "region forward read failed");
                // Resume from the watermark after a failure: the in-memory
                // page cursor is only valid within a healthy connection.
                after = None;
                tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(backoff(failures)) => {}
                }
                continue;
            }
        };
        failures = 0;
        status.update(|status| {
            status.phase = LinkPhase::Forward;
            status.last_success = Some(Instant::now());
        });
        if let Some(peer_now) = page.now {
            let skew = peer_now as i64 - now_ms() as i64;
            app.metrics.set_peer_clock_skew(&peer, skew / 1000);
        }
        let entries: Vec<_> = page
            .entries
            .iter()
            .filter(|entry| BackfillRecordKind::from_wire_name(&entry.record_kind).is_some())
            .cloned()
            .collect();
        let listed = entries.len() as u64;
        let highest = entries.iter().map(|entry| entry.version_ms).max();
        if !entries.is_empty() {
            let outcome = tokio::select! {
                biased;
                _ = cancel.cancelled() => return,
                outcome = run_pass(&app, &peer, &cancel, PassSource::Entries(entries), BackfillWindow { min_version_ms: None }) => outcome,
            };
            match outcome {
                BackfillPassOutcome::Completed { stats, .. } => {
                    app.metrics.record_region_sync_listed(&region, listed);
                    app.metrics
                        .record_region_sync_bytes(&region, stats.bytes_applied);
                }
                BackfillPassOutcome::Cancelled { .. } => return,
                BackfillPassOutcome::Failed { error, .. } => {
                    warn!(
                        peer,
                        region, error, "region page apply failed; retrying from the watermark"
                    );
                    after = None;
                    failures = failures.saturating_add(1);
                    tokio::select! {
                        biased;
                        _ = cancel.cancelled() => return,
                        _ = tokio::time::sleep(backoff(failures)) => {}
                    }
                    continue;
                }
            }
            if let Some(highest) = highest
                && let Err(error) = app.store.advance_sync_watermark(&region, highest).await
            {
                warn!(
                    peer,
                    region, error, "failed to advance the region watermark"
                );
            }
        }
        // The page cursor only moves when the peer scanned something; a
        // caught-up long-poll answers without one and we keep ours.
        if page.next_after.is_some() {
            after = page.next_after;
        }
    }
}
