// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

//! Helper types to recover in-memory states from log files.

use std::fs::{self, File as StdFile};
use std::io::Write;
use std::marker::PhantomData;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use fs2::FileExt;
use log::{error, info, warn};
use rayon::prelude::*;

use crate::config::{Config, RecoveryMode};
use crate::env::{FileSystem, Handle, Permission};
use crate::errors::is_no_space_err;
use crate::event_listener::EventListener;
use crate::log_batch::{LogItemBatch, LOG_BATCH_HEADER_LEN};
use crate::pipe_log::{FileId, FileSeq, LogQueue};
use crate::util::{Factory, ReadableSize};
use crate::{Error, Result};

use super::format::{
    build_reserved_file_name, lock_file_path, parse_reserved_file_name, FileNameExt, LogFileFormat,
};
use super::log_file::build_file_reader;
use super::pipe::{
    find_available_dir, DualPipes, File, PathId, Paths, SinglePipe, DEFAULT_FIRST_FILE_SEQ,
};
use super::reader::LogItemBatchFileReader;

/// Maximum size for the buffer for prefilling.
const PREFILL_BUFFER_SIZE: usize = ReadableSize::mb(16).0 as usize;

/// `ReplayMachine` is a type of deterministic state machine that obeys
/// associative law.
///
/// Sequentially arranged log items can be divided and replayed to several
/// [`ReplayMachine`]s, and their merged state will be the same as when
/// replayed to one single [`ReplayMachine`].
///
/// This abstraction is useful for recovery in parallel: a set of log files can
/// be replayed in a divide-and-conquer fashion.
pub trait ReplayMachine: Send {
    /// Inputs a batch of log items from the given file to this machine.
    /// Returns whether the input sequence up till now is accepted.
    fn replay(&mut self, item_batch: LogItemBatch, file_id: FileId) -> Result<()>;

    /// Merges with another [`ReplayMachine`] that has consumed newer log items
    /// in the same input sequence.
    fn merge(&mut self, rhs: Self, queue: LogQueue) -> Result<()>;
}

/// A factory of [`ReplayMachine`]s that can be default constructed.
#[derive(Clone, Default)]
pub struct DefaultMachineFactory<M>(PhantomData<std::sync::Mutex<M>>);

impl<M: ReplayMachine + Default> Factory<M> for DefaultMachineFactory<M> {
    fn new_target(&self) -> M {
        M::default()
    }
}

/// Container for basic settings on recovery.
pub struct RecoveryConfig {
    pub queue: LogQueue,
    pub mode: RecoveryMode,
    pub concurrency: usize,
    pub read_block_size: u64,
}

/// [`DualPipes`] factory that can also recover other customized memory states.
pub struct DualPipesBuilder<F: FileSystem> {
    cfg: Config,
    file_system: Arc<F>,
    listeners: Vec<Arc<dyn EventListener>>,

    /// Only filled after a successful call of `DualPipesBuilder::scan`.
    dirs: Paths,
    dir_locks: Vec<StdFile>,

    pub(crate) append_file_names: Vec<FileName>,
    pub(crate) rewrite_file_names: Vec<FileName>,
    pub(crate) recycled_file_names: Vec<FileName>,

    append_files: Vec<File<F>>,
    rewrite_files: Vec<File<F>>,
    recycled_files: Vec<File<F>>,
}

impl<F: FileSystem> DualPipesBuilder<F> {
    /// Creates a new builder.
    pub fn new(cfg: Config, file_system: Arc<F>, listeners: Vec<Arc<dyn EventListener>>) -> Self {
        Self {
            cfg,
            file_system,
            listeners,
            dirs: Vec::new(),
            dir_locks: Vec::new(),
            append_file_names: Vec::new(),
            rewrite_file_names: Vec::new(),
            recycled_file_names: Vec::new(),
            append_files: Vec::new(),
            rewrite_files: Vec::new(),
            recycled_files: Vec::new(),
        }
    }

