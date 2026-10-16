use std::{
    path::{Component, Path, PathBuf},
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
    time::{Duration, Instant},
};

use deadpool::unmanaged::{Object, Pool};
use tokio::{
    fs::{self, File, OpenOptions},
    io::{self, AsyncRead, AsyncSeek, AsyncWrite, AsyncWriteExt, ReadBuf},
    time::timeout,
};

use crate::metrics::Metrics;

pub const FD_POOL_EXHAUSTED_MARKER: &str = "fd_pool_exhausted";

pub fn is_fd_pool_exhausted_error(error: &str) -> bool {
    error.contains(FD_POOL_EXHAUSTED_MARKER)
}

#[derive(Clone)]
pub struct IoController {
    inner: Arc<IoControllerInner>,
}

struct IoControllerInner {
    pool: Pool<FileDescriptorToken>,
    acquire_timeout: Duration,
    metrics: Metrics,
    cwd: PathBuf,
    allowed_roots: Vec<PathBuf>,
}

#[derive(Debug)]
struct FileDescriptorToken;

pub struct TrackedFile {
    file: File,
    _lease: FileDescriptorLease,
}

pub struct PersistentFile {
    file: std::fs::File,
    _lease: FileDescriptorLease,
}

impl IoController {
    pub fn new(
        metrics: Metrics,
        pool_size: usize,
        acquire_timeout: Duration,
        allowed_roots: Vec<PathBuf>,
    ) -> Result<Self, String> {
        if allowed_roots.is_empty() {
            return Err("IoController requires at least one allowed storage root".into());
        }
        let cwd =
            std::env::current_dir().map_err(|error| format!("failed to determine cwd: {error}"))?;
        let mut normalized_roots = Vec::with_capacity(allowed_roots.len());
        for root in allowed_roots {
            normalized_roots.push(normalize_path(&cwd, &root)?);
        }
        let pool = Pool::from(
            std::iter::repeat_with(|| FileDescriptorToken)
                .take(pool_size)
                .collect::<Vec<_>>(),
        );
        let controller = Self {
            inner: Arc::new(IoControllerInner {
                pool,
                acquire_timeout,
                metrics,
                cwd,
                allowed_roots: normalized_roots,
            }),
        };
        controller.record_pool_status();
        Ok(controller)
    }

    pub async fn create_file(&self, path: &Path) -> Result<TrackedFile, String> {
        let path = self.validate_path(path)?;
        let lease = self.acquire("create_file").await?;
        let started_at = Instant::now();
        match File::create(&path).await {
            Ok(file) => {
                self.inner.metrics.record_file_operation(
                    "create_file",
                    "ok",
                    started_at.elapsed(),
                    0,
                );
                Ok(TrackedFile {
                    file,
                    _lease: lease,
                })
            }
            Err(error) => {
                self.inner.metrics.record_file_operation(
                    "create_file",
                    "error",
                    started_at.elapsed(),
                    0,
                );
                Err(format!("failed to create file {}: {error}", path.display()))
            }
        }
    }

    pub async fn open_file(&self, path: &Path) -> Result<TrackedFile, String> {
        let path = self.validate_path(path)?;
        let lease = self.acquire("open_file").await?;
        let started_at = Instant::now();
        match File::open(&path).await {
            Ok(file) => {
                self.inner.metrics.record_file_operation(
                    "open_file",
                    "ok",
                    started_at.elapsed(),
                    0,
                );
                Ok(TrackedFile {
                    file,
                    _lease: lease,
                })
            }
            Err(error) => {
                self.inner.metrics.record_file_operation(
                    "open_file",
                    "error",
                    started_at.elapsed(),
                    0,
                );
                Err(format!("failed to open file {}: {error}", path.display()))
            }
        }
    }

