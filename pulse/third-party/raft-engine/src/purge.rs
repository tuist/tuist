// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use std::collections::VecDeque;
use std::collections::{HashMap, HashSet};
use std::mem;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use fail::fail_point;
use log::{info, warn};
use parking_lot::{Mutex, RwLock};

use crate::config::Config;
use crate::engine::read_entry_bytes_from_file;
use crate::event_listener::EventListener;
use crate::log_batch::{AtomicGroupBuilder, LogBatch};
use crate::memtable::{MemTableHandle, MemTables};
use crate::metrics::*;
use crate::pipe_log::{FileBlockHandle, FileId, FileSeq, LogQueue, PipeLog};
use crate::{GlobalStats, Result};

// Force compact region with oldest 20% logs.
const FORCE_COMPACT_RATIO: f64 = 0.2;
// Only rewrite region with oldest 70% logs.
const REWRITE_RATIO: f64 = 0.7;
// Only rewrite region with stale logs less than this threshold.
const MAX_REWRITE_ENTRIES_PER_REGION: usize = 32;
const MAX_COUNT_BEFORE_FORCE_REWRITE: u32 = 9;

fn max_batch_bytes() -> usize {
    fail_point!("max_rewrite_batch_bytes", |s| s
        .unwrap()
        .parse::<usize>()
        .unwrap());
    128 * 1024
}

fn max_forcely_sync_bytes() -> usize {
    max_batch_bytes() * 4
}

pub struct PurgeManager<P>
where
    P: PipeLog,
{
    cfg: Arc<Config>,
    memtables: MemTables,
    pipe_log: Arc<P>,
    global_stats: Arc<GlobalStats>,
    listeners: Vec<Arc<dyn EventListener>>,

    // Only one thread can run `purge_expired_files` at a time.
    //
    // This table records Raft Groups that should be force compacted before. Those that are not
    // compacted in time (after `MAX_EPOCH_BEFORE_FORCE_REWRITE` epochs) will be force rewritten.
    force_rewrite_candidates: Arc<Mutex<HashMap<u64, u32>>>,
}