    /// Scans for all log files under the working directory. The directory will
    /// be created if not exists.
    pub fn scan(&mut self) -> Result<()> {
        self.scan_and_sort(true)?;

        // Open all files with suitable permissions.
        self.append_files = Vec::with_capacity(self.append_file_names.len());
        for (i, file_name) in self.append_file_names.iter().enumerate() {
            let perm = if i == self.append_file_names.len() - 1
                || self.cfg.recovery_mode == RecoveryMode::TolerateAnyCorruption
            {
                Permission::ReadWrite
            } else {
                Permission::ReadOnly
            };
            self.append_files.push(File {
                seq: file_name.seq,
                handle: Arc::new(self.file_system.open(&file_name.path, perm)?),
                format: LogFileFormat::default(),
                path_id: file_name.path_id,
                reserved: false,
            });
        }
        self.rewrite_files = Vec::with_capacity(self.rewrite_file_names.len());
        for (i, file_name) in self.rewrite_file_names.iter().enumerate() {
            let perm = if i == self.rewrite_file_names.len() - 1
                || self.cfg.recovery_mode == RecoveryMode::TolerateAnyCorruption
            {
                Permission::ReadWrite
            } else {
                Permission::ReadOnly
            };
            self.rewrite_files.push(File {
                seq: file_name.seq,
                handle: Arc::new(self.file_system.open(&file_name.path, perm)?),
                format: LogFileFormat::default(),
                path_id: file_name.path_id,
                reserved: false,
            });
        }
        self.recycled_files = Vec::with_capacity(self.recycled_file_names.len());
        for file_name in &self.recycled_file_names {
            self.recycled_files.push(File {
                seq: file_name.seq,
                handle: Arc::new(
                    self.file_system
                        .open(&file_name.path, Permission::ReadOnly)?,
                ),
                format: LogFileFormat::default(),
                path_id: file_name.path_id,
                reserved: true,
            });
        }

        // Validate and clear obsolete metadata and log files.
        for (queue, files, is_recycled_file) in [
            (LogQueue::Append, &mut self.append_files, false),
            (LogQueue::Rewrite, &mut self.rewrite_files, false),
            (LogQueue::Append, &mut self.recycled_files, true),
        ] {
            // Check the file_list and remove the hole of files.
            let mut invalid_idx = 0_usize;
            for (i, file_pair) in files.windows(2).enumerate() {
                // If there exists a black hole or duplicate scenario on FileSeq, these
                // files should be skipped and cleared.
                if file_pair[1].seq - file_pair[0].seq != 1 {
                    invalid_idx = i + 1;
                }
            }
            files.drain(..invalid_idx);
            // Try to cleanup stale metadata left by the previous version.
            if files.is_empty() || is_recycled_file {
                continue;
            }
            let max_sample = 100;
            // Find the first obsolete metadata.
            let mut delete_start = None;
            for i in 0..max_sample {
                let seq = i * files[0].seq / max_sample;
                let file_id = FileId { queue, seq };
                for dir in self.dirs.iter() {
                    if self
                        .file_system
                        .exists_metadata(file_id.build_file_path(dir))
                    {
                        delete_start = Some(i.saturating_sub(1) * files[0].seq / max_sample + 1);
                        break;
                    }
                }
                if delete_start.is_some() {
                    break;
                }
            }
            // Delete metadata starting from the oldest. Abort on error.
            let mut cleared = 0_u64;
            if let Some(clear_start) = delete_start {
                for seq in (clear_start..files[0].seq).rev() {
                    let file_id = FileId { queue, seq };
                    for dir in self.dirs.iter() {
                        let path = if is_recycled_file {
                            dir.join(build_reserved_file_name(seq))
                        } else {
                            file_id.build_file_path(dir)
                        };
                        if self.file_system.exists_metadata(&path) {
                            if let Err(e) = self.file_system.delete_metadata(&path) {
                                error!("failed to delete metadata of {}: {e}.", path.display());
                                break;
                            }
                            cleared += 1;
                        }
                    }
                }
            }
            if cleared > 0 {
                warn!(
                    "clear {cleared} stale metadata of {queue:?} in range [0, {}).",
                    files[0].seq,
                );
            }
        }
        Ok(())
    }

    pub(crate) fn scan_and_sort(&mut self, lock: bool) -> Result<()> {
        let dir = self.cfg.dir.clone();
        self.scan_dir(&dir, lock)?;

        if let Some(dir) = self.cfg.spill_dir.clone() {
            self.scan_dir(&dir, lock)?;
        }

        self.append_file_names.sort_by(|a, b| a.seq.cmp(&b.seq));
        self.rewrite_file_names.sort_by(|a, b| a.seq.cmp(&b.seq));
        self.recycled_file_names.sort_by(|a, b| a.seq.cmp(&b.seq));
        Ok(())
    }

