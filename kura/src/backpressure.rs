use rand::Rng as _;

/// `Retry-After` is expressed in whole seconds, so the hint is drawn uniformly
/// from `MIN_RETRY_AFTER_SECONDS..=ceiling`: a fleet shed together must not
/// return together.
pub(crate) const MIN_RETRY_AFTER_SECONDS: u64 = 1;
/// Ceiling for a shed that carries no backlog signal.
pub(crate) const IDLE_RETRY_AFTER_CEILING_SECONDS: u64 = 2;
/// Ceiling for a full queue: twice the admission wait, so a returning client
/// has given the pool a complete turnover.
pub(crate) const SATURATED_RETRY_AFTER_CEILING_SECONDS: u64 = 10;

pub(crate) fn retry_after_ceiling_seconds(backlog: u64, capacity: u64) -> u64 {
    if capacity == 0 {
        return IDLE_RETRY_AFTER_CEILING_SECONDS;
    }
    let backlog = backlog.min(capacity);
    let span = SATURATED_RETRY_AFTER_CEILING_SECONDS - IDLE_RETRY_AFTER_CEILING_SECONDS;
    IDLE_RETRY_AFTER_CEILING_SECONDS + span.saturating_mul(backlog).div_ceil(capacity)
}

pub(crate) fn retry_after_seconds(ceiling_seconds: u64) -> u64 {
    let ceiling = ceiling_seconds.max(MIN_RETRY_AFTER_SECONDS);
    rand::rng().random_range(MIN_RETRY_AFTER_SECONDS..=ceiling)
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    #[test]
    fn ceiling_grows_with_the_backlog() {
        assert_eq!(
            retry_after_ceiling_seconds(0, 8),
            IDLE_RETRY_AFTER_CEILING_SECONDS
        );
        assert_eq!(
            retry_after_ceiling_seconds(8, 8),
            SATURATED_RETRY_AFTER_CEILING_SECONDS
        );
        let ceilings: Vec<u64> = (0..=8)
            .map(|backlog| retry_after_ceiling_seconds(backlog, 8))
            .collect();
        assert!(
            ceilings.windows(2).all(|pair| pair[0] <= pair[1]),
            "{ceilings:?}"
        );
    }

    #[test]
    fn ceiling_tolerates_a_backlog_beyond_capacity_and_an_unsized_queue() {
        assert_eq!(
            retry_after_ceiling_seconds(64, 8),
            SATURATED_RETRY_AFTER_CEILING_SECONDS
        );
        assert_eq!(
            retry_after_ceiling_seconds(4, 0),
            IDLE_RETRY_AFTER_CEILING_SECONDS
        );
    }

    #[test]
    fn hints_spread_across_the_whole_range() {
        let ceiling = SATURATED_RETRY_AFTER_CEILING_SECONDS;
        let values: HashSet<u64> = (0..512).map(|_| retry_after_seconds(ceiling)).collect();

        assert!(values.len() > 1, "{values:?}");
        assert!(
            values
                .iter()
                .all(|value| (MIN_RETRY_AFTER_SECONDS..=ceiling).contains(value)),
            "{values:?}"
        );
        assert!(values.contains(&MIN_RETRY_AFTER_SECONDS), "{values:?}");
        assert!(values.contains(&ceiling), "{values:?}");
    }

    #[test]
    fn a_ceiling_below_the_floor_still_yields_a_retryable_hint() {
        assert_eq!(retry_after_seconds(0), MIN_RETRY_AFTER_SECONDS);
    }
}
