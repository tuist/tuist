// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use hashbrown::HashMap;

use crate::file_pipe_log::ReplayMachine;
use crate::log_batch::{LogItemBatch, LogItemContent};
use crate::pipe_log::{FileId, LogQueue};
use crate::Result;

/// A `ConsistencyChecker` scans for log entry holes in a log queue. It will
/// return a list of corrupted raft groups along with their last valid log
/// index.
#[derive(Default)]
pub struct ConsistencyChecker {
    // Mappings from raft group id to (first-index, last-index).
    raft_groups: HashMap<u64, (u64, u64)>,
    // Mappings from raft group id to last valid index.
    corrupted: HashMap<u64, u64>,
}

impl ConsistencyChecker {
    pub fn finish(self) -> HashMap<u64, u64> {
        self.corrupted
    }
}

impl ReplayMachine for ConsistencyChecker {
    fn replay(&mut self, item_batch: LogItemBatch, _file_id: FileId) -> Result<()> {
        for item in item_batch.iter() {
            if let LogItemContent::EntryIndexes(ents) = &item.content {
                if !ents.0.is_empty() {
                    let incoming_first_index = ents.0.first().unwrap().index;
                    let incoming_last_index = ents.0.last().unwrap().index;
                    let index_range = self
                        .raft_groups
                        .entry(item.raft_group_id)
                        .or_insert((incoming_first_index, incoming_last_index));
                    if index_range.1 + 1 < incoming_first_index {
                        self.corrupted
                            .entry(item.raft_group_id)
                            .or_insert(index_range.1);
                    }
                    index_range.1 = incoming_last_index;
                }
            }
        }
        Ok(())
    }

    fn merge(&mut self, mut rhs: Self, _queue: LogQueue) -> Result<()> {
        let mut corrupted_between_rhs: HashMap<u64, u64> = HashMap::default();
        for (id, (first, last)) in rhs.raft_groups.drain() {
            self.raft_groups
                .entry(id)
                .and_modify(|(_, l)| {
                    if *l + 1 < first {
                        corrupted_between_rhs.insert(id, *l);
                    }
                    *l = last;
                })
                .or_insert((first, last));
        }
        for (id, last_index) in corrupted_between_rhs.drain() {
            self.corrupted.entry(id).or_insert(last_index);
        }
        for (id, last_index) in rhs.corrupted.drain() {
            self.corrupted.entry(id).or_insert(last_index);
        }
        Ok(())
    }
}
