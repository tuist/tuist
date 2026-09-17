//! Actions builds answered from their local stores, waiting for the proxy to
//! send them to kura as keep-alives. Kura extends a blob's lifetime only when it
//! reads it, and a local hit is a read it never sees. Best effort throughout.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use sha2::{Digest as _, Sha256};

/// The ActionCache digest of an llcas action key.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct ActionDigest {
    pub hash: [u8; 32],
    pub size: u32,
}

impl ActionDigest {
    pub fn of(key: &[u8]) -> Self {
        Self {
            hash: Sha256::digest(key).into(),
            size: key.len() as u32,
        }
    }
}

/// Kura rejects a larger batch.
pub const BATCH: usize = 4_096;

const MAX_PENDING: usize = 200_000;

/// Well inside the time a blob spends in kura's Old band, which is when a
/// keep-alive copies it forward.
pub const RESEND_AFTER: Duration = Duration::from_secs(60 * 60);

const MAX_SENT: usize = 500_000;

/// A kura that predates keep-alive answers not-found.
pub const UNSUPPORTED_RETRY: Duration = Duration::from_secs(60 * 60);

pub const DECLINED_RETRY: Duration = Duration::from_secs(60);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Answer {
    Kept {
        found: u64,
        missing: u64,
        evicted: u64,
    },
    Unsupported,
    /// Under memory pressure; nothing was done.
    Declined,
    Failed,
}

#[derive(Default)]
pub struct KeepAlive {
    state: Mutex<State>,
}

#[derive(Default)]
struct State {
    pending: HashMap<String, HashSet<ActionDigest>>,
    pending_total: usize,
    sent: HashMap<String, HashMap<ActionDigest, Instant>>,
    sent_total: usize,
    paused_until: HashMap<String, Instant>,
    stats: Stats,
}

#[derive(Default, Clone, Copy, Debug, PartialEq, Eq)]
pub struct Stats {
    pub sent: u64,
    pub found: u64,
    pub missing: u64,
    pub evicted: u64,
    pub declined: u64,
    pub unsupported: u64,
    pub failed: u64,
    pub dropped: u64,
}

impl KeepAlive {
    /// Returns whether any action is newly waiting to be sent.
    pub fn note(
        &self,
        instance: &str,
        actions: impl IntoIterator<Item = ActionDigest>,
        now: Instant,
    ) -> bool {
        let mut state = self.state.lock().unwrap();
        let State {
            pending,
            pending_total,
            sent,
            stats,
            ..
        } = &mut *state;
        let recently_sent = sent.get(instance);
        let waiting = pending.entry(instance.to_string()).or_default();
        let mut added = false;
        for action in actions {
            if recently_sent
                .and_then(|sent| sent.get(&action))
                .is_some_and(|at| now.duration_since(*at) < RESEND_AFTER)
            {
                continue;
            }
            if waiting.contains(&action) {
                continue;
            }
            if *pending_total >= MAX_PENDING {
                stats.dropped += 1;
                continue;
            }
            waiting.insert(action);
            *pending_total += 1;
            added = true;
        }
        if waiting.is_empty() {
            pending.remove(instance);
        }
        added
    }

    /// The next batch to send, marked sent. `None` while the instance is backed off.
    pub fn take_batch(&self, instance: &str, now: Instant) -> Option<Vec<ActionDigest>> {
        let mut state = self.state.lock().unwrap();
        if state
            .paused_until
            .get(instance)
            .is_some_and(|until| now < *until)
        {
            return None;
        }
        let waiting = state.pending.get_mut(instance)?;
        let batch: Vec<ActionDigest> = waiting.iter().take(BATCH).copied().collect();
        for action in &batch {
            waiting.remove(action);
        }
        if waiting.is_empty() {
            state.pending.remove(instance);
        }
        state.pending_total -= batch.len();
        if batch.is_empty() {
            return None;
        }
        state.remember_sent(instance, &batch, now);
        Some(batch)
    }

