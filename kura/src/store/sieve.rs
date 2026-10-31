use std::{collections::HashMap, num::NonZeroU32, sync::Arc};

/// Insertion-ordered SIEVE queue. Hits only set a visited bit; eviction walks
/// from oldest to newest, clearing visited bits until it finds a victim.
/// The caller owns capacity limits and synchronization. Positions are one-based
/// so optional links occupy four bytes and keys share their allocation. The
/// existence cache limits each arena to 2,048 entries.
pub(super) struct SieveCache<V> {
    index: HashMap<Arc<str>, NonZeroU32>,
    entries: Vec<Option<Entry<V>>>,
    free: Vec<NonZeroU32>,
    oldest: Option<NonZeroU32>,
    newest: Option<NonZeroU32>,
    hand: Option<NonZeroU32>,
}

struct Entry<V> {
    key: Arc<str>,
    value: V,
    visited: bool,
    older: Option<NonZeroU32>,
    newer: Option<NonZeroU32>,
}

impl<V> SieveCache<V> {
    pub(super) fn new() -> Self {
        Self {
            index: HashMap::new(),
            entries: Vec::new(),
            free: Vec::new(),
            oldest: None,
            newest: None,
            hand: None,
        }
    }

    pub(super) fn len(&self) -> usize {
        self.index.len()
    }

    pub(super) fn get(&mut self, key: &str) -> Option<&mut V> {
        let position = *self.index.get(key)?;
        let entry = self.entries[position.get() as usize - 1]
            .as_mut()
            .expect("live SIEVE entry");
        entry.visited = true;
        Some(&mut entry.value)
    }

    pub(super) fn insert(&mut self, key: &str, value: V) {
        if let Some(existing) = self.get(key) {
            *existing = value;
            return;
        }

        let key: Arc<str> = Arc::from(key);
        let entry = Some(Entry {
            key: key.clone(),
            value,
            visited: false,
            older: self.newest,
            newer: None,
        });
        let position = if let Some(position) = self.free.pop() {
            self.entries[position.get() as usize - 1] = entry;
            position
        } else {
            self.entries.push(entry);
            Self::position(self.entries.len() - 1)
        };
        if let Some(newest) = self.newest {
            self.entries[newest.get() as usize - 1]
                .as_mut()
                .expect("live SIEVE entry")
                .newer = Some(position);
        } else {
            self.oldest = Some(position);
        }
        self.newest = Some(position);
        self.index.insert(key, position);
    }

    pub(super) fn remove(&mut self, key: &str) -> Option<V> {
        let position = *self.index.get(key)?;
        Some(self.remove_position(position))
    }

    pub(super) fn pop(&mut self) -> Option<V> {
        loop {
            let position = self.hand.or(self.oldest)?;
            let entry = self.entries[position.get() as usize - 1]
                .as_mut()
                .expect("live SIEVE entry");
            self.hand = entry.newer;
            if std::mem::replace(&mut entry.visited, false) {
                continue;
            }
            return Some(self.remove_position(position));
        }
    }

    fn remove_position(&mut self, position: NonZeroU32) -> V {
        let entry = self.entries[position.get() as usize - 1]
            .take()
            .expect("live SIEVE entry");
        self.index.remove(entry.key.as_ref());
        if let Some(older) = entry.older {
            self.entries[older.get() as usize - 1]
                .as_mut()
                .expect("live SIEVE entry")
                .newer = entry.newer;
        } else {
            self.oldest = entry.newer;
        }
        if let Some(newer) = entry.newer {
            self.entries[newer.get() as usize - 1]
                .as_mut()
                .expect("live SIEVE entry")
                .older = entry.older;
        } else {
            self.newest = entry.older;
        }
        if self.hand == Some(position) {
            self.hand = entry.newer;
        }
        self.free.push(position);
        if self.index.is_empty() {
            // Critical-pressure trimming must release the arena and key index.
            *self = Self::new();
        } else if self.entries.len() >= self.index.len().saturating_mul(2) {
            self.compact();
        }
        entry.value
    }

