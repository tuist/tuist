//! What the store removed from the action cache, so a cached snapshot index
//! can stop advertising it before its next reconcile.
//!
//! A snapshot index is served from memory and reconciled in the background, so
//! the first serve after an eviction answers from a view that still lists the
//! entries the eviction cascaded and the blobs it removed. A client resolving
//! from that view gets candidates it cannot restore, and every one of them
//! misses without a lookup the analytics can see. Recording each removal with a
//! sequence number lets the serve path drop exactly those entries from the
//! cached index, without the namespace scan a reconcile costs.
//!
//! One log serves every namespace, so its memory is bounded by a single cap no
//! matter how many namespaces churn through the node. A namespace is kept as a
//! hash rather than its name: a collision can only make an index drop an entry
//! whose key also matches another namespace's removal, which sends that key per
//! key. The log is in memory, like the action-cache generation: a fresh process
//! builds its indexes from the store, which already reflects every removal. A
//! reader whose position fell out of the retained window is told so and
//! rebuilds instead of trusting a partial list.

use std::{
    collections::{HashSet, VecDeque},
    hash::{DefaultHasher, Hash, Hasher},
};

/// Removals retained across all namespaces: 64 bytes each, 4 MiB at most. A
/// power of two, so the ring never grows past it. Readers are restamped by
/// every reconcile, so this only has to cover the removals between a reconcile
/// and the next serves; a larger burst (160k entries were measured in one
/// segment eviction) is exactly when a rebuild is the right call.
pub const ACTION_CACHE_REMOVAL_LOG_MAX: usize = 65_536;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum ActionCacheRemoval {
    /// An action-cache entry, by action hash.
    Entry([u8; 32]),
    /// A blob, by the digest in its logical key (`blob/{hash}/{size}`).
    Blob { hash: [u8; 32], size: u64 },
}

impl ActionCacheRemoval {
    /// The removal a deleted artifact stands for, or `None` for artifacts no
    /// snapshot index can reference.
    pub fn for_artifact_key(key: &str) -> Option<Self> {
        if let Some(hash) = crate::utils::action_cache_manifest_hash(key) {
            let hash: [u8; 32] = hex::decode(hash).ok()?.try_into().ok()?;
            return Some(Self::Entry(hash));
        }
        let (hash, size) = key.strip_prefix("blob/")?.split_once('/')?;
        Some(Self::Blob {
            hash: hex::decode(hash).ok()?.try_into().ok()?,
            size: size.parse().ok()?,
        })
    }
}

/// A namespace's removals after a reader's sequence number, up to `through`.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct ActionCacheRemovals {
    pub through: u64,
    pub entries: HashSet<[u8; 32]>,
    pub blobs: HashSet<([u8; 32], u64)>,
}

impl ActionCacheRemovals {
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty() && self.blobs.is_empty()
    }
}

pub struct ActionCacheRemovalLog {
    /// Sequence number of the newest recorded removal; 0 before the first.
    last: u64,
    /// `(sequence, namespace hash, removal)`, oldest first.
    retained: VecDeque<(u64, u64, ActionCacheRemoval)>,
    max: usize,
}

impl ActionCacheRemovalLog {
    pub fn new(max: usize) -> Self {
        Self {
            last: 0,
            retained: VecDeque::new(),
            max: max.max(1),
        }
    }

    pub fn record(&mut self, namespace_id: &str, removal: ActionCacheRemoval) {
        // Make room first: pushing onto a full ring would double its buffer.
        if self.retained.len() >= self.max {
            self.retained.pop_front();
        }
        self.last += 1;
        self.retained
            .push_back((self.last, namespace_hash(namespace_id), removal));
    }

    /// The sequence number a reader built from the store now resumes from.
    pub fn last(&self) -> u64 {
        self.last
    }

