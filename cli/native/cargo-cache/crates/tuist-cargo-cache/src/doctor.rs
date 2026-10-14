//! Installation and connectivity diagnostics.

use crate::config::Config;
use crate::policy;
use eyre::{Context, Result};
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase")]
enum Severity {
    Pass,
    Warn,
    Fail,
}

#[derive(Debug, PartialEq, Eq, serde::Serialize)]
struct Check {
    severity: Severity,
    name: &'static str,
    detail: String,
}

impl Check {
    fn pass(name: &'static str, detail: impl Into<String>) -> Self {
        Self {
            severity: Severity::Pass,
            name,
            detail: detail.into(),
        }
    }

    fn warn(name: &'static str, detail: impl Into<String>) -> Self {
        Self {
            severity: Severity::Warn,
            name,
            detail: detail.into(),
        }
    }

    fn fail(name: &'static str, detail: impl Into<String>) -> Self {
        Self {
            severity: Severity::Fail,
            name,
            detail: detail.into(),
        }
    }

    /// Answer a failed clone probe with what a restore will fall back to.
    ///
    /// A hard link works wherever the store and the target directory share a
    /// filesystem, which covers most machines that cannot clone at all --
    /// notably every ext4 one. It is a narrower arrangement than a clone, so
    /// the report says which of the two this location gets, and says plainly
    /// when it gets neither.
    fn and_then_link(self, cache_dir: &Path, target_dir: &Path, hardlink: bool) -> Self {
        if self.severity == Severity::Pass {
            return self;
        }
        let layout = format!("{} -> {}", cache_dir.display(), target_dir.display());
        if !hardlink {
            return Check::warn(
                "restore",
                format!(
                    "{layout}: cannot clone and restore_hardlink is off; every restored byte is copied"
                ),
            );
        }
        if hardlink_probe(cache_dir, target_dir).severity == Severity::Pass {
            return Check::pass(
                "restore",
                format!("{layout}: cannot clone; restores hard link the cached object instead"),
            );
        }
        Check::warn(
            "restore",
            format!("{layout}: cannot clone or link; every restored byte is copied"),
        )
    }
}

/// Run all diagnostics and fail only when tuist_cargo_cache cannot operate as configured.
pub fn run(config: &Config) -> Result<ExitCode> {
    run_formatted(config, false, None)
}

pub(crate) fn run_formatted(
    config: &Config,
    json: bool,
    toolchain: Option<&str>,
) -> Result<ExitCode> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let checks = runtime.block_on(check(config, toolchain));
    render(&checks, json)
}

fn render(checks: &[Check], json: bool) -> Result<ExitCode> {
    let failures = checks
        .iter()
        .filter(|check| check.severity == Severity::Fail)
        .count();
    let warnings = checks
        .iter()
        .filter(|check| check.severity == Severity::Warn)
        .count();
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&DoctorReport {
                version: 1,
                checks,
                failures,
                warnings,
            })?
        );
    } else {
        for check in checks {
            let marker = match check.severity {
                Severity::Pass => "ok",
                Severity::Warn => "warn",
                Severity::Fail => "FAIL",
            };
            println!("{marker:>4}  {:<12} {}", check.name, check.detail);
        }
        println!("\n{failures} failures, {warnings} warnings");
    }
    Ok(if failures == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

pub(crate) fn run_loaded(
    config: Result<Config>,
    json: bool,
    toolchain: Option<&str>,
) -> Result<ExitCode> {
    match config {
        Ok(config) => run_formatted(&config, json, toolchain),
        Err(error) => render(&[Check::fail("config", format!("{error:#}"))], json),
    }
}

#[derive(serde::Serialize)]
struct DoctorReport<'a> {
    version: u8,
    checks: &'a [Check],
    failures: usize,
    warnings: usize,
}

async fn check(config: &Config, toolchain: Option<&str>) -> Vec<Check> {
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| OsString::from("cargo"));
    let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| OsString::from("rustc"));
    let mut checks = vec![
        command_check("cargo", &cargo, toolchain),
        command_check("rustc", &rustc, toolchain),
    ];
    checks.push(cache_check(&config.cache_dir));
    #[cfg(unix)]
    checks.push(session_check());
    checks.push(Check::pass(
        "config",
        format!(
            "{} budget, automatic gc {}, managed targets {} at {}; `tuist_cargo_cache settings ls` shows every setting",
            bytesize::ByteSize::b(config.gc.max_bytes).display().iec(),
            enabled(config.gc.auto),
            enabled(config.target.views),
            config.target.root.display(),
        ),
    ));
    for destination in restore_destinations(config, &cargo, toolchain) {
        checks.push(restore_check(
            &config.cache_dir,
            &destination,
            config.restore_hardlink,
        ));
    }
    checks.push(archive_check(config));
    checks.push(setup_check());
    checks.extend(remote_checks(config).await);
    checks
}

