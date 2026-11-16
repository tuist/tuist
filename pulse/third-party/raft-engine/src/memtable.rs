// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use std::borrow::BorrowMut;
use std::collections::{BTreeMap, HashSet, VecDeque};
use std::marker::PhantomData;
use std::ops::Bound;
use std::sync::Arc;

use fail::fail_point;
use hashbrown::HashMap;
use log::{error, warn};
use parking_lot::{Mutex, RwLock};

use crate::config::Config;
use crate::file_pipe_log::ReplayMachine;
use crate::log_batch::{
    AtomicGroupStatus, Command, CompressionType, KeyValue, LogBatch, LogItem, LogItemBatch,
    LogItemContent, OpType,
};
use crate::metrics::MEMORY_USAGE;
use crate::pipe_log::{FileBlockHandle, FileId, FileSeq, LogQueue};
use crate::util::{hash_u64, Factory};
use crate::{Error, GlobalStats, Result};

#[cfg(feature = "swap")]
mod swap_conditional_imports {
    use crate::swappy_allocator::SwappyAllocator;
    use std::convert::TryFrom;
    use std::path::Path;

    pub trait AllocatorTrait: std::alloc::Allocator + Clone + Send + Sync {}
    impl<T: std::alloc::Allocator + Clone + Send + Sync> AllocatorTrait for T {}

    pub type VacantAllocator = std::alloc::Global;
    pub type SelectedAllocator = SwappyAllocator<std::alloc::Global>;

    pub fn new_vacant_allocator() -> VacantAllocator {
        std::alloc::Global
    }
    pub fn new_allocator(cfg: &crate::Config) -> SelectedAllocator {
        let memory_limit =
            usize::try_from(cfg.memory_limit.map_or(u64::MAX, |l| l.0)).unwrap_or(usize::MAX);
        let path = Path::new(&cfg.dir).join("swap");
        SwappyAllocator::new(&path, memory_limit)
    }
}

#[cfg(not(feature = "swap"))]
mod swap_conditional_imports {
    pub trait AllocatorTrait: Clone + Send + Sync {}

    #[derive(Clone)]
    pub struct DummyAllocator;
    impl AllocatorTrait for DummyAllocator {}

    pub type VacantAllocator = DummyAllocator;
    pub type SelectedAllocator = DummyAllocator;

    pub fn new_vacant_allocator() -> VacantAllocator {
        DummyAllocator
    }
    pub fn new_allocator(_: &crate::Config) -> SelectedAllocator {
        DummyAllocator
    }
}

use swap_conditional_imports::*;

/// Attempt to shrink entry container if its capacity reaches the threshold.
const CAPACITY_SHRINK_THRESHOLD: usize = 1024 - 1;
const CAPACITY_INIT: usize = 32 - 1;
/// Number of hash table to store [`MemTable`].
const MEMTABLE_SLOT_COUNT: usize = 128;

/// Location of a log entry.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub struct EntryIndex {
    /// Logical index.
    pub index: u64,

    /// File location of the group of entries that this entry belongs to.
    pub entries: Option<FileBlockHandle>,
    // How its group of entries is compacted.
    pub compression_type: CompressionType,

    /// The relative offset within its group of entries.
    pub entry_offset: u32,
    /// The encoded length within its group of entries.
    pub entry_len: u32,
}

impl Default for EntryIndex {
    fn default() -> EntryIndex {
        EntryIndex {
            index: 0,
            entries: None,
            compression_type: CompressionType::None,
            entry_offset: 0,
            entry_len: 0,
        }
    }
}