    fn scan_dir(&mut self, dir: &str, lock: bool) -> Result<()> {
        let dir = Path::new(dir);
        if !dir.exists() {
            if lock {
                info!("Create raft log directory: {}", dir.display());
                fs::create_dir(dir)?;
                self.dir_locks.push(lock_dir(dir)?);
            }
            self.dirs.push(dir.to_path_buf());
            return Ok(());
        }
        if !dir.is_dir() {
            return Err(box_err!("Not directory: {}", dir.display()));
        }
        if lock {
            self.dir_locks.push(lock_dir(dir)?);
        }
        self.dirs.push(dir.to_path_buf());
        let path_id = self.dirs.len() - 1;

        fs::read_dir(dir)?.try_for_each(|e| -> Result<()> {
            let dir_entry = e?;
            let p = dir_entry.path();
            if !p.is_file() {
                return Ok(());
            }
            let file_name = p.file_name().unwrap().to_str().unwrap();
            match FileId::parse_file_name(file_name) {
                Some(FileId {
                    queue: LogQueue::Append,
                    seq,
                }) => self.append_file_names.push(FileName {
                    seq,
                    path: p,
                    path_id,
                }),
                Some(FileId {
                    queue: LogQueue::Rewrite,
                    seq,
                }) => self.rewrite_file_names.push(FileName {
                    seq,
                    path: p,
                    path_id,
                }),
                _ => {
                    if let Some(seq) = parse_reserved_file_name(file_name) {
                        self.recycled_file_names.push(FileName {
                            seq,
                            path: p,
                            path_id,
                        })
                    }
                }
            }
            Ok(())
        })
    }

    /// Reads through log items in all available log files, and replays them to
    /// specific [`ReplayMachine`]s that can be constructed via
    /// `machine_factory`.
    pub fn recover<M: ReplayMachine, FA: Factory<M>>(
        &mut self,
        machine_factory: &FA,
    ) -> Result<(M, M)> {
        if self.append_files.is_empty() && self.rewrite_files.is_empty() {
            // Avoid creating a thread pool.
            return Ok((machine_factory.new_target(), machine_factory.new_target()));
        }
        let threads = std::cmp::min(
            self.cfg.recovery_threads,
            self.append_files.len() + self.rewrite_files.len(),
        );
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(threads)
            .build()
            .unwrap();
        let (append_concurrency, rewrite_concurrency) =
            match (self.append_files.len(), self.rewrite_files.len()) {
                (a, b) if a > 0 && b > 0 => {
                    let a_threads = std::cmp::max(1, threads * a / (a + b));
                    let b_threads = std::cmp::max(1, threads.saturating_sub(a_threads));
                    (a_threads, b_threads)
                }
                _ => (threads, threads),
            };
        let append_recovery_cfg = RecoveryConfig {
            queue: LogQueue::Append,
            mode: self.cfg.recovery_mode,
            concurrency: append_concurrency,
            read_block_size: self.cfg.recovery_read_block_size.0,
        };
        let rewrite_recovery_cfg = RecoveryConfig {
            queue: LogQueue::Rewrite,
            concurrency: rewrite_concurrency,
            ..append_recovery_cfg
        };

        let append_files = &mut self.append_files;
        let rewrite_files = &mut self.rewrite_files;

        let file_system = self.file_system.clone();
        // As the `recover_queue` would update the `LogFileFormat` of each log file
        // in `apend_files` and `rewrite_files`, we re-design the implementation on
        // `recover_queue` to make it compatiable to concurrent processing
        // with ThreadPool.
        let (append, rewrite) = pool.join(
            || {
                DualPipesBuilder::recover_queue_imp(
                    file_system.clone(),
                    append_recovery_cfg,
                    append_files,
                    machine_factory,
                )
            },
            || {
                DualPipesBuilder::recover_queue_imp(
                    file_system.clone(),
                    rewrite_recovery_cfg,
                    rewrite_files,
                    machine_factory,
                )
            },
        );
        Ok((append?, rewrite?))
    }

