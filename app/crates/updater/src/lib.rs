//! Authenticated, opt-in updates for the AppImage and per-user NSIS distributions.
//!
//! Calls block: run checks and downloads off the UI thread. Neither operation
//! installs anything. Only call [`PreparedUpdate::install_and_restart`] after
//! explicit user approval, event-loop shutdown, and releasing the instance lock.

use anyhow::{Context, Result, bail, ensure};
use base64::{Engine, engine::general_purpose::STANDARD};
use cargo_packager_updater::{Config, RemoteRelease, RemoteReleaseData, UpdateFormat};
use minisign_verify::{PublicKey, Signature};
use std::{io::Read, path::PathBuf, time::Duration};
use url::Url;

const FEED: &str = "https://github.com/tuist/tuist/releases/download/desktop-updates/latest.json";
const PUBLIC_KEY: &str = include_str!("public-key.txt");
const PACKAGE_KIND: &str = include_str!("package-kind.txt");
const MANIFEST_LIMIT: u64 = 256 * 1024;
const SIGNATURE_LIMIT: u64 = 16 * 1024;
const PAYLOAD_LIMIT: u64 = 512 * 1024 * 1024;
const METADATA_TIMEOUT: Duration = Duration::from_secs(20);
const PAYLOAD_TIMEOUT: Duration = Duration::from_secs(10 * 60);

#[derive(Clone)]
struct Runtime {
    key: String,
    target: &'static str,
    path: PathBuf,
    feed: String,
    #[cfg(test)]
    payload_endpoint: Option<Url>,
}

/// Why automatic updates are disabled, or `Ok` when this installation supports them.
/// Development builds deliberately ship without a key and distribution marker.
pub fn availability() -> std::result::Result<(), String> {
    runtime().map(|_| ()).map_err(|error| format!("{error:#}"))
}

fn runtime() -> Result<Runtime> {
    #[cfg(test)]
    if let Some(runtime) = tests::RUNTIME.with(|slot| slot.borrow().clone()) {
        return Ok(runtime);
    }

    ensure!(
        !PUBLIC_KEY.trim().is_empty(),
        "Automatic updates are disabled: this build has no release verification key"
    );
    decode_key(PUBLIC_KEY).context("Automatic updates are disabled: invalid release key")?;
    ensure!(
        cfg!(target_arch = "x86_64"),
        "Automatic updates are only available for x86_64 distributions"
    );
    let (path, target) = if cfg!(target_os = "linux") {
        ensure!(
            PACKAGE_KIND.trim() == "appimage",
            "Only packaged AppImage builds support automatic updates"
        );
        let image = PathBuf::from(
            std::env::var_os("APPIMAGE").context("Run the AppImage to use automatic updates")?,
        );
        ensure!(
            image.is_absolute() && image.is_file(),
            "APPIMAGE must name an existing absolute AppImage path"
        );
        let appdir = PathBuf::from(
            std::env::var_os("APPDIR").context("AppImage runtime APPDIR is missing")?,
        )
        .canonicalize()?;
        ensure!(
            std::env::current_exe()?
                .canonicalize()?
                .starts_with(&appdir),
            "This executable is not running inside the AppImage runtime"
        );
        (image.canonicalize()?, "linux-x86_64")
    } else if cfg!(target_os = "windows") {
        ensure!(
            PACKAGE_KIND.trim() == "nsis",
            "Only packaged NSIS builds support automatic updates"
        );
        let exe = std::env::current_exe()?.canonicalize()?;
        let directory = exe.parent().context("Installation directory is missing")?;
        let local =
            PathBuf::from(std::env::var_os("LOCALAPPDATA").context("LOCALAPPDATA is missing")?)
                .canonicalize()?;
        ensure!(
            directory == local.join("Tuist"),
            "Automatic updates require the per-user NSIS installation in LOCALAPPDATA\\Tuist"
        );
        ensure!(
            directory.join("uninstall.exe").is_file(),
            "NSIS uninstaller is missing; portable builds cannot update"
        );
        let marker = std::fs::read(directory.join("tuist-installation"))
            .context("NSIS installation marker is missing; portable builds cannot update")?;
        ensure!(
            marker == b"nsis" || marker == b"nsis\n",
            "Invalid NSIS installation marker"
        );
        (directory.to_path_buf(), "windows-x86_64")
    } else {
        bail!(
            "Automatic updates are only available on Linux AppImage and Windows NSIS installations"
        );
    };
    Ok(Runtime {
        key: PUBLIC_KEY.trim().to_owned(),
        target,
        path,
        feed: FEED.to_owned(),
        #[cfg(test)]
        payload_endpoint: None,
    })
}

