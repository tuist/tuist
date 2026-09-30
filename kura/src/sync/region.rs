//! The region link (design §4): one task per remote gateway, run only while
//! this node holds its region's gateway role. A buffered backward pass on
//! start, then ascending origin-filtered forward reads from the per-origin
//! watermark, long-polling when caught up.

use std::{
    sync::{
        Arc,
        atomic::{AtomicU32, Ordering},
    },
    time::{Duration, Instant},
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
    constants::{
        BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET, MAX_PEER_PAGE_BYTES, SYNC_UNSUPPORTED_REPROBE_MS,
    },
    http::BackfillEntriesPage,
    replication::read_bounded_body,
    state::SharedState,
    sync::coordinator::{LinkPhase, LinkStatusCell, PEER_UNSUPPORTED, backoff, pass_backoff},
    utils::{BackfillRecordKind, now_ms, url_encode},
};

fn tuning(app: &SharedState, source: PassSource) -> BackfillPassTuning {
    let mut tuning = BackfillPassTuning::from_config(&app.config);
    tuning.source = source;
    tuning.feed_rows = true;
    tuning.bandwidth_shaped = true;
    tuning
}

fn has_preferred_remote_donor(app: &SharedState, peer: &str) -> bool {
    !app.prefers_peer(peer)
        && app
            .peer_views
            .load()
            .iter()
            .any(|view| view.region != app.config.region && app.prefers_peer(&view.url))
}

async fn wait_for_preferred_donor(
    app: &SharedState,
    peer: &str,
    cancel: &CancellationToken,
    source: &PassSource,
) {
    if matches!(source, PassSource::PeerIndex) && has_preferred_remote_donor(app, peer) {
        tokio::select! {
            _ = cancel.cancelled() => {}
            _ = tokio::time::sleep(Duration::from_millis(200)) => {}
        }
    }
}

async fn run_pass(
    app: &SharedState,
    peer: &str,
    cancel: &CancellationToken,
    source: PassSource,
    window: BackfillWindow,
) -> BackfillPassOutcome {
    wait_for_preferred_donor(app, peer, cancel, &source).await;
    let guard = app.backfill_claims.register_pass();
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
        .peer_request(reqwest::Method::GET, peer, &url)?
        .send()
        .await
        .map_err(|error| format!("region listing request failed: {error}"))?;
    let status = response.status();
    if status == reqwest::StatusCode::NOT_FOUND || status == reqwest::StatusCode::METHOD_NOT_ALLOWED
    {
        return Err(format!("{PEER_UNSUPPORTED}: {status}"));
    }
    if !status.is_success() {
        return Err(format!("region listing answered {status}"));
    }
    let bytes = read_bounded_body(response, MAX_PEER_PAGE_BYTES, "region listing").await?;
    let page: BackfillEntriesPage = serde_json::from_slice(&bytes)
        .map_err(|error| format!("region listing decode failed: {error}"))?;
    // A release that predates pull serves this route too, but ignores
    // `order`, `from_version_ms` and `wait`: it answers the whole index at
    // once, so reading it as a forward listing re-scans the peer in a tight
    // loop. `now` shipped with the ascending read and marks a peer that
    // honours it.
    if page.now.is_none() {
        return Err(format!("{PEER_UNSUPPORTED}: listing carries no clock"));
    }
    Ok(page)
}

/// Replication lag in seconds of origin version time: how far the newest
/// version the remote gateway lists sits above the newest one applied here.
fn lag_seconds(newest_version_ms: u64, applied_through_ms: u64) -> u64 {
    newest_version_ms.saturating_sub(applied_through_ms) / 1000
}

fn record_lag(app: &SharedState, status: &LinkStatusCell, region: &str, lag_seconds: u64) {
    status.update(|status| status.lag_seconds = Some(lag_seconds));
    app.metrics.set_region_sync_lag(region, lag_seconds);
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
) -> Result<Option<u64>, String> {
    status.update(|status| status.phase = LinkPhase::Bootstrapping);
    let started = Instant::now();
    let probe = request_page(app, peer, region, 0, None, false).await?;
    let peer_now = probe.now;
    if let Some(peer_now) = peer_now {
        let skew = peer_now as i64 - now_ms() as i64;
        app.metrics.set_peer_clock_skew(peer, skew / 1000);
    }
    let watermark = seed_watermark(app, region)?;
    if let (Some(newest), Some(watermark)) = (probe.newest_version_ms, watermark) {
        record_lag(app, status, region, lag_seconds(newest, watermark));
    }
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
    // The pass applied everything the peer listed when it started; the
    // watermark sits a buffer below that, which is not lag.
    Ok(peer_now)
}