    /// Partial pressure trims and invalidations must not leave a hot survivor
    /// pinning the arena's historical peak. Rebuild only after halving occupancy,
    /// preserving insertion order, visited bits, and the hand's next candidate.
    fn compact(&mut self) {
        let mut entries = Vec::with_capacity(self.index.len());
        let mut current = self.oldest;
        let mut hand = None;
        while let Some(position) = current {
            let mut entry = self.entries[position.get() as usize - 1]
                .take()
                .expect("live SIEVE entry");
            current = entry.newer;
            let next_position = Self::position(entries.len());
            if self.hand == Some(position) {
                hand = Some(next_position);
            }
            entry.older = entries.len().checked_sub(1).map(Self::position);
            entry.newer = current.map(|_| Self::position(entries.len() + 1));
            *self
                .index
                .get_mut(entry.key.as_ref())
                .expect("indexed SIEVE entry") = next_position;
            entries.push(Some(entry));
        }
        self.oldest = Some(Self::position(0));
        self.newest = Some(Self::position(entries.len() - 1));
        self.hand = hand;
        self.entries = entries;
        self.free = Vec::new();
        self.index.shrink_to_fit();
    }

    fn position(index: usize) -> NonZeroU32 {
        NonZeroU32::new(u32::try_from(index + 1).expect("bounded SIEVE arena"))
            .expect("one-based SIEVE position")
    }
}

#[cfg(test)]
mod tests {
    use super::SieveCache;

    #[test]
    fn survivors_stay_in_insertion_order_and_the_hand_wraps() {
        let mut cache = SieveCache::new();
        for key in ["a", "b", "c"] {
            cache.insert(key, key);
        }
        assert_eq!(cache.get("a"), Some(&mut "a"));
        assert_eq!(cache.pop(), Some("b"));
        cache.insert("d", "d");
        assert_eq!(cache.get("c"), Some(&mut "c"));
        // FIFO-reinsertion/CLOCK would evict a here, not d.
        assert_eq!(cache.pop(), Some("d"));
        assert_eq!(cache.pop(), Some("a"));
        assert_eq!(cache.pop(), Some("c"));
        assert_eq!(cache.pop(), None);
    }

    #[test]
    fn updates_and_removals_preserve_the_eviction_hand() {
        let mut cache = SieveCache::new();
        for key in ["a", "b", "c", "d"] {
            cache.insert(key, key);
        }
        cache.insert("a", "updated");
        assert_eq!(cache.pop(), Some("b"));
        assert_eq!(cache.remove("c"), Some("c")); // the hand's candidate
        assert_eq!(cache.remove("a"), Some("updated")); // oldest
        cache.insert("e", "e"); // reuse a vacant slot
        assert_eq!(cache.remove("e"), Some("e")); // newest
        assert_eq!(cache.get("d"), Some(&mut "d"));
        assert_eq!(cache.pop(), Some("d")); // all visited, wrap to evict
        cache.insert("f", "f");
        assert_eq!(cache.len(), 1);
        assert_eq!(cache.pop(), Some("f"));
        assert_eq!(cache.remove("missing"), None);
    }

    #[test]
    fn partial_invalidation_preserves_the_hand_and_second_chances() {
        let mut cache = SieveCache::new();
        for key in ["a", "b", "c", "d", "e", "f", "g", "h"] {
            cache.insert(key, key);
        }
        cache.get("a");
        assert_eq!(cache.pop(), Some("b"));
        cache.get("c");
        // Cross the sparse-arena threshold with a nonempty cache and a hand
        // away from the oldest entry. Packing must preserve that candidate.
        for key in ["d", "e", "f", "g"] {
            assert_eq!(cache.remove(key), Some(key));
        }
        assert_eq!(cache.pop(), Some("h"));
        assert_eq!(cache.pop(), Some("a"));
        assert_eq!(cache.pop(), Some("c"));
    }
}