impl<P> PurgeManager<P>
where
    P: PipeLog,
{
    pub fn new(
        cfg: Arc<Config>,
        memtables: MemTables,
        pipe_log: Arc<P>,
        global_stats: Arc<GlobalStats>,
        listeners: Vec<Arc<dyn EventListener>>,
    ) -> PurgeManager<P> {
        PurgeManager {
            cfg,
            memtables,
            pipe_log,
            global_stats,
            listeners,
            force_rewrite_candidates: Arc::new(Mutex::new(HashMap::default())),
        }
    }

    pub fn purge_expired_files(&self) -> Result<Vec<u64>> {
        let _t = StopWatch::new(&*ENGINE_PURGE_DURATION_HISTOGRAM);
        let guard = self.force_rewrite_candidates.try_lock();
        if guard.is_none() {
            warn!("Unable to purge expired files: locked");
            return Ok(vec![]);
        }
        let mut rewrite_candidate_regions = guard.unwrap();

        let mut should_compact = HashSet::new();
        if self.needs_rewrite_log_files(LogQueue::Rewrite) {
            should_compact.extend(self.rewrite_rewrite_queue()?);
            self.rescan_memtables_and_purge_stale_files(
                LogQueue::Rewrite,
                self.pipe_log.file_span(LogQueue::Rewrite).1,
            )?;
        }

        if self.needs_rewrite_log_files(LogQueue::Append) {
            if let (Some(rewrite_watermark), Some(compact_watermark)) =
                self.append_queue_watermarks()
            {
                let (first_append, latest_append) = self.pipe_log.file_span(LogQueue::Append);
                let append_queue_barrier =
                    self.listeners.iter().fold(latest_append, |barrier, l| {
                        l.first_file_not_ready_for_purge(LogQueue::Append)
                            .map_or(barrier, |f| std::cmp::min(f, barrier))
                    });

                // Ordering
                // 1. Must rewrite tombstones AFTER acquiring `append_queue_barrier`, or
                //    deletion marks might be lost after restart.
                // 2. Must rewrite tombstones BEFORE rewrite entries, or entries from recreated
                //    region might be lost after restart.
                self.rewrite_append_queue_tombstones()?;
                should_compact.extend(self.rewrite_or_compact_append_queue(
                    rewrite_watermark,
                    compact_watermark,
                    &mut rewrite_candidate_regions,
                )?);

                if append_queue_barrier == first_append && first_append < latest_append {
                    warn!("Unable to purge expired files: blocked by barrier");
                }
                self.rescan_memtables_and_purge_stale_files(
                    LogQueue::Append,
                    append_queue_barrier,
                )?;
            }
        }
        Ok(should_compact.into_iter().collect())
    }

    /// Rewrite append files with seqno no larger than `watermark`. When it's
    /// None, rewrite the entire queue. Returns the number of purged files.
    pub fn must_rewrite_append_queue(
        &self,
        watermark: Option<FileSeq>,
        exit_after_step: Option<u64>,
    ) {
        let _lk = self.force_rewrite_candidates.try_lock().unwrap();
        let (_, last) = self.pipe_log.file_span(LogQueue::Append);
        let watermark = watermark.map_or(last, |w| std::cmp::min(w, last));
        if watermark == last {
            self.pipe_log.rotate(LogQueue::Append).unwrap();
        }
        self.rewrite_append_queue_tombstones().unwrap();
        if exit_after_step == Some(1) {
            return;
        }
        self.rewrite_memtables(self.memtables.collect(|_| true), 0, Some(watermark))
            .unwrap();
        if exit_after_step == Some(2) {
            return;
        }
        self.rescan_memtables_and_purge_stale_files(
            LogQueue::Append,
            self.pipe_log.file_span(LogQueue::Append).1,
        )
        .unwrap();
    }

    pub fn must_rewrite_rewrite_queue(&self) {
        let _lk = self.force_rewrite_candidates.try_lock().unwrap();
        self.rewrite_rewrite_queue().unwrap();
        self.rescan_memtables_and_purge_stale_files(
            LogQueue::Rewrite,
            self.pipe_log.file_span(LogQueue::Rewrite).1,
        )
        .unwrap();
    }

    pub fn must_purge_all_stale(&self) {
        let _lk = self.force_rewrite_candidates.try_lock().unwrap();
        self.pipe_log.rotate(LogQueue::Rewrite).unwrap();
        self.rescan_memtables_and_purge_stale_files(
            LogQueue::Rewrite,
            self.pipe_log.file_span(LogQueue::Rewrite).1,
        )
        .unwrap();
        self.pipe_log.rotate(LogQueue::Append).unwrap();
        self.rescan_memtables_and_purge_stale_files(
            LogQueue::Append,
            self.pipe_log.file_span(LogQueue::Append).1,
        )
        .unwrap();
    }

    pub(crate) fn needs_rewrite_log_files(&self, queue: LogQueue) -> bool {
        let (first_file, active_file) = self.pipe_log.file_span(queue);
        if active_file == first_file {
            return false;
        }

        let total_size = self.pipe_log.total_size(queue);
        match queue {
            LogQueue::Append => total_size > self.cfg.purge_threshold.0 as usize,
            LogQueue::Rewrite => {
                let compacted_rewrites_ratio = self.global_stats.deleted_rewrite_entries() as f64
                    / self.global_stats.rewrite_entries() as f64;
                total_size > self.cfg.purge_rewrite_threshold.unwrap().0 as usize
                    && compacted_rewrites_ratio > self.cfg.purge_rewrite_garbage_ratio
            }
        }
    }

    // Returns (rewrite_watermark, compact_watermark).
    // Files older than compact_watermark should be compacted;
    // Files between compact_watermark and rewrite_watermark should be rewritten.
    fn append_queue_watermarks(&self) -> (Option<FileSeq>, Option<FileSeq>) {
        let queue = LogQueue::Append;

        let (first_file, active_file) = self.pipe_log.file_span(queue);
        if active_file == first_file {
            // Can't rewrite or force compact the active file.
            return (None, None);
        }

        let rewrite_watermark = self.pipe_log.file_at(queue, REWRITE_RATIO);
        let compact_watermark = self.pipe_log.file_at(queue, FORCE_COMPACT_RATIO);
        debug_assert!(active_file - 1 > 0);
        (
            Some(std::cmp::min(rewrite_watermark, active_file - 1)),
            Some(std::cmp::min(compact_watermark, active_file - 1)),
        )
    }

    fn rewrite_or_compact_append_queue(
        &self,
        rewrite_watermark: FileSeq,
        compact_watermark: FileSeq,
        rewrite_candidates: &mut HashMap<u64, u32>,
    ) -> Result<Vec<u64>> {
        let _t = StopWatch::new(&*ENGINE_REWRITE_APPEND_DURATION_HISTOGRAM);
        debug_assert!(compact_watermark <= rewrite_watermark);
        let mut should_compact = Vec::with_capacity(16);

        let mut new_candidates = HashMap::with_capacity(rewrite_candidates.len());
        let memtables = self.memtables.collect(|t| {
            let min_append_seq = t.min_file_seq(LogQueue::Append).unwrap_or(u64::MAX);
            let old = min_append_seq < compact_watermark || t.rewrite_count() > 0;
            let has_something_to_rewrite = min_append_seq <= rewrite_watermark;
            let append_heavy = t.has_at_least_some_entries_before(
                FileId::new(LogQueue::Append, rewrite_watermark),
                MAX_REWRITE_ENTRIES_PER_REGION + t.rewrite_count(),
            );
            let full_heavy = t.has_at_least_some_entries_before(
                FileId::new(LogQueue::Append, rewrite_watermark),
                MAX_REWRITE_ENTRIES_PER_REGION,
            );
            // counter is the times that target region triggers force compact.
            let compact_counter = rewrite_candidates.get(&t.region_id()).unwrap_or(&0);
            if old && full_heavy {
                if *compact_counter < MAX_COUNT_BEFORE_FORCE_REWRITE {
                    // repeatedly ask user to compact these heavy regions.
                    should_compact.push(t.region_id());
                    new_candidates.insert(t.region_id(), *compact_counter + 1);
                    return false;
                } else {
                    // user is not responsive, do the rewrite ourselves.
                    should_compact.push(t.region_id());
                    return has_something_to_rewrite;
                }
            }
            !append_heavy && has_something_to_rewrite
        });

        self.rewrite_memtables(
            memtables,
            MAX_REWRITE_ENTRIES_PER_REGION,
            Some(rewrite_watermark),
        )?;
        *rewrite_candidates = new_candidates;

        Ok(should_compact)
    }

    // Rewrites the entire rewrite queue into new log files.
    fn rewrite_rewrite_queue(&self) -> Result<Vec<u64>> {
        let _t = StopWatch::new(&*ENGINE_REWRITE_REWRITE_DURATION_HISTOGRAM);
        self.pipe_log.rotate(LogQueue::Rewrite)?;

        let mut force_compact_regions = vec![];
        let memtables = self.memtables.collect(|t| {
            // if the region is force rewritten, we should also trigger compact.
            if t.rewrite_count() > MAX_REWRITE_ENTRIES_PER_REGION {
                force_compact_regions.push(t.region_id());
            }
            t.min_file_seq(LogQueue::Rewrite).is_some()
        });

        self.rewrite_memtables(memtables, 0 /* expect_rewrites_per_memtable */, None)?;
        self.global_stats.reset_rewrite_counters();
        Ok(force_compact_regions)
    }

    fn rewrite_append_queue_tombstones(&self) -> Result<()> {
        let mut log_batch = self.memtables.take_cleaned_region_logs();
        self.rewrite_impl(
            &mut log_batch,
            None, /* rewrite_watermark */
            true, /* sync */
        )?;
        Ok(())
    }

    // Exclusive.
    fn rescan_memtables_and_purge_stale_files(&self, queue: LogQueue, seq: FileSeq) -> Result<()> {
        let min_seq = self.memtables.fold(seq, |min, t| {
            t.min_file_seq(queue).map_or(min, |m| std::cmp::min(min, m))
        });

        let purged = self.pipe_log.purge_to(FileId {
            queue,
            seq: min_seq,
        })?;
        if purged > 0 {
            info!("purged {purged} expired log files for queue {queue:?}");
            for listener in &self.listeners {
                listener.post_purge(FileId {
                    queue,
                    seq: min_seq - 1,
                });
            }
        }
        Ok(())
    }

    fn rewrite_memtables(
        &self,
        memtables: Vec<MemTableHandle>,
        expect_rewrites_per_memtable: usize,
        rewrite: Option<FileSeq>,
    ) -> Result<()> {
        // Only use atomic group for rewrite-rewrite operation.
        let needs_atomicity = (|| {
            fail_point!("force_use_atomic_group", |_| true);
            rewrite.is_none()
        })();
        let mut log_batch = LogBatch::default();
        for memtable in memtables {
            let mut entry_indexes = Vec::with_capacity(expect_rewrites_per_memtable);
            let mut kvs = Vec::new();
            let region_id = {
                let m = memtable.read();
                if let Some(rewrite) = rewrite {
                    m.fetch_entry_indexes_before(rewrite, &mut entry_indexes)?;
                    m.fetch_kvs_before(rewrite, &mut kvs);
                } else {
                    m.fetch_rewritten_entry_indexes(&mut entry_indexes)?;
                    m.fetch_rewritten_kvs(&mut kvs);
                }
                m.region_id()
            };

            let mut previous_size = log_batch.approximate_size();
            let mut atomic_group = None;
            let mut atomic_group_start = None;
            let mut current_entry_indexes = Vec::new();
            let mut current_entries = Vec::new();
            let mut current_size = 0;
            let mut unsynced_size = 0;
            // Split the entries into smaller chunks, so that we don't OOM, and the
            // compression overhead is not too high.
            let mut entry_indexes = entry_indexes.into_iter().peekable();
            while let Some(ei) = entry_indexes.next() {
                let entry = read_entry_bytes_from_file(self.pipe_log.as_ref(), &ei)?;
                current_size += entry.len();
                current_entries.push(entry);
                current_entry_indexes.push(ei);
                unsynced_size += current_size;
                // If this is the last entry, we handle them outside the loop.
                if entry_indexes.peek().is_some()
                    && current_size + previous_size > max_batch_bytes()
                {
                    if needs_atomicity {
                        if previous_size > 0 {
                            // We are certain that prev raft group and current raft group cannot fit
                            // inside one batch.
                            // To avoid breaking atomicity, we need to flush.
                            self.rewrite_impl(&mut log_batch, rewrite, false)?;
                            previous_size = 0;
                            if current_size <= max_batch_bytes() {
                                continue;
                            }
                        }
                        match atomic_group.as_mut() {
                            None => {
                                let mut g = AtomicGroupBuilder::default();
                                g.begin(&mut log_batch);
                                atomic_group = Some(g);
                            }
                            Some(g) => {
                                g.add(&mut log_batch);
                            }
                        }
                    }

                    log_batch.add_raw_entries(
                        region_id,
                        mem::take(&mut current_entry_indexes),
                        mem::take(&mut current_entries),
                    )?;
                    current_size = 0;
                    previous_size = 0;
                    let sync = if unsynced_size >= max_forcely_sync_bytes() {
                        // Avoiding too many unsynced size can make the later `fdatasync` in
                        // the append progress blocked for too long.
                        unsynced_size = 0;
                        true
                    } else {
                        false
                    };
                    let handle = self.rewrite_impl(&mut log_batch, rewrite, sync)?.unwrap();
                    if needs_atomicity && atomic_group_start.is_none() {
                        atomic_group_start = Some(handle.id.seq);
                    }
                }
            }
            log_batch.add_raw_entries(region_id, current_entry_indexes, current_entries)?;
            for (k, v) in kvs {
                log_batch.put(region_id, k, v)?;
            }
            if let Some(g) = atomic_group.as_mut() {
                g.end(&mut log_batch);
                let handle = self.rewrite_impl(&mut log_batch, rewrite, false)?.unwrap();
                self.memtables.apply_rewrite_atomic_group(
                    region_id,
                    atomic_group_start.unwrap(),
                    handle.id.seq,
                );
            } else if log_batch.approximate_size() > max_batch_bytes() {
                self.rewrite_impl(&mut log_batch, rewrite, false)?;
            }
        }
        self.rewrite_impl(&mut log_batch, rewrite, true)?;
        Ok(())
    }

    fn rewrite_impl(
        &self,
        log_batch: &mut LogBatch,
        rewrite_watermark: Option<FileSeq>,
        sync: bool,
    ) -> Result<Option<FileBlockHandle>> {
        if log_batch.is_empty() {
            debug_assert!(sync);
            self.pipe_log.sync(LogQueue::Rewrite)?;
            return Ok(None);
        }
        log_batch.finish_populate(
            self.cfg.batch_compression_threshold.0 as usize,
            self.cfg.compression_level,
        )?;
        let file_handle = self.pipe_log.append(LogQueue::Rewrite, log_batch)?;
        if sync {
            self.pipe_log.sync(LogQueue::Rewrite)?;
        }
        log_batch.finish_write(file_handle);
        self.memtables.apply_rewrite_writes(
            log_batch.drain(),
            rewrite_watermark,
            file_handle.id.seq,
        );
        for listener in &self.listeners {
            listener.post_apply_memtables(file_handle.id);
        }
        if rewrite_watermark.is_none() {
            BACKGROUND_REWRITE_BYTES
                .rewrite
                .observe(file_handle.len as f64);
        } else {
            BACKGROUND_REWRITE_BYTES
                .append
                .observe(file_handle.len as f64);
        }
        Ok(Some(file_handle))
    }
}