/// Fetch and authenticate the fixed release feed before interpreting any metadata.
/// An authentic stable release not newer than this build returns `None`.
pub fn check() -> Result<Option<Update>> {
    let runtime = runtime()?;
    let client = client(METADATA_TIMEOUT)?;
    let manifest = fetch(&client, &runtime.feed, MANIFEST_LIMIT)?;
    let signature = fetch(&client, &format!("{}.sig", runtime.feed), SIGNATURE_LIMIT)?;
    let signature = std::str::from_utf8(&signature).context("Manifest signature is not UTF-8")?;
    let key = decode_key(&runtime.key)?;
    let signature = decode_signature(signature)?;
    key.verify(&manifest, &signature, false)
        .context("Release manifest signature verification failed")?;

    // Do not call upstream's check(): it fetches and deserializes unsigned JSON.
    let release: RemoteRelease =
        serde_json::from_slice(&manifest).context("Invalid signed release manifest")?;
    ensure!(
        release.version.pre.is_empty() && release.version.build.is_empty(),
        "Only stable release versions without build metadata are accepted"
    );
    let current = env!("CARGO_PKG_VERSION").parse::<cargo_packager_updater::semver::Version>()?;
    ensure!(
        current.pre.is_empty() && current.build.is_empty(),
        "This build is not on the stable update channel"
    );
    // Static platform metadata is required: dynamic metadata cannot bind a target.
    ensure!(
        matches!(release.data, RemoteReleaseData::Static { .. }),
        "The release manifest must name explicit platform targets"
    );
    let format = release.format(runtime.target)?;
    ensure!(
        matches!(
            (runtime.target, format),
            ("linux-x86_64", UpdateFormat::AppImage) | ("windows-x86_64", UpdateFormat::Nsis)
        ),
        "Release format does not match this distribution"
    );
    let url = release.download_url(runtime.target)?.clone();
    validate_asset_url(&url, &release.version.to_string(), format)?;
    // Reject unsigned/invalid payload entries even before a download is offered.
    decode_signature(release.signature(runtime.target)?)?;
    if release.version <= current {
        return Ok(None);
    }
    let inner = cargo_packager_updater::Update {
        config: Config {
            pubkey: runtime.key.clone(),
            ..Config::default()
        },
        current_version: current.to_string(),
        version: release.version.to_string(),
        date: release.pub_date,
        target: runtime.target.split('-').next().unwrap().to_owned(),
        extract_path: runtime.path.clone(),
        download_url: url,
        body: release.notes.clone(),
        signature: release.signature(runtime.target)?.clone(),
        timeout: Some(PAYLOAD_TIMEOUT),
        headers: Default::default(),
        format,
    };
    #[cfg(test)]
    let inner = cargo_packager_updater::Update {
        download_url: runtime
            .payload_endpoint
            .clone()
            .unwrap_or(inner.download_url),
        ..inner
    };
    Ok(Some(Update { inner, runtime }))
}

fn client(timeout: Duration) -> Result<reqwest::blocking::Client> {
    Ok(reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(timeout)
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() >= 5 {
                attempt.error("Too many updater redirects")
            } else if attempt.url().scheme() != "https" {
                attempt.error("Updater redirects must use HTTPS")
            } else {
                attempt.follow()
            }
        }))
        .user_agent("Tuist desktop updater")
        .build()?)
}

