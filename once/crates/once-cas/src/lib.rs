//! Local content-addressed store and action-result cache.
//!
//! Blobs are addressed by their BLAKE3 digest; action results are keyed
//! by an action digest supplied by the caller. Filesystem-backed via
//! `tokio::fs`, no remote tier.
//!
//! Durability: writes go via a uniquely-named tmp file, are fsynced
//! before rename, and the parent directory is fsynced after rename.
//! This is enough to survive an OS crash on common journaled
//! filesystems; for stricter expectations the caller should swap the
//! substrate for a REAPI-backed store.

use std::io;
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};
use tokio::fs::{self, File};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};

mod blob;
mod digest;
mod provider;
mod tuist;

pub use digest::Digest;
pub use provider::CacheProvider;
pub use tuist::{
    TuistAuth, TuistAuthPrompt, TuistCacheConfig, TUIST_APP_OAUTH_CLIENT_ID,
    TUIST_OAUTH_CLIENT_ID_ENV,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("io error at {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
    #[error("corrupt action result at {0}: {1}")]
    Corrupt(PathBuf, serde_json::Error),
    #[error("blob not found: {0}")]
    BlobNotFound(Digest),
    #[error("cache provider `{provider}` is misconfigured: {message}")]
    InvalidConfig {
        provider: &'static str,
        message: String,
    },
    #[error("cache provider `{provider}` failed during `{operation}`: {message}")]
    Remote {
        provider: &'static str,
        operation: &'static str,
        message: String,
    },
}

pub type Result<T> = std::result::Result<T, Error>;

/// Cached result of a single action execution.
///
/// `outputs` records each declared output file the action produced
/// (workspace-relative path -> blob digest). On a cache hit, the runner
/// restores these blobs from the CAS to their declared paths so a
/// dependent action sees the file it expected, even if the producing
/// action did not actually run on this machine.
///
/// `stdout` and `stderr` are optional: a caller that did not capture
/// output (or had nothing worth recording) simply leaves them unset
/// rather than materialising an empty blob.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ActionResult {
    pub exit_code: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stdout: Option<Digest>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stderr: Option<Digest>,
    #[serde(default, skip_serializing_if = "std::collections::BTreeMap::is_empty")]
    pub outputs: std::collections::BTreeMap<String, Digest>,
}

/// Local content-addressed store rooted at a workspace `.once/`
/// directory.
///
/// Layout:
/// - `cas/<aa>/<rest-of-hex>` - logical blob bodies, sharded by first
///   byte. Blob paths are addressed by the BLAKE3 digest of the
///   uncompressed bytes; the stored body may be raw bytes or a
///   zstd-wrapped representation.
/// - `actions/<aa>/<rest-of-hex>.json` - action results, same sharding
///   as `cas/`. Their referenced output digests are CAS-only.
///
/// `open` is cheap and side-effect-free; the directory tree is created
/// lazily on the first write. A read-only consumer never touches disk
/// outside its own reads.
#[derive(Debug, Clone)]
pub struct Cas {
    root: PathBuf,
}

