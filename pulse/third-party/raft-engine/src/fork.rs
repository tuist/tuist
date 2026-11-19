// Copyright (c) 2023-present, PingCAP, Inc. Licensed under Apache-2.0.

use std::fs::{copy, create_dir_all};
use std::path::Path;
use std::sync::Arc;

#[cfg(not(windows))]
use std::os::unix::fs::symlink;
#[cfg(windows)]
use std::os::windows::fs::symlink_file as symlink;

use crate::config::{Config, RecoveryMode};
use crate::env::FileSystem;
use crate::file_pipe_log::{FileNameExt, FilePipeLog, FilePipeLogBuilder};
use crate::pipe_log::{FileId, LogQueue};
use crate::Engine;

/// Returned by `Engine::fork`.
#[derive(Default)]
pub struct CopyDetails {
    /// Paths of copied log files.
    pub copied: Vec<String>,
    /// Paths of symlinked log files.
    pub symlinked: Vec<String>,
}

impl<F: FileSystem> Engine<F, FilePipeLog<F>> {
    /// Make a copy from `source` to `target`. `source` should exists but
    /// `target` shouldn't. And `source` shouldn't be opened, otherwise
    /// data corruption can happen.
    ///
    /// *symlink* will be used if possbile, otherwise *copy* will be used
    /// instead. Generally all inactive log files will be symlinked, but the
    /// last active one will be copied.
    ///
    /// After the copy is made both of 2 engines can be started and run at the
    /// same time.
    ///
    /// It reports errors if the source instance
    ///   * is specified with `enable_log_recycle = true`. `source` and `target`
    ///     can share log files, so log file reusing can cause data corruption.
    ///   * is specified with `recovery_mode = TolerateAnyCorruption`, in which
    ///     case *symlink* can't be use. Users should consider to copy the
    ///     instance directly.
    pub fn fork<T: AsRef<Path>>(
        source: &Config,
        fs: Arc<F>,
        target: T,
    ) -> Result<CopyDetails, String> {
        minimum_copy(source, fs, target)
    }
}

fn minimum_copy<F, P>(cfg: &Config, fs: Arc<F>, target: P) -> Result<CopyDetails, String>
where
    F: FileSystem,
    P: AsRef<Path>,
{
    if cfg.enable_log_recycle {
        return Err("enable_log_recycle should be false".to_owned());
    }
    if cfg.recovery_mode == RecoveryMode::TolerateAnyCorruption {
        return Err("recovery_mode shouldn't be TolerateAnyCorruption".to_owned());
    }

    let mut cfg = cfg.clone();
    cfg.sanitize()
        .map_err(|e| format!("sanitize config: {e}"))?;

    create_dir_all(&target)
        .map_err(|e| format!("create_dir_all({}): {e}", target.as_ref().display()))?;

    let mut builder = FilePipeLogBuilder::new(cfg.clone(), fs, vec![]);
    builder
        .scan_and_sort(false)
        .map_err(|e| format!("scan files: {e}"))?;

    // Iterate all log files and rewrite files.
    let mut details = CopyDetails::default();
    for (queue, files) in [
        (LogQueue::Append, &builder.append_file_names),
        (LogQueue::Rewrite, &builder.rewrite_file_names),
    ] {
        let count = files.len();
        for (i, f) in files.iter().enumerate() {
            let src: &Path = f.path.as_ref();
            let dst = FileId::new(queue, f.seq).build_file_path(&target);
            if i < count - 1 {
                symlink(src, &dst)
                    .map_err(|e| format!("symlink({}, {}): {e}", src.display(), dst.display()))?;
                let path = dst.canonicalize().unwrap().to_str().unwrap().to_owned();
                details.symlinked.push(path);
            } else {
                copy(src, &dst)
                    .map(|_| ())
                    .map_err(|e| format!("copy({}, {}): {e}", src.display(), dst.display()))?;
                let path = dst.canonicalize().unwrap().to_str().unwrap().to_owned();
                details.copied.push(path);
            };
        }
    }

    Ok(details)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::tests::RaftLogEngine;
    use crate::env::DefaultFileSystem;
    use crate::{LogBatch, ReadableSize};
    use std::path::PathBuf;

    #[test]
    fn test_fork() {
        let dir = tempfile::Builder::new()
            .prefix("test_engine_fork")
            .tempdir()
            .unwrap();

        let mut source = PathBuf::from(dir.as_ref());
        source.push("source");
        let mut cfg = Config {
            dir: source.to_str().unwrap().to_owned(),
            target_file_size: ReadableSize::kb(1),
            enable_log_recycle: false,
            ..Default::default()
        };
        let engine = RaftLogEngine::open(cfg.clone()).unwrap();

        let mut log_batch = LogBatch::default();
        log_batch.put(1, vec![b'1'; 16], vec![b'v'; 1024]).unwrap();
        engine.write(&mut log_batch, false).unwrap();
        engine.purge_manager().must_rewrite_append_queue(None, None);

        let mut log_batch = LogBatch::default();
        log_batch.put(1, vec![b'2'; 16], vec![b'v'; 1024]).unwrap();
        engine.write(&mut log_batch, false).unwrap();
        engine.purge_manager().must_rewrite_append_queue(None, None);

        let mut log_batch = LogBatch::default();
        log_batch.put(1, vec![b'3'; 16], vec![b'v'; 1024]).unwrap();
        engine.write(&mut log_batch, false).unwrap();

        let mut log_batch = LogBatch::default();
        log_batch.put(1, vec![b'4'; 16], vec![b'v'; 1024]).unwrap();
        engine.write(&mut log_batch, false).unwrap();

        let mut target = PathBuf::from(dir.as_ref());
        target.push("target");
        Engine::<_, _>::fork(&cfg, Arc::new(DefaultFileSystem), &target).unwrap();
        cfg.dir = target.to_str().unwrap().to_owned();
        let engine1 = RaftLogEngine::open(cfg.clone()).unwrap();

        assert!(engine1.get(1, vec![b'1'; 16].as_ref()).is_some());
        assert!(engine1.get(1, vec![b'2'; 16].as_ref()).is_some());
        assert!(engine1.get(1, vec![b'3'; 16].as_ref()).is_some());
        assert!(engine1.get(1, vec![b'4'; 16].as_ref()).is_some());

        let mut log_batch = LogBatch::default();
        log_batch.put(1, vec![b'5'; 16], vec![b'v'; 1024]).unwrap();
        engine.write(&mut log_batch, false).unwrap();

        let mut log_batch = LogBatch::default();
        log_batch.put(1, vec![b'6'; 16], vec![b'v'; 1024]).unwrap();
        engine1.write(&mut log_batch, false).unwrap();

        assert!(engine.get(1, vec![b'5'; 16].as_ref()).is_some());
        assert!(engine1.get(1, vec![b'6'; 16].as_ref()).is_some());

        let mut target = PathBuf::from(dir.as_ref());
        target.push("target-1");
        let mut cfg1 = cfg.clone();
        cfg1.enable_log_recycle = true;
        assert!(Engine::<_, _>::fork(&cfg1, Arc::new(DefaultFileSystem), &target).is_err());
        let mut cfg1 = cfg;
        cfg1.recovery_mode = RecoveryMode::TolerateAnyCorruption;
        assert!(Engine::<_, _>::fork(&cfg1, Arc::new(DefaultFileSystem), &target).is_err());
    }
}