    pub fn settle(&self, instance: &str, batch: Vec<ActionDigest>, answer: Answer, now: Instant) {
        let mut state = self.state.lock().unwrap();
        match answer {
            Answer::Kept {
                found,
                missing,
                evicted,
            } => {
                state.stats.sent += batch.len() as u64;
                state.stats.found += found;
                state.stats.missing += missing;
                state.stats.evicted += evicted;
            }
            Answer::Unsupported => {
                state.stats.unsupported += 1;
                if let Some(waiting) = state.pending.remove(instance) {
                    state.pending_total -= waiting.len();
                }
                state
                    .paused_until
                    .insert(instance.to_string(), now + UNSUPPORTED_RETRY);
            }
            Answer::Declined => {
                state.stats.declined += 1;
                state.forget_sent(instance, &batch);
                let free = MAX_PENDING.saturating_sub(state.pending_total);
                state.stats.dropped += batch.len().saturating_sub(free) as u64;
                let waiting = state.pending.entry(instance.to_string()).or_default();
                let before = waiting.len();
                waiting.extend(batch.into_iter().take(free));
                let requeued = waiting.len() - before;
                state.pending_total += requeued;
                state
                    .paused_until
                    .insert(instance.to_string(), now + DECLINED_RETRY);
            }
            Answer::Failed => {
                // Not requeued, so an unreachable server is not retried every tick.
                state.stats.failed += 1;
                state.forget_sent(instance, &batch);
            }
        }
    }

    pub fn due(&self, now: Instant) -> Vec<String> {
        let state = self.state.lock().unwrap();
        state
            .pending
            .keys()
            .filter(|instance| {
                state
                    .paused_until
                    .get(*instance)
                    .is_none_or(|until| now >= *until)
            })
            .cloned()
            .collect()
    }

    pub fn stats(&self) -> Stats {
        self.state.lock().unwrap().stats
    }
}

impl State {
    fn remember_sent(&mut self, instance: &str, batch: &[ActionDigest], now: Instant) {
        if self.sent_total + batch.len() > MAX_SENT {
            for sent in self.sent.values_mut() {
                sent.retain(|_, at| now.duration_since(*at) < RESEND_AFTER);
            }
            self.sent_total = self.sent.values().map(HashMap::len).sum();
            if self.sent_total + batch.len() > MAX_SENT {
                self.sent.clear();
                self.sent_total = 0;
            }
        }
        let sent = self.sent.entry(instance.to_string()).or_default();
        for action in batch {
            if sent.insert(*action, now).is_none() {
                self.sent_total += 1;
            }
        }
    }

