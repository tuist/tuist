// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use std::path::Path;
use std::sync::Arc;

use hashbrown::HashMap;
use rhai::{Engine, Scope, AST};
use scopeguard::{guard, ScopeGuard};

use crate::env::FileSystem;
use crate::file_pipe_log::debug::{build_file_reader, build_file_writer};
use crate::file_pipe_log::{FileNameExt, ReplayMachine};
use crate::log_batch::{
    Command, EntryIndexes, KeyValue, LogBatch, LogItem, LogItemBatch, LogItemContent, OpType,
};
use crate::pipe_log::{FileId, LogFileContext, LogQueue};
use crate::util::Factory;
use crate::{Error, Result};

/// `FilterResult` determines how to alter the existing log items in
/// `RhaiFilterMachine`.
#[derive(PartialEq, Eq)]
enum FilterResult {
    /// Apply in the usual way.
    Default,
    /// Ignore all incoming entries or operations.
    DiscardIncoming,
    /// Delete all existing entries.
    DiscardExisting,
}

impl FilterResult {
    fn from_i64(i: i64) -> Self {
        match i {
            0 => FilterResult::Default,
            1 => FilterResult::DiscardIncoming,
            2 => FilterResult::DiscardExisting,
            _ => unreachable!(),
        }
    }
}

/// `RaftGroupState` represents a simplistic view of a Raft Group.
#[derive(Copy, Clone)]
struct RaftGroupState {
    pub first_index: u64,
    pub count: usize,
    pub rewrite_count: usize,
}

impl RaftGroupState {
    /// Removes all data in this Raft Group.
    pub fn clear(&mut self) {
        self.first_index = 0;
        self.count = 0;
        self.rewrite_count = 0;
    }

    /// Applies `item` from `queue` into this Raft Group state.
    pub fn apply(&mut self, queue: LogQueue, item: &LogItemContent) -> Result<()> {
        match item {
            LogItemContent::EntryIndexes(EntryIndexes(eis)) => {
                if let (Some(first), Some(last)) = (eis.first(), eis.last()) {
                    let first = first.index;
                    let last = last.index;
                    if self.count > 0 {
                        // hole
                        if first > self.first_index + self.count as u64 {
                            if queue == LogQueue::Append {
                                return Err(Error::Corruption("Encountered hole".to_owned()));
                            } else {
                                self.clear();
                            }
                        }
                        // compacted
                        if first < self.first_index {
                            if queue == LogQueue::Append {
                                return Err(Error::Corruption("Write to compacted".to_owned()));
                            } else {
                                self.clear();
                            }
                        }
                        // non-contiguous rewrites
                        if queue == LogQueue::Rewrite
                            && self.first_index + (self.rewrite_count as u64) < first
                        {
                            return Err(Error::Corruption(
                                "Rewrites are not contiguous".to_owned(),
                            ));
                        }
                    }
                    if self.count == 0 {
                        // empty
                        self.first_index = first;
                        self.count = (last - first + 1) as usize;
                        self.rewrite_count = if queue == LogQueue::Rewrite {
                            self.count
                        } else {
                            0
                        };
                    } else {
                        self.count = (last - self.first_index + 1) as usize;
                        if queue == LogQueue::Rewrite {
                            self.rewrite_count = self.count;
                        } else {
                            self.rewrite_count = (first - self.first_index) as usize;
                        }
                    }
                }
            }
            LogItemContent::Command(Command::Compact { index })
                if *index > self.first_index && self.count > 0 =>
            {
                if *index < self.first_index + self.count as u64 - 1 {
                    let deleted = *index - self.first_index;
                    self.first_index = *index;
                    self.rewrite_count = self.rewrite_count.saturating_sub(deleted as usize);
                } else {
                    self.clear();
                }
            }
            LogItemContent::Command(Command::Clean) => self.clear(),
            _ => {}
        }
        Ok(())
    }
}

/// `RhaiFilter` is a stateless machine that filters incoming log items. Its
/// filtering logic is implemented in Rhai script.
/// Sample script:
/// ```rhai
/// fn filter_append(id, first, count, rewrite_count, queue, ifirst, ilast) {
///   if ifirst < first {
///     return 1; // discard incoming
///   }
///   0 // default
/// }
///
/// fn filter_compact(id, first, count, rewrite_count, queue, compact_to) {
///   0 // default
/// }
///
/// fn filter_clean(id, first, count, rewrite_count, queue) {
///   if queue == 1 { // rewrite queue
///     return 1; // discard incoming
///   }
///   0 // default
/// }
/// ```
struct RhaiFilter {
    engine: Arc<Engine>,
    ast: Arc<AST>,
    scope: Scope<'static>,
}

