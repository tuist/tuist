//! Profile-aware linker selection and verified GitHub release installation.

use crate::config::{HttpSettings, LinkerSettings};
use eyre::{Context, Result, bail};
use flate2::read::GzDecoder;
use reqwest::blocking::Client;
use reqwest::header::{AUTHORIZATION, HeaderMap, HeaderValue, USER_AGENT};
use serde::Deserialize;
use sha2::{Digest as _, Sha256};
use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{BufReader, Read as _, Write as _};
use std::path::{Path, PathBuf};
use std::process::Command;

const LINKER_ENV: &str = "TUIST_CARGO_CACHE_LINKER";

/// A linker selected for one Cargo invocation.
#[derive(Debug, Clone)]
pub(crate) enum Selection {
    Single(PathBuf),
    Targets(BTreeMap<String, PathBuf>),
}

/// Resolve and, where necessary, install the linker selected for this build.
pub(crate) fn resolve(
    settings: &LinkerSettings,
    cache_dir: &Path,
    http: &HttpSettings,
    cargo_arguments: &[String],
) -> Result<Option<Selection>> {
    let profile = cargo_profile(cargo_arguments);
    let environment = std::env::var(LINKER_ENV)
        .ok()
        .filter(|value| !value.trim().is_empty());
    let targets = cargo_targets(cargo_arguments);
    if !targets.is_empty() {
        let mut selections = BTreeMap::new();
        for target in targets {
            let rustc_target = normalize_cargo_target(&target, cargo_arguments)?;
            // Keep path-keyed policy compatible with the Cargo argument. Only
            // the host directive needs its concrete triple for policy lookup.
            let policy_target = if target == "host-tuple" {
                &rustc_target
            } else {
                &target
            };
            if let Some(executable) = resolve_target(
                settings,
                cache_dir,
                http,
                cargo_arguments,
                &profile,
                environment.clone(),
                Some(policy_target),
            )? {
                selections.insert(rustc_target, executable);
            }
        }
        return Ok((!selections.is_empty()).then_some(Selection::Targets(selections)));
    }
    let target = if environment.is_none() && settings.selections(&profile).is_some() {
        host_target(cargo_arguments)
    } else {
        None
    };
    Ok(resolve_target(
        settings,
        cache_dir,
        http,
        cargo_arguments,
        &profile,
        environment,
        target.as_deref(),
    )?
    .map(Selection::Single))
}

/// Resolve one profile/target selector to an executable; system needs no override.
fn resolve_target(
    settings: &LinkerSettings,
    cache_dir: &Path,
    http: &HttpSettings,
    cargo_arguments: &[String],
    profile: &str,
    environment: Option<String>,
    target: Option<&str>,
) -> Result<Option<PathBuf>> {
    let configured = environment
        .or_else(|| settings.for_build(profile, target))
        .unwrap_or_else(|| settings.default.clone());
    let spec = Spec::parse(&configured)?;
    match spec {
        Spec::System => Ok(None),
        Spec::Path(path) => Ok(Some(which::which(&path).wrap_err_with(|| {
            format!("failed to find selected linker `{}`", path.display())
        })?)),
        Spec::RustLld => Ok(Some(rust_lld(target, cache_dir, cargo_arguments)?)),
        Spec::Managed { provider, version } => {
            let installed = install(provider, &version, cache_dir, http)?;
            Ok(Some(installed))
        }
    }
}