    /// Manually reads through log items in all available log files of the
    /// specified queue, and replays them to specific [`ReplayMachine`]s
    /// that can be constructed via `machine_factory`.
    fn recover_queue_imp<M: ReplayMachine, FA: Factory<M>>(
        file_system: Arc<F>,
        recovery_cfg: RecoveryConfig,
        files: &mut Vec<File<F>>,
        machine_factory: &FA,
    ) -> Result<M> {
        if recovery_cfg.concurrency == 0 || files.is_empty() {
            return Ok(machine_factory.new_target());
        }
        let queue = recovery_cfg.queue;
        let concurrency = recovery_cfg.concurrency;
        let recovery_mode = recovery_cfg.mode;
        let recovery_read_block_size = recovery_cfg.read_block_size as usize;

        let max_chunk_size = std::cmp::max((files.len() + concurrency - 1) / concurrency, 1);
        let chunks = files.par_chunks_mut(max_chunk_size);
        let chunk_count = chunks.len();
        debug_assert!(chunk_count <= concurrency);
        let machine = chunks
            .enumerate()
            .map(|(index, chunk)| {
                let mut reader =
                    LogItemBatchFileReader::new(recovery_read_block_size);
                let mut machine = machine_factory.new_target();
                let file_count = chunk.len();
                for (i, f) in chunk.iter_mut().enumerate() {
                    let is_last_file = index == chunk_count - 1 && i == file_count - 1;
                    let file_reader = build_file_reader(file_system.as_ref(), f.handle.clone())?;
                    match reader.open(FileId { queue, seq: f.seq }, file_reader) {
                        Err(e) if matches!(e, Error::Io(_)) => return Err(e),
                        Err(e) => {
                            // TODO: More reliable tail detection.
                            if recovery_mode == RecoveryMode::TolerateAnyCorruption
                              || recovery_mode == RecoveryMode::TolerateTailCorruption
                                && is_last_file {
                                warn!(
                                    "Truncating log file due to broken header (queue={:?},seq={}): {}",
                                    queue, f.seq, e
                                );
                                f.handle.truncate(0)?;
                                f.format = LogFileFormat::default();
                                continue;
                            } else {
                                error!(
                                    "Failed to open log file due to broken header (queue={:?},seq={}): {}",
                                    queue, f.seq, e
                                );
                                return Err(e);
                            }
                        },
                        Ok(format) => {
                            f.format = format;
                        }
                    }
                    let mut pending_item = None;
                    loop {
                        match pending_item.unwrap_or_else(|| reader.next()) {
                            Ok(Some(item_batch)) => {
                                let next_item = reader.next();
                                // This is the last item. Check entries block.
                                if_chain::if_chain! {
                                    if matches!(next_item, Err(_) | Ok(None));
                                    if let Some(ei) = item_batch.entry_index();
                                    let handle = ei.entries.unwrap();
                                    if let Err(e) = crate::LogBatch::decode_entries_block(
                                        &reader.reader.as_mut().unwrap().read(handle)?,
                                        handle,
                                        ei.compression_type,
                                    );
                                    then {
                                        let offset = handle.offset as usize - LOG_BATCH_HEADER_LEN;
                                        if recovery_mode == RecoveryMode::AbsoluteConsistency {
                                            error!(
                                                "Failed to open log file due to broken entry (queue={:?},seq={},offset={}): {}",
                                                queue, f.seq, offset, e
                                            );
                                            return Err(e);
                                        } else {
                                            warn!(
                                                "Truncating log file due to broken entries block (queue={:?},seq={},offset={}): {}",
                                                queue, f.seq, offset, e
                                            );
                                            f.handle.truncate(offset)?;
                                            f.handle.sync()?;
                                            break;
                                        }
                                    }
                                }
                                pending_item = Some(next_item);
                                machine.replay(item_batch, FileId { queue, seq: f.seq })?;
                            }
                            Ok(None) => break,
                            Err(e)
                                if recovery_mode == RecoveryMode::TolerateTailCorruption
                                    && is_last_file || recovery_mode == RecoveryMode::TolerateAnyCorruption =>
                            {
                                warn!(
                                    "Truncating log file due to broken batch (queue={:?},seq={},offset={}): {}",
                                    queue, f.seq, reader.valid_offset(), e
                                );
                                f.handle.truncate(reader.valid_offset())?;
                                f.handle.sync()?;
                                break;
                            }
                            Err(e) => {
                                error!(
                                    "Failed to open log file due to broken batch (queue={:?},seq={},offset={}): {}",
                                    queue, f.seq, reader.valid_offset(), e
                                );
                                return Err(e);
                            }
                        }
                    }
                }
                Ok(machine)
            })
            .try_reduce(
                || machine_factory.new_target(),
                |mut lhs, rhs| {
                    lhs.merge(rhs, queue)?;
                    Ok(lhs)
                },
            )?;

        Ok(machine)
    }