fn fetch(client: &reqwest::blocking::Client, url: &str, limit: u64) -> Result<Vec<u8>> {
    let response = client.get(url).send()?.error_for_status()?;
    ensure!(
        response.status() == reqwest::StatusCode::OK,
        "Unexpected updater response status"
    );
    ensure!(
        response
            .content_length()
            .is_none_or(|length| length <= limit),
        "Updater response exceeds size limit"
    );
    let mut bytes = Vec::new();
    response.take(limit + 1).read_to_end(&mut bytes)?;
    ensure!(
        bytes.len() as u64 <= limit,
        "Updater response exceeds size limit"
    );
    Ok(bytes)
}

fn decode_key(encoded: &str) -> Result<PublicKey> {
    let bytes = STANDARD
        .decode(encoded.trim())
        .context("Release key must be base64 minisign text")?;
    PublicKey::decode(std::str::from_utf8(&bytes)?).context("Invalid minisign public key")
}

fn decode_signature(encoded: &str) -> Result<Signature> {
    let bytes = STANDARD
        .decode(encoded.trim())
        .context("Missing or invalid base64 minisign signature")?;
    Signature::decode(std::str::from_utf8(&bytes)?).context("Invalid minisign signature")
}

fn validate_asset_url(url: &Url, version: &str, format: UpdateFormat) -> Result<()> {
    ensure!(
        url.scheme() == "https" && url.host_str() == Some("github.com") && url.port().is_none(),
        "Update assets must use HTTPS on github.com"
    );
    ensure!(
        url.username().is_empty()
            && url.password().is_none()
            && url.query().is_none()
            && url.fragment().is_none(),
        "Update URLs must not contain credentials, queries, or fragments"
    );
    let prefix = format!("/tuist/tuist/releases/download/desktop@{version}/");
    let encoded_prefix = format!("/tuist/tuist/releases/download/desktop%40{version}/");
    let asset = url
        .path()
        .strip_prefix(&prefix)
        .or_else(|| url.path().strip_prefix(&encoded_prefix))
        .context("Update URL must name this version's immutable desktop release")?;
    ensure!(
        !asset.is_empty()
            && asset
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"._-".contains(&c)),
        "Update URL must name a single release asset"
    );
    let extension = match format {
        UpdateFormat::AppImage => ".AppImage",
        UpdateFormat::Nsis => ".exe",
        _ => bail!("Unsupported update format"),
    };
    ensure!(
        asset.ends_with(extension),
        "Update asset extension does not match its package format"
    );
    Ok(())
}

/// Authenticated metadata. Its private fields prevent callers from replacing trust data.
pub struct Update {
    inner: cargo_packager_updater::Update,
    runtime: Runtime,
}

impl Update {
    /// Stable semantic version offered by the authenticated feed.
    pub fn version(&self) -> &str {
        &self.inner.version
    }

    /// Release notes from the authenticated feed.
    pub fn notes(&self) -> Option<&str> {
        self.inner.body.as_deref()
    }

    /// Download and verify the package, without modifying the installation.
    pub fn download(self) -> Result<PreparedUpdate> {
        // Upstream's downloader buffers without a limit. Reuse the bounded
        // transport and minisign verification used for the manifest instead.
        let bytes = fetch(
            &client(PAYLOAD_TIMEOUT)?,
            self.inner.download_url.as_str(),
            PAYLOAD_LIMIT,
        )
        .context("Update package download failed")?;
        decode_key(&self.runtime.key)?
            .verify(&bytes, &decode_signature(&self.inner.signature)?, false)
            .context("Update package signature verification failed")?;
        Ok(PreparedUpdate {
            update: self,
            bytes,
        })
    }
}

/// Verified bytes held in memory. Dropping this value cancels without installing.
pub struct PreparedUpdate {
    update: Update,
    bytes: Vec<u8>,
}