impl RhaiFilter {
    /// Filters `new_item_content` from `new_item_queue` intended to be applied
    /// to the Raft Group.
    pub fn filter(
        &mut self,
        raft_group_id: u64,
        state: RaftGroupState,
        new_item_queue: LogQueue,
        new_item_content: &LogItemContent,
    ) -> Result<FilterResult> {
        let res = match new_item_content {
            LogItemContent::EntryIndexes(EntryIndexes(eis)) if !eis.is_empty() => {
                self.engine.call_fn(
                    &mut self.scope,
                    &self.ast,
                    "filter_append",
                    (
                        raft_group_id as i64,
                        state.first_index as i64,
                        state.count as i64,
                        state.rewrite_count as i64,
                        new_item_queue as i64,
                        eis.first().unwrap().index as i64,
                        eis.last().unwrap().index as i64,
                    ),
                )
            }
            LogItemContent::Command(Command::Compact { index }) => self.engine.call_fn(
                &mut self.scope,
                &self.ast,
                "filter_compact",
                (
                    raft_group_id as i64,
                    state.first_index as i64,
                    state.count as i64,
                    state.rewrite_count as i64,
                    new_item_queue as i64,
                    *index as i64,
                ),
            ),
            LogItemContent::Command(Command::Clean) => self.engine.call_fn(
                &mut self.scope,
                &self.ast,
                "filter_clean",
                (
                    raft_group_id as i64,
                    state.first_index as i64,
                    state.count as i64,
                    state.rewrite_count as i64,
                    new_item_queue as i64,
                ),
            ),
            _ => Ok(0),
        };
        match res {
            Ok(n) => Ok(FilterResult::from_i64(n)),
            Err(e) => {
                if matches!(*e, rhai::EvalAltResult::ErrorFunctionNotFound(_, _)) {
                    Ok(FilterResult::Default)
                } else {
                    Err(Error::Corruption(e.to_string()))
                }
            }
        }
    }
}

struct FileAndItems {
    file_id: FileId,
    items: Vec<LogItem>,
    filtered: bool,
}

/// `RhaiFilterMachine` is a `ReplayMachine` that filters existing log files
/// based on external Rhai script.
pub struct RhaiFilterMachine {
    filter: RhaiFilter,
    files: Vec<FileAndItems>,
    states: HashMap<u64, RaftGroupState>,
}

impl RhaiFilterMachine {
    fn new(filter: RhaiFilter) -> Self {
        Self {
            filter,
            files: Vec::new(),
            states: HashMap::new(),
        }
    }

    /// Writes out filtered log items and replaces existing log files. Always
    /// attempt to recover original log files on error. Panics if that recovery
    /// fails.
    pub fn finish<F: FileSystem>(self, system: &F, path: &Path) -> Result<()> {
        let mut log_batch = LogBatch::default();
        let mut guards = Vec::new();
        for f in self.files.into_iter() {
            if f.filtered {
                // Backup file and set up a guard to recover on exit.
                let target_path = f.file_id.build_file_path(path);
                let bak_path = target_path.with_extension("bak");
                system.rename(&target_path, &bak_path)?;
                guards.push((
                    bak_path.clone(),
                    guard(f.file_id, |f| {
                        let original = f.build_file_path(path);
                        let bak = original.with_extension("bak");
                        if bak.exists() {
                            system.rename(&bak, &original).unwrap_or_else(|e| {
                                panic!(
                                    "Failed to recover original log file {} ({e}),
                                you should manually replace it with {}.bak.",
                                    f.build_file_name(),
                                    f.build_file_name(),
                                )
                            });
                        }
                    }),
                ));
                let mut reader = build_file_reader(system, &bak_path)?;
                let format = reader.parse_format()?;
                let mut writer =
                    build_file_writer(system, &target_path, format, true /* create */)?;
                let log_file_context = LogFileContext::new(f.file_id, format.version);
                // Write out new log file.
                for item in f.items.into_iter() {
                    match item.content {
                        LogItemContent::EntryIndexes(EntryIndexes(eis)) => {
                            let mut entries = Vec::with_capacity(eis.len());
                            for ei in &eis {
                                let entries_buf = reader.read(ei.entries.unwrap())?;
                                let block = LogBatch::decode_entries_block(
                                    &entries_buf,
                                    ei.entries.unwrap(),
                                    ei.compression_type,
                                )?;
                                entries.push(
                                    block[ei.entry_offset as usize
                                        ..(ei.entry_offset + ei.entry_len) as usize]
                                        .to_owned(),
                                );
                            }
                            log_batch.add_raw_entries(item.raft_group_id, eis, entries)?;
                        }
                        LogItemContent::Command(cmd) => {
                            log_batch.add_command(item.raft_group_id, cmd);
                        }
                        LogItemContent::Kv(KeyValue {
                            op_type,
                            key,
                            value,
                            ..
                        }) => match op_type {
                            OpType::Put => {
                                log_batch.put(item.raft_group_id, key, value.unwrap())?
                            }
                            OpType::Del => log_batch.delete(item.raft_group_id, key),
                        },
                    }
                    // Batch 64KB.
                    if log_batch.approximate_size() >= 64 * 1024 {
                        log_batch.finish_populate(0 /* compression_threshold */, None)?;
                        log_batch.prepare_write(&log_file_context)?;
                        writer.write(
                            log_batch.encoded_bytes(),
                            usize::MAX, /* target_size_hint */
                        )?;
                        log_batch.drain();
                    }
                }
                if !log_batch.is_empty() {
                    log_batch.finish_populate(0 /* compression_threshold */, None)?;
                    log_batch.prepare_write(&log_file_context)?;
                    writer.write(
                        log_batch.encoded_bytes(),
                        usize::MAX, /* target_size_hint */
                    )?;
                    log_batch.drain();
                }
                writer.close()?;
            }
        }
        // Delete backup file and defuse the guard.
        for (bak, guard) in guards.into_iter() {
            let _ = std::fs::remove_file(bak);
            let _ = ScopeGuard::into_inner(guard);
        }
        Ok(())
    }