    pub async fn open_append_file(&self, path: &Path) -> Result<TrackedFile, String> {
        let path = self.validate_path(path)?;
        let lease = self.acquire("open_append_file").await?;
        let started_at = Instant::now();
        match OpenOptions::new()
            .create(true)
            .append(true)
            .read(true)
            .open(&path)
            .await
        {
            Ok(file) => {
                self.inner.metrics.record_file_operation(
                    "open_append_file",
                    "ok",
                    started_at.elapsed(),
                    0,
                );
                Ok(TrackedFile {
                    file,
                    _lease: lease,
                })
            }
            Err(error) => {
                self.inner.metrics.record_file_operation(
                    "open_append_file",
                    "error",
                    started_at.elapsed(),
                    0,
                );
                Err(format!(
                    "failed to open append file {}: {error}",
                    path.display()
                ))
            }
        }
    }

    pub async fn open_persistent_read_file(&self, path: &Path) -> Result<PersistentFile, String> {
        self.open_persistent(
            "open_persistent_read_file",
            "persistent file",
            path,
            |path| std::fs::File::open(path),
        )
        .await
    }

    /// Opens an append-only segment file without the operating system's append flag.
    ///
    /// Callers reserve non-overlapping offsets before writing. Linux ignores the
    /// supplied offset for positioned writes when the append flag is set, so the
    /// file must be opened for ordinary writes for those reservations to remain
    /// correct.
    pub async fn open_persistent_append_file(&self, path: &Path) -> Result<PersistentFile, String> {
        self.open_persistent(
            "open_persistent_append_file",
            "persistent append file",
            path,
            |path| {
                std::fs::OpenOptions::new()
                    .create(true)
                    .truncate(false)
                    .write(true)
                    .read(true)
                    .open(path)
            },
        )
        .await
    }

    /// Creates a staging file that must not already exist and opens it for
    /// positioned writes. Refusing an existing path guarantees a staging
    /// writer never truncates or interleaves with another writer's file.
    pub async fn create_new_persistent_file(&self, path: &Path) -> Result<PersistentFile, String> {
        self.open_persistent(
            "create_new_persistent_file",
            "new persistent file",
            path,
            |path| {
                std::fs::OpenOptions::new()
                    .create_new(true)
                    .write(true)
                    .read(true)
                    .open(path)
            },
        )
        .await
    }

    async fn open_persistent(
        &self,
        operation: &'static str,
        description: &'static str,
        path: &Path,
        open: fn(&Path) -> io::Result<std::fs::File>,
    ) -> Result<PersistentFile, String> {
        let path = self.validate_path(path)?;
        let lease = self.acquire(operation).await?;
        let started_at = Instant::now();
        // The blocking open owns the lease. If this future is cancelled while
        // the open runs, the descriptor the detached task may still create
        // stays counted against the pool until that task drops it.
        let result = tokio::task::spawn_blocking({
            let path = path.clone();
            move || {
                open(&path).map(|file| PersistentFile {
                    file,
                    _lease: lease,
                })
            }
        })
        .await;
        let outcome = match result {
            Ok(Ok(file)) => Ok(file),
            Ok(Err(error)) => Err(format!(
                "failed to open {description} {}: {error}",
                path.display()
            )),
            Err(error) => Err(format!(
                "failed to join {description} open task for {}: {error}",
                path.display()
            )),
        };
        self.inner.metrics.record_file_operation(
            operation,
            if outcome.is_ok() { "ok" } else { "error" },
            started_at.elapsed(),
            0,
        );
        outcome
    }

    pub async fn drop_cached_pages(
        &self,
        path: &Path,
        offset: u64,
        length: u64,
    ) -> Result<(), String> {
        let file = self.open_persistent_read_file(path).await?;
        file.drop_cached_pages(offset, length).map_err(|error| {
            format!(
                "failed to release file cache for {}: {error}",
                path.display()
            )
        })
    }

    pub async fn sync_drop_cache_and_reopen_append(
        &self,
        mut file: TrackedFile,
        path: &Path,
        offset: u64,
        length: u64,
    ) -> Result<TrackedFile, String> {
        file.flush()
            .await
            .map_err(|error| format!("failed to flush {}: {error}", path.display()))?;
        file.sync_data()
            .await
            .map_err(|error| format!("failed to sync {}: {error}", path.display()))?;

        // Keep cache eviction outside the lifetime of the asynchronous writer.
        // Advising completed ranges while that writer remained open caused
        // later buffered writes to disappear under Linux stress. Reopening in
        // append mode makes the continuation offset explicit and preserves the
        // append-only segment invariant.
        drop(file);
        self.drop_cached_pages(path, offset, length).await?;
        self.open_append_file(path).await
    }