/// Probe the transport every orchestrated build needs in this environment.
///
/// This uses a fresh temporary directory just like a real session. Sandboxes
/// can permit both creating the directory and opening an AF_UNIX socket while
/// still rejecting `bind`, so no filesystem-only check can answer this.
#[cfg(unix)]
fn session_check() -> Check {
    let directory = match tempfile::Builder::new()
        .prefix("tuist_cargo_cache-session-probe-")
        .tempdir()
    {
        Ok(directory) => directory,
        Err(error) => {
            return Check::warn(
                "session",
                format!(
                    "listener was not tested because a temporary directory could not be created: {error}"
                ),
            );
        }
    };
    let socket = directory.path().join("cache-agent.sock");
    let socket_probe = std::os::unix::net::UnixListener::bind(&socket).map(drop);
    session_check_from(socket_probe, || {
        crate::session::create_fifo(&directory.path().join("cache-agent.fifo"))
    })
}

/// Turn transport probe results into the diagnostic shown by `tuist_cargo_cache doctor`.
#[cfg(unix)]
fn session_check_from(
    socket_probe: std::io::Result<()>,
    fifo_probe: impl FnOnce() -> std::io::Result<()>,
) -> Check {
    match socket_probe {
        Ok(()) => Check::pass("session", "Unix-domain listeners are available"),
        Err(socket_error) => match fifo_probe() {
            Ok(()) => Check::warn(
                "session",
                format!(
                    "Unix-domain listener unavailable ({socket_error}); builds will use FIFO transport"
                ),
            ),
            Err(fifo_error) => Check::warn(
                "session",
                format!(
                    "Unix-domain listener unavailable ({socket_error}) and FIFO unavailable ({fifo_error}); builds will run without tuist_cargo_cache caching"
                ),
            ),
        },
    }
}

fn enabled(value: bool) -> &'static str {
    if value { "enabled" } else { "disabled" }
}

/// The arguments that ask a command for its version, under a toolchain when one
/// was named.
///
/// `tuist_cargo_cache +1.91 doctor` is a question about 1.91, so the answer has to come from
/// 1.91's compiler rather than from whichever one the shim resolves by default.
/// A `CARGO` or `RUSTC` that is not a rustup shim rejects the `+`, and the
/// check reports that failure rather than quietly describing another toolchain.
fn version_arguments(toolchain: Option<&str>) -> Vec<String> {
    match toolchain {
        Some(toolchain) => vec![format!("+{toolchain}"), "--version".into()],
        None => vec!["--version".into()],
    }
}

fn command_check(name: &'static str, command: &OsStr, toolchain: Option<&str>) -> Check {
    let arguments = version_arguments(toolchain);
    match Command::new(command).args(&arguments).output() {
        Ok(output) if output.status.success() => Check::pass(
            name,
            String::from_utf8_lossy(&output.stdout).trim().to_string(),
        ),
        Ok(output) => Check::fail(
            name,
            failure_detail(&arguments, output.status, &output.stderr),
        ),
        Err(error) => Check::fail(
            name,
            format!("could not execute {}: {error}", command.to_string_lossy()),
        ),
    }
}

/// Why a version query failed, in one line.
///
/// The arguments are named because a named toolchain is among them, and the
/// reason a toolchain query fails — most often that the toolchain is not
/// installed — is on stderr. Reporting the exit status alone leaves the reader
/// with a diagnostic that diagnoses nothing.
///
/// The status is taken as anything printable rather than as an `ExitStatus`,
/// which has no portable constructor: a test would otherwise have to spawn a
/// process that fails on every platform this runs on to reach one line of
/// formatting.
fn failure_detail(arguments: &[String], status: impl std::fmt::Display, stderr: &[u8]) -> String {
    let stderr = String::from_utf8_lossy(stderr);
    let reason = stderr
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or_default();
    let arguments = arguments.join(" ");
    if reason.is_empty() {
        format!("{arguments} exited with {status}")
    } else {
        format!("{arguments} exited with {status}: {reason}")
    }
}

