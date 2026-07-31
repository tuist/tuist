//! Pure window and completion logic for backfill passes: the age-based
//! horizon (R4), the per-peer watermark term (R5/R7), and the marginal-trade
//! capacity completion test (R6). Everything here takes plain inputs —
//! age-ordered segment stats, watermark values, clocks — so it unit-tests
//! without a store or network; `SegmentState::age_ordered_references` /
//! `next_evictee` produce the segment views.

use crate::{constants::BACKFILL_WATERMARK_SKEW_ALLOWANCE_MS, metrics::Metrics};

/// Min-age bound of one backfill pass. Entries with `version_ms` at or above
/// `min_version_ms` are inside the window; `None` means the window is
/// unbounded and extends to the peer's oldest entry (cold node).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BackfillWindow {
    pub min_version_ms: Option<u64>,
}

/// Computes the window bound for a pass (R4/R5) from the ring's age-ordered
/// stats and the per-peer watermark: the horizon carries the margin's share
/// of the ring's time span as structural slack, and a completed pass's
/// watermark shallowes later windows over the same peer, so a re-join
/// re-walks only the slack rather than history. Also exports the horizon
/// age-span gauge, so window computation is the single call a pass driver
/// needs.
pub fn compute_window(
    age_ordered_stats_ms: &[u64],
    ring_total_segments: usize,
    margin_percent: u64,
    peer_watermark_ms: Option<u64>,
    now_ms: u64,
    metrics: &Metrics,
) -> BackfillWindow {
    let horizon = horizon_version_ms(age_ordered_stats_ms, ring_total_segments, margin_percent);
    if let Some(horizon) = horizon {
        metrics.set_backfill_horizon_age_ms(now_ms.saturating_sub(horizon));
    }
    BackfillWindow {
        min_version_ms: horizon.max(peer_watermark_ms),
    }
}

/// The age-based horizon (R4): with segments ordered by their effective max
/// stat — data age, not ring position — the horizon is the stat of the
/// segment at the margin boundary, i.e. the oldest segment inside the newest
/// `margin_percent` of the ring (margin 40%, ring of 100 → the segment at
/// age-order position 60). `None` on an empty ring: a cold node's window is
/// unbounded.
///
/// The horizon is a ring rule, so it only engages once the ring holds its
/// desired total: below that count admitting older entries forces no
/// eviction, and a partially-filled ring's stats describe only the newest
/// data — bounding by them would permanently skip anything older. The
/// restart-mid-backfill shape makes that concrete: the interrupted walk
/// leaves one segment holding the newest bodies, and a horizon computed from
/// it would exclude the entire unapplied (older, still recent) tail, turning
/// a restart into permanent data loss instead of a bounded re-walk.
///
/// Pre-upgrade references fall back to `created_at_ms`, which overstates
/// recency for segments populated by the legacy hash-order bootstrap; on such
/// rings the horizon is conservative — shallower — until the ring turns over.
pub fn horizon_version_ms(
    age_ordered_stats_ms: &[u64],
    ring_total_segments: usize,
    margin_percent: u64,
) -> Option<u64> {
    if age_ordered_stats_ms.is_empty() || age_ordered_stats_ms.len() < ring_total_segments {
        return None;
    }
    let count = age_ordered_stats_ms.len();
    let margin_segments = count * margin_percent as usize / 100;
    // A margin that floors to zero segments carries no structural slack: the
    // boundary clamps to the newest segment's stat.
    let boundary = (count - margin_segments).min(count - 1);
    Some(age_ordered_stats_ms[boundary])
}

/// The watermark update on pass completion (R7):
/// `max(existing, pass start − skew allowance)`, where the pass start point
/// is the requester's wall clock at window computation time. The skew
/// allowance gives the watermark term the same kind of slack the horizon
/// term has — a writer whose clock runs behind the requester's can stamp
/// entries below an exact start-point watermark. The `max` guard keeps the
/// watermark monotonic if an older pass's completion lands after a newer
/// one's. Passes over a peer are serialized today, so that interleaving
/// cannot currently occur; the guard is retained as defense-in-depth (one
/// comparison, protects against future lifecycle changes) — do not simplify
/// it away.
pub fn advance_watermark(existing_watermark_ms: Option<u64>, pass_start_wallclock_ms: u64) -> u64 {
    let candidate = pass_start_wallclock_ms.saturating_sub(BACKFILL_WATERMARK_SKEW_ALLOWANCE_MS);
    existing_watermark_ms.map_or(candidate, |existing| existing.max(candidate))
}