    pub async fn sync_dir(&self, path: &Path) -> Result<(), String> {
        let path = self.validate_path(path)?;
        let lease = self.acquire("sync_dir").await?;
        let started_at = Instant::now();
        let result = tokio::task::spawn_blocking({
            let path = path.clone();
            move || {
                let directory = std::fs::File::open(&path).map_err(|error| {
                    format!("failed to open directory {}: {error}", path.display())
                })?;
                directory.sync_all().map_err(|error| {
                    format!("failed to sync directory {}: {error}", path.display())
                })
            }
        })
        .await
        .map_err(|error| format!("failed to join directory sync task: {error}"))?;
        drop(lease);
        self.inner.metrics.record_file_operation(
            "sync_dir",
            if result.is_ok() { "ok" } else { "error" },
            started_at.elapsed(),
            0,
        );
        result
    }

    pub async fn create_dir_all(&self, path: &Path) -> Result<(), String> {
        let path = self.validate_path(path)?;
        self.run("create_dir_all", 0, async {
            fs::create_dir_all(&path)
                .await
                .map_err(|error| format!("failed to create directory {}: {error}", path.display()))
        })
        .await
    }

    pub async fn metadata_len(&self, path: &Path) -> Result<u64, String> {
        let path = self.validate_path(path)?;
        self.run("metadata", 0, async {
            fs::metadata(&path)
                .await
                .map(|metadata| metadata.len())
                .map_err(|error| format!("failed to stat {}: {error}", path.display()))
        })
        .await
    }

    pub async fn path_exists(&self, path: &Path) -> Result<bool, String> {
        let path = self.validate_path(path)?;
        self.run("exists", 0, async {
            match fs::metadata(&path).await {
                Ok(_) => Ok(true),
                Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
                Err(error) => Err(format!("failed to inspect {}: {error}", path.display())),
            }
        })
        .await
    }

    pub async fn rename(&self, from: &Path, to: &Path) -> Result<(), String> {
        let from = self.validate_path(from)?;
        let to = self.validate_path(to)?;
        self.run("rename", 0, async {
            fs::rename(&from, &to).await.map_err(|error| {
                format!(
                    "failed to rename {} to {}: {error}",
                    from.display(),
                    to.display()
                )
            })
        })
        .await
    }

    pub async fn copy(&self, from: &Path, to: &Path) -> Result<u64, String> {
        let from = self.validate_path(from)?;
        let to = self.validate_path(to)?;
        self.run("copy", 0, async {
            fs::copy(&from, &to).await.map_err(|error| {
                format!(
                    "failed to copy {} to {}: {error}",
                    from.display(),
                    to.display()
                )
            })
        })
        .await
    }

    pub async fn remove_file(&self, path: &Path) -> Result<(), String> {
        let path = self.validate_path(path)?;
        self.run("remove_file", 0, async {
            fs::remove_file(&path)
                .await
                .map_err(|error| format!("failed to remove {}: {error}", path.display()))
        })
        .await
    }

    pub async fn remove_dir_all(&self, path: &Path) -> Result<(), String> {
        let path = self.validate_path(path)?;
        self.run("remove_dir_all", 0, async {
            fs::remove_dir_all(&path)
                .await
                .map_err(|error| format!("failed to remove directory {}: {error}", path.display()))
        })
        .await
    }

    #[cfg(test)]
    pub async fn write(&self, path: &Path, bytes: &[u8]) -> Result<(), String> {
        let path = self.validate_path(path)?;
        self.run("write", bytes.len() as u64, async {
            fs::write(&path, bytes)
                .await
                .map_err(|error| format!("failed to write {}: {error}", path.display()))
        })
        .await
    }

    pub async fn remove_file_if_exists_result(&self, path: &Path) -> Result<(), String> {
        match self.path_exists(path).await {
            Ok(true) => self.remove_file(path).await,
            Ok(false) => Ok(()),
            Err(error) => Err(error),
        }
    }

