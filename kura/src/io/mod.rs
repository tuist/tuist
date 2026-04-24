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
    io::{self, AsyncRead, AsyncSeek, AsyncWrite, ReadBuf},
    time::timeout,
};

use crate::metrics::Metrics;

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
        let path = self.validate_path(path)?;
        let lease = self.acquire("open_persistent_read_file").await?;
        let started_at = Instant::now();
        match tokio::task::spawn_blocking({
            let path = path.clone();
            move || std::fs::File::open(&path)
        })
        .await
        {
            Ok(Ok(file)) => {
                self.inner.metrics.record_file_operation(
                    "open_persistent_read_file",
                    "ok",
                    started_at.elapsed(),
                    0,
                );
                Ok(PersistentFile {
                    file,
                    _lease: lease,
                })
            }
            Ok(Err(error)) => {
                self.inner.metrics.record_file_operation(
                    "open_persistent_read_file",
                    "error",
                    started_at.elapsed(),
                    0,
                );
                Err(format!(
                    "failed to open persistent file {}: {error}",
                    path.display()
                ))
            }
            Err(error) => {
                self.inner.metrics.record_file_operation(
                    "open_persistent_read_file",
                    "error",
                    started_at.elapsed(),
                    0,
                );
                Err(format!(
                    "failed to join persistent file open task for {}: {error}",
                    path.display()
                ))
            }
        }
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

    pub async fn write(&self, path: &Path, bytes: &[u8]) -> Result<(), String> {
        let path = self.validate_path(path)?;
        self.run("write", bytes.len() as u64, async {
            fs::write(&path, bytes)
                .await
                .map_err(|error| format!("failed to write {}: {error}", path.display()))
        })
        .await
    }

    pub async fn read(&self, path: &Path) -> Result<Vec<u8>, String> {
        let path = self.validate_path(path)?;
        self.run("read", 0, async {
            fs::read(&path)
                .await
                .map_err(|error| format!("failed to read {}: {error}", path.display()))
        })
        .await
    }

    pub async fn remove_file_if_exists(&self, path: &Path) {
        match self.path_exists(path).await {
            Ok(true) => {
                if let Err(error) = self.remove_file(path).await {
                    tracing::warn!("{error}");
                }
            }
            Ok(false) => {}
            Err(error) => tracing::warn!("{error}"),
        }
    }

    pub async fn remove_dir_all_if_exists(&self, path: &Path) {
        match self.path_exists(path).await {
            Ok(true) => {
                if let Err(error) = self.remove_dir_all(path).await {
                    tracing::warn!("{error}");
                }
            }
            Ok(false) => {}
            Err(error) => tracing::warn!("{error}"),
        }
    }

    pub fn metrics(&self) -> Metrics {
        self.inner.metrics.clone()
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
                    "timed out waiting {:?} for file descriptor permit during {operation}",
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

impl PersistentFile {
    pub fn as_std(&self) -> &std::fs::File {
        &self.file
    }
}

impl TrackedFile {
    pub async fn sync_data(&self) -> Result<(), io::Error> {
        self.file.sync_data().await
    }
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
}