fn cache_check(cache_dir: &Path) -> Check {
    if let Err(error) = std::fs::create_dir_all(cache_dir) {
        return Check::fail("cache", format!("{}: {error}", cache_dir.display()));
    }
    match tempfile::NamedTempFile::new_in(cache_dir) {
        Ok(_) => Check::pass("cache", format!("{} is writable", cache_dir.display())),
        Err(error) => Check::fail(
            "cache",
            format!("{} is not writable: {error}", cache_dir.display()),
        ),
    }
}

/// Probe both the managed root and Cargo's resolved output location. An existing
/// target or an explicit Cargo target setting can keep a build outside the
/// managed root, even when managed views are enabled.
fn restore_destinations(config: &Config, cargo: &OsStr, toolchain: Option<&str>) -> Vec<PathBuf> {
    let mut destinations = Vec::new();
    if config.target.views {
        destinations.push(config.target.root.clone());
    }
    let mut command = Command::new(cargo);
    if let Some(toolchain) = toolchain {
        command.arg(format!("+{toolchain}"));
    }
    let target = command
        .args([
            "metadata",
            "--no-deps",
            "--format-version",
            "1",
            "--offline",
            "--locked",
        ])
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| serde_json::from_slice::<serde_json::Value>(&output.stdout).ok())
        .and_then(|value| value.get("target_directory")?.as_str().map(PathBuf::from))
        .or_else(|| std::env::var_os("CARGO_TARGET_DIR").map(PathBuf::from));
    if let Some(target) = target {
        destinations.push(target);
    } else if !config.target.views
        && let Ok(cwd) = std::env::current_dir()
    {
        destinations.push(cwd.join("target"));
    }
    destinations.sort();
    destinations.dedup();
    destinations
}

/// Say how a restore to this location will actually put bytes there.
///
/// The mechanism decides what a cache hit costs. A clone or a link writes
/// nothing; a copy writes every restored byte, which on a warm build of a
/// mid-size workspace is gigabytes. Which one applies is a property of the
/// filesystem under the target directory and of whether it is the same
/// filesystem the store is on, so it is worth probing rather than assuming --
/// and worth reporting, because a run that quietly copies looks exactly like
/// one that does not.
fn restore_check(cache_dir: &Path, target_dir: &Path, hardlink: bool) -> Check {
    reflink_check_with(cache_dir, target_dir, |source, destination| {
        reflink_copy::reflink(source, destination)
    })
    .and_then_link(cache_dir, target_dir, hardlink)
}

fn hardlink_probe(cache_dir: &Path, target_dir: &Path) -> Check {
    reflink_check_with(cache_dir, target_dir, |source, destination| {
        std::fs::hard_link(source, destination)
    })
}

fn reflink_check_with(
    cache_dir: &Path,
    target_dir: &Path,
    clone: impl FnOnce(&Path, &Path) -> std::io::Result<()>,
) -> Check {
    let layout = format!("{} -> {}", cache_dir.display(), target_dir.display());
    let probe = || -> std::io::Result<()> {
        let source_dir = tempfile::Builder::new()
            .prefix("tuist_cargo_cache-reflink-")
            .tempdir_in(cache_dir)?;
        // Avoid creating target directories just to inspect them. The closest
        // existing ancestor uses the destination filesystem; an existing target
        // symlink is followed by tempdir_in, just as a real restore follows it.
        let absolute_target = std::path::absolute(target_dir)?;
        let parent = absolute_target
            .ancestors()
            .find(|path| path.exists())
            .ok_or_else(|| {
                std::io::Error::new(std::io::ErrorKind::NotFound, "no target ancestor exists")
            })?;
        let destination_dir = tempfile::Builder::new()
            .prefix("tuist_cargo_cache-reflink-")
            .tempdir_in(parent)?;
        let source = source_dir.path().join("source");
        let destination = destination_dir.path().join("destination");
        std::fs::write(&source, b"tuist_cargo_cache reflink probe")?;
        clone(&source, &destination)
    };
    match probe() {
        Ok(()) => Check::pass("restore", format!("{layout}: cloning is supported")),
        Err(error) => {
            let reason = match error.kind() {
                std::io::ErrorKind::CrossesDevices => "different filesystems",
                std::io::ErrorKind::PermissionDenied => "permission denied",
                std::io::ErrorKind::Unsupported => "cloning unsupported",
                _ => "clone probe failed",
            };
            Check::warn(
                "restore",
                format!(
                    "{layout}: {reason} ({error}); restores to this location may require copying"
                ),
            )
        }
    }
}