impl PreparedUpdate {
    /// Install only after user consent, UI shutdown, and dropping the instance lock.
    /// Windows launches NSIS with `/P /R` and exits the process upstream. Linux
    /// atomically replaces the AppImage and restarts without stale mount variables.
    pub fn install_and_restart(self) -> Result<()> {
        let runtime = runtime().context("Installation no longer supports automatic updates")?;
        ensure!(
            runtime.path == self.update.runtime.path
                && runtime.target == self.update.runtime.target
                && runtime.key == self.update.runtime.key,
            "Installation changed since the update was checked"
        );
        if runtime.target == "linux-x86_64" {
            #[cfg(unix)]
            {
                install_appimage(&runtime.path, &self.bytes).context("Failed to install update")?;
                let mut command = appimage_restart_command(&runtime.path, std::env::vars_os());
                #[cfg(test)]
                if let Some(result) = tests::RESTART
                    .with(|slot| slot.borrow().as_ref().map(|restart| restart(&mut command)))
                {
                    return result;
                }
                command
                    .spawn()
                    .context("Update installed, but restarting the AppImage failed")?;
                return Ok(());
            }
            #[cfg(not(unix))]
            bail!("AppImage updates require Unix");
        }
        // Keep upstream's NSIS handoff and process-exit behavior on Windows.
        #[cfg(target_os = "windows")]
        {
            self.update
                .inner
                .install(self.bytes)
                .context("Failed to install update")?;
            Ok(())
        }
        #[cfg(not(target_os = "windows"))]
        bail!("NSIS updates require Windows")
    }
}

#[cfg(unix)]
fn install_appimage(path: &std::path::Path, bytes: &[u8]) -> Result<()> {
    use std::io::Write;

    let parent = path.parent().context("AppImage directory is missing")?;
    let permissions = std::fs::metadata(path)?.permissions();
    // A sibling guarantees the commit stays on one filesystem. Until rename,
    // even an interrupted write leaves the existing executable untouched.
    let mut staged = tempfile::NamedTempFile::new_in(parent)?;
    staged.write_all(bytes)?;
    staged.as_file().set_permissions(permissions)?;
    staged.as_file().sync_all()?;
    #[cfg(test)]
    tests::BEFORE_COMMIT.with(|slot| {
        if let Some(before_commit) = slot.borrow().as_ref() {
            before_commit(path, staged.path())?;
        }
        Ok::<_, anyhow::Error>(())
    })?;
    staged.persist(path).map_err(|error| error.error)?;
    // Make the directory entry durable as well as the replacement's contents.
    // Failure here means installation committed, but durability is uncertain.
    std::fs::File::open(parent)
        .and_then(|directory| directory.sync_all())
        .context("Update installed, but syncing the AppImage directory failed")?;
    Ok(())
}

#[cfg(unix)]
fn appimage_restart_command(
    path: &std::path::Path,
    environment: impl IntoIterator<Item = (std::ffi::OsString, std::ffi::OsString)>,
) -> std::process::Command {
    let mut environment: std::collections::BTreeMap<_, _> = environment.into_iter().collect();
    // Keep user settings such as APPIMAGE_EXTRACT_AND_RUN (FUSE-less mode),
    // but never reuse paths into the old runtime's mount/extraction directory.
    for name in [
        "APPIMAGE",
        "APPDIR",
        "ARGV0",
        "OWD",
        "APPIMAGE_SILENT_INSTALL",
    ] {
        environment.remove(std::ffi::OsStr::new(name));
    }
    environment.remove(std::ffi::OsStr::new("LD_LIBRARY_PATH"));
    if let Some(original) = environment.remove(std::ffi::OsStr::new("LD_LIBRARY_PATH_ORIG")) {
        environment.insert("LD_LIBRARY_PATH".into(), original);
    }
    let mut command = std::process::Command::new(path);
    // Do not forward arguments: URLs may contain expired credentials.
    command.env_clear().envs(environment);
    command
}

#[cfg(test)]
mod tests;
