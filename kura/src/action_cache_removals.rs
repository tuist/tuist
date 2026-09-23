//! What the store removed from each namespace's action cache, so a cached
//! snapshot index can stop advertising it before its next reconcile.
//!
//! A snapshot index is served from memory and reconciled in the background, so
//! the first serve after an eviction answers from a view that still lists the
//! entries the eviction cascaded and the blobs it removed. A client resolving
//! from that view gets candidates it cannot restore, and every one of them
//! misses without a lookup the analytics can see. Recording each removal with a
//! sequence number lets the serve path drop exactly those entries from the
//! cached index, without the namespace scan a reconcile costs.
//!
//! The log is in memory and per node, like the action-cache generation: a fresh
//! process builds its indexes from the store, which already reflects every
//! removal. It is bounded per namespace; a reader that fell behind the retained
//! window is told so and rebuilds instead of trusting a partial list.

use std::collections::{HashMap, HashSet, VecDeque};

/// Removals retained per namespace, about 4 MiB at most. A reader behind the
/// window rebuilds from the store, so this only has to cover the removals between
/// two serves of a busy namespace; a cascade larger than it (160k entries were
/// measured in one segment eviction) is exactly when a rebuild is the right call.
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

/// The removals after a reader's sequence number, up to `through`.
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

#[derive(Default)]
struct NamespaceLog {
    /// Sequence number of the newest recorded removal; 0 before the first.
    last: u64,
    /// `(sequence, removal)` pairs, oldest first.
    retained: VecDeque<(u64, ActionCacheRemoval)>,
}

#[derive(Default)]
pub struct ActionCacheRemovalLog {
    namespaces: HashMap<String, NamespaceLog>,
    max_per_namespace: usize,
}

impl ActionCacheRemovalLog {
    pub fn new(max_per_namespace: usize) -> Self {
        Self {
            namespaces: HashMap::new(),
            max_per_namespace,
        }
    }

    pub fn record(&mut self, namespace_id: &str, removal: ActionCacheRemoval) {
        let log = self.namespaces.entry(namespace_id.to_owned()).or_default();
        log.last += 1;
        log.retained.push_back((log.last, removal));
        while log.retained.len() > self.max_per_namespace {
            log.retained.pop_front();
        }
    }

    /// The sequence number a reader built from the store now should resume from.
    pub fn last(&self, namespace_id: &str) -> u64 {
        self.namespaces.get(namespace_id).map_or(0, |log| log.last)
    }

    /// The removals recorded after `after`, or `None` when some of them are no
    /// longer retained and the reader has to rebuild from the store.
    pub fn since(&self, namespace_id: &str, after: u64) -> Option<ActionCacheRemovals> {
        let Some(log) = self.namespaces.get(namespace_id) else {
            return Some(ActionCacheRemovals {
                through: after,
                ..Default::default()
            });
        };
        let oldest_retained = log.retained.front().map_or(log.last + 1, |(seq, _)| *seq);
        if after < log.last && after + 1 < oldest_retained {
            return None;
        }
        let mut removals = ActionCacheRemovals {
            through: log.last.max(after),
            ..Default::default()
        };
        for (_, removal) in log.retained.iter().filter(|(seq, _)| *seq > after) {
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
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(byte: u8) -> ActionCacheRemoval {
        ActionCacheRemoval::Entry([byte; 32])
    }

    #[test]
    fn a_reader_gets_only_the_removals_after_its_sequence() {
        let mut log = ActionCacheRemovalLog::new(16);
        log.record("ios", entry(1));
        let resume = log.last("ios");
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

        assert_eq!(removals.through, 3);
        assert_eq!(removals.entries, HashSet::from([[2; 32]]));
        assert_eq!(removals.blobs, HashSet::from([([0xaa; 32], 7)]));
        assert!(log.since("ios", 3).expect("caught up").is_empty());
    }

    #[test]
    fn a_namespace_with_no_removals_is_caught_up() {
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