    pub async fn remove_file_if_exists(&self, path: &Path) {
        if let Err(error) = self.remove_file_if_exists_result(path).await {
            tracing::warn!("{error}");
        }
    }

    pub async fn remove_dir_all_if_exists(&self, path: &Path) -> Result<(), String> {
        match self.path_exists(path).await {
            Ok(true) => self.remove_dir_all(path).await,
            Ok(false) => Ok(()),
            Err(error) => Err(error),
        }
    }

    pub fn metrics(&self) -> &Metrics {
        &self.inner.metrics
    }

    async fn run<T, F>(&self, operation: &'static str, bytes: u64, future: F) -> Result<T, String>
    where
        F: std::future::Future<Output = Result<T, String>>,
    {
        let _lease = self.acquire(operation).await?;
        let started_at = Instant::now();
        match future.await {
            Ok(value) => {
                self.inner.metrics.record_file_operation(
                    operation,
                    "ok",
                    started_at.elapsed(),
                    bytes,
                );
                Ok(value)
            }
            Err(error) => {
                self.inner.metrics.record_file_operation(
                    operation,
                    "error",
                    started_at.elapsed(),
                    0,
                );
                Err(error)
            }
        }
    }

    async fn acquire(&self, operation: &'static str) -> Result<FileDescriptorLease, String> {
        let started_at = Instant::now();
        let permit = timeout(self.inner.acquire_timeout, self.inner.pool.get())
            .await
            .map_err(|_| {
                self.inner
                    .metrics
                    .record_file_descriptor_wait("timeout", started_at.elapsed());
                format!(
                    "{FD_POOL_EXHAUSTED_MARKER}: timed out waiting {:?} for file descriptor permit during {operation}",
                    self.inner.acquire_timeout
                )
            })?
            .map_err(|error| {
                self.inner
                    .metrics
                    .record_file_descriptor_wait("error", started_at.elapsed());
                format!("failed to acquire file descriptor permit: {error}")
            })?;

        self.inner
            .metrics
            .record_file_descriptor_wait("ok", started_at.elapsed());
        self.record_pool_status();

        Ok(FileDescriptorLease {
            controller: self.clone(),
            permit: Some(permit),
        })
    }

    fn record_pool_status(&self) {
        let status = self.inner.pool.status();
        self.inner.metrics.update_file_descriptor_pool(
            status.max_size,
            status.size.saturating_sub(status.available),
            status.available,
            status.waiting,
        );
    }

    fn validate_path(&self, path: &Path) -> Result<PathBuf, String> {
        let normalized = normalize_path(&self.inner.cwd, path)?;
        if self
            .inner
            .allowed_roots
            .iter()
            .any(|root| normalized.starts_with(root))
        {
            return Ok(normalized);
        }

        Err(format!(
            "refused to access path outside configured storage roots: {}",
            path.display()
        ))
    }
}

struct FileDescriptorLease {
    controller: IoController,
    permit: Option<Object<FileDescriptorToken>>,
}

impl Drop for FileDescriptorLease {
    fn drop(&mut self) {
        let _ = self.permit.take();
        self.controller.record_pool_status();
    }
}

impl AsyncRead for TrackedFile {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        Pin::new(&mut this.file).poll_read(cx, buf)
    }
}

impl AsyncWrite for TrackedFile {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<Result<usize, io::Error>> {
        let this = self.get_mut();
        Pin::new(&mut this.file).poll_write(cx, buf)
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let this = self.get_mut();
        Pin::new(&mut this.file).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let this = self.get_mut();
        Pin::new(&mut this.file).poll_shutdown(cx)
    }
}

impl AsyncSeek for TrackedFile {
    fn start_seek(self: Pin<&mut Self>, position: io::SeekFrom) -> Result<(), io::Error> {
        let this = self.get_mut();
        Pin::new(&mut this.file).start_seek(position)
    }