/// Validate a selector supplied by repository-owned workspace policy.
pub(crate) fn validate_workspace_selector(value: &str) -> Result<()> {
    match Spec::parse(value)? {
        Spec::Path(_) => bail!("workspace linker policy may not select an executable path"),
        _ => Ok(()),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Provider {
    Mold,
    Wild,
}

impl Provider {
    fn parse(name: &str) -> Option<Self> {
        match name {
            "mold" => Some(Self::Mold),
            "wild" => Some(Self::Wild),
            _ => None,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Mold => "mold",
            Self::Wild => "wild",
        }
    }

    fn repository(self) -> &'static str {
        match self {
            Self::Mold => "rui314/mold",
            Self::Wild => "wild-linker/wild",
        }
    }

    fn tag(self, version: &str) -> String {
        match self {
            Self::Wild => version.to_owned(),
            Self::Mold => format!("v{version}"),
        }
    }

    fn asset(self, version: &str) -> Result<String> {
        let arch = std::env::consts::ARCH;
        match self {
            Self::Mold if cfg!(target_os = "linux") => {
                let arch = match arch {
                    "x86_64" | "aarch64" | "riscv64" | "s390x" => arch,
                    "powerpc64" if cfg!(target_endian = "little") => "ppc64le",
                    other => bail!("mold does not publish a managed binary for {other}-linux"),
                };
                Ok(format!("mold-{version}-{arch}-linux.tar.gz"))
            }
            Self::Wild if cfg!(target_os = "linux") => {
                let arch = match arch {
                    "x86_64" | "aarch64" => arch,
                    "riscv64" => "riscv64gc",
                    other => bail!("Wild does not publish a managed binary for {other}-linux"),
                };
                let environment = if cfg!(target_env = "musl") {
                    "musl"
                } else {
                    "gnu"
                };
                Ok(format!(
                    "wild-linker-{version}-{arch}-unknown-linux-{environment}.tar.gz"
                ))
            }
            _ => bail!(
                "{} does not publish a managed binary for {}-{}",
                self.name(),
                arch,
                std::env::consts::OS
            ),
        }
    }

    fn executable_suffix(self) -> String {
        match self {
            Self::Mold => "/bin/mold".into(),
            Self::Wild => "/wild".into(),
        }
    }
}

enum Spec {
    System,
    RustLld,
    Path(PathBuf),
    Managed { provider: Provider, version: String },
}

impl Spec {
    fn parse(value: &str) -> Result<Self> {
        let value = value.trim();
        if value == "system" {
            return Ok(Self::System);
        }
        if matches!(value, "lld" | "rust-lld") {
            return Ok(Self::RustLld);
        }
        if let Some(path) = value.strip_prefix("path:") {
            if path.is_empty() {
                bail!("linker selector `path:` requires an executable path");
            }
            return Ok(Self::Path(path.into()));
        }
        let Some((name, version)) = value.split_once('@') else {
            bail!(
                "unknown linker selector `{value}`; use system, rust-lld, path:<executable>, or mold|wild@<version>"
            );
        };
        let Some(provider) = Provider::parse(name) else {
            bail!("unknown managed linker `{name}`; supported linkers are mold and wild");
        };
        let version = version.trim_start_matches('v');
        if version.is_empty() || matches!(version, "." | ".." | "latest") {
            bail!("managed linker `{name}` must name an exact version");
        }
        if !version
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_' | b'+'))
        {
            bail!("managed linker `{name}` has an invalid version `{version}`");
        }
        Ok(Self::Managed {
            provider,
            version: version.to_owned(),
        })
    }
}

#[derive(Deserialize)]
struct Release {
    assets: Vec<ReleaseAsset>,
}

#[derive(Deserialize)]
struct ReleaseAsset {
    name: String,
    browser_download_url: String,
    digest: Option<String>,
}

fn install(
    provider: Provider,
    version: &str,
    cache_dir: &Path,
    http: &HttpSettings,
) -> Result<PathBuf> {
    let install_dir = cache_dir
        .join("tools")
        .join(provider.name())
        .join(version)
        .join(host_install_name());
    let executable = install_dir.join(executable_filename(provider.name()));
    crate::storage::require_local(
        &install_dir,
        "managed linker directory",
        "TUIST_CARGO_CACHE_DIR",
    )?;
    if executable.is_file() {
        return Ok(executable);
    }
    fs::create_dir_all(&install_dir)?;
    let lock_path = install_dir.join("install.lock");
    let mut lock = fslock::LockFile::open(&lock_path)?;
    lock.lock()?;
    if executable.is_file() {
        return Ok(executable);
    }

    let client = github_client(http)?;
    let tag = provider.tag(version);
    let release_url = format!(
        "https://api.github.com/repos/{}/releases/tags/{tag}",
        provider.repository()
    );
    let release: Release = client
        .get(&release_url)
        .send()
        .wrap_err_with(|| format!("failed to query {release_url}"))?
        .error_for_status()?
        .json()
        .wrap_err("invalid GitHub release response")?;
    let asset_name = provider.asset(version)?;
    let asset = release
        .assets
        .into_iter()
        .find(|asset| asset.name == asset_name)
        .ok_or_else(|| {
            eyre::eyre!(
                "{} {version} has no release asset `{asset_name}`",
                provider.name()
            )
        })?;
    let expected = asset
        .digest
        .as_deref()
        .and_then(|digest| digest.strip_prefix("sha256:"))
        .ok_or_else(|| eyre::eyre!("GitHub reported no SHA-256 digest for `{asset_name}`"))?;

    crate::session::note(&format!(
        "tuist_cargo_cache[linker]: downloading {} {version} for {}",
        provider.name(),
        host_install_name()
    ));
    let mut response = client
        .get(&asset.browser_download_url)
        .send()
        .wrap_err_with(|| format!("failed to download `{asset_name}`"))?
        .error_for_status()?;
    let archive_path = install_dir.join(format!(".{asset_name}.download"));
    let mut archive = File::create(&archive_path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = response.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        archive.write_all(&buffer[..count])?;
        hasher.update(&buffer[..count]);
    }
    archive.sync_all()?;
    let actual = hex::encode(hasher.finalize());
    if !actual.eq_ignore_ascii_case(expected) {
        bail!("checksum mismatch for `{asset_name}`: expected {expected}, got {actual}");
    }

    let temporary = install_dir.join(format!(".{}.new", provider.name()));
    extract_executable(&archive_path, &temporary, &provider.executable_suffix())?;
    fs::rename(&temporary, &executable)?;
    let _ = fs::remove_file(&archive_path);
    Ok(executable)
}

fn github_client(http: &HttpSettings) -> Result<Client> {
    let mut headers = HeaderMap::new();
    headers.insert(USER_AGENT, HeaderValue::from_static("mr-boxington"));
    if let Ok(token) = std::env::var("GITHUB_TOKEN")
        && !token.is_empty()
    {
        headers.insert(
            AUTHORIZATION,
            HeaderValue::from_str(&format!("Bearer {token}"))?,
        );
    }
    Ok(Client::builder()
        .default_headers(headers)
        .connect_timeout(http.timeout)
        .timeout(http.download_timeout)
        .build()?)
}

fn extract_executable(archive: &Path, destination: &Path, suffix: &str) -> Result<()> {
    let input = BufReader::new(File::open(archive)?);
    let mut archive = tar::Archive::new(GzDecoder::new(input));
    for entry in archive.entries()? {
        let mut entry = entry?;
        let path = entry.path()?;
        let normalized = path.to_string_lossy();
        if normalized == suffix.trim_start_matches('/') || normalized.ends_with(suffix) {
            let mut output = File::create(destination)?;
            std::io::copy(&mut entry, &mut output)?;
            output.sync_all()?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt as _;
                fs::set_permissions(destination, fs::Permissions::from_mode(0o755))?;
            }
            return Ok(());
        }
    }
    bail!("release archive did not contain an executable ending in `{suffix}`")
}