    fn forget_sent(&mut self, instance: &str, batch: &[ActionDigest]) {
        if let Some(sent) = self.sent.get_mut(instance) {
            for action in batch {
                if sent.remove(action).is_some() {
                    self.sent_total -= 1;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn actions(range: std::ops::Range<u32>) -> Vec<ActionDigest> {
        range
            .map(|index| ActionDigest::of(format!("key-{index}").as_bytes()))
            .collect()
    }

    fn kept() -> Answer {
        Answer::Kept {
            found: 0,
            missing: 0,
            evicted: 0,
        }
    }

    #[test]
    fn an_action_digest_is_the_one_a_resolve_looks_up() {
        let digest = ActionDigest::of(b"llcas action key");
        assert_eq!(digest.size, 16);
        assert_eq!(
            digest.hash,
            <[u8; 32]>::from(Sha256::digest(b"llcas action key"))
        );
    }

    #[test]
    fn an_action_answered_repeatedly_is_sent_once() {
        let keep_alive = KeepAlive::default();
        let now = Instant::now();
        assert!(keep_alive.note("acme/app", actions(0..3), now));
        assert!(
            !keep_alive.note("acme/app", actions(0..3), now),
            "already waiting"
        );

        let batch = keep_alive.take_batch("acme/app", now).expect("a batch");
        assert_eq!(batch.len(), 3);
        keep_alive.settle("acme/app", batch, kept(), now);

        assert!(
            !keep_alive.note("acme/app", actions(0..3), now + Duration::from_secs(60)),
            "a long-lived proxy does not re-send what it sent within the hour"
        );
        assert_eq!(keep_alive.take_batch("acme/app", now), None);
        assert!(
            keep_alive.note("acme/app", actions(0..3), now + RESEND_AFTER),
            "and sends it again once kura may have aged it back into its Old band"
        );
    }

    #[test]
    fn instances_are_kept_apart() {
        let keep_alive = KeepAlive::default();
        let now = Instant::now();
        keep_alive.note("acme/app", actions(0..2), now);
        let batch = keep_alive.take_batch("acme/app", now).expect("a batch");
        keep_alive.settle("acme/app", batch, kept(), now);

        assert!(
            keep_alive.note("acme/other", actions(0..2), now),
            "the same key in another project is another entry on the server"
        );
        assert_eq!(
            keep_alive
                .take_batch("acme/other", now)
                .map(|batch| batch.len()),
            Some(2)
        );
    }

    #[test]
    fn a_batch_never_exceeds_what_kura_accepts() {
        let keep_alive = KeepAlive::default();
        let now = Instant::now();
        keep_alive.note("acme/app", actions(0..(BATCH as u32 + 10)), now);
        assert_eq!(
            keep_alive.take_batch("acme/app", now).map(|b| b.len()),
            Some(BATCH)
        );
        assert_eq!(
            keep_alive.take_batch("acme/app", now).map(|b| b.len()),
            Some(10)
        );
        assert_eq!(keep_alive.take_batch("acme/app", now), None);
    }

    #[test]
    fn a_declined_batch_waits_out_the_backoff_and_goes_with_the_next() {
        let keep_alive = KeepAlive::default();
        let now = Instant::now();
        keep_alive.note("acme/app", actions(0..3), now);
        let batch = keep_alive.take_batch("acme/app", now).expect("a batch");
        keep_alive.settle("acme/app", batch, Answer::Declined, now);
        keep_alive.note("acme/app", actions(3..5), now);

        assert!(
            keep_alive.due(now).is_empty(),
            "a declining server is backed off from"
        );
        assert_eq!(keep_alive.take_batch("acme/app", now), None);

        let later = now + DECLINED_RETRY;
        assert_eq!(keep_alive.due(later), vec!["acme/app".to_string()]);
        let mut resent = keep_alive.take_batch("acme/app", later).expect("a batch");
        resent.sort_by_key(|action| action.hash);
        let mut expected = actions(0..5);
        expected.sort_by_key(|action| action.hash);
        assert_eq!(resent, expected);
    }

    #[test]
    fn a_server_without_keep_alive_is_left_alone_for_an_hour() {
        let keep_alive = KeepAlive::default();
        let now = Instant::now();
        keep_alive.note("acme/app", actions(0..(BATCH as u32 + 5)), now);
        let batch = keep_alive.take_batch("acme/app", now).expect("a batch");
        keep_alive.settle("acme/app", batch, Answer::Unsupported, now);

        assert_eq!(
            keep_alive.take_batch("acme/app", now),
            None,
            "the rest of the backlog is dropped rather than sent to a server that cannot use it"
        );
        keep_alive.note(
            "acme/app",
            actions(10_000..10_002),
            now + Duration::from_secs(60),
        );
        assert!(keep_alive.due(now + Duration::from_secs(60)).is_empty());
        assert_eq!(
            keep_alive.due(now + UNSUPPORTED_RETRY),
            vec!["acme/app".to_string()],
            "the server may have been upgraded under a long-lived proxy"
        );
    }

    #[test]
    fn a_failed_batch_is_sent_again_by_the_next_build_that_answers_it() {
        let keep_alive = KeepAlive::default();
        let now = Instant::now();
        keep_alive.note("acme/app", actions(0..3), now);
        let batch = keep_alive.take_batch("acme/app", now).expect("a batch");
        keep_alive.settle("acme/app", batch, Answer::Failed, now);

        assert_eq!(
            keep_alive.take_batch("acme/app", now),
            None,
            "not retried on its own"
        );
        assert!(keep_alive.note("acme/app", actions(0..3), now));
        assert_eq!(keep_alive.stats().failed, 1);
    }

    #[test]
    fn the_backlog_is_bounded() {
        let keep_alive = KeepAlive::default();
        let now = Instant::now();
        keep_alive.note("acme/app", actions(0..(MAX_PENDING as u32 + 7)), now);
        assert_eq!(keep_alive.stats().dropped, 7);
        assert_eq!(keep_alive.state.lock().unwrap().pending_total, MAX_PENDING);
    }
}