    fn poll_complete(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<u64, io::Error>> {
        let this = self.get_mut();
        Pin::new(&mut this.file).poll_complete(cx)
    }
}

/// Runs a synchronous file operation (a positioned write, sync or cache
/// advice) from async code. On the multithreaded runtime the worker hands its
/// other tasks to the scheduler first, so a dirty-page-throttled write never
/// stalls them; the operation keeps borrowing the caller's buffer and handle,
/// so nothing outlives a cancelled caller. Current-thread runtimes (tests)
/// run it directly.
pub(crate) fn run_blocking_file_operation<T>(operation: impl FnOnce() -> T) -> T {
    match tokio::runtime::Handle::current().runtime_flavor() {
        tokio::runtime::RuntimeFlavor::MultiThread => tokio::task::block_in_place(operation),
        _ => operation(),
    }
}

impl PersistentFile {
    pub fn as_std(&self) -> &std::fs::File {
        &self.file
    }

    pub fn write_all_at(&self, bytes: &[u8], offset: u64) -> Result<(), io::Error> {
        #[cfg(unix)]
        {
            use std::os::unix::fs::FileExt as _;

            self.file.write_all_at(bytes, offset)?;
        }
        #[cfg(windows)]
        {
            use std::os::windows::fs::FileExt as _;

            let mut remaining = bytes;
            let mut next_offset = offset;
            while !remaining.is_empty() {
                match self.file.seek_write(remaining, next_offset) {
                    Ok(0) => return Err(io::Error::from(io::ErrorKind::WriteZero)),
                    Ok(written) => {
                        remaining = &remaining[written..];
                        next_offset = next_offset.saturating_add(written as u64);
                    }
                    Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                    Err(error) => return Err(error),
                }
            }
        }
        #[cfg(not(any(unix, windows)))]
        {
            let _ = (bytes, offset);
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "positioned segment writes require Unix or Windows file support",
            ));
        }
        Ok(())
    }

    pub fn sync_data(&self) -> Result<(), io::Error> {
        sync_segment_data(&self.file)
    }

    /// Returns whether the file currently has at least `needed` bytes.
    ///
    /// This deliberately asks the file system on every pre-stream guard. A
    /// cached append-only high-water mark would hide external truncation and
    /// let a response begin before the short read becomes visible.
    pub fn has_len(&self, needed: u64) -> Result<bool, io::Error> {
        Ok(self.file.metadata()?.len() >= needed)
    }

    pub fn drop_cached_pages(&self, offset: u64, length: u64) -> Result<(), io::Error> {
        #[cfg(target_os = "linux")]
        {
            drop_file_cached_pages(&self.file, offset, length)
        }

        #[cfg(not(target_os = "linux"))]
        {
            let _ = (offset, length);
            Ok(())
        }
    }
}

/// Segment synchronization orders segment bytes before the metadata that
/// references them. On Linux that is `fdatasync`, the same primitive RocksDB
/// uses for its WAL. On Apple platforms Rust's `sync_data` issues
/// `F_FULLFSYNC`, which flushes the whole drive cache, while the bundled
/// RocksDB build syncs its WAL with plain `fdatasync` (it is compiled without
/// `HAVE_FULLFSYNC`). An acknowledged manifest there is therefore only as
/// durable as `fdatasync`, and what the segment sync must add is ordering:
/// segment bytes must never reach stable storage after the WAL record that
/// points at them. `F_BARRIERFSYNC` provides exactly that (an fsync plus an
/// I/O barrier) without a full cache flush per group commit. File systems
/// that do not support it fall back to the full flush.
fn sync_segment_data(file: &std::fs::File) -> Result<(), io::Error> {
    #[cfg(target_vendor = "apple")]
    {
        use std::os::fd::AsRawFd;
        loop {
            // SAFETY: fcntl with F_BARRIERFSYNC takes no argument beyond the
            // descriptor, which `file` keeps open for the duration of the call.
            let result = unsafe { libc::fcntl(file.as_raw_fd(), libc::F_BARRIERFSYNC) };
            if result != -1 {
                return Ok(());
            }
            let error = io::Error::last_os_error();
            match error.raw_os_error() {
                Some(libc::EINTR) => continue,
                Some(libc::EINVAL) | Some(libc::ENOTSUP) => return file.sync_data(),
                _ => return Err(error),
            }
        }
    }
    #[cfg(not(target_vendor = "apple"))]
    {
        file.sync_data()
    }
}