/// Report whether native archives will carry a timestamp that moves their
/// digest between otherwise identical builds.
///
/// A stamping toolchain is not itself a problem; it becomes one when tuist_cargo_cache is not
/// normalizing it, because then every rebuild of a CMake-style native
/// dependency republishes the same archive under a new digest and misses every
/// cached action downstream of it. So the probe's answer is only worth a
/// warning when the configured policy leaves this build unnormalized.
fn archive_check(config: &Config) -> Check {
    let mode = crate::ar::ArDeterminism::parse(&config.ar_determinism);
    match crate::ar::probe() {
        crate::ar::Probe::Deterministic => Check::pass(
            "archives",
            "the archive tools already produce identical bytes for identical input",
        ),
        // Warned rather than passed: the probe did not assess anything, and a
        // green line would read as "archives are fine" when what happened is
        // that nobody looked. The other probes here report the same way.
        crate::ar::Probe::Unavailable(reason) => Check::warn(
            "archives",
            format!("archive determinism could not be probed ({reason})"),
        ),
        crate::ar::Probe::Stamps => {
            // The probe says what the tools do; the policy says what tuist_cargo_cache will
            // do about it. `release` under `auto` is a deliberate choice rather
            // than an oversight, so it is reported without alarm.
            let normalized_here = crate::ar::normalizes(mode, Some("debug"), false);
            let normalized_release = crate::ar::normalizes(mode, Some("release"), false);
            if normalized_here {
                let release = if normalized_release {
                    "release included"
                } else {
                    "release left as the toolchain makes it"
                };
                Check::pass(
                    "archives",
                    format!(
                        "the archive tools stamp a timestamp; tuist_cargo_cache sets ZERO_AR_DATE for build \
                         scripts ({release})"
                    ),
                )
            } else {
                Check::warn(
                    "archives",
                    format!(
                        "the archive tools stamp a timestamp and ar_determinism is \"{}\"; \
                         native archives may change digest between identical builds and miss \
                         cached actions downstream",
                        mode.as_str()
                    ),
                )
            }
        }
    }
}

/// Report the persistent Cargo shim installed by `tuist_cargo_cache setup`.
fn setup_check() -> Check {
    let Some(expected_shim) = setup_path() else {
        return Check::warn(
            "setup",
            "the platform data directory could not be determined",
        );
    };
    let Ok(executable) = std::env::current_exe() else {
        return Check::warn(
            "setup",
            "could not locate the running tuist_cargo_cache executable",
        );
    };
    setup_check_at(
        &executable,
        &expected_shim,
        crate::cli::cargo_activation_path().as_deref(),
        mise_cargo_wrapper_is_configured(),
    )
}

fn setup_check_at(
    executable: &Path,
    expected_shim: &Path,
    path: Option<&OsStr>,
    mise_wrapper_configured: bool,
) -> Check {
    if !expected_shim.is_file() {
        return Check::warn(
            "setup",
            "Cargo shim is not installed; plain Cargo bypasses tuist_cargo_cache, while explicit `tuist_cargo_cache <cargo-command>` still works",
        );
    }
    match crate::cli::cargo_shim_is_current(executable, expected_shim) {
        Ok(false) => {
            return Check::warn(
                "setup",
                "Cargo shim is outdated; run `tuist_cargo_cache setup`",
            );
        }
        Err(error) => {
            return Check::warn("setup", format!("Cargo shim could not be checked: {error}"));
        }
        Ok(true) => {}
    }

    let active_cargo = path.and_then(cargo_on_path);
    if mise_wrapper_configured
        && active_cargo
            .as_deref()
            .is_some_and(crate::cli::is_mise_command_wrapper_path)
    {
        return Check::pass(
            "setup",
            format!(
                "mise Cargo wrapper is active and the fallback shim is current at {}",
                expected_shim.display()
            ),
        );
    }
    if active_cargo
        .as_deref()
        .is_none_or(|cargo| !same_path(cargo, expected_shim))
    {
        let resolved = active_cargo
            .as_deref()
            .map(|cargo| cargo.display().to_string())
            .unwrap_or_else(|| "nothing".into());
        return Check::warn(
            "setup",
            format!(
                "Cargo shim is current but not active; PATH resolves cargo to {resolved}; prepend {} to PATH",
                expected_shim.parent().unwrap_or(expected_shim).display()
            ),
        );
    }

    Check::pass(
        "setup",
        format!(
            "Cargo shim is active and current at {}",
            expected_shim.display()
        ),
    )
}