#[derive(Default)]
pub struct PurgeHook {
    // Append queue log files that are not yet fully applied to MemTable must not be
    // purged even when not referenced by any MemTable.
    // In order to identify them, maintain a per-file reference counter for all active
    // log files in append queue. No need to track rewrite queue because it is only
    // written by purge thread.
    active_log_files: RwLock<VecDeque<(FileSeq, AtomicUsize)>>,
}

impl EventListener for PurgeHook {
    fn post_new_log_file(&self, file_id: FileId) {
        if file_id.queue == LogQueue::Append {
            let mut active_log_files = self.active_log_files.write();
            if let Some(seq) = active_log_files.back().map(|x| x.0) {
                assert_eq!(
                    seq + 1,
                    file_id.seq,
                    "active log files should be contiguous"
                );
            }
            let counter = AtomicUsize::new(0);
            active_log_files.push_back((file_id.seq, counter));
        }
    }

    fn on_append_log_file(&self, handle: FileBlockHandle) {
        if handle.id.queue == LogQueue::Append {
            let active_log_files = self.active_log_files.read();
            assert!(!active_log_files.is_empty());
            let front = active_log_files[0].0;
            let counter = &active_log_files[(handle.id.seq - front) as usize].1;
            counter.fetch_add(1, Ordering::Release);
        }
    }

    fn post_apply_memtables(&self, file_id: FileId) {
        if file_id.queue == LogQueue::Append {
            let active_log_files = self.active_log_files.read();
            assert!(!active_log_files.is_empty());
            let front = active_log_files[0].0;
            let counter = &active_log_files[(file_id.seq - front) as usize].1;
            counter.fetch_sub(1, Ordering::Release);
        }
    }

    fn first_file_not_ready_for_purge(&self, queue: LogQueue) -> Option<FileSeq> {
        if queue == LogQueue::Append {
            let active_log_files = self.active_log_files.read();
            for (id, counter) in active_log_files.iter() {
                if counter.load(Ordering::Acquire) > 0 {
                    return Some(*id);
                }
            }
        }
        None
    }

    fn post_purge(&self, file_id: FileId) {
        if file_id.queue == LogQueue::Append {
            let mut active_log_files = self.active_log_files.write();
            assert!(!active_log_files.is_empty());
            let front = active_log_files[0].0;
            if front <= file_id.seq {
                let mut purged = active_log_files.drain(0..=(file_id.seq - front) as usize);
                assert_eq!(purged.next_back().unwrap().0, file_id.seq);
            }
        }
    }
}
