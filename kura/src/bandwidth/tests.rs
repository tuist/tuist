
use super::*;

#[test]
fn disabled_when_limit_is_zero() {
    assert!(BandwidthLimiter::new(0, 100, RuntimeState::new()).is_none());
}

#[test]
fn duration_rounds_up_to_avoid_zero_cost_bytes() {
    assert_eq!(
        duration_for_bytes(1, 10_000_000_000),
        Duration::from_nanos(1)
    );
    assert_eq!(duration_for_bytes(2_000, 1_000), Duration::from_secs(2));
}

#[test]
fn effective_rate_shrinks_as_public_inflight_grows() {
    assert_eq!(effective_bytes_per_second(10_000, 0, 1), 10_000);
    assert_eq!(effective_bytes_per_second(10_000, 1, 1), 5_000);
    assert_eq!(effective_bytes_per_second(10_000, 4, 1), 2_000);
    assert_eq!(effective_bytes_per_second(1, 10, 1), 1);
    assert_eq!(effective_bytes_per_second(0, 10, 1), 0);
}

#[test]
fn effective_rate_uses_larger_latency_pressure_divisor() {
    assert_eq!(effective_bytes_per_second(10_000, 0, 4), 2_500);
    assert_eq!(effective_bytes_per_second(10_000, 4, 2), 2_000);
}