impl TrackedFile {
    pub async fn sync_data(&self) -> Result<(), io::Error> {
        self.file.sync_data().await
    }
}

#[cfg(target_os = "linux")]
fn drop_file_cached_pages(file: &std::fs::File, offset: u64, length: u64) -> Result<(), io::Error> {
    let Some((aligned_offset, aligned_length)) =
        aligned_advice_range(offset, length, rustix::param::page_size() as u64)
    else {
        return Ok(());
    };
    rustix::fs::fadvise(
        file,
        aligned_offset,
        Some(aligned_length),
        rustix::fs::Advice::DontNeed,
    )
    .map_err(io::Error::from)
}

#[cfg(any(target_os = "linux", test))]
fn aligned_advice_range(
    offset: u64,
    length: u64,
    page_size: u64,
) -> Option<(u64, std::num::NonZeroU64)> {
    if length == 0 || page_size == 0 {
        return None;
    }
    let aligned_offset = offset / page_size * page_size;
    let end = offset.saturating_add(length);
    let aligned_end = end.div_ceil(page_size).saturating_mul(page_size);
    std::num::NonZeroU64::new(aligned_end.saturating_sub(aligned_offset))
        .map(|aligned_length| (aligned_offset, aligned_length))
}

impl IoController {
    pub async fn sync_directory(&self, path: &Path) -> Result<(), String> {
        let path = self.validate_path(path)?;
        #[cfg(unix)]
        {
            self.run("sync_directory", 0, async move {
                tokio::task::spawn_blocking({
                    let path = path.clone();
                    move || -> Result<(), String> {
                        let directory = std::fs::File::open(&path).map_err(|error| {
                            format!(
                                "failed to open directory {} for sync: {error}",
                                path.display()
                            )
                        })?;
                        directory.sync_all().map_err(|error| {
                            format!("failed to sync directory {}: {error}", path.display())
                        })
                    }
                })
                .await
                .map_err(|error| {
                    format!(
                        "failed to join directory sync task for {}: {error}",
                        path.display()
                    )
                })?
            })
            .await
        }

        #[cfg(not(unix))]
        {
            let _ = path;
            Ok(())
        }
    }
}

fn normalize_path(cwd: &Path, path: &Path) -> Result<PathBuf, String> {
    let joined = if path.is_absolute() {
        path.to_path_buf()
    } else {
        cwd.join(path)
    };
    let mut normalized = PathBuf::new();
    for component in joined.components() {
        match component {
            Component::Prefix(prefix) => normalized.push(prefix.as_os_str()),
            Component::RootDir => normalized.push(component.as_os_str()),
            Component::CurDir => {}
            Component::Normal(part) => normalized.push(part),
            Component::ParentDir => {
                return Err(format!(
                    "refused path containing parent traversal component: {}",
                    path.display()
                ));
            }
        }
    }
    Ok(normalized)
}

#[cfg(test)]
mod tests {
    use std::hint::black_box;

    use tempfile::tempdir;
    use tokio::{sync::oneshot, time::timeout};

    use super::*;

