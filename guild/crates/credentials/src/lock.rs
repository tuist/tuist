use std::fs::{self, File, OpenOptions, TryLockError};
use std::io;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

/// Swift's `CachedValueStore` waits at most this long for a peer.
const TIMEOUT: Duration = Duration::from_secs(30);
const RETRY_INTERVAL: Duration = Duration::from_millis(100);

#[derive(Debug)]
pub enum LockError {
    TimedOut(Duration),
    Io(io::Error),
}

impl std::fmt::Display for LockError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TimedOut(after) => write!(
                f,
                "timed out after {}s waiting for another Tuist process to finish refreshing the session",
                after.as_secs()
            ),
            Self::Io(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for LockError {}

/// The exclusive lock every Tuist client holds while it reads, rotates, and
/// writes one server's credentials.
///
/// It is the same file the Swift clients lock:
/// `<state>/cached_value_store/credential-refresh-<fnv1a64(storage key)>.lock`.
/// `File::lock` is `flock(LOCK_EX)` on macOS and Linux, matching TSCBasic's
/// `FileLock`, and `LockFileEx` on Windows. Dropping the guard releases it.
#[derive(Debug)]
pub struct RefreshLock {
    _file: File,
}

impl RefreshLock {
    /// The lock for the CLI's credentials file, whose storage key is its path.
    pub fn path(state_directory: &Path, credentials_path: &Path) -> PathBuf {
        Self::path_for_key(state_directory, &credentials_path.to_string_lossy())
    }

    /// `ServerCredentialsStore.storageKey(serverURL:)`: the credentials file
    /// path, or the canonical server URL for the Tuist app's Keychain items.
    pub fn path_for_key(state_directory: &Path, storage_key: &str) -> PathBuf {
        let key = format!("credential-refresh-{}", stable_hash(storage_key));
        state_directory
            .join("cached_value_store")
            .join(format!("{}.lock", sanitized(&key)))
    }

    pub fn acquire(path: &Path) -> Result<Self, LockError> {
        Self::acquire_within(path, TIMEOUT)
    }

    /// Polls a non-blocking lock so a stuck peer becomes an error instead of a
    /// hang, like `CachedValueStore.acquireFileLockWithTimeout`.
    pub fn acquire_within(path: &Path, timeout: Duration) -> Result<Self, LockError> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(LockError::Io)?;
        }
        let file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .open(path)
            .map_err(LockError::Io)?;
        let deadline = Instant::now() + timeout;
        loop {
            match file.try_lock() {
                Ok(()) => return Ok(Self { _file: file }),
                Err(TryLockError::WouldBlock) if Instant::now() < deadline => {
                    thread::sleep(RETRY_INTERVAL)
                }
                Err(TryLockError::WouldBlock) => return Err(LockError::TimedOut(timeout)),
                Err(TryLockError::Error(error)) => return Err(LockError::Io(error)),
            }
        }
    }
}

/// `ServerAuthenticationController.stableHash`: 64-bit FNV-1a over UTF-8, in
/// unpadded lowercase hexadecimal.
fn stable_hash(value: &str) -> String {
    let hash = value
        .bytes()
        .fold(14_695_981_039_346_656_037_u64, |hash, byte| {
            (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211)
        });
    format!("{hash:x}")
}

fn sanitized(key: &str) -> String {
    key.replace(['/', ':', ' '], "_")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lock_path_matches_the_swift_cached_value_store() {
        // fnv1a64("/Users/ana/.config/tuist/credentials/tuist.dev.json"), computed independently.
        let path = RefreshLock::path(
            Path::new("/Users/ana/.local/state/tuist"),
            Path::new("/Users/ana/.config/tuist/credentials/tuist.dev.json"),
        );
        assert_eq!(
            path,
            PathBuf::from(
                "/Users/ana/.local/state/tuist/cached_value_store/credential-refresh-990d81e8c70e3d4c.lock"
            )
        );
    }

    #[test]
    fn keychain_lock_path_hashes_the_canonical_server_url() {
        // fnv1a64("https://tuist.dev"), computed independently.
        assert_eq!(
            RefreshLock::path_for_key(Path::new("/s"), "https://tuist.dev"),
            PathBuf::from("/s/cached_value_store/credential-refresh-d79fb54a63e03cb2.lock")
        );
    }

    #[test]
    fn a_held_lock_times_out_other_holders_and_releases_on_drop() {
        let path = std::env::temp_dir().join(format!("tuist-lock-{}/a.lock", std::process::id()));
        let held = RefreshLock::acquire(&path).unwrap();
        assert!(matches!(
            RefreshLock::acquire_within(&path, Duration::from_millis(250)),
            Err(LockError::TimedOut(_))
        ));
        drop(held);
        RefreshLock::acquire_within(&path, Duration::from_millis(250)).unwrap();
    }
}