    /// Assumes the last element in `self.files` is `file_id`.
    fn replay_item(&mut self, item: LogItem, file_id: FileId) -> Result<()> {
        let current = self.files.last_mut().unwrap();
        let state = self
            .states
            .entry(item.raft_group_id)
            .or_insert(RaftGroupState {
                first_index: 0,
                count: 0,
                rewrite_count: 0,
            });
        let result =
            self.filter
                .filter(item.raft_group_id, *state, file_id.queue, &item.content)?;
        if result == FilterResult::DiscardIncoming {
            current.filtered = true;
            return Ok(());
        } else if result == FilterResult::DiscardExisting {
            current.filtered = true;
            state.clear();
            current.items.push(LogItem::new_command(
                item.raft_group_id,
                Command::Compact { index: u64::MAX },
            ));
        }
        state.apply(file_id.queue, &item.content)?;
        current.items.push(item.clone());
        Ok(())
    }
}

impl ReplayMachine for RhaiFilterMachine {
    fn replay(&mut self, mut item_batch: LogItemBatch, file_id: FileId) -> Result<()> {
        if self.files.is_empty() || self.files.last().unwrap().file_id != file_id {
            self.files.push(FileAndItems {
                file_id,
                items: Vec::new(),
                filtered: false,
            });
        }
        for item in item_batch.drain() {
            self.replay_item(item, file_id)?;
        }
        Ok(())
    }

    fn merge(&mut self, rhs: Self, _queue: LogQueue) -> Result<()> {
        for f in rhs.files.into_iter() {
            if self.files.is_empty() || self.files.last().unwrap().file_id != f.file_id {
                self.files.push(FileAndItems {
                    file_id: f.file_id,
                    items: Vec::new(),
                    filtered: f.filtered,
                });
            }
            for item in f.items.into_iter() {
                self.replay_item(item, f.file_id)?;
            }
        }
        Ok(())
    }
}

pub struct RhaiFilterMachineFactory {
    engine: Arc<Engine>,
    ast: Arc<AST>,
}

impl RhaiFilterMachineFactory {
    pub fn from_script(script: String) -> Self {
        let engine = Engine::new();
        let ast = engine.compile(script).unwrap();
        engine.run_ast_with_scope(&mut Scope::new(), &ast).unwrap();
        Self {
            engine: Arc::new(engine),
            ast: Arc::new(ast),
        }
    }
}

impl Factory<RhaiFilterMachine> for RhaiFilterMachineFactory {
    fn new_target(&self) -> RhaiFilterMachine {
        let filter = RhaiFilter {
            engine: self.engine.clone(),
            ast: self.ast.clone(),
            scope: Scope::new(),
        };
        RhaiFilterMachine::new(filter)
    }
}