    #[tokio::test]
    async fn controller_blocks_when_all_permits_are_checked_out() {
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let directory = tempdir().expect("failed to create temp dir");
        let controller = IoController::new(
            metrics,
            1,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("controller should initialize");
        let first = controller
            .acquire("test")
            .await
            .expect("first permit should be acquired");

        let controller_clone = controller.clone();
        let (started_tx, started_rx) = oneshot::channel();
        let mut waiter = tokio::spawn(async move {
            started_tx
                .send(())
                .expect("started signal should be delivered");
            controller_clone.acquire("test").await
        });

        let _ = started_rx.await;
        assert!(
            timeout(Duration::from_millis(50), &mut waiter)
                .await
                .is_err(),
            "second checkout should wait while the only permit is held"
        );

        drop(first);

        waiter
            .await
            .expect("waiter task should complete")
            .expect("second permit should acquire after release");
    }

    #[tokio::test]
    async fn rejects_paths_outside_allowed_roots() {
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let allowed_root = tempdir().expect("failed to create allowed root");
        let outside_root = tempdir().expect("failed to create outside root");
        let controller = IoController::new(
            metrics,
            1,
            Duration::from_secs(1),
            vec![allowed_root.path().to_path_buf()],
        )
        .expect("controller should initialize");

        let error = match controller
            .create_file(&outside_root.path().join("escape"))
            .await
        {
            Ok(_) => panic!("path outside the allowed roots should be rejected"),
            Err(error) => error,
        };

        assert!(error.contains("outside configured storage roots"));
    }

    #[tokio::test]
    async fn rejects_paths_with_parent_traversal_components() {
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let allowed_root = tempdir().expect("failed to create allowed root");
        let controller = IoController::new(
            metrics,
            1,
            Duration::from_secs(1),
            vec![allowed_root.path().to_path_buf()],
        )
        .expect("controller should initialize");

        let error = match controller
            .create_file(&allowed_root.path().join("nested").join("..").join("escape"))
            .await
        {
            Ok(_) => panic!("path traversal should be rejected"),
            Err(error) => error,
        };

        assert!(error.contains("parent traversal component"));
    }

    #[tokio::test]
    async fn persistent_positioned_writes_preserve_disjoint_ranges() {
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let directory = tempdir().expect("failed to create temp dir");
        let controller = IoController::new(
            metrics,
            1,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("controller should initialize");
        let path = directory.path().join("positioned-writes");
        let file = controller
            .open_persistent_append_file(&path)
            .await
            .expect("positioned file should open");

        file.write_all_at(b"second", 5)
            .expect("second range should write");
        file.write_all_at(b"first", 0)
            .expect("first range should write");

        assert!(file.has_len(11).expect("current length should read"));
        assert_eq!(
            std::fs::read(&path).expect("positioned file should read"),
            b"firstsecond"
        );

        file.as_std()
            .set_len(5)
            .expect("test truncation should succeed");
        assert!(
            !file.has_len(11).expect("truncated length should read"),
            "the pre-stream length guard must observe external truncation"
        );
    }

    #[tokio::test]
    async fn create_new_persistent_file_refuses_existing_paths_without_truncating() {
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let directory = tempdir().expect("failed to create temp dir");
        let outside_root = tempdir().expect("failed to create outside root");
        let controller = IoController::new(
            metrics,
            1,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("controller should initialize");
        let path = directory.path().join("staged");

        let file = controller
            .create_new_persistent_file(&path)
            .await
            .expect("a fresh staging path should be created");
        file.write_all_at(b"bytes", 7)
            .expect("second range should write");
        file.write_all_at(b"staged ", 0)
            .expect("first range should write");
        drop(file);

        let error = match controller.create_new_persistent_file(&path).await {
            Ok(_) => panic!("an existing staging path must be refused"),
            Err(error) => error,
        };
        assert!(
            error.contains("failed to open new persistent file"),
            "{error}"
        );
        assert_eq!(
            std::fs::read(&path).expect("staged file should read"),
            b"staged bytes",
            "a refused create must not truncate the existing file"
        );

        let error = match controller
            .create_new_persistent_file(&outside_root.path().join("escape"))
            .await
        {
            Ok(_) => panic!("path outside the allowed roots should be rejected"),
            Err(error) => error,
        };
        assert!(error.contains("outside configured storage roots"));
    }

    // Opening a FIFO for reading blocks until a writer opens it, which holds
    // the blocking open in flight without timing assumptions. Cancelling the
    // caller there must not return the descriptor permit while the detached
    // open can still produce a descriptor.
    #[cfg(unix)]
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn cancelled_persistent_open_keeps_its_lease_until_the_open_finishes() {
        use std::os::unix::ffi::OsStrExt as _;

        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let directory = tempdir().expect("failed to create temp dir");
        let controller = IoController::new(
            metrics,
            1,
            Duration::from_millis(50),
            vec![directory.path().to_path_buf()],
        )
        .expect("controller should initialize");
        let fifo = directory.path().join("blocked-open");
        let fifo_path = std::ffi::CString::new(fifo.as_os_str().as_bytes())
            .expect("fifo path should not contain NUL");
        // SAFETY: `fifo_path` is a valid NUL-terminated path for the call.
        assert_eq!(unsafe { libc::mkfifo(fifo_path.as_ptr(), 0o600) }, 0);

        let open = tokio::spawn({
            let controller = controller.clone();
            let fifo = fifo.clone();
            async move { controller.open_persistent_read_file(&fifo).await.map(drop) }
        });
        // The open takes its lease and spawns the blocking open without an
        // intervening suspension, so once the permit is gone the open owns it.
        while controller.inner.pool.status().available != 0 {
            tokio::task::yield_now().await;
        }
        open.abort();
        assert!(
            open.await
                .expect_err("the open should be cancelled")
                .is_cancelled()
        );

        let error = match controller.acquire("test").await {
            Ok(_) => panic!("the cancelled open must still hold the only permit"),
            Err(error) => error,
        };
        assert!(is_fd_pool_exhausted_error(&error), "{error}");

        tokio::task::spawn_blocking(move || {
            std::fs::OpenOptions::new()
                .write(true)
                .open(&fifo)
                .expect("the fifo writer should release the blocked open")
        })
        .await
        .expect("fifo writer task should complete");
        let _permit = timeout(Duration::from_secs(10), controller.inner.pool.get())
            .await
            .expect("the permit should return once the detached open finishes")
            .expect("the pool should hand out the returned permit");
    }

    #[test]
    fn file_cache_advice_expands_to_complete_pages() {
        let (offset, length) = aligned_advice_range(4_095, 4_098, 4_096)
            .expect("a non-empty range should produce advice");

        assert_eq!(offset, 0);
        assert_eq!(length.get(), 12_288);
        assert_eq!(aligned_advice_range(0, 0, 4_096), None);
    }

    #[test]
    #[ignore = "performance benchmark run manually"]
    fn borrowed_metrics_access_benchmark() {
        const ITERATIONS: usize = 200_000;
        const SAMPLES: usize = 7;

        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let directory = tempdir().expect("failed to create benchmark directory");
        let controller = IoController::new(
            metrics,
            1,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("controller should initialize");
        controller.metrics().record_manifest_cache_lookup("hit");

        let measure = |clone_metrics: bool| {
            let started_at = std::time::Instant::now();
            for _ in 0..ITERATIONS {
                if clone_metrics {
                    black_box(controller.inner.metrics.clone()).record_manifest_cache_lookup("hit");
                } else {
                    black_box(controller.metrics()).record_manifest_cache_lookup("hit");
                }
            }
            started_at.elapsed().as_secs_f64()
        };

        let mut speedups = Vec::with_capacity(SAMPLES);
        let mut baseline_rates = Vec::with_capacity(SAMPLES);
        let mut candidate_rates = Vec::with_capacity(SAMPLES);
        for sample in 0..=SAMPLES {
            let (baseline_seconds, candidate_seconds) = if sample % 2 == 0 {
                (measure(true), measure(false))
            } else {
                let candidate = measure(false);
                (measure(true), candidate)
            };
            if sample == 0 {
                continue;
            }
            let baseline_rate = ITERATIONS as f64 / baseline_seconds;
            let candidate_rate = ITERATIONS as f64 / candidate_seconds;
            baseline_rates.push(baseline_rate);
            candidate_rates.push(candidate_rate);
            speedups.push(candidate_rate / baseline_rate);
        }
        baseline_rates.sort_by(f64::total_cmp);
        candidate_rates.sort_by(f64::total_cmp);
        speedups.sort_by(f64::total_cmp);
        let median = SAMPLES / 2;
        println!(
            "METRIC io_metrics_borrow_speedup_ratio={:.6}",
            speedups[median]
        );
        println!(
            "METRIC io_metrics_clone_baseline_per_second={:.3}",
            baseline_rates[median]
        );
        println!(
            "METRIC io_metrics_borrow_candidate_per_second={:.3}",
            candidate_rates[median]
        );
    }
}