impl EntryIndex {
    fn from_thin(index: u64, e: ThinEntryIndex) -> Self {
        Self {
            index,
            entries: e.entries,
            compression_type: e.compression_type,
            entry_offset: e.entry_offset,
            entry_len: e.entry_len,
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
struct ThinEntryIndex {
    entries: Option<FileBlockHandle>,
    compression_type: CompressionType,
    entry_offset: u32,
    entry_len: u32,
}

impl From<&EntryIndex> for ThinEntryIndex {
    fn from(e: &EntryIndex) -> Self {
        Self {
            entries: e.entries,
            compression_type: e.compression_type,
            entry_offset: e.entry_offset,
            entry_len: e.entry_len,
        }
    }
}

/// In-memory storage for Raft Groups.
///
/// Each Raft Group has its own `MemTable` to store all key value pairs and the
/// file locations of all log entries.
pub struct MemTable<A: AllocatorTrait> {
    /// The ID of current Raft Group.
    region_id: u64,

    /// Container of entries. Incoming entries are pushed to the back with
    /// ascending log indexes.
    #[cfg(feature = "swap")]
    entry_indexes: VecDeque<ThinEntryIndex, A>,
    #[cfg(not(feature = "swap"))]
    entry_indexes: VecDeque<ThinEntryIndex>,
    /// The log index of the first entry.
    first_index: u64,
    /// The amount of rewritten entries. Rewritten entries are the oldest
    /// entries and stored at the front of the container.
    rewrite_count: usize,

    /// A map of active key value pairs.
    kvs: BTreeMap<Vec<u8>, (Vec<u8>, FileId)>,

    /// (start_seq, end_seq).
    /// If there's an active entry stored before end_seq, it possibly belongs to
    /// an atomic group. In order to not lose this entry, We cannot delete any
    /// other entries in that group.
    /// Only applies to Rewrite queue. Each Raft Group has at most one atomic
    /// group at a time, because we only use atomic group for rewrite-rewrite
    /// operation, a group always contains all the Rewrite entries in a Raft
    /// Group.
    atomic_group: Option<(FileSeq, FileSeq)>,

    /// Shared statistics.
    global_stats: Arc<GlobalStats>,

    _phantom: PhantomData<A>,
}

impl MemTable<VacantAllocator> {
    #[allow(dead_code)]
    fn new(region_id: u64, global_stats: Arc<GlobalStats>) -> MemTable<VacantAllocator> {
        Self::with_allocator(region_id, global_stats, &new_vacant_allocator())
    }
}

impl<A: AllocatorTrait> MemTable<A> {
    fn with_allocator(
        region_id: u64,
        global_stats: Arc<GlobalStats>,
        _allocator: &A,
    ) -> MemTable<A> {
        MemTable {
            region_id,
            #[cfg(feature = "swap")]
            entry_indexes: VecDeque::with_capacity_in(CAPACITY_INIT, _allocator.clone()),
            #[cfg(not(feature = "swap"))]
            entry_indexes: VecDeque::with_capacity(CAPACITY_INIT),
            first_index: 0,
            rewrite_count: 0,
            kvs: BTreeMap::default(),
            atomic_group: None,
            global_stats,
            _phantom: PhantomData,
        }
    }

    /// Merges with a newer neighbor [`MemTable`].
    ///
    /// This method is only used for recovery.
    pub fn merge_newer_neighbor(&mut self, rhs: &mut Self) {
        debug_assert_eq!(self.region_id, rhs.region_id);
        if let Some((rhs_first, _)) = rhs.span() {
            self.prepare_append(
                rhs_first,
                // Rewrite -> Compact Append -> Rewrite.
                // TODO: add test case.
                rhs.rewrite_count > 0, /* allow_hole */
                // Always true, because `self` might not have all entries in
                // history.
                true, /* allow_overwrite */
            );
            self.global_stats.add(
                rhs.entry_indexes[0].entries.unwrap().id.queue,
                rhs.entry_indexes.len(),
            );
            self.rewrite_count += rhs.rewrite_count;
            self.entry_indexes.append(&mut rhs.entry_indexes);
            rhs.rewrite_count = 0;
        }

        for (key, (value, file_id)) in rhs.kvs.iter() {
            self.put(key.clone(), value.clone(), *file_id);
        }

        if let Some(g) = rhs.atomic_group.take() {
            assert!(self.atomic_group.map_or(true, |(_, end)| end <= g.0));
            self.atomic_group = Some(g);
        }

        let deleted = rhs.global_stats.deleted_rewrite_entries();
        self.global_stats.add(LogQueue::Rewrite, deleted);
        self.global_stats.delete(LogQueue::Rewrite, deleted);
    }

    /// Merges with a [`MemTable`] that contains only append data. Assumes
    /// `self` contains all rewritten data of the same region.
    ///
    /// This method is only used for recovery.
    pub fn merge_append_table(&mut self, rhs: &mut Self) {
        debug_assert_eq!(self.region_id, rhs.region_id);
        debug_assert_eq!(self.rewrite_count, self.entry_indexes.len());
        debug_assert_eq!(rhs.rewrite_count, 0);

        if let Some((first, _)) = rhs.span() {
            self.prepare_append(
                first,
                // FIXME: It's possibly okay to set it to false. Any compact
                // command applied to append queue will also be applied to
                // rewrite queue.
                true, /* allow_hole */
                // Compact -> Rewrite -> Data loss of the compact command.
                true, /* allow_overwrite */
            );
            self.global_stats.add(
                rhs.entry_indexes[0].entries.unwrap().id.queue,
                rhs.entry_indexes.len(),
            );
            self.entry_indexes.append(&mut rhs.entry_indexes);
        }

        for (key, (value, file_id)) in rhs.kvs.iter() {
            self.put(key.clone(), value.clone(), *file_id);
        }

        assert!(rhs.atomic_group.is_none());

        let deleted = rhs.global_stats.deleted_rewrite_entries();
        self.global_stats.add(LogQueue::Rewrite, deleted);
        self.global_stats.delete(LogQueue::Rewrite, deleted);
    }

    /// Returns value for a given key.
    pub fn get(&self, key: &[u8]) -> Option<Vec<u8>> {
        self.kvs.get(key).map(|v| v.0.clone())
    }

    /// Iterates over [start_key, end_key) range and yields all key value pairs
    /// as bytes.
    pub fn scan<F>(
        &self,
        start_key: Option<&[u8]>,
        end_key: Option<&[u8]>,
        reverse: bool,
        mut f: F,
    ) -> Result<()>
    where
        F: FnMut(&[u8], &[u8]) -> bool,
    {
        let lower = start_key.map(Bound::Included).unwrap_or(Bound::Unbounded);
        let upper = end_key.map(Bound::Excluded).unwrap_or(Bound::Unbounded);
        let iter = self.kvs.range::<[u8], _>((lower, upper));
        if reverse {
            for (key, (value, _)) in iter.rev() {
                if !f(key, value) {
                    break;
                }
            }
        } else {
            for (key, (value, _)) in iter {
                if !f(key, value) {
                    break;
                }
            }
        }
        Ok(())
    }

    /// Deletes a key value pair.
    pub fn delete(&mut self, key: &[u8]) {
        if let Some(value) = self.kvs.remove(key) {
            self.global_stats.delete(value.1.queue, 1);
        }
    }

    /// Puts a key value pair that has been written to the specified file. The
    /// old value for this key will be deleted if exists.
    pub fn put(&mut self, key: Vec<u8>, value: Vec<u8>, file_id: FileId) {
        if let Some(origin) = self.kvs.insert(key, (value, file_id)) {
            self.global_stats.delete(origin.1.queue, 1);
        }
        self.global_stats.add(file_id.queue, 1);
    }

    /// Rewrites a key by marking its location to the `seq`-th log file in
    /// rewrite queue. No-op if the key does not exist.
    ///
    /// When `gate` is present, only append data no newer than it will be
    /// rewritten.
    pub fn rewrite_key(&mut self, key: Vec<u8>, gate: Option<FileSeq>, seq: FileSeq) {
        self.global_stats.add(LogQueue::Rewrite, 1);
        if let Some(origin) = self.kvs.get_mut(&key) {
            if origin.1.queue == LogQueue::Append {
                if let Some(gate) = gate {
                    if origin.1.seq <= gate {
                        origin.1 = FileId {
                            queue: LogQueue::Rewrite,
                            seq,
                        };
                        self.global_stats.delete(LogQueue::Append, 1);
                        return;
                    }
                }
            } else {
                assert!(origin.1.seq <= seq);
                origin.1.seq = seq;
            }
        }
        self.global_stats.delete(LogQueue::Rewrite, 1);
    }

    /// Returns the log entry location for a given logical log index.
    pub fn get_entry(&self, index: u64) -> Option<EntryIndex> {
        if let Some((first, last)) = self.span() {
            if index < first || index > last {
                return None;
            }

            let ioffset = (index - first) as usize;
            let entry_index = self.entry_indexes[ioffset];
            Some(EntryIndex::from_thin(index, entry_index))
        } else {
            None
        }
    }

    /// Appends some log entries from append queue. Existing entries newer than
    /// any of the incoming entries will be deleted silently. Assumes the
    /// provided entries have consecutive logical indexes.
    ///
    /// # Panics
    ///
    /// Panics if index of the first entry in `entry_indexes` is greater than
    /// largest existing index + 1 (hole).
    ///
    /// Panics if incoming entries contains indexes that might be compacted
    /// before (overwrite history).
    pub fn append(&mut self, entry_indexes: Vec<EntryIndex>) {
        let len = entry_indexes.len();
        if len > 0 {
            self.prepare_append(
                entry_indexes[0].index,
                false, /* allow_hole */
                false, /* allow_overwrite */
            );
            self.global_stats.add(LogQueue::Append, len);
            for ei in &entry_indexes {
                self.entry_indexes.push_back(ei.into());
            }
        }
    }

    /// Appends some entries from append queue. Assumes this table has no
    /// rewrite data.
    ///
    /// This method is only used for recovery.
    pub fn replay_append(&mut self, entry_indexes: Vec<EntryIndex>) {
        let len = entry_indexes.len();
        if len > 0 {
            debug_assert_eq!(self.rewrite_count, 0);
            self.prepare_append(
                entry_indexes[0].index,
                false, /* allow_hole */
                // Refer to case in `merge_newer_neighbor`.
                true, /* allow_overwrite */
            );
            self.global_stats.add(LogQueue::Append, len);
            for ei in &entry_indexes {
                debug_assert_eq!(ei.entries.unwrap().id.queue, LogQueue::Append);
                self.entry_indexes.push_back(ei.into());
            }
        }
    }

    /// Rewrites some entries by modifying their location.
    ///
    /// When `gate` is present, only append data no newer than it will be
    /// rewritten.
    ///
    /// # Panics
    ///
    /// Panics if index of the first entry in `rewrite_indexes` is greater than
    /// largest existing rewritten index + 1 (hole).
    pub fn rewrite(&mut self, rewrite_indexes: Vec<EntryIndex>, gate: Option<FileSeq>) {
        if rewrite_indexes.is_empty() {
            return;
        }
        self.global_stats
            .add(LogQueue::Rewrite, rewrite_indexes.len());

        let len = self.entry_indexes.len();
        if len == 0 {
            self.global_stats
                .delete(LogQueue::Rewrite, rewrite_indexes.len());
            return;
        }

        let first = self.first_index;
        let last = self.first_index + len as u64 - 1;
        let rewrite_first = std::cmp::max(rewrite_indexes[0].index, first);
        let rewrite_last = std::cmp::min(rewrite_indexes[rewrite_indexes.len() - 1].index, last);
        let mut rewrite_len = (rewrite_last + 1).saturating_sub(rewrite_first) as usize;
        if rewrite_len == 0 {
            self.global_stats
                .delete(LogQueue::Rewrite, rewrite_indexes.len());
            return;
        }

        let pos = (rewrite_first - first) as usize;
        // No normal log entry mixed in rewritten entries at the front.
        assert!(
            pos == 0 || self.entry_indexes[pos - 1].entries.unwrap().id.queue == LogQueue::Rewrite
        );
        let rewrite_pos = (rewrite_first - rewrite_indexes[0].index) as usize;

        for (i, rindex) in rewrite_indexes[rewrite_pos..rewrite_pos + rewrite_len]
            .iter()
            .enumerate()
        {
            let index = &mut self.entry_indexes[i + pos];
            if let Some(gate) = gate {
                debug_assert_eq!(index.entries.unwrap().id.queue, LogQueue::Append);
                if index.entries.unwrap().id.seq > gate {
                    // Some entries are overwritten by new appends.
                    rewrite_len = i;
                    break;
                }
            } else if index.entries.unwrap().id.queue == LogQueue::Append {
                // Squeeze operation encounters a new append.
                rewrite_len = i;
                break;
            }

            *index = rindex.into();
        }

        if gate.is_none() {
            // We either replaced some old rewrite entries, or some incoming entries are
            // discarded.
            self.global_stats
                .delete(LogQueue::Rewrite, rewrite_indexes.len());
            // rewrite-rewrite could partially renew rewrite entries due to batch splitting.
            self.rewrite_count = std::cmp::max(self.rewrite_count, pos + rewrite_len);
        } else {
            self.global_stats.delete(LogQueue::Append, rewrite_len);
            self.global_stats
                .delete(LogQueue::Rewrite, rewrite_indexes.len() - rewrite_len);
            // rewrite-append always push forward.
            assert!(pos + rewrite_len >= self.rewrite_count);
            self.rewrite_count = pos + rewrite_len;
        }
    }

    /// Appends some entries from rewrite queue. Assumes this table has no
    /// append data.
    ///
    /// This method is only used for recovery.
    pub fn replay_rewrite(&mut self, entry_indexes: Vec<EntryIndex>) {
        let len = entry_indexes.len();
        if len > 0 {
            debug_assert_eq!(self.rewrite_count, self.entry_indexes.len());
            self.prepare_append(
                entry_indexes[0].index,
                // Rewrite -> Compact Append -> Rewrite.
                true, /* allow_hole */
                // Refer to case in `merge_append_table`. They can be adapted
                // to attack this path via a global rewrite without deleting
                // obsolete rewrite files.
                true, /* allow_overwrite */
            );
            self.global_stats.add(LogQueue::Rewrite, len);
            for ei in &entry_indexes {
                self.entry_indexes.push_back(ei.into());
            }
            self.rewrite_count = self.entry_indexes.len();
        }
    }

    /// Removes all entries with index smaller than `index`. Returns the number
    /// of deleted entries.
    pub fn compact_to(&mut self, index: u64) -> u64 {
        if self.entry_indexes.is_empty() {
            return 0;
        }
        let first = self.first_index;
        if index <= first {
            return 0;
        }
        let count = std::cmp::min((index - first) as usize, self.entry_indexes.len());
        self.first_index = index;
        self.entry_indexes.drain(..count);
        self.maybe_shrink_entry_indexes();

        let compacted_rewrite = std::cmp::min(count, self.rewrite_count);
        self.rewrite_count -= compacted_rewrite;
        self.global_stats
            .delete(LogQueue::Rewrite, compacted_rewrite);
        self.global_stats
            .delete(LogQueue::Append, count - compacted_rewrite);
        count as u64
    }

    pub fn apply_rewrite_atomic_group(&mut self, start: FileSeq, end: FileSeq) {
        assert!(self.atomic_group.map_or(true, |(_, b)| b <= start));
        self.atomic_group = Some((start, end));
    }

    /// Removes all entry indexes with index greater than or equal to `index`.
    /// Assumes `index` <= `last`.
    ///
    /// Returns the number of deleted entries.
    fn unsafe_truncate_back(&mut self, first: u64, index: u64, last: u64) -> usize {
        debug_assert!(index <= last);
        let len = self.entry_indexes.len();
        debug_assert_eq!(len as u64, last - first + 1);
        self.entry_indexes
            .truncate(index.saturating_sub(first) as usize);
        let new_len = self.entry_indexes.len();
        let truncated = len - new_len;

        if self.rewrite_count > new_len {
            let truncated_rewrite = self.rewrite_count - new_len;
            self.rewrite_count = new_len;
            self.global_stats
                .delete(LogQueue::Rewrite, truncated_rewrite);
            self.global_stats
                .delete(LogQueue::Append, truncated - truncated_rewrite);
        } else {
            self.global_stats.delete(LogQueue::Append, truncated);
        }
        truncated
    }

    /// Prepares to append entries with indexes starting at
    /// `first_index_to_add`. After preparation, those entries can be directly
    /// appended to internal container.
    ///
    /// When `allow_hole` is set, existing entries will be removes if there is a
    /// hole detected. Otherwise, panic.
    ///
    /// When `allow_overwrite_compacted` is set, existing entries will be
    /// removes if incoming entries attempt to overwrite compacted slots.
    /// Otherwise, panic.
    #[inline]
    fn prepare_append(
        &mut self,
        first_index_to_add: u64,
        allow_hole: bool,
        allow_overwrite_compacted: bool,
    ) {
        if let Some((first, last)) = self.span() {
            if first_index_to_add < first {
                if allow_overwrite_compacted {
                    self.unsafe_truncate_back(first, 0, last);
                } else {
                    panic!(
                        "attempt to overwrite compacted entries in {}",
                        self.region_id
                    );
                }
                self.first_index = first_index_to_add;
            } else if last + 1 < first_index_to_add {
                if allow_hole {
                    self.unsafe_truncate_back(first, 0, last);
                } else {
                    panic!("memtable {} has a hole", self.region_id);
                }
                self.first_index = first_index_to_add;
            } else if first_index_to_add != last + 1 {
                self.unsafe_truncate_back(first, first_index_to_add, last);
            }
        } else {
            self.first_index = first_index_to_add;
        }
    }

    #[inline]
    fn maybe_shrink_entry_indexes(&mut self) {
        if self.entry_indexes.capacity() >= CAPACITY_SHRINK_THRESHOLD {
            self.entry_indexes.shrink_to_fit();
        }
    }

    /// Pulls all entries between log index `begin` and `end` to the given
    /// buffer. Returns error if any entry is missing.
    ///
    /// When `max_size` is present, stops pulling entries when the total size
    /// reaches it.
    pub fn fetch_entries_to(
        &self,
        begin: u64,
        end: u64,
        max_size: Option<usize>,
        vec_idx: &mut Vec<EntryIndex>,
    ) -> Result<()> {
        if end <= begin {
            return Ok(());
        }
        let len = self.entry_indexes.len();
        if len == 0 {
            return Err(Error::EntryNotFound);
        }
        let first = self.first_index;
        if begin < first {
            return Err(Error::EntryCompacted);
        }
        if end > self.first_index + len as u64 {
            return Err(Error::EntryNotFound);
        }

        let start_pos = (begin - first) as usize;
        let end_pos = (end - begin) as usize + start_pos;

        let mut total_size = 0;
        let mut index = begin;
        for idx in self.entry_indexes.range(start_pos..end_pos) {
            total_size += idx.entry_len;
            // No matter max_size's value, fetch one entry at least.
            if let Some(max_size) = max_size {
                if total_size as usize > max_size && total_size > idx.entry_len {
                    break;
                }
            }
            vec_idx.push(EntryIndex::from_thin(index, *idx));
            index += 1;
        }
        Ok(())
    }

    /// Pulls all append entries older than or equal to `gate`, to the provided
    /// buffer.
    pub fn fetch_entry_indexes_before(
        &self,
        gate: FileSeq,
        vec_idx: &mut Vec<EntryIndex>,
    ) -> Result<()> {
        if let Some((first, last)) = self.span() {
            let mut i = self.rewrite_count;
            while first + i as u64 <= last && self.entry_indexes[i].entries.unwrap().id.seq <= gate
            {
                vec_idx.push(EntryIndex::from_thin(
                    first + i as u64,
                    self.entry_indexes[i],
                ));
                i += 1;
            }
        }
        Ok(())
    }

    /// Pulls all rewrite entries to the provided buffer.
    pub fn fetch_rewritten_entry_indexes(&self, vec_idx: &mut Vec<EntryIndex>) -> Result<()> {
        if self.rewrite_count > 0 {
            let first = self.first_index;
            let end = self.first_index + self.rewrite_count as u64;
            self.fetch_entries_to(first, end, None, vec_idx)
        } else {
            Ok(())
        }
    }

    /// Pulls all key value pairs older than or equal to `gate`, to the provided
    /// buffer.
    pub fn fetch_kvs_before(&self, gate: FileSeq, vec: &mut Vec<(Vec<u8>, Vec<u8>)>) {
        for (key, (value, file_id)) in &self.kvs {
            if file_id.queue == LogQueue::Append && file_id.seq <= gate {
                vec.push((key.clone(), value.clone()));
            }
        }
    }

    /// Pulls all rewrite key value pairs to the provided buffer.
    pub fn fetch_rewritten_kvs(&self, vec: &mut Vec<(Vec<u8>, Vec<u8>)>) {
        for (key, (value, file_id)) in &self.kvs {
            if file_id.queue == LogQueue::Rewrite {
                vec.push((key.clone(), value.clone()));
            }
        }
    }

    /// Returns the smallest file sequence number of entries or key value pairs
    /// in this table.
    pub fn min_file_seq(&self, queue: LogQueue) -> Option<FileSeq> {
        let entry = match queue {
            LogQueue::Append => self.entry_indexes.get(self.rewrite_count),
            LogQueue::Rewrite if self.rewrite_count == 0 => None,
            LogQueue::Rewrite => self.entry_indexes.front(),
        };
        let ents_min = entry.map(|e| e.entries.unwrap().id.seq);
        let kvs_min = self
            .kvs
            .values()
            .filter(|v| v.1.queue == queue)
            .fold(None, |min, v| {
                if let Some(min) = min {
                    Some(std::cmp::min(min, v.1.seq))
                } else {
                    Some(v.1.seq)
                }
            });
        let res = match (ents_min, kvs_min) {
            (Some(ents_min), Some(kvs_min)) => std::cmp::min(kvs_min, ents_min),
            (Some(ents_min), None) => ents_min,
            (None, Some(kvs_min)) => kvs_min,
            (None, None) => return None,
        };
        if queue == LogQueue::Rewrite {
            if let Some((start, end)) = self.atomic_group {
                if res <= end {
                    return Some(std::cmp::min(start, res));
                }
            }
        }
        Some(res)
    }

    #[inline]
    pub fn has_at_least_some_entries_before(&self, gate: FileId, count: usize) -> bool {
        debug_assert!(count > 0);
        self.entry_indexes
            .get(count - 1)
            .map_or(false, |ei| ei.entries.unwrap().id.seq <= gate.seq)
    }

    /// Returns the region ID.
    pub fn region_id(&self) -> u64 {
        self.region_id
    }

    pub(crate) fn rewrite_count(&self) -> usize {
        self.rewrite_count
    }

    /// Returns the log index of the first log entry.
    pub fn first_index(&self) -> Option<u64> {
        self.span().map(|s| s.0)
    }

    /// Returns the log index of the last log entry.
    pub fn last_index(&self) -> Option<u64> {
        self.span().map(|s| s.1)
    }

    #[allow(dead_code)]
    fn heap_size(&self) -> usize {
        // FIXME: cover the map of kvs.
        self.entry_indexes.capacity() * std::mem::size_of::<EntryIndex>()
    }

    /// Returns the first and last log index of the entries in this table.
    #[inline]
    fn span(&self) -> Option<(u64, u64)> {
        let len = self.entry_indexes.len();
        if len > 0 {
            Some((self.first_index, self.first_index + len as u64 - 1))
        } else {
            None
        }
    }

    #[cfg(test)]
    fn consistency_check(&self) {
        let mut seen_append = false;
        for idx in self.entry_indexes.iter() {
            // rewrites are at the front.
            let queue = idx.entries.unwrap().id.queue;
            if queue == LogQueue::Append {
                seen_append = true;
            }
            assert_eq!(
                queue,
                if seen_append {
                    LogQueue::Append
                } else {
                    LogQueue::Rewrite
                }
            );
        }
    }
}

impl<A: AllocatorTrait> Drop for MemTable<A> {
    fn drop(&mut self) {
        let mut append_kvs = 0;
        let mut rewrite_kvs = 0;
        for (_v, id) in self.kvs.values() {
            match id.queue {
                LogQueue::Rewrite => rewrite_kvs += 1,
                LogQueue::Append => append_kvs += 1,
            }
        }

        self.global_stats
            .delete(LogQueue::Rewrite, self.rewrite_count + rewrite_kvs);
        self.global_stats.delete(
            LogQueue::Append,
            self.entry_indexes.len() - self.rewrite_count + append_kvs,
        );
    }
}

type MemTableMap<A> = HashMap<u64, Arc<RwLock<MemTable<A>>>>;
pub type MemTableHandle = Arc<RwLock<MemTable<SelectedAllocator>>>;
pub type MemTables = MemTableAccessor<SelectedAllocator>;

/// A collection of [`MemTable`]s.
///
/// Internally, they are stored in multiple [`HashMap`]s, which are indexed by
/// hashed region IDs.
#[derive(Clone)]
pub struct MemTableAccessor<A: AllocatorTrait> {
    global_stats: Arc<GlobalStats>,
    allocator: A,

    /// A fixed-size array of maps of [`MemTable`]s.
    slots: Vec<Arc<RwLock<MemTableMap<A>>>>,
    /// Deleted [`MemTable`]s that are not yet rewritten.
    removed_memtables: Arc<Mutex<VecDeque<u64>>>,
}

impl MemTableAccessor<VacantAllocator> {
    pub fn new(global_stats: Arc<GlobalStats>) -> MemTableAccessor<VacantAllocator> {
        let mut slots = Vec::with_capacity(MEMTABLE_SLOT_COUNT);
        for _ in 0..MEMTABLE_SLOT_COUNT {
            slots.push(Arc::new(RwLock::new(MemTableMap::default())));
        }
        MemTableAccessor {
            global_stats,
            allocator: new_vacant_allocator(),
            slots,
            removed_memtables: Default::default(),
        }
    }
}

impl MemTableAccessor<SelectedAllocator> {
    pub fn memory_usage(&self) -> usize {
        #[cfg(not(feature = "swap"))]
        {
            let mut total = 0;
            for tables in &self.slots {
                tables.read().values().for_each(|t| {
                    total += t.read().heap_size();
                });
            }
            total
        }
        #[cfg(feature = "swap")]
        {
            self.allocator.memory_usage()
        }
    }

    pub(crate) fn flush_metrics(&self) {
        MEMORY_USAGE.set(self.memory_usage() as i64);
    }
}

impl<A: AllocatorTrait> MemTableAccessor<A> {
    pub fn new_with_allocator(global_stats: Arc<GlobalStats>, allocator: A) -> MemTableAccessor<A> {
        let mut slots = Vec::with_capacity(MEMTABLE_SLOT_COUNT);
        for _ in 0..MEMTABLE_SLOT_COUNT {
            slots.push(Arc::new(RwLock::new(MemTableMap::default())));
        }
        MemTableAccessor {
            global_stats,
            allocator,
            slots,
            removed_memtables: Default::default(),
        }
    }

    pub fn get_or_insert(&self, raft_group_id: u64) -> Arc<RwLock<MemTable<A>>> {
        let global_stats = self.global_stats.clone();
        let mut memtables = self.slots[Self::slot_index(raft_group_id)].write();
        let memtable = memtables.entry(raft_group_id).or_insert_with(|| {
            let memtable =
                MemTable::with_allocator(raft_group_id, global_stats.clone(), &self.allocator);
            Arc::new(RwLock::new(memtable))
        });
        memtable.clone()
    }

    pub fn get(&self, raft_group_id: u64) -> Option<Arc<RwLock<MemTable<A>>>> {
        self.slots[Self::slot_index(raft_group_id)]
            .read()
            .get(&raft_group_id)
            .cloned()
    }

    pub fn insert(&self, raft_group_id: u64, memtable: Arc<RwLock<MemTable<A>>>) {
        self.slots[Self::slot_index(raft_group_id)]
            .write()
            .insert(raft_group_id, memtable);
    }

    pub fn remove(&self, raft_group_id: u64, record_tombstone: bool) {
        self.slots[Self::slot_index(raft_group_id)]
            .write()
            .remove(&raft_group_id);
        if record_tombstone {
            let mut removed_memtables = self.removed_memtables.lock();
            removed_memtables.push_back(raft_group_id);
        }
    }

    pub fn fold<B, F: Fn(B, &MemTable<A>) -> B>(&self, mut init: B, fold: F) -> B {
        for tables in &self.slots {
            for memtable in tables.read().values() {
                init = fold(init, &*memtable.read());
            }
        }
        init
    }

    pub fn collect<F: FnMut(&MemTable<A>) -> bool>(
        &self,
        mut condition: F,
    ) -> Vec<Arc<RwLock<MemTable<A>>>> {
        let mut memtables = Vec::new();
        for tables in &self.slots {
            memtables.extend(tables.read().values().filter_map(|t| {
                if condition(&*t.read()) {
                    return Some(t.clone());
                }
                None
            }));
        }
        memtables
    }

    /// Returns a [`LogBatch`] containing `Command::Clean`s of all deleted
    /// [`MemTable`]s. The records for these tables will be cleaned up
    /// afterwards.
    pub fn take_cleaned_region_logs(&self) -> LogBatch {
        let mut log_batch = LogBatch::default();
        let mut removed_memtables = self.removed_memtables.lock();
        for id in removed_memtables.drain(..) {
            log_batch.add_command(id, Command::Clean);
        }
        log_batch
    }

    /// Returns a [`HashSet`] containing region IDs of all deleted
    /// [`MemTable`]s.
    ///
    /// This method is only used for recovery.
    #[cfg(test)]
    pub fn cleaned_region_ids(&self) -> HashSet<u64> {
        let mut ids = HashSet::default();
        let removed_memtables = self.removed_memtables.lock();
        for raft_id in removed_memtables.iter() {
            ids.insert(*raft_id);
        }
        ids
    }

    /// Returns `true` if it does not contains any memtable.
    pub fn is_empty(&self) -> bool {
        for i in 0..MEMTABLE_SLOT_COUNT {
            if !self.slots[i].read().is_empty() {
                return false;
            }
        }
        true
    }

    /// Merges with a newer neighbor [`MemTableAccessor`].
    ///
    /// This method is only used for recovery.
    pub fn merge_newer_neighbor(&self, mut rhs: Self) {
        for slot in rhs.slots.iter_mut() {
            for (raft_group_id, memtable) in slot.write().drain() {
                self.get_or_insert(raft_group_id)
                    .write()
                    .merge_newer_neighbor(memtable.write().borrow_mut());
            }
        }
        // Discarding neighbor's tombstones, they will be applied by
        // `MemTableRecoverContext`.
    }

    /// Merges with a [`MemTableAccessor`] that contains only append data.
    /// Assumes `self` contains all rewritten data.
    ///
    /// This method is only used for recovery.
    pub fn merge_append_table(&self, mut rhs: Self) {
        for slot in rhs.slots.iter_mut() {
            for (id, memtable) in std::mem::take(&mut *slot.write()) {
                if let Some(existing_memtable) = self.get(id) {
                    existing_memtable
                        .write()
                        .merge_append_table(&mut *memtable.write());
                } else {
                    self.insert(id, memtable);
                }
            }
        }
        // Tombstones from both table are identical.
        debug_assert_eq!(
            self.removed_memtables.lock().len(),
            rhs.removed_memtables.lock().len()
        );
    }

    /// Applies changes from log items that have been written to append queue.
    pub fn apply_append_writes(&self, log_items: impl Iterator<Item = LogItem>) {
        for item in log_items {
            if has_internal_key(&item) {
                continue;
            }
            let raft = item.raft_group_id;
            let memtable = self.get_or_insert(raft);
            fail_point!(
                "memtable_accessor::apply_append_writes::region_3",
                raft == 3,
                |_| {}
            );
            match item.content {
                LogItemContent::EntryIndexes(entries_to_add) => {
                    memtable.write().append(entries_to_add.0);
                }
                LogItemContent::Command(Command::Clean) => {
                    self.remove(raft, true /* record_tombstone */);
                }
                LogItemContent::Command(Command::Compact { index }) => {
                    memtable.write().compact_to(index);
                }
                LogItemContent::Kv(kv) => match kv.op_type {
                    OpType::Put => {
                        let value = kv.value.unwrap();
                        memtable.write().put(kv.key, value, kv.file_id.unwrap());
                    }
                    OpType::Del => {
                        let key = kv.key;
                        memtable.write().delete(key.as_slice());
                    }
                },
            }
        }
    }

    /// Applies changes from log items that are replayed from a append queue.
    /// Assumes it haven't applied any rewrite data.
    ///
    /// This method is only used for recovery.
    pub fn replay_append_writes(&self, log_items: impl Iterator<Item = LogItem>) {
        for item in log_items {
            if has_internal_key(&item) {
                continue;
            }
            let raft = item.raft_group_id;
            let memtable = self.get_or_insert(raft);
            match item.content {
                LogItemContent::EntryIndexes(entries_to_add) => {
                    memtable.write().replay_append(entries_to_add.0);
                }
                LogItemContent::Command(Command::Clean) => {
                    self.remove(raft, true /* record_tombstone */);
                }
                LogItemContent::Command(Command::Compact { index }) => {
                    memtable.write().compact_to(index);
                }
                LogItemContent::Kv(kv) => match kv.op_type {
                    OpType::Put => {
                        let value = kv.value.unwrap();
                        memtable.write().put(kv.key, value, kv.file_id.unwrap());
                    }
                    OpType::Del => {
                        let key = kv.key;
                        memtable.write().delete(key.as_slice());
                    }
                },
            }
        }
    }

    /// Applies changes from log items that have been written to rewrite queue.
    pub fn apply_rewrite_writes(
        &self,
        log_items: impl Iterator<Item = LogItem>,
        watermark: Option<FileSeq>,
        new_file: FileSeq,
    ) {
        for item in log_items {
            if has_internal_key(&item) {
                continue;
            }
            let raft = item.raft_group_id;
            let memtable = self.get_or_insert(raft);
            match item.content {
                LogItemContent::EntryIndexes(entries_to_add) => {
                    memtable.write().rewrite(entries_to_add.0, watermark);
                }
                LogItemContent::Kv(kv) => match kv.op_type {
                    OpType::Put => {
                        let key = kv.key;
                        memtable.write().rewrite_key(key, watermark, new_file);
                    }
                    _ => unreachable!(),
                },
                LogItemContent::Command(Command::Clean) => {}
                _ => unreachable!(),
            }
        }
    }

    /// Applies changes from log items that are replayed from a rewrite queue.
    /// Assumes it haven't applied any append data.
    ///
    /// This method is only used for recovery.
    pub fn replay_rewrite_writes(&self, log_items: impl Iterator<Item = LogItem>) {
        for item in log_items {
            if has_internal_key(&item) {
                continue;
            }
            let raft = item.raft_group_id;
            let memtable = self.get_or_insert(raft);
            match item.content {
                LogItemContent::EntryIndexes(entries_to_add) => {
                    memtable.write().replay_rewrite(entries_to_add.0);
                }
                LogItemContent::Command(Command::Clean) => {
                    // Only append tombstone needs to be recorded.
                    self.remove(raft, false /* record_tombstone */);
                }
                LogItemContent::Command(Command::Compact { index }) => {
                    memtable.write().compact_to(index);
                }
                LogItemContent::Kv(kv) => match kv.op_type {
                    OpType::Put => {
                        let value = kv.value.unwrap();
                        memtable.write().put(kv.key, value, kv.file_id.unwrap());
                    }
                    OpType::Del => {
                        let key = kv.key;
                        memtable.write().delete(key.as_slice());
                    }
                },
            }
        }
    }

    pub fn apply_rewrite_atomic_group(&self, raft: u64, start: FileSeq, end: FileSeq) {
        let memtable = self.get_or_insert(raft);
        memtable.write().apply_rewrite_atomic_group(start, end);
    }

    #[inline]
    fn slot_index(id: u64) -> usize {
        debug_assert!(MEMTABLE_SLOT_COUNT.is_power_of_two());
        hash_u64(id) as usize & (MEMTABLE_SLOT_COUNT - 1)
    }
}

#[inline]
fn has_internal_key(item: &LogItem) -> bool {
    matches!(&item.content, LogItemContent::Kv(KeyValue { key, .. }) if crate::is_internal_key(key, None))
}

struct PendingAtomicGroup {
    status: AtomicGroupStatus,
    items: Vec<LogItem>,
    tombstone_items: Vec<LogItem>,
    start: FileSeq,
    end: FileSeq,
}

pub struct MemTableRecoverContext<A: AllocatorTrait> {
    stats: Arc<GlobalStats>,
    // Tombstones that needs to be transmitted to other context.
    tombstone_items: Vec<LogItem>,
    memtables: MemTableAccessor<A>,

    // All atomic groups that are not yet completed.
    // Each id maps to a list of groups. Each list contains at least one, at most two groups.
    pending_atomic_groups: HashMap<u64, Vec<PendingAtomicGroup>>,
}

impl MemTableRecoverContext<VacantAllocator> {
    fn new() -> Self {
        let stats = Arc::new(GlobalStats::default());
        Self {
            stats: stats.clone(),
            tombstone_items: Vec::new(),
            memtables: MemTableAccessor::new(stats),
            pending_atomic_groups: HashMap::new(),
        }
    }
}

impl<A: AllocatorTrait> MemTableRecoverContext<A> {
    fn new_with_allocator(allocator: A) -> Self {
        let stats = Arc::new(GlobalStats::default());
        Self {
            stats: stats.clone(),
            tombstone_items: Vec::new(),
            memtables: MemTableAccessor::new_with_allocator(stats, allocator),
            pending_atomic_groups: HashMap::new(),
        }
    }

    pub fn finish(self) -> (MemTableAccessor<A>, Arc<GlobalStats>) {
        (self.memtables, self.stats)
    }

    pub fn merge_append_context(&self, append: MemTableRecoverContext<A>) {
        self.memtables
            .apply_append_writes(append.tombstone_items.into_iter());
        self.memtables.merge_append_table(append.memtables);
    }

    #[inline]
    fn is_tombstone(item: &LogItem) -> bool {
        match &item.content {
            LogItemContent::Command(Command::Clean)
            | LogItemContent::Command(Command::Compact { .. }) => true,
            LogItemContent::Kv(KeyValue { op_type, .. }) if *op_type == OpType::Del => true,
            _ => false,
        }
    }

    fn accept_new_group(&mut self, queue: LogQueue, id: u64, mut new_group: PendingAtomicGroup) {
        assert_eq!(queue, LogQueue::Rewrite);
        if let Some(groups) = self.pending_atomic_groups.get_mut(&id) {
            let group = groups.last_mut().unwrap();
            match (group.status, new_group.status) {
                (AtomicGroupStatus::End, AtomicGroupStatus::Begin) => {
                    groups.push(new_group);
                }
                // (begin, begin), (middle, begin)
                (_, AtomicGroupStatus::Begin) => {
                    warn!(
                        "discard old atomic group, status: {:?}, raft_group_id: {:?}",
                        group.status,
                        group.items.first().map(|item| item.raft_group_id)
                    );
                    *group = new_group;
                }
                // (end, middle), (end, end)
                (AtomicGroupStatus::End, _) => {
                    warn!(
                        "discard new atomic group, status: {:?}, raft_group_id: {:?}",
                        new_group.status,
                        new_group.items.first().map(|item| item.raft_group_id)
                    );
                }
                (AtomicGroupStatus::Begin, AtomicGroupStatus::Middle)
                | (AtomicGroupStatus::Middle, AtomicGroupStatus::Middle) => {
                    group.items.append(&mut new_group.items);
                    group.tombstone_items.append(&mut new_group.tombstone_items);
                    assert!(group.end <= new_group.start);
                    group.end = new_group.end;
                }
                (AtomicGroupStatus::Middle, AtomicGroupStatus::End) => {
                    group.items.append(&mut new_group.items);
                    group.tombstone_items.append(&mut new_group.tombstone_items);
                    group.status = new_group.status;
                    assert!(group.end <= new_group.start);
                    group.end = new_group.end;
                }
                (AtomicGroupStatus::Begin, AtomicGroupStatus::End) => {
                    let mut group = groups.pop().unwrap();
                    let mut rids = HashSet::with_capacity(1);
                    for item in group
                        .items
                        .iter()
                        .chain(group.tombstone_items.iter())
                        .chain(new_group.items.iter())
                        .chain(new_group.tombstone_items.iter())
                    {
                        rids.insert(item.raft_group_id);
                    }
                    self.tombstone_items.append(&mut group.tombstone_items);
                    self.tombstone_items.append(&mut new_group.tombstone_items);
                    self.memtables
                        .replay_rewrite_writes(group.items.into_iter());
                    self.memtables
                        .replay_rewrite_writes(new_group.items.into_iter());
                    assert!(group.end <= new_group.start);
                    for rid in rids {
                        self.memtables
                            .apply_rewrite_atomic_group(rid, group.start, new_group.end);
                    }
                }
            }
            if groups.is_empty() {
                self.pending_atomic_groups.remove(&id);
            }
        } else {
            self.pending_atomic_groups.insert(id, vec![new_group]);
        }
    }
}

impl Default for MemTableRecoverContext<VacantAllocator> {
    fn default() -> Self {
        Self::new()
    }
}

impl<A: AllocatorTrait> ReplayMachine for MemTableRecoverContext<A> {
    fn replay(&mut self, mut item_batch: LogItemBatch, file_id: FileId) -> Result<()> {
        if file_id.queue == LogQueue::Append {
            let mut new_tombstones = Vec::new();
            self.memtables
                .replay_append_writes(item_batch.drain().filter(|item| {
                    if Self::is_tombstone(item) {
                        new_tombstones.push(item.clone());
                    }
                    true
                }));
            self.tombstone_items.append(&mut new_tombstones);
        } else {
            let mut new_tombstones = Vec::new();
            let mut is_group = None;
            let items = item_batch
                .drain()
                .filter(|item| {
                    if let Some(g) = AtomicGroupStatus::parse(item) {
                        if is_group.is_none() {
                            is_group = Some(g);
                        } else {
                            let msg = format!("skipped an atomic group: {g:?}");
                            error!("{msg}");
                            debug_assert!(false, "{}", msg);
                        }
                        return false;
                    }
                    if Self::is_tombstone(item) {
                        new_tombstones.push(item.clone());
                    }
                    true
                })
                .collect();
            if let Some((id, status)) = is_group {
                self.accept_new_group(
                    file_id.queue,
                    id,
                    PendingAtomicGroup {
                        status,
                        items,
                        tombstone_items: new_tombstones,
                        start: file_id.seq,
                        end: file_id.seq,
                    },
                );
            } else {
                self.tombstone_items.append(&mut new_tombstones);
                self.memtables.replay_rewrite_writes(items.into_iter());
            }
        }
        Ok(())
    }

    fn merge(&mut self, mut rhs: Self, queue: LogQueue) -> Result<()> {
        self.tombstone_items
            .append(&mut rhs.tombstone_items.clone());
        for (id, groups) in rhs.pending_atomic_groups.drain() {
            for group in groups {
                self.accept_new_group(queue, id, group);
            }
        }
        match queue {
            LogQueue::Append => self
                .memtables
                .replay_append_writes(rhs.tombstone_items.into_iter()),
            LogQueue::Rewrite => self
                .memtables
                .replay_rewrite_writes(rhs.tombstone_items.into_iter()),
        }
        self.memtables.merge_newer_neighbor(rhs.memtables);
        Ok(())
    }
}

pub struct MemTableRecoverContextFactory {
    allocator: SelectedAllocator,
}

impl MemTableRecoverContextFactory {
    pub fn new(cfg: &Config) -> Self {
        Self {
            allocator: new_allocator(cfg),
        }
    }
}

impl Factory<MemTableRecoverContext<SelectedAllocator>> for MemTableRecoverContextFactory {
    fn new_target(&self) -> MemTableRecoverContext<SelectedAllocator> {
        MemTableRecoverContext::new_with_allocator(self.allocator.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_util::{catch_unwind_silent, generate_entry_indexes};

    impl<A: AllocatorTrait> MemTable<A> {
        fn max_file_seq(&self, queue: LogQueue) -> Option<FileSeq> {
            let entry = match queue {
                LogQueue::Append if self.rewrite_count == self.entry_indexes.len() => None,
                LogQueue::Append => self.entry_indexes.back(),
                LogQueue::Rewrite if self.rewrite_count == 0 => None,
                LogQueue::Rewrite => self.entry_indexes.get(self.rewrite_count - 1),
            };
            let ents_max = entry.map(|e| e.entries.unwrap().id.seq);

            let kvs_max = self.kvs_max_file_seq(queue);
            match (ents_max, kvs_max) {
                (Some(ents_max), Some(kvs_max)) => Some(FileSeq::max(kvs_max, ents_max)),
                (Some(ents_max), None) => Some(ents_max),
                (None, Some(kvs_max)) => Some(kvs_max),
                (None, None) => None,
            }
        }

        pub fn kvs_max_file_seq(&self, queue: LogQueue) -> Option<FileSeq> {
            self.kvs
                .values()
                .filter(|v| v.1.queue == queue)
                .fold(None, |max, v| {
                    if let Some(max) = max {
                        Some(std::cmp::max(max, v.1.seq))
                    } else {
                        Some(v.1.seq)
                    }
                })
        }

        pub fn fetch_all(&self, vec_idx: &mut Vec<EntryIndex>) {
            if let Some((first, last)) = self.span() {
                self.fetch_entries_to(first, last + 1, None, vec_idx)
                    .unwrap();
            }
        }

        fn entries_size(&self) -> usize {
            self.entry_indexes
                .iter()
                .fold(0, |acc, e| acc + e.entry_len) as usize
        }
    }

    #[test]
    fn test_memtable_append() {
        let region_id = 8;
        let mut memtable = MemTable::new(region_id, Arc::new(GlobalStats::default()));

        // Append entries [10, 20) file_num = 1.
        // after appending
        // [10, 20) file_num = 1
        memtable.append(generate_entry_indexes(
            10,
            20,
            FileId::new(LogQueue::Append, 1),
        ));
        assert_eq!(memtable.entries_size(), 10);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 1);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 1);
        memtable.consistency_check();

        // Empty.
        memtable.append(Vec::new());

        // Hole.
        assert!(
            catch_unwind_silent(|| memtable.append(generate_entry_indexes(
                21,
                22,
                FileId::dummy(LogQueue::Append)
            )))
            .is_err()
        );
        memtable.consistency_check();

        // Append entries [20, 30) file_num = 2.
        // after appending:
        // [10, 20) file_num = 1
        // [20, 30) file_num = 2
        memtable.append(generate_entry_indexes(
            20,
            30,
            FileId::new(LogQueue::Append, 2),
        ));
        assert_eq!(memtable.entries_size(), 20);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 1);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 2);
        memtable.consistency_check();
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            memtable.entries_size()
        );

        // Partial overlap Appending.
        // Append entries [25, 35) file_num = 3.
        // After appending:
        // [10, 20) file_num = 1
        // [20, 25) file_num = 2
        // [25, 35) file_num = 3
        memtable.append(generate_entry_indexes(
            25,
            35,
            FileId::new(LogQueue::Append, 3),
        ));
        assert_eq!(memtable.entries_size(), 25);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 1);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 3);
        memtable.consistency_check();
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            memtable.entries_size()
        );

        // Full overlap Appending.
        // Append entries [10, 40) file_num = 4.
        // After appending:
        // [10, 40) file_num = 4
        memtable.append(generate_entry_indexes(
            10,
            40,
            FileId::new(LogQueue::Append, 4),
        ));
        assert_eq!(memtable.entries_size(), 30);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 4);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 4);
        memtable.consistency_check();
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            memtable.entries_size()
        );

        let global_stats = Arc::clone(&memtable.global_stats);
        drop(memtable);
        assert_eq!(global_stats.live_entries(LogQueue::Append), 0);
    }

    #[test]
    fn test_memtable_compact() {
        let region_id = 8;
        let mut memtable = MemTable::new(region_id, Arc::new(GlobalStats::default()));

        // After appending:
        // [0, 10) file_num = 1
        // [10, 20) file_num = 2
        // [20, 25) file_num = 3
        memtable.append(generate_entry_indexes(
            0,
            10,
            FileId::new(LogQueue::Append, 1),
        ));
        memtable.append(generate_entry_indexes(
            10,
            15,
            FileId::new(LogQueue::Append, 2),
        ));
        memtable.append(generate_entry_indexes(
            15,
            20,
            FileId::new(LogQueue::Append, 2),
        ));
        memtable.append(generate_entry_indexes(
            20,
            25,
            FileId::new(LogQueue::Append, 3),
        ));

        assert_eq!(memtable.entries_size(), 25);
        assert_eq!(memtable.first_index().unwrap(), 0);
        assert_eq!(memtable.last_index().unwrap(), 24);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 1);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 3);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            memtable.entries_size()
        );
        memtable.consistency_check();

        // Compact to 5.
        // Only index is needed to compact.
        assert_eq!(memtable.compact_to(5), 5);
        assert_eq!(memtable.entries_size(), 20);
        assert_eq!(memtable.first_index().unwrap(), 5);
        assert_eq!(memtable.last_index().unwrap(), 24);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 1);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 3);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            memtable.entries_size()
        );
        // Can't override compacted entries.
        assert!(
            catch_unwind_silent(|| memtable.append(generate_entry_indexes(
                4,
                5,
                FileId::dummy(LogQueue::Append)
            )))
            .is_err()
        );
        memtable.consistency_check();

        // Compact to 20.
        assert_eq!(memtable.compact_to(20), 15);
        assert_eq!(memtable.entries_size(), 5);
        assert_eq!(memtable.first_index().unwrap(), 20);
        assert_eq!(memtable.last_index().unwrap(), 24);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 3);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 3);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            memtable.entries_size()
        );
        memtable.consistency_check();

        // Compact to 20 or smaller index, nothing happens.
        assert_eq!(memtable.compact_to(20), 0);
        assert_eq!(memtable.compact_to(15), 0);
        assert_eq!(memtable.entries_size(), 5);
        assert_eq!(memtable.first_index().unwrap(), 20);
        assert_eq!(memtable.last_index().unwrap(), 24);
        memtable.consistency_check();
    }

    #[test]
    fn test_memtable_fetch() {
        let region_id = 8;
        let mut memtable = MemTable::new(region_id, Arc::new(GlobalStats::default()));

        let mut ents_idx = vec![];

        // Fetch empty.
        memtable.fetch_all(&mut ents_idx);
        assert!(ents_idx.is_empty());
        memtable
            .fetch_entries_to(0, 0, None, &mut ents_idx)
            .unwrap();
        assert!(matches!(
            memtable
                .fetch_entries_to(0, 1, None, &mut ents_idx)
                .unwrap_err(),
            Error::EntryNotFound
        ));

        // After appending:
        // [0, 10) file_num = 1
        // [10, 15) file_num = 2
        // [15, 20) file_num = 2
        // [20, 25) file_num = 3
        memtable.append(generate_entry_indexes(
            0,
            10,
            FileId::new(LogQueue::Append, 1),
        ));
        memtable.append(generate_entry_indexes(
            10,
            20,
            FileId::new(LogQueue::Append, 2),
        ));
        memtable.append(generate_entry_indexes(
            20,
            25,
            FileId::new(LogQueue::Append, 3),
        ));

        // Fetching all
        memtable.fetch_all(&mut ents_idx);
        assert_eq!(ents_idx.len(), 25);
        assert_eq!(ents_idx[0].index, 0);
        assert_eq!(ents_idx[24].index, 24);

        // After compact:
        // [10, 15) file_num = 2
        // [15, 20) file_num = 2
        // [20, 25) file_num = 3
        assert_eq!(memtable.compact_to(10), 10);

        // Out of range fetching.
        ents_idx.clear();
        assert!(matches!(
            memtable
                .fetch_entries_to(5, 15, None, &mut ents_idx)
                .unwrap_err(),
            Error::EntryCompacted
        ));

        // Out of range fetching.
        ents_idx.clear();
        assert!(matches!(
            memtable
                .fetch_entries_to(20, 30, None, &mut ents_idx)
                .unwrap_err(),
            Error::EntryNotFound
        ));

        ents_idx.clear();
        memtable
            .fetch_entries_to(20, 25, None, &mut ents_idx)
            .unwrap();
        assert_eq!(ents_idx.len(), 5);
        assert_eq!(ents_idx[0].index, 20);
        assert_eq!(ents_idx[4].index, 24);

        ents_idx.clear();
        memtable
            .fetch_entries_to(10, 15, None, &mut ents_idx)
            .unwrap();
        assert_eq!(ents_idx.len(), 5);
        assert_eq!(ents_idx[0].index, 10);
        assert_eq!(ents_idx[4].index, 14);

        ents_idx.clear();
        memtable
            .fetch_entries_to(10, 25, None, &mut ents_idx)
            .unwrap();
        assert_eq!(ents_idx.len(), 15);
        assert_eq!(ents_idx[0].index, 10);
        assert_eq!(ents_idx[14].index, 24);

        // Max size limitation range fetching.
        // Only can fetch [10, 20) because of size limitation,
        ents_idx.clear();
        let max_size = Some(10);
        memtable
            .fetch_entries_to(10, 25, max_size, &mut ents_idx)
            .unwrap();
        assert_eq!(ents_idx.len(), 10);
        assert_eq!(ents_idx[0].index, 10);
        assert_eq!(ents_idx[9].index, 19);

        // Even max size limitation is 0, at least fetch one entry.
        ents_idx.clear();
        memtable
            .fetch_entries_to(20, 25, Some(0), &mut ents_idx)
            .unwrap();
        assert_eq!(ents_idx.len(), 1);
        assert_eq!(ents_idx[0].index, 20);
    }

    #[test]
    fn test_memtable_fetch_rewrite() {
        let region_id = 8;
        let mut memtable = MemTable::new(region_id, Arc::new(GlobalStats::default()));
        let (k1, v1) = (b"key1", b"value1");
        let (k2, v2) = (b"key2", b"value2");
        let (k3, v3) = (b"key3", b"value3");

        // After appending:
        // [0, 10) file_num = 1
        // [10, 20) file_num = 2
        // [20, 25) file_num = 3
        memtable.append(generate_entry_indexes(
            0,
            10,
            FileId::new(LogQueue::Append, 1),
        ));
        memtable.put(k1.to_vec(), v1.to_vec(), FileId::new(LogQueue::Append, 1));
        memtable.append(generate_entry_indexes(
            10,
            20,
            FileId::new(LogQueue::Append, 2),
        ));
        memtable.put(k2.to_vec(), v2.to_vec(), FileId::new(LogQueue::Append, 2));
        memtable.append(generate_entry_indexes(
            20,
            25,
            FileId::new(LogQueue::Append, 3),
        ));
        memtable.put(k3.to_vec(), v3.to_vec(), FileId::new(LogQueue::Append, 3));
        memtable.consistency_check();

        // Rewrite k1.
        memtable.rewrite_key(k1.to_vec(), Some(1), 50);
        let mut kvs = Vec::new();
        memtable.fetch_kvs_before(1, &mut kvs);
        assert!(kvs.is_empty());
        memtable.fetch_rewritten_kvs(&mut kvs);
        assert_eq!(kvs.len(), 1);
        assert_eq!(kvs.pop().unwrap(), (k1.to_vec(), v1.to_vec()));
        // Rewrite deleted k1.
        memtable.delete(k1.as_ref());
        assert_eq!(memtable.global_stats.deleted_rewrite_entries(), 1);
        memtable.rewrite_key(k1.to_vec(), Some(1), 50);
        assert_eq!(memtable.get(k1.as_ref()), None);
        memtable.fetch_rewritten_kvs(&mut kvs);
        assert!(kvs.is_empty());
        assert_eq!(memtable.global_stats.deleted_rewrite_entries(), 2);
        // Rewrite newer append k2/k3.
        memtable.rewrite_key(k2.to_vec(), Some(1), 50);
        memtable.fetch_rewritten_kvs(&mut kvs);
        assert!(kvs.is_empty());
        memtable.rewrite_key(k3.to_vec(), None, 50); // Rewrite encounters newer append.
        memtable.fetch_rewritten_kvs(&mut kvs);
        assert!(kvs.is_empty());
        assert_eq!(memtable.global_stats.deleted_rewrite_entries(), 4);
        // Rewrite k3 multiple times.
        memtable.rewrite_key(k3.to_vec(), Some(10), 50);
        memtable.rewrite_key(k3.to_vec(), None, 51);
        memtable.rewrite_key(k3.to_vec(), Some(11), 52);
        memtable.fetch_rewritten_kvs(&mut kvs);
        assert_eq!(kvs.len(), 1);
        assert_eq!(kvs.pop().unwrap(), (k3.to_vec(), v3.to_vec()));

        // Rewrite indexes:
        // [0, 10) queue = rewrite, file_num = 1,
        // [10, 20) file_num = 2
        // [20, 25) file_num = 3
        let ents_idx = generate_entry_indexes(0, 10, FileId::new(LogQueue::Rewrite, 1));
        memtable.rewrite(ents_idx, Some(1));
        assert_eq!(memtable.entries_size(), 25);
        memtable.consistency_check();

        let mut ents_idx = vec![];
        assert!(memtable
            .fetch_entry_indexes_before(2, &mut ents_idx)
            .is_ok());
        assert_eq!(ents_idx.len(), 10);
        assert_eq!(ents_idx.last().unwrap().index, 19);
        ents_idx.clear();
        assert!(memtable
            .fetch_entry_indexes_before(1, &mut ents_idx)
            .is_ok());
        assert!(ents_idx.is_empty());

        ents_idx.clear();
        assert!(memtable
            .fetch_rewritten_entry_indexes(&mut ents_idx)
            .is_ok());
        assert_eq!(ents_idx.len(), 10);
        assert_eq!(ents_idx.first().unwrap().index, 0);
        assert_eq!(ents_idx.last().unwrap().index, 9);
    }

    #[test]
    fn test_memtable_kv_operations() {
        fn key(i: u64) -> Vec<u8> {
            format!("k{i}").as_bytes().to_vec()
        }
        fn value(i: u64) -> Vec<u8> {
            format!("v{i}").as_bytes().to_vec()
        }

        let region_id = 8;
        let mut memtable = MemTable::new(region_id, Arc::new(GlobalStats::default()));

        memtable.put(key(1), value(1), FileId::new(LogQueue::Append, 1));
        memtable.put(key(5), value(5), FileId::new(LogQueue::Append, 5));
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 1);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 5);
        assert_eq!(memtable.get(&key(1)), Some(value(1)));
        assert_eq!(memtable.get(&key(5)), Some(value(5)));

        let mut res = Vec::new();
        memtable
            .scan(None, None, false, |k, v| {
                res.push((k.to_vec(), v.to_vec()));
                false
            })
            .unwrap();
        assert_eq!(res, vec![(key(1), value(1))]);
        res.clear();
        memtable
            .scan(None, None, true, |k, v| {
                res.push((k.to_vec(), v.to_vec()));
                false
            })
            .unwrap();
        assert_eq!(res, vec![(key(5), value(5))]);
        res.clear();
        memtable
            .scan(Some(&key(5)), None, false, |key, value| {
                res.push((key.to_vec(), value.to_vec()));
                true
            })
            .unwrap();
        assert_eq!(res, vec![(key(5), value(5))]);
        res.clear();
        memtable
            .scan(Some(&key(1)), Some(&key(5)), false, |key, value| {
                res.push((key.to_vec(), value.to_vec()));
                true
            })
            .unwrap();
        assert_eq!(res, vec![(key(1), value(1))]);

        memtable.delete(&key(5));
        assert_eq!(memtable.get(&key(5)), None);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 1);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 1);

        memtable.put(key(1), value(1), FileId::new(LogQueue::Rewrite, 2));
        memtable.put(key(5), value(5), FileId::new(LogQueue::Rewrite, 3));
        assert_eq!(memtable.min_file_seq(LogQueue::Append), None);
        assert_eq!(memtable.max_file_seq(LogQueue::Append), None);
        assert_eq!(memtable.min_file_seq(LogQueue::Rewrite).unwrap(), 2);
        assert_eq!(memtable.max_file_seq(LogQueue::Rewrite).unwrap(), 3);
        assert_eq!(memtable.global_stats.rewrite_entries(), 2);

        memtable.delete(&key(1));
        assert_eq!(memtable.min_file_seq(LogQueue::Rewrite).unwrap(), 3);
        assert_eq!(memtable.max_file_seq(LogQueue::Rewrite).unwrap(), 3);
        assert_eq!(memtable.global_stats.deleted_rewrite_entries(), 1);

        memtable.put(key(5), value(5), FileId::new(LogQueue::Append, 7));
        assert_eq!(memtable.min_file_seq(LogQueue::Rewrite), None);
        assert_eq!(memtable.max_file_seq(LogQueue::Rewrite), None);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 7);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 7);
        assert_eq!(memtable.global_stats.deleted_rewrite_entries(), 2);
    }

    #[test]
    fn test_memtable_get_entry() {
        let region_id = 8;
        let mut memtable = MemTable::new(region_id, Arc::new(GlobalStats::default()));

        assert_eq!(memtable.get_entry(0), None);

        // [5, 10) file_num = 1
        // [10, 20) file_num = 2
        memtable.append(generate_entry_indexes(
            5,
            10,
            FileId::new(LogQueue::Append, 1),
        ));
        memtable.append(generate_entry_indexes(
            10,
            20,
            FileId::new(LogQueue::Append, 2),
        ));

        // Not in range.
        assert_eq!(memtable.get_entry(2), None);
        assert_eq!(memtable.get_entry(25), None);

        let entry_idx = memtable.get_entry(5);
        assert_eq!(entry_idx.unwrap().index, 5);
    }

    #[test]
    fn test_memtable_rewrite() {
        let region_id = 8;
        let mut memtable = MemTable::new(region_id, Arc::new(GlobalStats::default()));
        let mut expected_append = 0;
        let mut expected_rewrite = 0;
        let mut expected_deleted_rewrite = 0;

        // Rewrite to empty table.
        let ents_idx = generate_entry_indexes(0, 10, FileId::new(LogQueue::Rewrite, 1));
        memtable.rewrite(ents_idx, Some(1));
        expected_rewrite += 10;
        expected_deleted_rewrite += 10;
        assert_eq!(memtable.min_file_seq(LogQueue::Rewrite), None);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            expected_append
        );
        assert_eq!(memtable.global_stats.rewrite_entries(), expected_rewrite);
        assert_eq!(
            memtable.global_stats.deleted_rewrite_entries(),
            expected_deleted_rewrite
        );

        // Append and compact:
        // [10, 20) file_num = 2
        // [20, 30) file_num = 3
        // [30, 40) file_num = 4
        // kk1 -> 2, kk2 -> 3, kk3 -> 4
        memtable.append(generate_entry_indexes(
            0,
            10,
            FileId::new(LogQueue::Append, 1),
        ));
        memtable.append(generate_entry_indexes(
            10,
            20,
            FileId::new(LogQueue::Append, 2),
        ));
        memtable.put(
            b"kk1".to_vec(),
            b"vv1".to_vec(),
            FileId::new(LogQueue::Append, 2),
        );
        memtable.append(generate_entry_indexes(
            20,
            30,
            FileId::new(LogQueue::Append, 3),
        ));
        memtable.put(
            b"kk2".to_vec(),
            b"vv2".to_vec(),
            FileId::new(LogQueue::Append, 3),
        );
        memtable.append(generate_entry_indexes(
            30,
            40,
            FileId::new(LogQueue::Append, 4),
        ));
        memtable.put(
            b"kk3".to_vec(),
            b"vv3".to_vec(),
            FileId::new(LogQueue::Append, 4),
        );
        expected_append += 4 * 10 + 3;
        memtable.compact_to(10);
        expected_append -= 10;
        assert_eq!(memtable.entries_size(), 30);
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 2);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 4);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            expected_append
        );
        memtable.consistency_check();

        // Rewrite compacted entries.
        // [10, 20) file_num = 2
        // [20, 30) file_num = 3
        // [30, 40) file_num = 4
        // kk1 -> 2, kk2 -> 3, kk3 -> 4
        let ents_idx = generate_entry_indexes(0, 10, FileId::new(LogQueue::Rewrite, 50));
        memtable.rewrite(ents_idx, Some(1));
        memtable.rewrite_key(b"kk0".to_vec(), Some(1), 50);
        expected_rewrite += 10 + 1;
        expected_deleted_rewrite += 10 + 1;
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 2);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 4);
        assert!(memtable.min_file_seq(LogQueue::Rewrite).is_none());
        assert!(memtable.max_file_seq(LogQueue::Rewrite).is_none());
        assert_eq!(memtable.rewrite_count, 0);
        assert_eq!(memtable.get(b"kk0"), None);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            expected_append
        );
        assert_eq!(memtable.global_stats.rewrite_entries(), expected_rewrite);
        assert_eq!(
            memtable.global_stats.deleted_rewrite_entries(),
            expected_deleted_rewrite
        );
        memtable.consistency_check();

        // Mixed rewrite.
        // [10, 20) file_num = 100(r)
        // [20, 30) file_num = 101(r)
        // [30, 40) file_num = 4
        // kk1 -> 100(r), kk2 -> 101(r), kk3 -> 4
        let ents_idx = generate_entry_indexes(0, 20, FileId::new(LogQueue::Rewrite, 100));
        memtable.rewrite(ents_idx, Some(2));
        memtable.rewrite_key(b"kk0".to_vec(), Some(1), 50);
        memtable.rewrite_key(b"kk1".to_vec(), Some(2), 100);
        expected_append -= 10 + 1;
        expected_rewrite += 20 + 2;
        expected_deleted_rewrite += 10 + 1;
        let ents_idx = generate_entry_indexes(20, 30, FileId::new(LogQueue::Rewrite, 101));
        memtable.rewrite(ents_idx, Some(3));
        memtable.rewrite_key(b"kk2".to_vec(), Some(3), 101);
        expected_append -= 10 + 1;
        expected_rewrite += 10 + 1;
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 4);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 4);
        assert_eq!(memtable.min_file_seq(LogQueue::Rewrite).unwrap(), 100);
        assert_eq!(memtable.max_file_seq(LogQueue::Rewrite).unwrap(), 101);
        assert_eq!(memtable.rewrite_count, 20);
        assert_eq!(memtable.get(b"kk1"), Some(b"vv1".to_vec()));
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            expected_append
        );
        assert_eq!(memtable.global_stats.rewrite_entries(), expected_rewrite);
        assert_eq!(
            memtable.global_stats.deleted_rewrite_entries(),
            expected_deleted_rewrite
        );
        memtable.consistency_check();

        // Put some entries overwritting entires in file 4. Then try to rewrite.
        // [10, 20) file_num = 100(r)
        // [20, 30) file_num = 101(r)
        // [30, 35) file_num = 4 -> 102(r)
        // 35 file_num = 5
        // kk1 -> 100(r), kk2 -> 101(r), kk3 -> 5
        memtable.append(generate_entry_indexes(
            35,
            36,
            FileId::new(LogQueue::Append, 5),
        ));
        expected_append -= 4;
        memtable.put(
            b"kk3".to_vec(),
            b"vv33".to_vec(),
            FileId::new(LogQueue::Append, 5),
        );
        assert_eq!(memtable.last_index().unwrap(), 35);
        memtable.consistency_check();
        let ents_idx = generate_entry_indexes(30, 40, FileId::new(LogQueue::Rewrite, 102));
        memtable.rewrite(ents_idx, Some(4));
        expected_append -= 5;
        expected_rewrite += 10;
        expected_deleted_rewrite += 5;
        assert_eq!(memtable.min_file_seq(LogQueue::Append).unwrap(), 5);
        assert_eq!(memtable.max_file_seq(LogQueue::Append).unwrap(), 5);
        assert_eq!(memtable.min_file_seq(LogQueue::Rewrite).unwrap(), 100);
        assert_eq!(memtable.max_file_seq(LogQueue::Rewrite).unwrap(), 102);
        assert_eq!(memtable.rewrite_count, 25);
        assert_eq!(memtable.get(b"kk3"), Some(b"vv33".to_vec()));
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            expected_append
        );
        assert_eq!(memtable.global_stats.rewrite_entries(), expected_rewrite);
        assert_eq!(
            memtable.global_stats.deleted_rewrite_entries(),
            expected_deleted_rewrite
        );
        memtable.consistency_check();

        // Compact after rewrite.
        // [30, 35) file_num = 102(r)
        // [35, 50) file_num = 6
        // kk1 -> 100(r), kk2 -> 101(r), kk3 -> 5
        memtable.append(generate_entry_indexes(
            35,
            50,
            FileId::new(LogQueue::Append, 6),
        ));
        expected_append += 15 - 1;
        memtable.compact_to(30);
        expected_deleted_rewrite += 20;
        assert_eq!(memtable.last_index().unwrap(), 49);
        assert_eq!(memtable.rewrite_count, 5);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            expected_append
        );
        assert_eq!(memtable.global_stats.rewrite_entries(), expected_rewrite);
        assert_eq!(
            memtable.global_stats.deleted_rewrite_entries(),
            expected_deleted_rewrite
        );
        memtable.consistency_check();

        // Squeeze some.
        // [30, 35) file_num = 103(r)
        // [35, 50) file_num = 6
        // kk1 -> 100(r), kk2 -> 101(r), kk3 -> 5
        let ents_idx = generate_entry_indexes(10, 60, FileId::new(LogQueue::Rewrite, 103));
        memtable.rewrite(ents_idx, None);
        expected_rewrite += 50;
        expected_deleted_rewrite += 50;
        assert_eq!(memtable.first_index().unwrap(), 30);
        assert_eq!(memtable.rewrite_count, 5);
        assert_eq!(
            memtable.global_stats.live_entries(LogQueue::Append),
            expected_append
        );
        assert_eq!(memtable.global_stats.rewrite_entries(), expected_rewrite);
        assert_eq!(
            memtable.global_stats.deleted_rewrite_entries(),
            expected_deleted_rewrite
        );
        memtable.consistency_check();

        let global_stats = Arc::clone(&memtable.global_stats);
        drop(memtable);
        assert_eq!(global_stats.live_entries(LogQueue::Append), 0);
        assert_eq!(global_stats.live_entries(LogQueue::Rewrite), 0);
    }

    #[test]
    fn test_memtable_merge_append() {
        type TestMemTable = MemTable<VacantAllocator>;
        fn empty_table(id: u64) -> TestMemTable {
            MemTable::new(id, Arc::new(GlobalStats::default()))
        }
        let cases = [
            |mut memtable: TestMemTable, on: Option<LogQueue>| -> TestMemTable {
                match on {
                    None => {
                        memtable.append(generate_entry_indexes(
                            0,
                            10,
                            FileId::new(LogQueue::Append, 1),
                        ));
                        memtable.append(generate_entry_indexes(
                            7,
                            15,
                            FileId::new(LogQueue::Append, 2),
                        ));
                        memtable.rewrite(
                            generate_entry_indexes(0, 10, FileId::new(LogQueue::Rewrite, 1)),
                            Some(1),
                        );
                    }
                    Some(LogQueue::Append) => {
                        memtable.append(generate_entry_indexes(
                            0,
                            10,
                            FileId::new(LogQueue::Append, 1),
                        ));
                        memtable.append(generate_entry_indexes(
                            7,
                            15,
                            FileId::new(LogQueue::Append, 2),
                        ));
                        memtable.compact_to(7);
                    }
                    Some(LogQueue::Rewrite) => {
                        memtable.replay_rewrite(generate_entry_indexes(
                            0,
                            7,
                            FileId::new(LogQueue::Rewrite, 1),
                        ));
                        memtable.replay_rewrite(Vec::new());
                    }
                }
                memtable
            },
            |mut memtable: TestMemTable, on: Option<LogQueue>| -> TestMemTable {
                match on {
                    None => {
                        memtable.append(generate_entry_indexes(
                            0,
                            10,
                            FileId::new(LogQueue::Append, 1),
                        ));
                        memtable.append(generate_entry_indexes(
                            7,
                            15,
                            FileId::new(LogQueue::Append, 2),
                        ));
                        memtable.rewrite(
                            generate_entry_indexes(0, 10, FileId::new(LogQueue::Rewrite, 1)),
                            Some(1),
                        );
                        memtable.compact_to(10);
                    }
                    Some(LogQueue::Append) => {
                        memtable.append(generate_entry_indexes(
                            0,
                            10,
                            FileId::new(LogQueue::Append, 1),
                        ));
                        memtable.append(generate_entry_indexes(
                            7,
                            15,
                            FileId::new(LogQueue::Append, 2),
                        ));
                        memtable.compact_to(10);
                    }
                    Some(LogQueue::Rewrite) => {
                        memtable.replay_rewrite(generate_entry_indexes(
                            0,
                            7,
                            FileId::new(LogQueue::Rewrite, 1),
                        ));
                        // By MemTableRecoveryContext.
                        memtable.compact_to(10);
                    }
                }
                memtable
            },
            |mut memtable: TestMemTable, on: Option<LogQueue>| -> TestMemTable {
                match on {
                    None => {
                        memtable.append(generate_entry_indexes(
                            0,
                            10,
                            FileId::new(LogQueue::Append, 1),
                        ));
                        memtable.rewrite(
                            generate_entry_indexes(0, 10, FileId::new(LogQueue::Rewrite, 1)),
                            Some(1),
                        );
                        memtable.append(generate_entry_indexes(
                            10,
                            15,
                            FileId::new(LogQueue::Append, 2),
                        ));
                        memtable.append(generate_entry_indexes(
                            5,
                            10,
                            FileId::new(LogQueue::Append, 2),
                        ));
                    }
                    Some(LogQueue::Append) => {
                        let mut m1 = empty_table(memtable.region_id);
                        m1.append(generate_entry_indexes(
                            10,
                            15,
                            FileId::new(LogQueue::Append, 2),
                        ));
                        let mut m2 = empty_table(memtable.region_id);
                        m2.append(generate_entry_indexes(
                            5,
                            10,
                            FileId::new(LogQueue::Append, 2),
                        ));
                        m1.merge_newer_neighbor(&mut m2);
                        memtable.merge_newer_neighbor(&mut m1);
                    }
                    Some(LogQueue::Rewrite) => {
                        memtable.replay_rewrite(generate_entry_indexes(
                            0,
                            10,
                            FileId::new(LogQueue::Rewrite, 1),
                        ));
                    }
                }
                memtable
            },
        ];

        // merge against empty table.
        for (i, case) in cases.iter().enumerate() {
            let region_id = i as u64;
            let mut append = empty_table(region_id);
            let mut rewrite = case(empty_table(region_id), Some(LogQueue::Rewrite));
            rewrite.merge_append_table(&mut append);
            assert_eq!(
                rewrite.entry_indexes,
                case(empty_table(region_id), Some(LogQueue::Rewrite)).entry_indexes,
            );
            assert!(append.entry_indexes.is_empty());

            let mut append = case(empty_table(region_id), Some(LogQueue::Append));
            let mut rewrite = empty_table(region_id);
            rewrite.merge_append_table(&mut append);
            assert_eq!(
                rewrite.entry_indexes,
                case(empty_table(region_id), Some(LogQueue::Append)).entry_indexes
            );
            assert!(append.entry_indexes.is_empty());
        }

        for (i, case) in cases.iter().enumerate() {
            let region_id = i as u64;
            let mut append = case(empty_table(region_id), Some(LogQueue::Append));
            let mut rewrite = case(empty_table(region_id), Some(LogQueue::Rewrite));
            rewrite.merge_append_table(&mut append);
            let expected = case(empty_table(region_id), None);
            assert_eq!(
                rewrite.global_stats.live_entries(LogQueue::Append),
                expected.global_stats.live_entries(LogQueue::Append)
            );
            assert_eq!(
                rewrite.global_stats.live_entries(LogQueue::Rewrite),
                expected.global_stats.live_entries(LogQueue::Rewrite)
            );
            assert_eq!(rewrite.entry_indexes, expected.entry_indexes);
            assert!(append.entry_indexes.is_empty());
        }
    }

    #[test]
    fn test_memtables_merge_append_neighbor() {
        let first_rid = 17;
        let mut last_rid = first_rid;

        let mut batches = vec![
            LogItemBatch::with_capacity(0),
            LogItemBatch::with_capacity(0),
            LogItemBatch::with_capacity(0),
        ];
        let files: Vec<_> = (0..batches.len())
            .map(|i| FileId::new(LogQueue::Append, 10 + i as u64))
            .collect();

        // put (key1, v1) => del (key1) => put (key1, v2)
        batches[0].put(last_rid, b"key1".to_vec(), b"val1".to_vec());
        batches[1].delete(last_rid, b"key1".to_vec());
        batches[2].put(last_rid, b"key1".to_vec(), b"val2".to_vec());

        // put (k, _) => cleanup
        last_rid += 1;
        batches[0].put(last_rid, b"key".to_vec(), b"ANYTHING".to_vec());
        batches[1].add_command(last_rid, Command::Clean);

        // entries [1, 10] => compact 5 => entries [11, 20]
        last_rid += 1;
        batches[0].add_entry_indexes(last_rid, generate_entry_indexes(1, 11, files[0]));
        batches[1].add_command(last_rid, Command::Compact { index: 5 });
        batches[2].add_entry_indexes(last_rid, generate_entry_indexes(11, 21, files[2]));

        // entries [1, 10] => entries [11, 20][5, 10] => compact 8
        last_rid += 1;
        batches[0].add_entry_indexes(last_rid, generate_entry_indexes(1, 11, files[0]));
        batches[1].add_entry_indexes(last_rid, generate_entry_indexes(11, 21, files[1]));
        batches[1].add_entry_indexes(last_rid, generate_entry_indexes(5, 11, files[1]));
        batches[2].add_command(last_rid, Command::Compact { index: 8 });

        for b in batches.iter_mut() {
            b.finish_write(FileBlockHandle::dummy(LogQueue::Append));
        }

        // reverse merge
        let mut ctxs = VecDeque::default();
        for (batch, file_id) in batches.clone().into_iter().zip(files) {
            let mut ctx = MemTableRecoverContext::default();
            ctx.replay(batch, file_id).unwrap();
            ctxs.push_back(ctx);
        }
        while ctxs.len() > 1 {
            let (y, mut x) = (ctxs.pop_back().unwrap(), ctxs.pop_back().unwrap());
            x.merge(y, LogQueue::Append).unwrap();
            ctxs.push_back(x);
        }
        let (merged_memtables, merged_global_stats) = ctxs.pop_front().unwrap().finish();

        // sequential apply
        let sequential_global_stats = Arc::new(GlobalStats::default());
        let sequential_memtables = MemTableAccessor::new(sequential_global_stats.clone());
        for mut batch in batches.clone() {
            sequential_memtables.apply_append_writes(batch.drain());
        }

        for rid in first_rid..=last_rid {
            let m = merged_memtables.get(rid);
            let s = sequential_memtables.get(rid);
            if m.is_none() {
                assert!(s.is_none());
                continue;
            }
            let merged = m.as_ref().unwrap().read();
            let sequential = s.as_ref().unwrap().read();
            let mut merged_vec = Vec::new();
            let mut sequential_vec = Vec::new();
            merged
                .fetch_entry_indexes_before(u64::MAX, &mut merged_vec)
                .unwrap();
            sequential
                .fetch_entry_indexes_before(u64::MAX, &mut sequential_vec)
                .unwrap();
            assert_eq!(merged_vec, sequential_vec);
            merged_vec.clear();
            sequential_vec.clear();
            merged
                .fetch_rewritten_entry_indexes(&mut merged_vec)
                .unwrap();
            sequential
                .fetch_rewritten_entry_indexes(&mut sequential_vec)
                .unwrap();
            assert_eq!(merged_vec, sequential_vec);
            let mut merged_vec = Vec::new();
            let mut sequential_vec = Vec::new();
            merged.fetch_kvs_before(u64::MAX, &mut merged_vec);
            sequential.fetch_kvs_before(u64::MAX, &mut sequential_vec);
            assert_eq!(merged_vec, sequential_vec);
            merged_vec.clear();
            sequential_vec.clear();
            merged.fetch_rewritten_kvs(&mut merged_vec);
            sequential.fetch_rewritten_kvs(&mut sequential_vec);
            assert_eq!(merged_vec, sequential_vec);
        }
        assert_eq!(
            merged_global_stats.live_entries(LogQueue::Append),
            sequential_global_stats.live_entries(LogQueue::Append),
        );
        assert_eq!(
            merged_global_stats.rewrite_entries(),
            sequential_global_stats.rewrite_entries(),
        );
        assert_eq!(
            merged_global_stats.deleted_rewrite_entries(),
            sequential_global_stats.deleted_rewrite_entries(),
        );
    }

    #[cfg(feature = "nightly")]
    #[bench]
    fn bench_memtable_single_put(b: &mut test::Bencher) {
        let mut memtable = MemTable::new(0, Arc::new(GlobalStats::default()));
        let key = b"some_key".to_vec();
        let value = vec![7; 12];
        b.iter(move || {
            memtable.put(key.clone(), value.clone(), FileId::dummy(LogQueue::Append));
        });
    }

    #[cfg(feature = "nightly")]
    #[bench]
    fn bench_memtable_triple_puts(b: &mut test::Bencher) {
        let mut memtable = MemTable::new(0, Arc::new(GlobalStats::default()));
        let key0 = b"some_key0".to_vec();
        let key1 = b"some_key1".to_vec();
        let key2 = b"some_key2".to_vec();
        let value = vec![7; 12];
        b.iter(move || {
            memtable.put(key0.clone(), value.clone(), FileId::dummy(LogQueue::Append));
            memtable.put(key1.clone(), value.clone(), FileId::dummy(LogQueue::Append));
            memtable.put(key2.clone(), value.clone(), FileId::dummy(LogQueue::Append));
        });
    }
}
