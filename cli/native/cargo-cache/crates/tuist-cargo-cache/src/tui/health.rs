//! Recent cache pressure, measured while this dashboard is watching.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

pub(super) const WINDOW: Duration = Duration::from_secs(5 * 60);

#[derive(Default)]
struct Sample {
    evicted: u64,
    hits: u64,
    misses: u64,
}

pub(super) struct Health {
    started: Instant,
    now: Instant,
    baseline: Option<(u64, u64, Instant)>,
    samples: VecDeque<(Instant, Sample)>,
    pub evicted: u64,
    pub eviction_updates: usize,
    pub hits: u64,
    pub misses: u64,
}

impl Default for Health {
    fn default() -> Self {
        let now = Instant::now();
        Self {
            started: now,
            now,
            baseline: None,
            samples: VecDeque::new(),
            evicted: 0,
            eviction_updates: 0,
            hits: 0,
            misses: 0,
        }
    }
}

impl Health {
    pub(super) fn advance(&mut self, now: Instant) {
        self.now = now;
        while self
            .samples
            .front()
            .is_some_and(|(time, _)| now.saturating_duration_since(*time) >= WINDOW)
        {
            let (_, sample) = self.samples.pop_front().unwrap();
            self.evicted -= sample.evicted;
            self.eviction_updates -= usize::from(sample.evicted > 0);
            self.hits -= sample.hits;
            self.misses -= sample.misses;
        }
    }

    pub(super) fn lookups(&mut self, now: Instant, hits: u64, misses: u64) {
        self.advance(now);
        if hits == 0 && misses == 0 {
            return;
        }
        // Coalesce reads within a second to keep memory bounded even when keys
        // repeat or hundreds of events arrive between store refreshes.
        if let Some((time, sample)) = self.samples.back_mut()
            && now.saturating_duration_since(*time) < Duration::from_secs(1)
        {
            sample.hits += hits;
            sample.misses += misses;
        } else {
            self.samples.push_back((
                now,
                Sample {
                    hits,
                    misses,
                    ..Sample::default()
                },
            ));
        }
        self.hits += hits;
        self.misses += misses;
    }

    pub(super) fn observe_evictions(&mut self, now: Instant, since: u64, total: u64) {
        self.advance(now);
        let previous = self.baseline.replace((since, total, now));
        let Some((previous_since, previous_total, previous_time)) = previous else {
            return;
        };
        // A reset/replaced ledger is a new baseline, never a giant eviction.
        if since != previous_since
            || total < previous_total
            || now.saturating_duration_since(previous_time) >= WINDOW
        {
            self.samples.clear();
            self.evicted = 0;
            self.eviction_updates = 0;
            self.hits = 0;
            self.misses = 0;
            return;
        }
        let evicted = total - previous_total;
        if evicted > 0 {
            self.samples.push_back((
                now,
                Sample {
                    evicted,
                    ..Sample::default()
                },
            ));
            self.evicted += evicted;
            self.eviction_updates += 1;
        }
    }

    pub(super) fn possible_thrashing(&self, budget: Option<u64>) -> bool {
        let Some(budget) = budget.filter(|bytes| *bytes > 0) else {
            return false;
        };
        let lookups = self.hits + self.misses;
        self.eviction_updates >= 3
            && self.evicted as u128 * 4 >= budget as u128
            && lookups >= 20
            && self.misses as u128 * 2 >= lookups as u128
    }

    pub(super) fn bright(&self) -> bool {
        self.now
            .saturating_duration_since(self.started)
            .as_secs()
            .is_multiple_of(2)
    }

    pub(super) fn miss_rate(&self) -> f64 {
        let lookups = self.hits + self.misses;
        if lookups == 0 {
            0.0
        } else {
            self.misses as f64 * 100.0 / lookups as f64
        }
    }

    /// Equal-width buckets over the actual observation window, oldest first.
    /// Idle time stays zero; opening the dashboard never invents a waveform.
    pub(super) fn lookup_series(&self, columns: usize) -> (Vec<u64>, Vec<u64>) {
        let mut hits = vec![0u64; columns];
        let mut misses = vec![0u64; columns];
        if columns == 0 {
            return (hits, misses);
        }
        for (time, sample) in &self.samples {
            let age = self.now.saturating_duration_since(*time).as_millis();
            if age >= WINDOW.as_millis() {
                continue;
            }
            let index = columns - 1 - (age * columns as u128 / WINDOW.as_millis()) as usize;
            hits[index] = hits[index].saturating_add(sample.hits);
            misses[index] = misses[index].saturating_add(sample.misses);
        }
        (hits, misses)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn traffic_buckets_preserve_idle_time_counts_and_expiry() {
        let mut health = Health::default();
        let now = Instant::now();
        assert_eq!(health.lookup_series(0), (vec![], vec![]));
        assert_eq!(health.lookup_series(3), (vec![0; 3], vec![0; 3]));
        health.lookups(now, 10, 2);
        health.lookups(now + Duration::from_secs(101), 20, 3);
        health.lookups(now + Duration::from_secs(250), 30, 4);
        health.advance(now + Duration::from_secs(299));
        assert_eq!(health.lookup_series(3), (vec![10, 20, 30], vec![2, 3, 4]));
        health.advance(now + Duration::from_secs(300));
        assert_eq!(health.lookup_series(3), (vec![0, 20, 30], vec![0, 3, 4]));
        health.advance(now + Duration::from_secs(551));
        assert_eq!(health.lookup_series(3), (vec![0; 3], vec![0; 3]));
    }

    #[test]
    fn startup_and_one_cleanup_do_not_look_like_thrashing() {
        let mut health = Health::default();
        let now = Instant::now();
        health.observe_evictions(now, 1, 10_000);
        assert_eq!(health.evicted, 0);
        health.lookups(now, 0, 30);
        health.observe_evictions(now + Duration::from_secs(2), 1, 20_000);
        assert_eq!(health.evicted, 10_000);
        assert!(!health.possible_thrashing(Some(1000)));
    }

    #[test]
    fn alert_requires_repeated_churn_and_misses_and_expires() {
        let mut health = Health::default();
        let now = Instant::now();
        health.observe_evictions(now, 1, 0);
        for i in 1..=3 {
            health.observe_evictions(now + Duration::from_secs(i * 2), 1, i * 100);
        }
        health.lookups(now + Duration::from_secs(7), 30, 0);
        assert!(!health.possible_thrashing(Some(1000)));
        health.lookups(now + Duration::from_secs(8), 0, 30);
        assert!(health.possible_thrashing(Some(1000)));
        assert!(!health.possible_thrashing(Some(2000)));
        assert!(!health.possible_thrashing(None));
        assert!(!health.possible_thrashing(Some(0)));
        health.advance(now + WINDOW + Duration::from_secs(9));
        assert!(!health.possible_thrashing(Some(1000)));
        assert_eq!(health.evicted, 0);
    }

    #[test]
    fn ledger_reset_discards_old_pressure() {
        let mut health = Health::default();
        let now = Instant::now();
        health.observe_evictions(now, 1, 100);
        health.observe_evictions(now, 1, 200);
        health.observe_evictions(now, 2, 50);
        assert_eq!(health.evicted, 0);
        assert_eq!(health.eviction_updates, 0);
        health.observe_evictions(now, 2, 70);
        assert_eq!(health.evicted, 20);
    }
}