fn mise_cargo_wrapper_is_configured() -> bool {
    let config_value = |key: &str| {
        Command::new("mise")
            .args(["config", "get", key])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
    };
    config_value("wrappers.cargo.command").as_deref() == Some("tuist_cargo_cache")
        && config_value("wrappers.cargo.env.TUIST_CARGO_CACHE_CARGO_SHIM_MODE").as_deref()
            == Some("1")
}

fn cargo_on_path(path: &OsStr) -> Option<PathBuf> {
    let name = if cfg!(windows) { "cargo.exe" } else { "cargo" };
    std::env::split_paths(path)
        .map(|directory| directory.join(name))
        .find(|candidate| is_executable_file(candidate))
}

fn is_executable_file(path: &Path) -> bool {
    let Ok(metadata) = path.metadata() else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

fn same_path(left: &Path, right: &Path) -> bool {
    match (std::fs::canonicalize(left), std::fs::canonicalize(right)) {
        (Ok(left), Ok(right)) => {
            #[cfg(windows)]
            {
                left.to_string_lossy()
                    .eq_ignore_ascii_case(&right.to_string_lossy())
            }
            #[cfg(not(windows))]
            {
                left == right
            }
        }
        _ => false,
    }
}

fn setup_path() -> Option<PathBuf> {
    Some(crate::cli::setup_install_dir()?.join(if cfg!(windows) { "cargo.exe" } else { "cargo" }))
}

async fn remote_checks(config: &Config) -> Vec<Check> {
    let effective_mode = policy::effective_remote_cache_mode(config.remote.mode);
    remote_checks_with_policy(config, effective_mode).await
}

async fn remote_checks_with_policy(
    config: &Config,
    effective_mode: Option<tuist_cargo_cache_core::RemoteCacheMode>,
) -> Vec<Check> {
    let Some(base_url) = config
        .remote
        .url
        .as_deref()
        .map(str::trim)
        .filter(|url| !url.is_empty())
    else {
        return vec![Check::pass(
            "remote",
            "not configured; using the local cache",
        )];
    };
    let effective = effective_mode.map_or_else(
        || "disabled by cache write policy".to_string(),
        |mode| mode.to_string(),
    );
    let policy = Check::pass(
        "policy",
        format!("configured {}, effective {effective}", config.remote.mode),
    );
    if effective_mode.is_none() {
        return vec![
            policy,
            Check::pass("remote", "probe skipped because remote caching is disabled"),
        ];
    }
    let namespace = config
        .remote
        .namespace
        .as_deref()
        .unwrap_or_default()
        .trim();
    // The build builds its client the same way, so a configuration it would
    // refuse is reported here rather than discovered mid-compilation.
    let (client, credentials) = match crate::remote::connect(config).await {
        Ok(Some(remote)) => (remote.client, remote.credentials),
        Ok(None) => {
            return vec![
                policy,
                Check::pass("remote", "not configured; using the local cache"),
            ];
        }
        Err(error) => return vec![policy, Check::fail("remote", format!("{error:#}"))],
    };
    let remote = match client
        .check_connection()
        .await
        .wrap_err("connection check failed")
    {
        Ok(()) => Check::pass("remote", format!("{base_url} ({namespace}) is compatible")),
        Err(error) => Check::fail("remote", format!("{error:#}")),
    };
    let mut checks = vec![policy];
    checks.extend(credentials.map(|origin| Check::pass("credentials", origin.describe())));
    checks.push(remote);
    checks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writable_cache_passes_and_leaves_no_probe() {
        let directory = tempfile::tempdir().unwrap();
        assert_eq!(cache_check(directory.path()).severity, Severity::Pass);
        assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);
    }

    #[cfg(unix)]
    #[test]
    fn the_build_session_transport_is_probed() {
        let check = session_check();
        assert_eq!(check.name, "session");
        match check.severity {
            Severity::Pass => assert!(check.detail.contains("Unix-domain")),
            Severity::Warn => assert!(
                check.detail.contains("FIFO transport")
                    || check.detail.contains("without tuist_cargo_cache caching")
            ),
            Severity::Fail => panic!("session transport probes are advisory"),
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_blocked_listener_reports_the_fifo_fallback() {
        let check = session_check_from(
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
            || Ok(()),
        );
        assert_eq!(check.severity, Severity::Warn);
        assert!(check.detail.contains("builds will use FIFO transport"));
    }

    #[cfg(unix)]
    #[test]
    fn blocked_socket_and_fifo_report_the_uncached_fallback() {
        let check = session_check_from(
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
            || Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
        );
        assert_eq!(check.severity, Severity::Warn);
        assert!(
            check
                .detail
                .contains("builds will run without tuist_cargo_cache caching")
        );
    }

    #[test]
    fn a_named_toolchain_is_the_one_the_version_checks_ask() {
        assert_eq!(version_arguments(None), ["--version"]);
        assert_eq!(version_arguments(Some("1.91")), ["+1.91", "--version"]);
    }

    #[test]
    fn a_failed_version_query_reports_what_it_asked_and_why_it_failed() {
        let arguments = version_arguments(Some("1.91"));
        let status = "exit status: 1";

        let detail = failure_detail(
            &arguments,
            status,
            b"error: toolchain '1.91' is not installed\nnote: run rustup\n",
        );

        assert_eq!(
            detail,
            "+1.91 --version exited with exit status: 1: error: toolchain '1.91' is not installed"
        );
        // Nothing on stderr leaves the status to end the line, rather than a
        // dangling separator.
        assert_eq!(
            failure_detail(&arguments, status, b"  \n"),
            "+1.91 --version exited with exit status: 1"
        );
    }

    #[test]
    fn setup_requires_a_current_shim_that_wins_path_resolution() {
        let directory = tempfile::tempdir().unwrap();
        let executable = directory.path().join("tuist_cargo_cache");
        let shim_dir = directory.path().join("shim");
        let shim = shim_dir.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
        let real_dir = directory.path().join("real");
        let real_cargo = real_dir.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
        std::fs::create_dir_all(&shim_dir).unwrap();
        std::fs::create_dir_all(&real_dir).unwrap();
        std::fs::write(&executable, b"current tuist_cargo_cache").unwrap();
        make_executable(&executable);
        std::fs::write(&real_cargo, b"real cargo").unwrap();
        make_executable(&real_cargo);

        let real_first = std::env::join_paths([&real_dir, &shim_dir]).unwrap();
        assert_eq!(
            setup_check_at(&executable, &shim, Some(&real_first), false).detail,
            "Cargo shim is not installed; plain Cargo bypasses tuist_cargo_cache, while explicit `tuist_cargo_cache <cargo-command>` still works"
        );

        std::fs::write(&shim, b"old tuist_cargo_cache").unwrap();
        assert_eq!(
            setup_check_at(&executable, &shim, Some(&real_first), false).detail,
            "Cargo shim is outdated; run `tuist_cargo_cache setup`"
        );

        assert_eq!(
            crate::cli::doctor_setup_at_action(
                &executable,
                &shim_dir,
                &crate::cli::DoctorMiseScope::None,
                crate::cli::DoctorSetupAction::Install,
            )
            .unwrap(),
            ExitCode::SUCCESS
        );
        let inactive = setup_check_at(&executable, &shim, Some(&real_first), false);
        assert_eq!(inactive.severity, Severity::Warn);
        assert!(inactive.detail.contains("current but not active"));
        assert!(inactive.detail.contains(&real_cargo.display().to_string()));

        let shim_first = std::env::join_paths([&shim_dir, &real_dir]).unwrap();
        let active = setup_check_at(&executable, &shim, Some(&shim_first), false);
        assert_eq!(active.severity, Severity::Pass);
        assert!(active.detail.contains("active and current"));

        let wrapper_dir = directory.path().join("command-wrappers/bin");
        let wrapper = wrapper_dir.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
        std::fs::create_dir_all(&wrapper_dir).unwrap();
        std::fs::write(&wrapper, b"mise wrapper").unwrap();
        make_executable(&wrapper);
        let wrapper_first = std::env::join_paths([&wrapper_dir, &real_dir]).unwrap();
        let active = setup_check_at(&executable, &shim, Some(&wrapper_first), true);
        assert_eq!(active.severity, Severity::Pass);
        assert!(active.detail.contains("mise Cargo wrapper is active"));
    }

    #[cfg(unix)]
    #[test]
    fn setup_warns_when_the_shim_target_was_removed() {
        let directory = tempfile::tempdir().unwrap();
        let removed = directory.path().join("removed/tuist_cargo_cache");
        let executable = directory.path().join("tuist_cargo_cache");
        let shim_dir = directory.path().join("shim");
        let shim = shim_dir.join("cargo");
        std::fs::create_dir_all(removed.parent().unwrap()).unwrap();
        std::fs::write(&removed, b"old tuist_cargo_cache").unwrap();
        make_executable(&removed);
        std::fs::write(&executable, b"current tuist_cargo_cache").unwrap();
        make_executable(&executable);
        assert_eq!(
            crate::cli::doctor_setup_at_action(
                &removed,
                &shim_dir,
                &crate::cli::DoctorMiseScope::None,
                crate::cli::DoctorSetupAction::Install,
            )
            .unwrap(),
            ExitCode::SUCCESS
        );
        std::fs::remove_dir_all(removed.parent().unwrap()).unwrap();

        let check = setup_check_at(&executable, &shim, Some(shim_dir.as_os_str()), false);
        assert_eq!(check.severity, Severity::Warn);
        assert_eq!(
            check.detail,
            "Cargo shim is outdated; run `tuist_cargo_cache setup`"
        );
    }

    #[cfg(unix)]
    #[test]
    fn setup_warns_when_the_shim_is_not_executable() {
        let directory = tempfile::tempdir().unwrap();
        let executable = directory.path().join("tuist_cargo_cache");
        let shim_dir = directory.path().join("shim");
        let shim = shim_dir.join("cargo");
        std::fs::create_dir_all(&shim_dir).unwrap();
        std::fs::write(&executable, b"current tuist_cargo_cache").unwrap();
        make_executable(&executable);
        std::fs::write(&shim, crate::cli::DOCTOR_CARGO_SHIM_LAUNCHER).unwrap();
        std::fs::write(
            shim_dir.join("tuist_cargo_cache-target"),
            format!("{}\n", executable.display()),
        )
        .unwrap();

        let check = setup_check_at(&executable, &shim, Some(shim_dir.as_os_str()), false);
        assert_eq!(check.severity, Severity::Warn);
        assert!(check.detail.contains("current but not active"));
        assert!(check.detail.contains("PATH resolves cargo to nothing"));
    }

    #[cfg(unix)]
    fn make_executable(path: &Path) {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = path.metadata().unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(path, permissions).unwrap();
    }

    #[cfg(not(unix))]
    fn make_executable(_path: &Path) {}

    #[test]
    fn missing_remote_namespace_fails() {
        let directory = tempfile::tempdir().unwrap();
        let mut config = Config {
            cache_dir: directory.path().to_path_buf(),
            shims_dir: directory.path().join("shims"),
            stats_report: None,
            ar_determinism: "auto".into(),
            verify: false,
            verify_sample_rate: 0,
            incremental: false,
            eager_incremental: false,
            share_out_dir: false,
            restore_hardlink: true,
            share_workspace_root: false,
            build_script_execution: false,
            events: false,
            cc: false,
            cc_store_path_specific: true,
            forward_compiler_notifications: true,
            remote: Default::default(),
            http: Default::default(),
            gc: Default::default(),
            scheduler: Default::default(),
            linker: Default::default(),
            target: crate::config::TargetSettings {
                views: true,
                lanes: true,
                seed: false,
                root: directory.path().join("targets"),
            },
        };
        config.remote.url = Some("https://cache.example".into());
        config.remote.mode = tuist_cargo_cache_core::RemoteCacheMode::ReadWrite;
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let checks = runtime.block_on(remote_checks_with_policy(
            &config,
            Some(tuist_cargo_cache_core::RemoteCacheMode::ReadOnly),
        ));
        let failure = checks
            .iter()
            .find(|check| check.severity == Severity::Fail)
            .expect("the missing namespace should fail");
        assert!(failure.detail.contains("namespace"));
    }

    #[test]
    fn disabled_remote_does_not_require_a_namespace_or_client() {
        let directory = tempfile::tempdir().unwrap();
        let mut config = Config {
            cache_dir: directory.path().to_path_buf(),
            shims_dir: directory.path().join("shims"),
            stats_report: None,
            ar_determinism: "auto".into(),
            verify: false,
            verify_sample_rate: 0,
            incremental: false,
            eager_incremental: false,
            share_out_dir: false,
            restore_hardlink: true,
            share_workspace_root: false,
            build_script_execution: false,
            events: false,
            cc: false,
            cc_store_path_specific: true,
            forward_compiler_notifications: true,
            remote: Default::default(),
            http: Default::default(),
            gc: Default::default(),
            scheduler: Default::default(),
            linker: Default::default(),
            target: crate::config::TargetSettings {
                views: true,
                lanes: true,
                seed: false,
                root: directory.path().join("targets"),
            },
        };
        config.remote.url = Some("not a URL".into());
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let checks = runtime.block_on(remote_checks_with_policy(&config, None));

        assert!(checks.iter().all(|check| check.severity == Severity::Pass));
        assert!(checks.iter().any(|check| {
            check.name == "policy" && check.detail.contains("disabled by cache write policy")
        }));
        assert!(
            checks
                .iter()
                .any(|check| { check.name == "remote" && check.detail.contains("probe skipped") })
        );
    }
}

#[cfg(test)]
mod layout_tests {
    use super::*;

    #[test]
    fn probe_crosses_from_cache_into_target_and_cleans_up() {
        let cache = tempfile::tempdir().unwrap();
        let target = tempfile::tempdir().unwrap();
        let missing = target.path().join("not-created/deps");
        let result = reflink_check_with(cache.path(), &missing, |source, destination| {
            assert!(source.starts_with(cache.path()));
            assert!(destination.starts_with(target.path()));
            assert_eq!(
                std::fs::read(source).unwrap(),
                b"tuist_cargo_cache reflink probe"
            );
            std::fs::copy(source, destination).map(|_| ())
        });
        assert_eq!(result.severity, Severity::Pass);
        assert!(result.detail.contains(&missing.display().to_string()));
        assert_eq!(std::fs::read_dir(cache.path()).unwrap().count(), 0);
        assert_eq!(std::fs::read_dir(target.path()).unwrap().count(), 0);
    }

    #[test]
    fn cross_device_and_permission_failures_name_both_locations() {
        let cache = tempfile::tempdir().unwrap();
        let target = tempfile::tempdir().unwrap();
        for (kind, reason) in [
            (std::io::ErrorKind::CrossesDevices, "different filesystems"),
            (std::io::ErrorKind::PermissionDenied, "permission denied"),
            (std::io::ErrorKind::Unsupported, "cloning unsupported"),
        ] {
            let result = reflink_check_with(cache.path(), target.path(), |_, _| Err(kind.into()));
            assert_eq!(result.severity, Severity::Warn);
            assert!(result.detail.contains(reason));
            assert!(result.detail.contains(&cache.path().display().to_string()));
            assert!(result.detail.contains(&target.path().display().to_string()));
        }
        assert_eq!(std::fs::read_dir(target.path()).unwrap().count(), 0);
    }

    #[cfg(unix)]
    #[test]
    fn existing_target_symlink_is_probed_on_its_destination() {
        let cache = tempfile::tempdir().unwrap();
        let workspace = tempfile::tempdir().unwrap();
        let target = tempfile::tempdir().unwrap();
        let link = workspace.path().join("target");
        std::os::unix::fs::symlink(target.path(), &link).unwrap();
        let result = reflink_check_with(cache.path(), &link, |_, destination| {
            assert!(
                destination
                    .parent()
                    .unwrap()
                    .canonicalize()
                    .unwrap()
                    .starts_with(target.path().canonicalize().unwrap())
            );
            Ok(())
        });
        assert_eq!(result.severity, Severity::Pass);
        assert_eq!(std::fs::read_dir(target.path()).unwrap().count(), 0);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn real_cross_device_probe_warns() {
        use std::os::unix::fs::MetadataExt;
        let cache = tempfile::tempdir().unwrap();
        let Ok(target) = tempfile::tempdir_in("/dev/shm") else {
            return;
        };
        if cache.path().metadata().unwrap().dev() == target.path().metadata().unwrap().dev() {
            return;
        }
        let result = restore_check(cache.path(), target.path(), true);
        assert_eq!(result.severity, Severity::Warn);
        assert!(result.detail.contains("copied"), "{}", result.detail);
    }
}