pub async fn run(
    app: SharedState,
    peer: String,
    region: String,
    cancel: CancellationToken,
    status: Arc<LinkStatusCell>,
    pass_failures: Arc<AtomicU32>,
) {
    let covered_through_ms = loop {
        let outcome = tokio::select! {
            biased;
            _ = cancel.cancelled() => return,
            outcome = backward_pass(&app, &peer, &region, &cancel, &status) => outcome,
        };
        match outcome {
            Ok(covered_through_ms) => {
                pass_failures.store(0, Ordering::Relaxed);
                status.update(|status| {
                    status.settled = true;
                    status.unsupported = false;
                    status.last_success = Some(Instant::now());
                });
                break covered_through_ms.unwrap_or_default();
            }
            Err(error) => {
                if error == "cancelled" {
                    return;
                }
                if error.starts_with(PEER_UNSUPPORTED) {
                    let first = status.snapshot();
                    status.update(|status| {
                        status.settled = true;
                        status.unsupported = true;
                        status.phase = LinkPhase::Retrying;
                    });
                    if !first.unsupported {
                        app.metrics.record_backfill_pass_event("unsupported");
                        warn!(
                            peer,
                            region,
                            error,
                            "remote gateway runs a release that predates pull; its writes arrive through the push receivers until it is upgraded"
                        );
                    }
                    tokio::select! {
                        biased;
                        _ = cancel.cancelled() => return,
                        _ = tokio::time::sleep(Duration::from_millis(SYNC_UNSUPPORTED_REPROBE_MS)) => {}
                    }
                    continue;
                }
                status.update(|status| status.unsupported = false);
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
    };

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
            Err(error) if error.starts_with(PEER_UNSUPPORTED) => {
                let first = status.snapshot();
                status.update(|status| {
                    status.unsupported = true;
                    status.phase = LinkPhase::Retrying;
                });
                if !first.unsupported {
                    app.metrics.record_backfill_pass_event("unsupported");
                    warn!(
                        peer,
                        region,
                        error,
                        "remote gateway runs a release that predates pull; its writes arrive through the push receivers until it is upgraded"
                    );
                }
                after = None;
                tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(Duration::from_millis(SYNC_UNSUPPORTED_REPROBE_MS)) => {}
                }
                continue;
            }
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
            status.unsupported = false;
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
        let applied = from_version_ms
            .max(highest.unwrap_or_default())
            .max(covered_through_ms);
        match page.newest_version_ms {
            Some(newest) => record_lag(&app, &status, &region, lag_seconds(newest, applied)),
            // An older source reports nothing; a caught-up page is all it
            // can tell.
            None if page.entries.is_empty() && page.next_after.is_none() => {
                record_lag(&app, &status, &region, 0);
            }
            None => {}
        }
        // The page cursor only moves when the peer scanned something; a
        // caught-up long-poll answers without one and we keep ours.
        if page.next_after.is_some() {
            after = page.next_after;
        }
    }
}

#[cfg(test)]
mod topology_tests {
    use super::*;
    use crate::{peer_topology::PeerTopology, sync::roles::PeerView, test_support::test_context};

    #[tokio::test]
    async fn only_backward_passes_yield_to_healthy_remote_private_donors() {
        let own = PeerTopology {
            provider: "ovh".into(),
            private_network: Some("verified".into()),
            private_url: Some("https://private.example:7443".into()),
        };
        let ctx = test_context(|config| {
            config.region = "local".into();
            config.peer_topology = Some(own.clone());
        })
        .await;
        tokio::time::pause();
        let preferred = "https://preferred.example:7443";
        let other = "https://cross-provider.example:7443";
        let cancel = CancellationToken::new();
        for (region, healthy, source, target, expected_ms) in [
            ("remote", true, PassSource::PeerIndex, other, 200),
            ("remote", true, PassSource::Entries(vec![]), other, 0),
            ("local", true, PassSource::PeerIndex, other, 0),
            ("remote", false, PassSource::PeerIndex, other, 0),
            ("remote", true, PassSource::PeerIndex, preferred, 0),
        ] {
            ctx.state.apply_peer_views(vec![PeerView {
                url: preferred.into(),
                region: region.into(),
                topology: Some(own.clone()),
                private_healthy: healthy,
                serving: true,
                draining: false,
            }]);
            let start = tokio::time::Instant::now();
            wait_for_preferred_donor(&ctx.state, target, &cancel, &source).await;
            if expected_ms == 0 {
                assert_eq!(start.elapsed(), Duration::ZERO);
            } else {
                // Tokio rounds timer deadlines up to its next millisecond tick.
                assert!(
                    (Duration::from_millis(200)..=Duration::from_millis(201))
                        .contains(&start.elapsed())
                );
            }
        }
        cancel.cancel();
        let start = tokio::time::Instant::now();
        wait_for_preferred_donor(&ctx.state, other, &cancel, &PassSource::PeerIndex).await;
        assert_eq!(start.elapsed(), Duration::ZERO);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lag_is_zero_at_or_past_the_newest_version() {
        assert_eq!(lag_seconds(10_000, 10_000), 0);
        assert_eq!(lag_seconds(10_000, 20_000), 0);
        assert_eq!(lag_seconds(310_000, 10_000), 300);
    }
}