impl Cas {
    /// Borrow a CAS rooted at `root`. Does no I/O.
    pub fn open(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    fn blobs_dir(&self) -> PathBuf {
        self.root.join("cas")
    }

    fn actions_dir(&self) -> PathBuf {
        self.root.join("actions")
    }

    fn scratch_dir(&self) -> PathBuf {
        self.root.join("scratch")
    }

    fn shard_path(base: &Path, digest: &Digest, suffix: &str) -> PathBuf {
        let hex = digest.to_hex();
        let (prefix, rest) = hex.split_at(2);
        base.join(prefix).join(format!("{rest}{suffix}"))
    }

    fn blob_path(&self, digest: &Digest) -> PathBuf {
        Self::shard_path(&self.blobs_dir(), digest, "")
    }

    pub(crate) async fn blob_size(&self, digest: &Digest) -> Result<u64> {
        let path = self.blob_path(digest);
        let mut file = match File::open(&path).await {
            Ok(file) => Ok(file),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Err(Error::BlobNotFound(*digest)),
            Err(source) => Err(Error::Io {
                path: path.clone(),
                source,
            }),
        }?;
        let metadata = file.metadata().await.map_err(|source| Error::Io {
            path: path.clone(),
            source,
        })?;
        let mut header = vec![0_u8; blob::ZSTD_BLOB_HEADER_LEN];
        match file.read_exact(&mut header).await {
            Ok(_) => Ok(blob::raw_size_from_header(&header).unwrap_or(metadata.len())),
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => Ok(metadata.len()),
            Err(source) => Err(Error::Io { path, source }),
        }
    }

    fn action_path(&self, digest: &Digest) -> PathBuf {
        Self::shard_path(&self.actions_dir(), digest, ".json")
    }

    /// Store a blob; returns its digest. Idempotent - putting the same
    /// bytes twice is safe even from concurrent writers.
    pub async fn put_blob(&self, bytes: &[u8]) -> Result<Digest> {
        let digest = Digest::of_bytes(bytes);
        let path = self.blob_path(&digest);
        if fs::try_exists(&path).await.unwrap_or(false) {
            return Ok(digest);
        }
        let stored = blob::encode_bytes(bytes).map_err(|source| Error::Io {
            path: path.clone(),
            source,
        })?;
        write_durably(&path, &stored).await?;
        Ok(digest)
    }

    /// Stream `reader` into the CAS, returning the content's digest.
    ///
    /// Memory use while reading is bounded by `STREAM_CHUNK` regardless
    /// of the input size - this is the path subprocess stdout/stderr go
    /// through, so a multi-GB linker log doesn't OOM the executor. The
    /// stream is hashed and written to a scratch file in one pass; on
    /// completion the scratch file is optionally compressed, then
    /// renamed into place or discarded if the blob already exists. On
    /// any error along the way the scratch file is removed; a crashed
    /// writer leaves at most one orphaned `scratch/stream-*` that
    /// future cache invocations ignore.
    pub async fn put_stream<R: AsyncRead + Unpin>(&self, reader: R) -> Result<Digest> {
        let (tmp, digest) = self.stream_to_tmp("stream", reader).await?;
        let final_path = self.blob_path(&digest);

        if fs::try_exists(&final_path).await.unwrap_or(false) {
            // Another writer beat us, or this content is already cached.
            let _ = fs::remove_file(&tmp).await;
            return Ok(digest);
        }

        let stored_tmp = self.prepare_blob_tmp(&tmp).await?;
        if fs::try_exists(&final_path).await.unwrap_or(false) {
            let _ = fs::remove_file(&stored_tmp).await;
            if stored_tmp != tmp {
                let _ = fs::remove_file(&tmp).await;
            }
            return Ok(digest);
        }

        rename_into_place(&stored_tmp, &final_path).await?;
        if stored_tmp != tmp {
            let _ = fs::remove_file(&tmp).await;
        }
        Ok(digest)
    }

    /// Stream `reader` into the scratch dir and compute the BLAKE3 of
    /// the bytes. The caller is responsible for renaming the returned
    /// tmp path into its final location.
    async fn stream_to_tmp<R: AsyncRead + Unpin>(
        &self,
        prefix: &str,
        reader: R,
    ) -> Result<(PathBuf, Digest)> {
        let scratch = self.scratch_dir();
        ensure_dir(&scratch).await?;
        let pid = process::id();
        let seq = TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let tmp = scratch.join(format!("{prefix}-{pid}-{seq}"));

        match self.write_stream_to(&tmp, reader).await {
            Ok(digest) => Ok((tmp, digest)),
            Err(e) => {
                let _ = fs::remove_file(&tmp).await;
                Err(e)
            }
        }
    }

    async fn write_stream_to<R: AsyncRead + Unpin>(
        &self,
        tmp: &Path,
        mut reader: R,
    ) -> Result<Digest> {
        let mut file = File::create(tmp).await.map_err(|source| Error::Io {
            path: tmp.to_path_buf(),
            source,
        })?;
        let mut hasher = blake3::Hasher::new();
        let mut buf = vec![0u8; STREAM_CHUNK];
        loop {
            let n = reader.read(&mut buf).await.map_err(|source| Error::Io {
                path: tmp.to_path_buf(),
                source,
            })?;
            if n == 0 {
                break;
            }
            hasher.update(&buf[..n]);
            file.write_all(&buf[..n])
                .await
                .map_err(|source| Error::Io {
                    path: tmp.to_path_buf(),
                    source,
                })?;
        }
        file.sync_all().await.map_err(|source| Error::Io {
            path: tmp.to_path_buf(),
            source,
        })?;
        Ok(Digest::from_bytes(*hasher.finalize().as_bytes()))
    }

    async fn prepare_blob_tmp(&self, raw_tmp: &Path) -> Result<PathBuf> {
        let scratch = self.scratch_dir();
        ensure_dir(&scratch).await?;
        let pid = process::id();
        let seq = TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let encoded_tmp = scratch.join(format!("zstd-{pid}-{seq}"));
        let raw_for_task = raw_tmp.to_path_buf();
        let encoded_for_task = encoded_tmp.clone();
        let encoded = tokio::task::spawn_blocking(move || {
            blob::encode_file(&raw_for_task, &encoded_for_task)
        })
        .await
        .map_err(|source| Error::Io {
            path: raw_tmp.to_path_buf(),
            source: io::Error::other(source.to_string()),
        })?
        .map_err(|source| Error::Io {
            path: raw_tmp.to_path_buf(),
            source,
        })?;

        if encoded.should_store {
            Ok(encoded_tmp)
        } else {
            let _ = fs::remove_file(&encoded_tmp).await;
            Ok(raw_tmp.to_path_buf())
        }
    }

    /// Read a content-addressed blob.
    pub async fn get_blob(&self, digest: &Digest) -> Result<Vec<u8>> {
        let path = self.blob_path(digest);
        match fs::read(&path).await {
            Ok(bytes) => blob::decode_bytes(bytes).map_err(|source| Error::Io { path, source }),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Err(Error::BlobNotFound(*digest)),
            Err(source) => Err(Error::Io { path, source }),
        }
    }

    /// True if a content-addressed blob exists at `digest`.
    pub async fn has_blob(&self, digest: &Digest) -> Result<bool> {
        let path = self.blob_path(digest);
        fs::try_exists(&path)
            .await
            .map_err(|source| Error::Io { path, source })
    }

    pub async fn put_action_result(&self, action: &Digest, result: &ActionResult) -> Result<()> {
        let path = self.action_path(action);
        let bytes = serde_json::to_vec(result).expect("ActionResult is serializable");
        write_durably(&path, &bytes).await
    }

    pub async fn get_action_result(&self, action: &Digest) -> Result<Option<ActionResult>> {
        let path = self.action_path(action);
        match fs::read(&path).await {
            Ok(bytes) => {
                let result =
                    serde_json::from_slice(&bytes).map_err(|e| Error::Corrupt(path.clone(), e))?;
                Ok(Some(result))
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(source) => Err(Error::Io { path, source }),
        }
    }

    /// Delete a single action result. Useful for `once cache forget`.
    pub async fn forget_action(&self, action: &Digest) -> Result<bool> {
        let path = self.action_path(action);
        match fs::remove_file(&path).await {
            Ok(()) => Ok(true),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(source) => Err(Error::Io { path, source }),
        }
    }

    pub async fn stats(&self) -> Result<Stats> {
        let blobs_dir = self.blobs_dir();
        let actions_dir = self.actions_dir();
        let (blobs, actions) =
            tokio::try_join!(count_files(&blobs_dir), count_files(&actions_dir))?;
        Ok(Stats {
            blob_count: blobs.0,
            blob_bytes: blobs.1,
            action_count: actions.0,
            action_bytes: actions.1,
        })
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Stats {
    pub blob_count: u64,
    pub blob_bytes: u64,
    pub action_count: u64,
    pub action_bytes: u64,
}

/// Buffer size for [`Cas::put_stream`]. Bounds per-stream memory use.
const STREAM_CHUNK: usize = 64 * 1024;

/// Process-wide tmp-file counter so concurrent writers within one
/// process never collide.
static TMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Atomically write `bytes` to `path` with crash-survivable durability:
/// fsync the temp file, rename, fsync the parent dir.
///
/// Tmp filename includes the PID and a per-process counter so that two
/// concurrent writers of the same target never collide on the temp
/// path.
async fn write_durably(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    ensure_dir(parent).await?;

    let pid = process::id();
    let seq = TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    let basename = path
        .file_name()
        .map_or_else(|| std::borrow::Cow::Borrowed(""), |n| n.to_string_lossy());
    let tmp = parent.join(format!(".tmp-{basename}-{pid}-{seq}"));

    write_and_sync(&tmp, bytes).await?;

    if let Err(source) = fs::rename(&tmp, path).await {
        // Best-effort cleanup; failure here doesn't change the caller's
        // error.
        let _ = fs::remove_file(&tmp).await;
        return Err(Error::Io {
            path: path.to_path_buf(),
            source,
        });
    }
    fsync_dir(parent).await
}

async fn write_and_sync(path: &Path, bytes: &[u8]) -> Result<()> {
    let mut f = File::create(path).await.map_err(|source| Error::Io {
        path: path.to_path_buf(),
        source,
    })?;
    f.write_all(bytes).await.map_err(|source| Error::Io {
        path: path.to_path_buf(),
        source,
    })?;
    f.sync_all().await.map_err(|source| Error::Io {
        path: path.to_path_buf(),
        source,
    })?;
    Ok(())
}

#[cfg(unix)]
async fn fsync_dir(dir: &Path) -> Result<()> {
    let f = File::open(dir).await.map_err(|source| Error::Io {
        path: dir.to_path_buf(),
        source,
    })?;
    f.sync_all().await.map_err(|source| Error::Io {
        path: dir.to_path_buf(),
        source,
    })?;
    Ok(())
}

// Windows can't fsync a directory; the rename is the durable point.
#[cfg(not(unix))]
async fn fsync_dir(_: &Path) -> Result<()> {
    Ok(())
}

async fn rename_into_place(tmp: &Path, final_path: &Path) -> Result<()> {
    let parent = final_path.parent().expect("shard path has parent");
    ensure_dir(parent).await?;
    fs::rename(tmp, final_path)
        .await
        .map_err(|source| Error::Io {
            path: final_path.to_path_buf(),
            source,
        })?;
    fsync_dir(parent).await
}

async fn ensure_dir(path: &Path) -> Result<()> {
    fs::create_dir_all(path).await.map_err(|source| Error::Io {
        path: path.to_path_buf(),
        source,
    })
}

async fn count_files(root: &Path) -> Result<(u64, u64)> {
    let mut count = 0u64;
    let mut bytes = 0u64;
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let mut entries = match fs::read_dir(&dir).await {
            Ok(e) => e,
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(source) => return Err(Error::Io { path: dir, source }),
        };
        loop {
            let entry = match entries.next_entry().await {
                Ok(Some(entry)) => entry,
                Ok(None) => break,
                Err(source) => {
                    return Err(Error::Io {
                        path: dir.clone(),
                        source,
                    })
                }
            };
            let ft = entry.file_type().await.map_err(|source| Error::Io {
                path: entry.path(),
                source,
            })?;
            if ft.is_dir() {
                stack.push(entry.path());
            } else if ft.is_file() {
                // Skip half-written tmp files that crashed before rename.
                let name = entry.file_name();
                if name.to_string_lossy().starts_with(".tmp-") {
                    continue;
                }
                count += 1;
                bytes += entry
                    .metadata()
                    .await
                    .map_err(|source| Error::Io {
                        path: entry.path(),
                        source,
                    })?
                    .len();
            }
        }
    }
    Ok((count, bytes))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use tempfile::TempDir;

    #[test]
    fn open_does_no_io() {
        let tmp = TempDir::new().unwrap();
        let nested = tmp.path().join("not/yet/created");
        let _cas = Cas::open(&nested);
        assert!(!nested.exists(), "open must not touch disk");
    }

    #[tokio::test]
    async fn put_get_blob_roundtrip() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let d = cas.put_blob(b"hello").await.unwrap();
        assert_eq!(cas.get_blob(&d).await.unwrap(), b"hello");
    }

    #[tokio::test]
    async fn put_blob_compresses_repetitive_payload_at_rest() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let payload = b"cache line\n".repeat(4096);

        let d = cas.put_blob(&payload).await.unwrap();
        let stored = fs::read(cas.blob_path(&d)).await.unwrap();

        assert!(stored.starts_with(blob::ZSTD_BLOB_MAGIC));
        assert!(stored.len() < payload.len());
        assert_eq!(cas.blob_size(&d).await.unwrap(), payload.len() as u64);
        assert_eq!(cas.get_blob(&d).await.unwrap(), payload);
    }

    #[tokio::test]
    async fn get_blob_reads_legacy_raw_blob() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let payload = b"legacy raw blob";
        let d = Digest::of_bytes(payload);
        let path = cas.blob_path(&d);
        fs::create_dir_all(path.parent().unwrap()).await.unwrap();
        fs::write(&path, payload).await.unwrap();

        assert_eq!(cas.get_blob(&d).await.unwrap(), payload);
        assert_eq!(cas.blob_size(&d).await.unwrap(), payload.len() as u64);
    }