    /// The namespace's removals recorded after `after`, or `None` when the log
    /// has discarded removals after `after` (any namespace's) and the reader
    /// has to rebuild from the store.
    pub fn since(&self, namespace_id: &str, after: u64) -> Option<ActionCacheRemovals> {
        let oldest_retained = self
            .retained
            .front()
            .map_or(self.last + 1, |(seq, ..)| *seq);
        if after < self.last && after + 1 < oldest_retained {
            return None;
        }
        let namespace = namespace_hash(namespace_id);
        let mut removals = ActionCacheRemovals {
            through: self.last.max(after),
            ..Default::default()
        };
        for (_, _, removal) in self
            .retained
            .iter()
            .filter(|(seq, hash, _)| *seq > after && *hash == namespace)
        {
            match removal {
                ActionCacheRemoval::Entry(hash) => {
                    removals.entries.insert(*hash);
                }
                ActionCacheRemoval::Blob { hash, size } => {
                    removals.blobs.insert((*hash, *size));
                }
            }
        }
        Some(removals)
    }

    #[cfg(test)]
    fn retained_capacity(&self) -> usize {
        self.retained.capacity()
    }
}

fn namespace_hash(namespace_id: &str) -> u64 {
    let mut hasher = DefaultHasher::new();
    namespace_id.hash(&mut hasher);
    hasher.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(byte: u8) -> ActionCacheRemoval {
        ActionCacheRemoval::Entry([byte; 32])
    }

    #[test]
    fn a_reader_gets_only_its_namespaces_removals_after_its_sequence() {
        let mut log = ActionCacheRemovalLog::new(16);
        log.record("ios", entry(1));
        let resume = log.last();
        log.record("ios", entry(2));
        log.record(
            "ios",
            ActionCacheRemoval::Blob {
                hash: [0xaa; 32],
                size: 7,
            },
        );
        log.record("android", entry(3));

        let removals = log.since("ios", resume).expect("within the window");

        assert_eq!(removals.through, 4);
        assert_eq!(removals.entries, HashSet::from([[2; 32]]));
        assert_eq!(removals.blobs, HashSet::from([([0xaa; 32], 7)]));
        assert!(log.since("ios", 4).expect("caught up").is_empty());
    }

    #[test]
    fn an_empty_log_is_caught_up() {
        let log = ActionCacheRemovalLog::new(16);

        let removals = log.since("ios", 0).expect("nothing to miss");

        assert!(removals.is_empty());
        assert_eq!(removals.through, 0);
    }

    #[test]
    fn a_reader_behind_the_retained_window_must_rebuild() {
        let mut log = ActionCacheRemovalLog::new(2);
        for byte in 1..=4 {
            log.record("ios", entry(byte));
        }

        assert_eq!(log.since("ios", 1), None);
        let removals = log.since("ios", 2).expect("the next removal is retained");
        assert_eq!(removals.entries, HashSet::from([[3; 32], [4; 32]]));
    }

    #[test]
    fn another_namespaces_churn_pushes_a_reader_out_of_the_window() {
        let mut log = ActionCacheRemovalLog::new(4);
        log.record("ios", entry(1));
        let resume = log.last();
        for byte in 2..=8 {
            log.record(&format!("churn-{byte}"), entry(byte));
        }

        assert_eq!(
            log.since("ios", resume),
            None,
            "discarded history may have held this namespace's removals"
        );
    }

    #[test]
    fn a_full_log_never_grows_past_its_cap() {
        let mut log = ActionCacheRemovalLog::new(1024);
        for round in 0..10_000u32 {
            log.record(&format!("namespace-{round}"), entry(round as u8));
        }

        assert!(log.retained_capacity() <= 1024);
    }

    #[test]
    fn only_entries_and_blobs_are_removals_an_index_can_see() {
        let hash = "ab".repeat(32);

        assert_eq!(
            ActionCacheRemoval::for_artifact_key(&format!("action_cache/{hash}/10")),
            Some(ActionCacheRemoval::Entry([0xab; 32]))
        );
        assert_eq!(
            ActionCacheRemoval::for_artifact_key(&format!("blob/{hash}/7")),
            Some(ActionCacheRemoval::Blob {
                hash: [0xab; 32],
                size: 7,
            })
        );
        assert_eq!(ActionCacheRemoval::for_artifact_key("blob/aa/7"), None);
        assert_eq!(ActionCacheRemoval::for_artifact_key("module/x/y"), None);
        assert_eq!(
            ActionCacheRemoval::for_artifact_key("action_cache/zz/1"),
            None
        );
    }
}