fn rust_lld(target: Option<&str>, cache_dir: &Path, cargo_arguments: &[String]) -> Result<PathBuf> {
    if cfg!(windows) {
        bail!("managed rust-lld selection on Windows is not supported yet");
    }
    let output = rustc_command(cargo_arguments)
        .args(["--print", "sysroot"])
        .output()
        .wrap_err("failed to find the active Rust sysroot")?;
    if !output.status.success() {
        bail!("rustc could not report its sysroot");
    }
    let sysroot = String::from_utf8(output.stdout)?;
    let host = host_target(cargo_arguments)
        .ok_or_else(|| eyre::eyre!("rustc did not report its host target"))?;
    let path = PathBuf::from(sysroot.trim())
        .join("lib/rustlib")
        .join(&host)
        .join("bin")
        .join("rust-lld");
    if !path.is_file() {
        bail!(
            "the active Rust toolchain has no bundled linker at `{}`",
            path.display()
        );
    }
    let link_target = target.unwrap_or(&host);
    let flavor = if link_target.contains("apple") {
        "ld64.lld"
    } else {
        "ld.lld"
    };
    let sysroot_key = hex::encode(Sha256::digest(sysroot.trim().as_bytes()));
    let shim_dir = cache_dir
        .join("tools/rust-lld")
        .join(host)
        .join(sysroot_key);
    crate::storage::require_local(
        &shim_dir,
        "managed linker shim directory",
        "TUIST_CARGO_CACHE_DIR",
    )?;
    fs::create_dir_all(&shim_dir)?;
    let shim = shim_dir.join(flavor);
    #[cfg(unix)]
    {
        let mut lock = fslock::LockFile::open(&shim_dir.join("install.lock"))?;
        lock.lock()?;
        if fs::read_link(&shim).is_ok_and(|target| target == path) {
            return Ok(shim);
        }
        let temporary = shim_dir.join(format!(".{flavor}.new"));
        let _ = fs::remove_file(&temporary);
        std::os::unix::fs::symlink(&path, &temporary)?;
        fs::rename(&temporary, &shim)?;
    }
    Ok(shim)
}