    /// Manually reads through log items in all available log files of the
    /// specified `[LogQueue]`, and replays them to specific
    /// [`ReplayMachine`]s that can be constructed via `machine_factory`.
    #[allow(dead_code)]
    pub fn recover_queue<M: ReplayMachine, FA: Factory<M>>(
        &mut self,
        file_system: Arc<F>,
        recovery_cfg: RecoveryConfig,
        replay_machine_factory: &FA,
    ) -> Result<M> {
        let files = if recovery_cfg.queue == LogQueue::Append {
            &mut self.append_files
        } else {
            &mut self.rewrite_files
        };
        DualPipesBuilder::recover_queue_imp(
            file_system,
            recovery_cfg,
            files,
            replay_machine_factory,
        )
    }

    fn initialize_files(&mut self) -> Result<()> {
        let target_file_size = self.cfg.target_file_size.0 as usize;
        let mut target = std::cmp::min(
            self.cfg.prefill_capacity(),
            self.cfg
                .recycle_capacity()
                .saturating_sub(self.append_files.len()),
        );
        let to_create = target.saturating_sub(self.recycled_files.len());
        if to_create > 0 {
            let now = Instant::now();
            for _ in 0..to_create {
                let seq = self
                    .recycled_files
                    .last()
                    .map(|f| f.seq + 1)
                    .unwrap_or_else(|| DEFAULT_FIRST_FILE_SEQ);
                let path_id = find_available_dir(&self.dirs, target_file_size);
                let root_path = &self.dirs[path_id];
                let path = root_path.join(build_reserved_file_name(seq));
                let handle = Arc::new(self.file_system.create(path)?);
                let mut writer = self.file_system.new_writer(handle.clone())?;
                let mut written = 0;
                let buf = vec![0; std::cmp::min(PREFILL_BUFFER_SIZE, target_file_size)];
                while written < target_file_size {
                    if let Err(e) = writer.write_all(&buf) {
                        warn!("failed to build reserved file, err: {e}");
                        if is_no_space_err(&e) {
                            warn!("no enough space for preparing reserved logs");
                            // Clear partially prepared recycled log list if there has no enough
                            // space for it.
                            target = 0;
                        }
                        break;
                    }
                    written += buf.len();
                }
                self.recycled_files.push(File {
                    seq,
                    handle,
                    format: LogFileFormat::default(),
                    path_id,
                    reserved: true,
                });
            }
            info!(
                "prefill logs takes {:?}, created {to_create} files",
                now.elapsed(),
            );
        }
        // If target recycled capacity has been changed when restarting by manually
        // modifications, such as setting `Config::enable-log-recycle` from TRUE to
        // FALSE, setting `Config::prefill-for-recycle` from TRUE to FALSE or
        // changing the recycle capacity, we should remove redundant
        // recycled files in advance.
        while self.recycled_files.len() > target {
            let f = self.recycled_files.pop().unwrap();
            let root_path = &self.dirs[f.path_id];
            let path = root_path.join(build_reserved_file_name(f.seq));
            let _ = self.file_system.delete(path);
        }
        Ok(())
    }

    /// Builds a [`DualPipes`] that contains all available log files.
    pub fn finish(mut self) -> Result<DualPipes<F>> {
        self.initialize_files()?;
        let appender = SinglePipe::open(
            &self.cfg,
            self.dirs.clone(),
            self.file_system.clone(),
            self.listeners.clone(),
            LogQueue::Append,
            self.append_files,
            self.recycled_files,
        )?;
        let rewriter = SinglePipe::open(
            &self.cfg,
            self.dirs,
            self.file_system.clone(),
            self.listeners.clone(),
            LogQueue::Rewrite,
            self.rewrite_files,
            Vec::new(),
        )?;
        DualPipes::open(self.dir_locks, appender, rewriter)
    }
}

/// Creates and exclusively locks a lock file under the given directory.
pub(super) fn lock_dir<P: AsRef<Path>>(dir: P) -> Result<StdFile> {
    let lock_file = StdFile::create(lock_file_path(dir))?;
    lock_file.try_lock_exclusive().map_err(|e| {
        Error::Other(box_err!(
            "Failed to lock file: {}, maybe another instance is using this directory.",
            e
        ))
    })?;
    Ok(lock_file)
}

pub(crate) struct FileName {
    pub seq: FileSeq,
    pub path: PathBuf,
    path_id: PathId,
}
