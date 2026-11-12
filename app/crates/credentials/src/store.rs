use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use url::Url;

/// Swift's `ServerCredentials`, encoded as `JSONEncoder` does: camelCase keys,
/// absent optionals omitted.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Credentials {
    pub access_token: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    /// The OAuth client that issued the pair; refreshes must present it.
    #[serde(
        default,
        rename = "oauthClientID",
        skip_serializing_if = "Option::is_none"
    )]
    pub oauth_client_id: Option<String>,
    /// The server refused the refresh token. Kept distinct from signing out so
    /// every client asks the person to sign in again instead of acting anonymously.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rejected: Option<bool>,
}

impl Credentials {
    pub fn is_rejected(&self) -> bool {
        self.rejected == Some(true)
    }
}

#[derive(Debug)]
pub enum StoreError {
    InvalidServerUrl(String),
    /// The file exists but is not readable credentials. Never treated as signed out.
    Corrupt(PathBuf),
    Io(io::Error),
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidServerUrl(url) => write!(f, "the server URL {url} has no host"),
            Self::Corrupt(path) => write!(f, "the credentials at {} are invalid", path.display()),
            Self::Io(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for StoreError {}

impl From<io::Error> for StoreError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

/// One JSON file per server host under `<config>/credentials/`.
#[derive(Debug, Clone)]
pub struct CredentialsStore {
    directory: PathBuf,
}

impl CredentialsStore {
    pub fn new(config_directory: &Path) -> Self {
        Self {
            directory: config_directory.join("credentials"),
        }
    }

    /// The canonical file for a server. Its path string also identifies the
    /// server's refresh lock.
    pub fn path(&self, server: &Url) -> Result<PathBuf, StoreError> {
        let host = server
            .host_str()
            .ok_or_else(|| StoreError::InvalidServerUrl(server.to_string()))?;
        Ok(self
            .directory
            .join(format!("{}.json", normalized_host(host))))
    }

    pub fn read(&self, server: &Url) -> Result<Option<Credentials>, StoreError> {
        let path = self.candidates(server)?.swap_remove(0);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|_| StoreError::Corrupt(path))
    }

    /// Replaces the canonical file atomically, so concurrent readers see either
    /// the old or the new pair.
    pub fn store(&self, server: &Url, credentials: &Credentials) -> Result<(), StoreError> {
        let path = self.path(server)?;
        atomic_write_private(
            &path,
            &serde_json::to_vec(credentials).map_err(io::Error::other)?,
        )?;
        Ok(())
    }

    /// Removes the canonical file and every legacy alias, as explicit sign-out does.
    pub fn delete(&self, server: &Url) -> Result<bool, StoreError> {
        let mut deleted = false;
        for path in self.candidates(server)? {
            match fs::remove_file(&path) {
                Ok(()) => deleted = true,
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(error) => return Err(error.into()),
            }
        }
        Ok(deleted)
    }

    /// `CredentialFileLocator.paths`: older clients wrote files named with the
    /// host's original case or trailing dots. The canonical file wins; otherwise
    /// the first alias by path. Directory errors fail closed.
    fn candidates(&self, server: &Url) -> Result<Vec<PathBuf>, StoreError> {
        let canonical = self.path(server)?;
        let entries = match fs::read_dir(&self.directory) {
            Ok(entries) => entries,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(vec![canonical]),
            Err(error) => return Err(error.into()),
        };
        let host = normalized_host(server.host_str().unwrap_or_default());
        let mut aliases = Vec::new();
        for entry in entries {
            let path = entry?.path();
            let is_alias = path
                .extension()
                .is_some_and(|extension| extension == "json")
                && path
                    .file_stem()
                    .and_then(|stem| stem.to_str())
                    .is_some_and(|stem| normalized_host(stem) == host)
                && path != canonical;
            if is_alias {
                aliases.push(path);
            }
        }
        aliases.sort();
        if canonical.exists() {
            aliases.insert(0, canonical);
            Ok(aliases)
        } else if aliases.is_empty() {
            Ok(vec![canonical])
        } else {
            Ok(aliases)
        }
    }
}

fn normalized_host(host: &str) -> String {
    host.to_lowercase().trim_end_matches('.').to_string()
}

/// Atomically replaces private JSON, using a new 0600 file even if the old
/// destination had broader permissions. Callers serialize read/modify/write.
pub fn atomic_write_private(path: &Path, bytes: &[u8]) -> io::Result<()> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let (temporary, mut file) = loop {
        let temporary = path.with_extension(format!(
            "{}.{}.tmp",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        match private_file(&temporary) {
            Ok(file) => break (temporary, file),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    };
    let result = (|| {
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[cfg(unix)]
fn private_file(path: &Path) -> io::Result<fs::File> {
    use std::os::unix::fs::OpenOptionsExt;
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
}

#[cfg(not(unix))]
fn private_file(path: &Path) -> io::Result<fs::File> {
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("tuist-credentials-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn server() -> Url {
        Url::parse("https://Tuist.dev.").unwrap()
    }

    #[test]
    fn writes_the_swift_encoding_to_the_normalized_host_file() {
        let dir = temp_dir("encoding");
        let store = CredentialsStore::new(&dir);
        let credentials = Credentials {
            access_token: "a".into(),
            refresh_token: Some("r".into()),
            oauth_client_id: Some("c".into()),
            rejected: None,
        };
        store.store(&server(), &credentials).unwrap();

        let written: serde_json::Value =
            serde_json::from_slice(&fs::read(dir.join("credentials/tuist.dev.json")).unwrap())
                .unwrap();
        assert_eq!(
            written,
            serde_json::json!({"accessToken": "a", "refreshToken": "r", "oauthClientID": "c"})
        );
        assert_eq!(store.read(&server()).unwrap(), Some(credentials));
    }

    #[test]
    fn reads_a_legacy_alias_and_sign_out_removes_every_alias() {
        let dir = temp_dir("alias");
        fs::create_dir_all(dir.join("credentials")).unwrap();
        fs::write(
            dir.join("credentials/TUIST.dev.json"),
            r#"{"accessToken":"legacy"}"#,
        )
        .unwrap();
        fs::write(
            dir.join("credentials/other.dev.json"),
            r#"{"accessToken":"other"}"#,
        )
        .unwrap();
        let store = CredentialsStore::new(&dir);

        assert_eq!(
            store.read(&server()).unwrap().unwrap().access_token,
            "legacy"
        );
        assert!(store.delete(&server()).unwrap());
        assert_eq!(store.read(&server()).unwrap(), None);
        assert!(dir.join("credentials/other.dev.json").exists());
    }

    #[test]
    fn corrupt_files_are_errors_not_signed_out() {
        let dir = temp_dir("corrupt");
        fs::create_dir_all(dir.join("credentials")).unwrap();
        fs::write(dir.join("credentials/tuist.dev.json"), "{").unwrap();
        assert!(matches!(
            CredentialsStore::new(&dir).read(&server()),
            Err(StoreError::Corrupt(_))
        ));
    }
}