pub(crate) fn cargo_profile(arguments: &[String]) -> String {
    let mut arguments = arguments
        .iter()
        .take_while(|argument| argument.as_str() != "--");
    let mut subcommand = None;
    let mut profile = None;
    let mut debug = false;
    while let Some(argument) = arguments.next() {
        if argument == "--release" {
            profile = Some("release".to_owned());
        } else if argument == "--debug" {
            debug = true;
        } else if argument == "--profile" {
            profile = arguments.next().cloned();
        } else if let Some(value) = argument.strip_prefix("--profile=") {
            profile = Some(value.to_owned());
        } else if matches!(argument.as_str(), "--config" | "--color" | "-Z") {
            let _ = arguments.next();
        } else if !argument.starts_with('-') && !argument.starts_with('+') && subcommand.is_none() {
            subcommand = Some(argument.as_str());
        }
    }
    profile.unwrap_or_else(|| {
        match subcommand {
            Some("bench") => "bench",
            // `cargo install` builds with `release`. Its `--debug` selects the
            // `debug` profile from Cargo 1.99, which inherits `dev`.
            Some("install") if debug => "debug",
            Some("install") => "release",
            _ => "dev",
        }
        .into()
    })
}

/// Collect repeated Cargo target flags, stopping before program arguments.
pub(crate) fn cargo_targets(arguments: &[String]) -> Vec<String> {
    let mut targets = Vec::new();
    let mut arguments = arguments
        .iter()
        .take_while(|argument| argument.as_str() != "--");
    while let Some(argument) = arguments.next() {
        let value = if argument == "--target" {
            arguments.next().cloned()
        } else {
            argument.strip_prefix("--target=").map(str::to_owned)
        };
        if let Some(value) = value {
            targets.push(value);
        }
    }
    targets
}

/// Match Cargo's target spelling before using it as a rustc routing key.
fn normalize_cargo_target(target: &str, cargo_arguments: &[String]) -> Result<String> {
    // Cargo substitutes this directive before trimming ordinary target names.
    if target == "host-tuple" {
        let mut command = Command::new(std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into()));
        if let Some(toolchain) = cargo_arguments
            .first()
            .filter(|argument| argument.starts_with('+'))
        {
            command.arg(toolchain);
        }
        let output = command
            .arg("-vV")
            .output()
            .wrap_err("failed to query Cargo's host target")?;
        if !output.status.success() {
            bail!("Cargo could not report its host target");
        }
        return String::from_utf8(output.stdout)?
            .lines()
            .find_map(|line| line.strip_prefix("host: ").map(str::to_owned))
            .ok_or_else(|| eyre::eyre!("Cargo did not report its host target"));
    }
    let target = target.trim();
    if target.ends_with(".json") {
        return fs::canonicalize(target)
            .wrap_err_with(|| format!("failed to canonicalize Cargo target `{target}`"))?
            .into_os_string()
            .into_string()
            .map_err(|_| eyre::eyre!("Cargo target path is not valid Unicode"));
    }
    Ok(target.to_owned())
}