/// The marginal-trade capacity test (R6), for segmented-artifact retrieval
/// only: once the ring is full, keep fetching only while what the cursor
/// gains is newer than what the rotation it forces would destroy. When the
/// next evictee's stat is at or equal to the cursor the trade is losing or
/// neutral, so the pass capacity-completes (equality completes: the recorded
/// max can only overstate an evictee's live content under promotion, so the
/// test errs toward completing early, and promoted entries already survive
/// in the head segment). On an age-inverted cold ring the evictee holds
/// previously fetched — newer — data, so this fires the moment the ring
/// fills, retaining the newest ring-worth; on a warm ordered ring it fires
/// when the cursor descends below the oldest retained stat.
///
/// Mixed-depth capacity churn is accepted: two concurrent passes at
/// different cursor depths can partially evict each other's just-applied
/// segments at the capacity boundary, but each pass individually honors the
/// marginal trade, so the ring converges to the newest ring-worth of
/// segmented data.
pub fn capacity_complete(
    segment_count: usize,
    ring_total_segments: usize,
    next_evictee_stat_ms: Option<u64>,
    cursor_version_ms: u64,
) -> bool {
    if segment_count < ring_total_segments {
        return false;
    }
    next_evictee_stat_ms.is_some_and(|evictee_stat| evictee_stat >= cursor_version_ms)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::segment::{reference::SegmentReference, state::SegmentState};

    fn test_metrics() -> Metrics {
        Metrics::new("test-region".into(), "test-tenant".into())
    }

    fn next_random(seed: &mut u64) -> u64 {
        *seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        *seed >> 33
    }

    fn shuffled(mut values: Vec<u64>, seed: &mut u64) -> Vec<u64> {
        for index in (1..values.len()).rev() {
            let other = (next_random(seed) % (index as u64 + 1)) as usize;
            values.swap(index, other);
        }
        values
    }

    fn age_ordered_stats(state: &SegmentState) -> Vec<u64> {
        state
            .age_ordered_references()
            .iter()
            .map(|reference| reference.effective_max_version_ms())
            .collect()
    }

    #[test]
    fn warm_ordered_ring_horizon_matches_the_ring_position_answer() {
        // Parity claim from the origin design: on a warm ring, where ring
        // position and data age agree, the age-based horizon is identical to
        // the ring-position percentile.
        for count in [1usize, 2, 5, 7, 40, 100] {
            for margin_percent in [1u64, 20, 40, 55, 100] {
                let stats: Vec<u64> = (0..count as u64).map(|index| 1_000 + index).collect();
                let margin_segments = count * margin_percent as usize / 100;
                let ring_position_answer = stats[(count - margin_segments).min(count - 1)];
                assert_eq!(
                    horizon_version_ms(&stats, count, margin_percent),
                    Some(ring_position_answer),
                    "count {count} margin {margin_percent}"
                );
            }
        }
    }

    #[test]
    fn origin_r4_example_margin_40_ring_of_100_selects_segment_60() {
        // Origin R4 example, verbatim: "margin 40%, ring of 100 segments →
        // segment 60" (segments ordered 0 = oldest to N = most recent).
        let stats: Vec<u64> = (0..100).map(|segment| 1_000 + segment).collect();
        assert_eq!(horizon_version_ms(&stats, 100, 40), Some(1_060));
    }

    #[test]
    fn origin_r4_default_margin_matches_the_new_band_on_a_warm_1_2_2_ring() {
        // Origin R4: "under the existing 1:2:2 old/current/new ring ratio the
        // default matches the 'new' band on a warm node" — the margin band is
        // the two new segments and the horizon is the older one's stat.
        let stats = vec![10, 20, 30, 40, 50];
        assert_eq!(horizon_version_ms(&stats, 5, 40), Some(40));
    }

    #[test]
    fn backfill_inverted_ring_horizon_tracks_data_age_not_ring_position() {
        let mut state = SegmentState::default();
        // Ring position s1…s5, but the data ages are scrambled the way a
        // newest-first backfill scrambles them.
        for (id, created_at_ms, max_version_ms) in [
            ("s1", 1, Some(900)),
            ("s2", 2, Some(300)),
            ("s3", 3, Some(700)),
            ("s4", 4, Some(100)),
            ("s5", 5, Some(500)),
        ] {
            let mut reference = SegmentReference::new(id.into(), created_at_ms);
            reference.max_version_ms = max_version_ms;
            state.push_new(reference, 1, 2, 2);
        }

        let stats = age_ordered_stats(&state);
        assert_eq!(stats, vec![100, 300, 500, 700, 900]);
        // The margin band is the two age-newest segments (700, 900) and the
        // horizon is its boundary stat; ring-position indexing would have
        // landed on s4's 100 instead.
        assert_eq!(horizon_version_ms(&stats, 5, 40), Some(700));
    }

    #[test]
    fn all_fallback_ring_uses_created_at_as_the_conservative_horizon() {
        // Pre-upgrade ring: no reference carries the seal-time stat, so every
        // segment reads its created_at_ms. For a legacy-bootstrap-populated
        // ring those timestamps are recent while the content spans arbitrary
        // ages — the horizon lands on a recent value, i.e. a shallower
        // (conservative) window.
        let mut state = SegmentState::default();
        for (id, created_at_ms) in [
            ("s1", 5_000),
            ("s2", 5_010),
            ("s3", 5_020),
            ("s4", 5_030),
            ("s5", 5_040),
        ] {
            state.push_new(SegmentReference::new(id.into(), created_at_ms), 1, 2, 2);
        }

        let stats = age_ordered_stats(&state);
        assert_eq!(horizon_version_ms(&stats, 5, 40), Some(5_030));
    }

    #[test]
    fn partially_filled_ring_carries_no_horizon() {
        // The restart-mid-backfill shape: the interrupted newest-first walk
        // left one segment holding only the newest applied bodies. A horizon
        // computed from that segment would exclude the entire unapplied
        // (older) tail and turn the restart into permanent loss; below the
        // desired total the ring has no eviction pressure, so no bound.
        let metrics = test_metrics();
        for count in 1usize..5 {
            let stats: Vec<u64> = (0..count as u64).map(|index| 9_000 + index).collect();
            assert_eq!(horizon_version_ms(&stats, 5, 40), None, "count {count}");
            let window = compute_window(&stats, 5, 40, None, 10_000, &metrics);
            assert_eq!(window.min_version_ms, None, "count {count}");
        }
        // The watermark term still bounds a re-join pass on a partial ring.
        let window = compute_window(&[9_000], 5, 40, Some(8_500), 10_000, &metrics);
        assert_eq!(window.min_version_ms, Some(8_500));
    }

    #[test]
    fn cold_node_window_is_unbounded() {
        let metrics = test_metrics();
        let window = compute_window(&[], 5, 40, None, 10_000, &metrics);
        assert_eq!(window.min_version_ms, None);
    }

    #[test]
    fn watermark_term_shallowes_the_window_on_rejoin() {
        let metrics = test_metrics();
        let stats = vec![100, 200, 300, 400, 500];

        // A watermark above the horizon bounds the re-join pass.
        let window = compute_window(&stats, 5, 40, Some(450), 10_000, &metrics);
        assert_eq!(window.min_version_ms, Some(450));

        // A watermark below the horizon never deepens the window past it.
        let window = compute_window(&stats, 5, 40, Some(150), 10_000, &metrics);
        assert_eq!(window.min_version_ms, Some(400));

        // No watermark: the horizon alone bounds the pass.
        let window = compute_window(&stats, 5, 40, None, 10_000, &metrics);
        assert_eq!(window.min_version_ms, Some(400));
    }

    #[test]
    fn capacity_test_fires_the_moment_the_ring_fills_on_an_age_inverted_cold_ring() {
        // Cold backfill, newest-first: sealed segments hold data newer than
        // the descending cursor, so the next evictee is always newer than the
        // cursor and the only thing deferring completion is ring fullness.
        let ring_total = 3;
        let first_sealed_stat = Some(1_000);

        assert!(!capacity_complete(1, ring_total, first_sealed_stat, 940));
        assert!(!capacity_complete(2, ring_total, first_sealed_stat, 910));
        assert!(capacity_complete(3, ring_total, first_sealed_stat, 890));
    }

    #[test]
    fn capacity_test_on_a_warm_ring_fires_when_the_cursor_descends_below_the_oldest_stat() {
        let ring_total = 5;
        let oldest_retained_stat = Some(100);

        assert!(!capacity_complete(5, ring_total, oldest_retained_stat, 150));
        assert!(capacity_complete(5, ring_total, oldest_retained_stat, 90));
        // Equality completes: the fetch would gain nothing over what the
        // rotation destroys (conservative by construction).
        assert!(capacity_complete(5, ring_total, oldest_retained_stat, 100));
        // An empty ring view never capacity-completes regardless of counts.
        assert!(!capacity_complete(5, ring_total, None, 90));
    }

    #[test]
    fn watermark_is_monotonic_under_out_of_order_completion_attempts() {
        let skew = crate::constants::BACKFILL_WATERMARK_SKEW_ALLOWANCE_MS;
        let older_pass_start = 500_000;
        let newer_pass_start = 900_000;

        // The dirty-triggered newer pass completes first…
        let watermark = advance_watermark(None, newer_pass_start);
        assert_eq!(watermark, newer_pass_start - skew);

        // …then the retried older pass completes; the max guard holds.
        let watermark = advance_watermark(Some(watermark), older_pass_start);
        assert_eq!(watermark, newer_pass_start - skew);

        // In-order completions still advance.
        let watermark = advance_watermark(Some(watermark), newer_pass_start + 1_000);
        assert_eq!(watermark, newer_pass_start + 1_000 - skew);
    }

    #[test]
    fn watermark_applies_the_skew_allowance_and_saturates_at_zero() {
        let skew = crate::constants::BACKFILL_WATERMARK_SKEW_ALLOWANCE_MS;
        assert_eq!(advance_watermark(None, skew + 5), 5);
        assert_eq!(advance_watermark(None, skew / 2), 0);
    }

    #[test]
    fn horizon_age_span_gauge_tracks_now_minus_horizon_across_ring_shapes() {
        for (stats, margin_percent, now_ms, expected_age) in [
            // Warm ordered ring: horizon 400, age span 600.
            (vec![100u64, 200, 300, 400, 500], 40u64, 1_000u64, 600u64),
            // Age-inverted ring input arrives age-ordered all the same.
            (vec![100, 300, 500, 700, 900], 40, 1_000, 300),
            // Single-segment ring: horizon clamps to its only stat.
            (vec![250], 40, 1_000, 750),
        ] {
            let metrics = test_metrics();
            compute_window(&stats, stats.len(), margin_percent, None, now_ms, &metrics);
            let rendered = metrics.render();
            assert!(
                rendered.contains(&format!("kura_backfill_horizon_age_ms {expected_age}")),
                "expected age {expected_age} in: {rendered}"
            );
        }
    }

    #[test]
    fn cold_node_leaves_the_horizon_age_span_gauge_untouched() {
        let metrics = test_metrics();
        compute_window(&[], 5, 40, None, 1_000, &metrics);
        assert!(metrics.render().contains("kura_backfill_horizon_age_ms 0"));
    }

    #[test]
    fn horizon_properties_hold_over_synthetic_rings() {
        let mut seed = 0x5eed_cafe_u64;
        for count in 1usize..=64 {
            let sorted: Vec<u64> = (0..count as u64).map(|index| 10 + index * 7).collect();
            let scrambled_ring = shuffled(sorted.clone(), &mut seed);

            // Age-ordering the scrambled ring recovers the sorted view, so
            // the horizon is invariant to ring position by construction.
            let mut recovered = scrambled_ring.clone();
            recovered.sort_unstable();
            assert_eq!(recovered, sorted);

            let mut previous_horizon = None;
            for margin_percent in 1u64..=100 {
                let horizon = horizon_version_ms(&sorted, count, margin_percent)
                    .expect("full ring always has a horizon");
                // The horizon is always one of the retained stats.
                assert!(sorted.contains(&horizon));
                // More margin means more slack: the horizon never rises as
                // the margin grows.
                if let Some(previous) = previous_horizon {
                    assert!(horizon <= previous, "count {count} margin {margin_percent}");
                }
                previous_horizon = Some(horizon);
            }
            // Full margin reaches the oldest stat.
            assert_eq!(horizon_version_ms(&sorted, count, 100), Some(sorted[0]));
        }
    }
}