    #[tokio::test]
    async fn put_blob_is_idempotent() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let d1 = cas.put_blob(b"hello").await.unwrap();
        let d2 = cas.put_blob(b"hello").await.unwrap();
        assert_eq!(d1, d2);
    }

    #[tokio::test]
    async fn concurrent_writers_of_identical_blob_do_not_race() {
        let tmp = TempDir::new().unwrap();
        let cas = Arc::new(Cas::open(tmp.path()));
        let mut handles = Vec::new();
        for _ in 0..16 {
            let cas = Arc::clone(&cas);
            handles.push(tokio::spawn(async move {
                cas.put_blob(b"shared content").await
            }));
        }
        let mut digests = Vec::new();
        for h in handles {
            digests.push(h.await.unwrap().unwrap());
        }
        assert!(digests.windows(2).all(|w| w[0] == w[1]));
        assert_eq!(cas.get_blob(&digests[0]).await.unwrap(), b"shared content");
    }

    #[tokio::test]
    async fn action_result_roundtrip() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let stdout = cas.put_blob(b"out").await.unwrap();
        let stderr = cas.put_blob(b"err").await.unwrap();
        let action = Digest::of_bytes(b"action-key");
        let result = ActionResult {
            exit_code: 0,
            stdout: Some(stdout),
            stderr: Some(stderr),
            outputs: std::collections::BTreeMap::new(),
        };
        cas.put_action_result(&action, &result).await.unwrap();
        assert_eq!(cas.get_action_result(&action).await.unwrap(), Some(result));
    }

    #[tokio::test]
    async fn action_result_without_stdout_or_stderr_roundtrips() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let action = Digest::of_bytes(b"silent-action");
        let result = ActionResult {
            exit_code: 0,
            stdout: None,
            stderr: None,
            outputs: std::collections::BTreeMap::new(),
        };
        cas.put_action_result(&action, &result).await.unwrap();
        assert_eq!(cas.get_action_result(&action).await.unwrap(), Some(result));
    }

    #[tokio::test]
    async fn missing_action_returns_none() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let d = Digest::of_bytes(b"nope");
        assert_eq!(cas.get_action_result(&d).await.unwrap(), None);
    }

    #[tokio::test]
    async fn forget_action_removes_only_the_target() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let stdout = cas.put_blob(b"x").await.unwrap();
        let key = Digest::of_bytes(b"k");
        let result = ActionResult {
            exit_code: 0,
            stdout: Some(stdout),
            stderr: Some(stdout),
            outputs: std::collections::BTreeMap::new(),
        };
        cas.put_action_result(&key, &result).await.unwrap();
        assert!(cas.forget_action(&key).await.unwrap());
        assert_eq!(cas.get_action_result(&key).await.unwrap(), None);
        // Blob is untouched - multiple actions may share a stdout blob.
        assert_eq!(cas.get_blob(&stdout).await.unwrap(), b"x");
        // Forgetting again is a no-op.
        assert!(!cas.forget_action(&key).await.unwrap());
    }

    #[tokio::test]
    async fn stats_ignores_orphaned_tmp_files() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        cas.put_blob(b"real").await.unwrap();
        // Simulate a crashed write.
        let orphan = cas.blobs_dir().join("zz").join(".tmp-leftover-1234-5");
        fs::create_dir_all(orphan.parent().unwrap()).await.unwrap();
        fs::write(&orphan, b"junk").await.unwrap();
        let s = cas.stats().await.unwrap();
        assert_eq!(s.blob_count, 1);
    }

    #[tokio::test]
    async fn stats_counts_blobs_and_actions() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        cas.put_blob(b"abc").await.unwrap();
        cas.put_blob(b"defg").await.unwrap();
        let key = Digest::of_bytes(b"k");
        let stdout = cas.put_blob(b"out").await.unwrap();
        cas.put_action_result(
            &key,
            &ActionResult {
                exit_code: 0,
                stdout: Some(stdout),
                stderr: Some(stdout),
                outputs: std::collections::BTreeMap::new(),
            },
        )
        .await
        .unwrap();
        let s = cas.stats().await.unwrap();
        assert_eq!(s.blob_count, 3);
        assert_eq!(s.blob_bytes, 3 + 4 + 3);
        assert_eq!(s.action_count, 1);
        assert!(s.action_bytes > 0);
    }

    #[tokio::test]
    async fn stats_on_empty_cas_returns_zeros() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let s = cas.stats().await.unwrap();
        assert_eq!(s.blob_count, 0);
        assert_eq!(s.blob_bytes, 0);
        assert_eq!(s.action_count, 0);
        assert_eq!(s.action_bytes, 0);
    }

    #[tokio::test]
    async fn put_stream_roundtrip_small() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let payload = b"streamed payload";
        let d = cas.put_stream(&payload[..]).await.unwrap();
        assert_eq!(d, Digest::of_bytes(payload));
        assert_eq!(cas.get_blob(&d).await.unwrap(), payload);
    }

    #[tokio::test]
    async fn put_stream_handles_empty_input() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let d = cas.put_stream(&b""[..]).await.unwrap();
        assert_eq!(d, Digest::of_bytes(b""));
        assert!(cas.get_blob(&d).await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn put_stream_handles_payload_larger_than_chunk() {
        // STREAM_CHUNK = 64 KiB; use a payload that crosses the
        // boundary several times to exercise the loop.
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let payload: Vec<u8> = (0..(STREAM_CHUNK * 3 + 7))
            .map(|i| u8::try_from(i & 0xff).unwrap())
            .collect();
        let d = cas.put_stream(&payload[..]).await.unwrap();
        assert_eq!(d, Digest::of_bytes(&payload));
        assert_eq!(cas.get_blob(&d).await.unwrap(), payload);
    }

    #[tokio::test]
    async fn put_stream_compresses_repetitive_payload_at_rest() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let payload = vec![b'x'; STREAM_CHUNK * 3];

        let d = cas.put_stream(payload.as_slice()).await.unwrap();
        let stored = fs::read(cas.blob_path(&d)).await.unwrap();

        assert_eq!(d, Digest::of_bytes(&payload));
        assert!(stored.starts_with(blob::ZSTD_BLOB_MAGIC));
        assert!(stored.len() < payload.len());
        assert_eq!(cas.get_blob(&d).await.unwrap(), payload);
    }

    #[tokio::test]
    async fn put_stream_cleans_up_scratch_on_read_error() {
        use std::io;
        use std::pin::Pin;
        use std::task::{Context, Poll};
        use tokio::io::ReadBuf;

        struct ExplodingReader;
        impl AsyncRead for ExplodingReader {
            fn poll_read(
                self: Pin<&mut Self>,
                _cx: &mut Context<'_>,
                _buf: &mut ReadBuf<'_>,
            ) -> Poll<io::Result<()>> {
                Poll::Ready(Err(io::Error::other("synthetic read failure")))
            }
        }

        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let err = cas.put_stream(ExplodingReader).await.unwrap_err();
        assert!(matches!(err, Error::Io { .. }));

        // The scratch directory must contain no `stream-*` leftovers.
        let scratch = cas.scratch_dir();
        if scratch.exists() {
            let mut entries = fs::read_dir(&scratch).await.unwrap();
            while let Some(entry) = entries.next_entry().await.unwrap() {
                let name = entry.file_name();
                let name = name.to_string_lossy();
                assert!(
                    !name.starts_with("stream-"),
                    "leftover scratch file: {name}"
                );
            }
        }
    }

    #[tokio::test]
    async fn put_stream_dedups_identical_content() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let payload = vec![42u8; STREAM_CHUNK + 100];
        let d1 = cas.put_stream(&payload[..]).await.unwrap();
        let d2 = cas.put_stream(&payload[..]).await.unwrap();
        assert_eq!(d1, d2);
        // Only one blob entry exists despite two puts.
        assert_eq!(cas.stats().await.unwrap().blob_count, 1);
    }

    #[tokio::test]
    async fn concurrent_put_stream_of_identical_content_is_safe() {
        let tmp = TempDir::new().unwrap();
        let cas = Arc::new(Cas::open(tmp.path()));
        let payload: Vec<u8> = (0..(STREAM_CHUNK * 2))
            .map(|i| u8::try_from(i & 0xff).unwrap())
            .collect();
        let payload = Arc::new(payload);
        let mut handles = Vec::new();
        for _ in 0..8 {
            let cas = Arc::clone(&cas);
            let payload = Arc::clone(&payload);
            handles.push(tokio::spawn(async move {
                cas.put_stream(payload.as_slice()).await
            }));
        }
        let mut digests = Vec::new();
        for h in handles {
            digests.push(h.await.unwrap().unwrap());
        }
        assert!(digests.windows(2).all(|w| w[0] == w[1]));
        assert_eq!(cas.stats().await.unwrap().blob_count, 1);
    }

    #[tokio::test]
    async fn concurrent_writers_of_distinct_blobs_all_persist() {
        // Different content goes to different shards; nothing races on
        // the same final path.
        let tmp = TempDir::new().unwrap();
        let cas = Arc::new(Cas::open(tmp.path()));
        let mut handles = Vec::new();
        for i in 0..32u32 {
            let cas = Arc::clone(&cas);
            handles.push(tokio::spawn(async move {
                cas.put_blob(format!("blob-{i}").as_bytes()).await
            }));
        }
        let mut digests = Vec::new();
        for h in handles {
            digests.push(h.await.unwrap().unwrap());
        }
        // All 32 distinct, all readable.
        let unique: std::collections::HashSet<_> = digests.iter().collect();
        assert_eq!(unique.len(), 32);
        for (i, d) in digests.iter().enumerate() {
            assert_eq!(
                cas.get_blob(d).await.unwrap(),
                format!("blob-{i}").as_bytes()
            );
        }
    }

    #[tokio::test]
    async fn has_blob_is_false_for_unknown_digest() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let d = Digest::of_bytes(b"never-stored");
        assert!(!cas.has_blob(&d).await.unwrap());
    }

    #[tokio::test]
    async fn has_blob_finds_content_addressed_blob() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let d = cas.put_blob(b"hello").await.unwrap();
        assert!(cas.has_blob(&d).await.unwrap());
    }

    #[tokio::test]
    async fn get_blob_returns_blob_not_found_for_unknown_digest() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        let d = Digest::of_bytes(b"never-stored");
        match cas.get_blob(&d).await {
            Err(Error::BlobNotFound(missing)) => assert_eq!(missing, d),
            other => panic!("expected BlobNotFound, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn get_action_result_surfaces_corruption() {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        // Plant a corrupted action-result file at a known digest path.
        let key = Digest::of_bytes(b"corrupt");
        let stdout = cas.put_blob(b"x").await.unwrap();
        cas.put_action_result(
            &key,
            &ActionResult {
                exit_code: 0,
                stdout: Some(stdout),
                stderr: Some(stdout),
                outputs: std::collections::BTreeMap::new(),
            },
        )
        .await
        .unwrap();
        // Overwrite with non-JSON.
        let action_path = cas.action_path(&key);
        fs::write(&action_path, b"not json").await.unwrap();
        match cas.get_action_result(&key).await {
            Err(Error::Corrupt(path, _)) => assert_eq!(path, action_path),
            other => panic!("expected Corrupt, got {other:?}"),
        }
    }
}