fn rustc_command(cargo_arguments: &[String]) -> Command {
    let mut command = Command::new(std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into()));
    if let Some(toolchain) = cargo_arguments
        .first()
        .filter(|argument| argument.starts_with('+'))
    {
        command.arg(toolchain);
    }
    command
}

fn host_target(cargo_arguments: &[String]) -> Option<String> {
    let output = rustc_command(cargo_arguments).arg("-vV").output().ok()?;
    String::from_utf8(output.stdout)
        .ok()?
        .lines()
        .find_map(|line| line.strip_prefix("host: ").map(str::to_owned))
}

fn host_install_name() -> String {
    host_target(&[])
        .unwrap_or_else(|| format!("{}-{}", std::env::consts::ARCH, std::env::consts::OS))
}

fn executable_filename(name: &str) -> String {
    if cfg!(windows) {
        format!("{name}.exe")
    } else {
        name.into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_profiles_without_reading_program_arguments() {
        assert_eq!(cargo_profile(&["build".into()]), "dev");
        assert_eq!(
            cargo_profile(&["build".into(), "--release".into()]),
            "release"
        );
        assert_eq!(cargo_profile(&["bench".into()]), "bench");
        assert_eq!(
            cargo_profile(&["--config".into(), "build.jobs=1".into(), "bench".into(),]),
            "bench"
        );
        assert_eq!(
            cargo_profile(&["build".into(), "--profile=fast".into()]),
            "fast"
        );
        assert_eq!(
            cargo_profile(&["run".into(), "--".into(), "--profile=ignored".into()]),
            "dev"
        );
        assert_eq!(
            cargo_profile(&["install".into(), "ripgrep".into()]),
            "release"
        );
        assert_eq!(
            cargo_profile(&["install".into(), "--debug".into(), "ripgrep".into()]),
            "debug"
        );
        assert_eq!(
            cargo_profile(&["run".into(), "--".into(), "--debug".into()]),
            "dev"
        );
    }

    #[test]
    fn parses_supported_selectors() {
        assert!(matches!(Spec::parse("system").unwrap(), Spec::System));
        assert!(matches!(Spec::parse("lld").unwrap(), Spec::RustLld));
        assert!(matches!(
            Spec::parse("path:/tmp/ld").unwrap(),
            Spec::Path(_)
        ));
        assert!(matches!(
            Spec::parse("mold@2.42.0").unwrap(),
            Spec::Managed { provider: Provider::Mold, version } if version == "2.42.0"
        ));
        assert!(Spec::parse("wild@latest").is_err());
        assert!(Spec::parse("mold@../../escape").is_err());
        assert!(Spec::parse("mold@..").is_err());
        assert!(Spec::parse("unknown@1").is_err());
    }

    #[test]
    fn parses_multiple_targets_without_reading_program_arguments() {
        assert!(cargo_targets(&["build".into()]).is_empty());
        assert_eq!(
            cargo_targets(&[
                "build".into(),
                "--target".into(),
                "aarch64-apple-darwin".into(),
                "--target=x86_64-apple-darwin".into(),
                "--".into(),
                "--target=ignored".into(),
            ]),
            ["aarch64-apple-darwin", "x86_64-apple-darwin"]
        );
    }

    #[test]
    fn system_linker_accepts_universal_macos_build() {
        let cache = tempfile::tempdir().unwrap();
        let arguments = [
            "build",
            "--release",
            "--bin",
            "usage",
            "--manifest-path",
            "cli/Cargo.toml",
            "--target",
            "aarch64-apple-darwin",
            "--target",
            "x86_64-apple-darwin",
        ]
        .map(str::to_owned);
        assert!(
            resolve(
                &LinkerSettings::default(),
                cache.path(),
                &HttpSettings::default(),
                &arguments
            )
            .unwrap()
            .is_none()
        );
    }

    #[test]
    fn resolves_each_targets_profile_policy() {
        let cache = tempfile::tempdir().unwrap();
        let executable = std::env::current_exe().unwrap();
        let settings = LinkerSettings {
            profiles: BTreeMap::from([(
                "release".into(),
                BTreeMap::from([
                    (
                        "aarch64-apple-darwin".into(),
                        format!("path:{}", executable.display()),
                    ),
                    ("x86_64-apple-darwin".into(), "system".into()),
                ]),
            )]),
            ..Default::default()
        };
        let arguments = [
            "build",
            "--release",
            "--target=aarch64-apple-darwin",
            "--target=x86_64-apple-darwin",
        ]
        .map(str::to_owned);
        let Some(Selection::Targets(selections)) = resolve(
            &settings,
            cache.path(),
            &HttpSettings::default(),
            &arguments,
        )
        .unwrap() else {
            panic!("expected target-specific selection");
        };
        assert_eq!(
            selections,
            BTreeMap::from([("aarch64-apple-darwin".into(), executable)])
        );
    }

    #[test]
    fn normalizes_cargo_host_directive_and_target_paths() {
        assert_eq!(
            normalize_cargo_target("host-tuple", &[]).unwrap(),
            host_target(&[]).unwrap()
        );
        assert_eq!(
            normalize_cargo_target(" aarch64-apple-darwin ", &[]).unwrap(),
            "aarch64-apple-darwin"
        );
        let directory = tempfile::tempdir_in(std::env::current_dir().unwrap()).unwrap();
        let target = directory.path().join("custom.json");
        fs::write(&target, "{}").unwrap();
        let relative = target
            .strip_prefix(std::env::current_dir().unwrap())
            .unwrap();
        assert_eq!(
            normalize_cargo_target(relative.to_str().unwrap(), &[]).unwrap(),
            fs::canonicalize(&target).unwrap().to_str().unwrap()
        );
    }

    #[test]
    fn host_directive_uses_concrete_target_profile_policy() {
        let cache = tempfile::tempdir().unwrap();
        let host = normalize_cargo_target("host-tuple", &[]).unwrap();
        let executable = std::env::current_exe().unwrap();
        let settings = LinkerSettings {
            profiles: BTreeMap::from([(
                "dev".into(),
                BTreeMap::from([(host.clone(), format!("path:{}", executable.display()))]),
            )]),
            ..Default::default()
        };
        let Some(Selection::Targets(selections)) = resolve(
            &settings,
            cache.path(),
            &HttpSettings::default(),
            &["build".into(), "--target=host-tuple".into()],
        )
        .unwrap() else {
            panic!("expected target-specific selection");
        };
        assert_eq!(selections, BTreeMap::from([(host, executable)]));
    }

    #[test]
    fn relative_json_target_keeps_its_profile_policy() {
        let directory = tempfile::tempdir_in(std::env::current_dir().unwrap()).unwrap();
        let target = directory.path().join("custom.json");
        fs::write(&target, "{}").unwrap();
        let relative = target
            .strip_prefix(std::env::current_dir().unwrap())
            .unwrap()
            .to_str()
            .unwrap()
            .to_owned();
        let executable = std::env::current_exe().unwrap();
        let settings = LinkerSettings {
            profiles: BTreeMap::from([(
                "dev".into(),
                BTreeMap::from([(relative.clone(), format!("path:{}", executable.display()))]),
            )]),
            ..Default::default()
        };
        let Some(Selection::Targets(selections)) = resolve(
            &settings,
            directory.path(),
            &HttpSettings::default(),
            &["build".into(), "--target".into(), relative],
        )
        .unwrap() else {
            panic!("expected target-specific selection");
        };
        assert_eq!(
            selections,
            BTreeMap::from([(
                fs::canonicalize(target)
                    .unwrap()
                    .to_str()
                    .unwrap()
                    .to_owned(),
                executable
            )])
        );
    }

    #[cfg(unix)]
    #[test]
    fn rust_lld_repairs_a_dangling_cached_shim() {
        let cache = tempfile::tempdir().unwrap();
        let shim = rust_lld(None, cache.path(), &[]).unwrap();
        fs::remove_file(&shim).unwrap();
        std::os::unix::fs::symlink("/missing/rust-lld", &shim).unwrap();

        assert_eq!(rust_lld(None, cache.path(), &[]).unwrap(), shim);
        assert!(fs::read_link(shim).unwrap().is_file());
    }
}
