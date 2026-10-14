//! Cargo owns executable selection; tuist_cargo_cache owns the lifetime of its build context.
use eyre::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const SHIM: &str = "tuist_cargo_cache-launch";
const CAPTURE: &str = "TUIST_CARGO_CACHE_LAUNCH_CAPTURE";
const RESTORE: &str = "TUIST_CARGO_CACHE_SESSION_RESTORE";
const LEASE: &str = "TUIST_CARGO_CACHE_SESSION_LEASE";
const BUILD_PATH: &str = "TUIST_CARGO_CACHE_SESSION_PATH";

type Environment = BTreeMap<OsString, OsString>;

fn current_environment() -> Environment {
    let variables = std::env::vars_os();
    // Windows names are case-insensitive: an inherited `Path` must match the
    // `PATH` override instead of being mistaken for absent.
    #[cfg(windows)]
    let variables = variables.map(|(name, value)| (name.to_ascii_uppercase(), value));
    variables.collect()
}

/// Snapshot before CLI dispatch changes PATH or CARGO.
static CALLER: std::sync::OnceLock<Environment> = std::sync::OnceLock::new();

/// Remember the environment to restore when a build later launches an application.
pub fn remember_caller() {
    CALLER.get_or_init(|| {
        let mut environment = restored_environment().unwrap_or_else(|_| current_environment());
        environment.remove(OsStr::new("TUIST_CARGO_CACHE_CARGO_SHIM_MODE"));
        environment.remove(OsStr::new("TUIST_CARGO_CACHE_CARGO_SHIM_PATH"));
        environment
    });
}

pub(super) fn plain_launch(cargo: &OsStr, arguments: &[String]) -> Result<ExitCode> {
    let mut command = Command::new(cargo);
    command.args(arguments);
    if let Some(caller) = CALLER.get() {
        command.env_clear().envs(caller);
    }
    Ok(super::cargo::exit_code(command.status()?))
}

/// Re-enter from the original environment when an application launch starts a
/// new build, or when a previous session has ended. Compiler shims never call
/// this: their diagnostic streams still belong to the compiler.
pub fn recover_cli() -> Result<Option<ExitCode>> {
    if std::env::var_os(RESTORE).is_none() {
        return Ok(None);
    }
    let arguments: Vec<_> = std::env::args_os().skip(1).collect();
    let launching = matches!(cargo_subcommand(&arguments), Some("run" | "r"));
    let live = std::env::var_os(LEASE)
        .and_then(|path| std::fs::File::open(path).ok())
        .is_some_and(|file| matches!(file.try_lock(), Err(std::fs::TryLockError::WouldBlock)));
    if live && !launching {
        return Ok(None);
    }
    let mut command = Command::new(std::env::current_exe()?);
    command
        .args(std::env::args_os().skip(1))
        .env_clear()
        .envs(restored_environment()?);
    if super::is_cargo_shim() {
        command.env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1");
    }
    let status = command.status()?;
    Ok(Some(super::cargo::exit_code(status)))
}

/// Config overrides cannot be resolved by cargo-config2. Let Cargo handle
/// these launches with the caller's environment until it offers a stable
/// resolved-config API. In particular, never replace an unknown runner.
pub(super) fn needs_plain_launch(arguments: &[String]) -> bool {
    let args: Vec<_> = arguments
        .iter()
        .take_while(|arg| arg.as_str() != "--")
        .collect();
    matches!(cargo_subcommand(arguments), Some("run" | "r"))
        && args.iter().any(|arg| {
            arg.starts_with('+')
                || arg.as_str() == "--config"
                || arg.starts_with("--config=")
                || arg.as_str() == "-C"
        })
}

/// Locate the command without interpreting option values or program arguments
/// as subcommands. Cargo globals may precede a command through the Cargo shim.
pub(super) fn cargo_subcommand<T: AsRef<OsStr>>(arguments: &[T]) -> Option<&str> {
    cargo_subcommand_at(arguments).map(|(_, command)| command)
}

/// The subcommand and where it sits, so a caller can put an alias expansion in
/// its place and keep the rest of the command line.
pub(super) fn cargo_subcommand_at<T: AsRef<OsStr>>(arguments: &[T]) -> Option<(usize, &str)> {
    let mut arguments = arguments.iter().enumerate();
    while let Some((index, argument)) = arguments.next() {
        let argument = argument.as_ref().to_str()?;
        match argument {
            "--" => return None,
            "--color" | "--config" | "-Z" | "-C" | "--directory" => {
                arguments.next()?;
            }
            value if !value.starts_with('-') && !value.starts_with('+') => {
                return Some((index, value));
            }
            _ => {}
        }
    }
    None
}

/// Cargo's configuration, read the way Cargo reads it.
///
/// Cargo takes an empty `build.rustc-wrapper` to mean no wrapper: a workspace
/// writes `rustc-wrapper = ""` to cancel one it inherits from a parent
/// directory or the global configuration. cargo-config2 would run the empty
/// string as the wrapper program, so evaluating a `[target.'cfg(...)']`
/// section, which asks rustc for the target's cfg, failed to execute `""`.
pub(super) fn load_cargo_config() -> Result<cargo_config2::Config> {
    Ok(without_empty_wrappers(cargo_config2::Config::load()?))
}

pub(super) fn without_empty_wrappers(mut config: cargo_config2::Config) -> cargo_config2::Config {
    for wrapper in [
        &mut config.build.rustc_wrapper,
        &mut config.build.rustc_workspace_wrapper,
    ] {
        if wrapper
            .as_ref()
            .is_some_and(|path| path.as_os_str().is_empty())
        {
            *wrapper = None;
        }
    }
    config
}

/// The targets a Cargo command builds for: its `--target` flags, or else the
/// configured or host target.
pub(super) fn requested_targets(
    config: &cargo_config2::Config,
    arguments: &[String],
) -> Result<Vec<cargo_config2::TargetTriple>> {
    let mut targets = Vec::new();
    let mut args = arguments.iter().take_while(|arg| arg.as_str() != "--");
    while let Some(arg) = args.next() {
        if arg == "--target" {
            if let Some(target) = args.next() {
                targets.push(target.clone());
            }
        } else if let Some(target) = arg.strip_prefix("--target=") {
            targets.push(target.to_owned());
        }
    }
    Ok(config.build_target_for_config(&targets)?)
}

/// The environment variable that overrides Cargo's runner for one target.
pub(super) fn runner_key(target: &cargo_config2::TargetTriple) -> String {
    format!(
        "CARGO_TARGET_{}_RUNNER",
        target.triple().replace(['-', '.'], "_").to_uppercase()
    )
}

pub(super) fn lease(
    directory: &Path,
    environment: &mut BTreeMap<String, String>,
) -> Result<std::fs::File> {
    let path = directory.join("owner.lock");
    let file = std::fs::File::create(&path)?;
    file.lock()?;
    environment.insert(LEASE.into(), path.to_string_lossy().into_owned());
    Ok(file)
}

/// Only values overwritten by tuist_cargo_cache are restored. Cargo's own launch environment
/// (notably dynamic-library paths and CARGO_MANIFEST_DIR) must survive.
#[derive(Serialize, Deserialize)]
struct Restore(Vec<(OsString, Option<OsString>)>);

pub(super) fn record_overlay(environment: &mut BTreeMap<String, String>) -> Result<()> {
    let current = current_environment();
    let caller = CALLER.get().unwrap_or(&current);
    let build_path = environment
        .get("PATH")
        .map(OsString::from)
        .or_else(|| current.get(OsStr::new("PATH")).cloned());
    environment.insert(BUILD_PATH.into(), serde_json::to_string(&build_path)?);
    let mut restore = BTreeMap::new();
    // A nested explicit tuist_cargo_cache command may replace only part of its parent's
    // overlay. Carry the other keys too, so recovery cannot strand an outer
    // runner or compiler adapter in a later application.
    if let Some(encoded) = current.get(OsStr::new(RESTORE)) {
        let previous: Restore = serde_json::from_str(&encoded.to_string_lossy())?;
        for (name, _) in previous.0 {
            restore.insert(name.clone(), caller.get(&name).cloned());
        }
    }
    for name in environment
        .keys()
        .map(OsString::from)
        .chain(["PATH", "CARGO"].into_iter().map(OsString::from))
    {
        restore.insert(name.clone(), caller.get(&name).cloned());
    }
    restore.insert(RESTORE.into(), None);
    environment.insert(
        RESTORE.into(),
        serde_json::to_string(&Restore(restore.into_iter().collect()))?,
    );
    Ok(())
}

fn restored_environment() -> Result<Environment> {
    let mut environment = current_environment();
    if let Some(encoded) = environment.remove(OsStr::new(RESTORE)) {
        let restore: Restore = serde_json::from_str(&encoded.to_string_lossy())?;
        for (name, value) in restore.0 {
            match value {
                Some(value) => {
                    environment.insert(name, value);
                }
                None => {
                    environment.remove(&name);
                }
            }
        }
    }
    environment.remove(OsStr::new(CAPTURE));
    Ok(environment)
}

pub(super) struct Launch {
    capture: PathBuf,
    runner: Option<cargo_config2::PathAndArgs>,
    runner_key: String,
    shim: PathBuf,
}

impl Launch {
    pub(super) fn prepare(arguments: &[String], directory: &Path) -> Result<Option<Self>> {
        let args: Vec<_> = arguments
            .iter()
            .take_while(|arg| arg.as_str() != "--")
            .collect();
        if args
            .iter()
            .any(|arg| matches!(arg.as_str(), "--help" | "-h"))
        {
            return Ok(None);
        }
        if !matches!(cargo_subcommand(arguments), Some("run" | "r")) {
            return Ok(None);
        }
        let config = load_cargo_config()?;
        let targets = requested_targets(&config, arguments)?;
        eyre::ensure!(targets.len() == 1, "cargo run requires exactly one target");
        let target = &targets[0];
        let runner = config.runner(target)?;
        let runner_key = runner_key(target);
        let shim = crate::session::install_shim_named(
            &std::env::current_exe()?,
            directory,
            SHIM,
            crate::session::ShimLink::Tracking,
        )?;
        Ok(Some(Self {
            capture: directory.join("launch.json"),
            runner,
            runner_key,
            shim,
        }))
    }

    pub(super) fn environment(&self, environment: &mut BTreeMap<String, String>) -> Result<()> {
        // Cargo splits environment runner strings on whitespace. Resolve the
        // shim through PATH so a temporary directory containing spaces works.
        let path = std::env::var_os("PATH").unwrap_or_default();
        let path = std::env::join_paths(
            std::iter::once(self.shim.parent().unwrap().to_path_buf())
                .chain(std::env::split_paths(&path)),
        )?;
        environment.insert("PATH".into(), path.to_string_lossy().into_owned());
        environment.insert(self.runner_key.clone(), SHIM.into());
        environment.insert(CAPTURE.into(), self.capture.to_string_lossy().into_owned());
        Ok(())
    }

    pub(super) fn was_captured(&self) -> bool {
        self.capture.is_file()
    }

    pub(super) fn run(&self) -> Result<ExitCode> {
        let captured: Captured = serde_json::from_slice(
            &std::fs::read(&self.capture)
                .wrap_err("Cargo did not hand off the application launch")?,
        )?;
        std::fs::remove_file(&self.capture)?;
        let mut args = captured.arguments.into_iter();
        let executable = args
            .next()
            .ok_or_else(|| eyre::eyre!("Cargo supplied no executable"))?;
        let mut command = if let Some(runner) = &self.runner {
            let mut command = Command::new(&runner.path);
            command.args(&runner.args).arg(executable);
            command
        } else {
            Command::new(executable)
        };
        command
            .args(args)
            .current_dir(captured.directory)
            .env_clear()
            .envs(captured.environment);
        Ok(super::cargo::exit_code(
            command
                .status()
                .wrap_err("failed to launch Cargo application")?,
        ))
    }
}

#[derive(Serialize, Deserialize)]
struct Captured {
    arguments: Vec<OsString>,
    environment: Vec<(OsString, OsString)>,
    directory: PathBuf,
}

fn application_environment() -> Result<Environment> {
    let mut restored = restored_environment()?;
    // Cargo supplies its own executable path to the application, independently
    // of the CARGO value tuist_cargo_cache changed during compiler dispatch.
    if let Some(cargo) = std::env::var_os("CARGO") {
        restored.insert("CARGO".into(), cargo);
    }
    let build_path: Option<OsString> = std::env::var(BUILD_PATH)
        .ok()
        .map(|value| serde_json::from_str(&value))
        .transpose()?
        .flatten();
    if let (Some(build), Some(launch)) = (build_path, std::env::var_os("PATH")) {
        let original = restored
            .get(OsStr::new("PATH"))
            .cloned()
            .unwrap_or_default();
        restored.insert(
            "PATH".into(),
            restore_launch_path(&build, &launch, &original)?,
        );
    }
    Ok(restored)
}

fn restore_launch_path(build: &OsStr, launch: &OsStr, original: &OsStr) -> Result<OsString> {
    let build: Vec<_> = std::env::split_paths(build).collect();
    let mut launch: Vec<_> = std::env::split_paths(launch).collect();
    // On Windows Cargo adds native DLL search paths ahead of the build PATH.
    // Replace only the inherited suffix, retaining those runtime additions.
    if launch.ends_with(&build) {
        launch.truncate(launch.len() - build.len());
        launch.extend(std::env::split_paths(original));
    }
    Ok(std::env::join_paths(launch)?)
}

/// Capture Cargo's selected executable before normal tuist_cargo_cache CLI dispatch.
pub fn dispatch() -> Option<ExitCode> {
    if std::env::args_os()
        .next()
        .is_none_or(|arg| Path::new(&arg).file_stem() != Some(OsStr::new(SHIM)))
    {
        return None;
    }
    let result = (|| -> Result<()> {
        let path = std::env::var_os(CAPTURE)
            .ok_or_else(|| eyre::eyre!("missing Cargo launch destination"))?;
        let captured = Captured {
            arguments: std::env::args_os().skip(1).collect(),
            environment: application_environment()?.into_iter().collect(),
            directory: std::env::current_dir()?,
        };
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        serde_json::to_writer(options.open(path)?, &captured)?;
        Ok(())
    })();
    Some(match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("tuist_cargo_cache[error]: failed to capture Cargo launch: {error:#}");
            ExitCode::FAILURE
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn run_values_do_not_disable_caching_for_other_commands() {
        for args in [
            vec!["+nightly", "test", "run"],
            vec!["+stable", "build", "--bin", "run"],
            vec!["+nightly", "build", "--features", "run"],
            vec!["--config", "run", "check"],
        ] {
            assert!(!needs_plain_launch(
                &args.iter().map(|s| s.to_string()).collect::<Vec<_>>()
            ));
        }
        assert_eq!(cargo_subcommand(&["--color", "always", "run"]), Some("run"));
        assert_eq!(
            cargo_subcommand(&["-Z", "unstable-options", "--directory", "run", "check"]),
            Some("check")
        );
        assert!(needs_plain_launch(&[
            "--config".into(),
            "a.toml".into(),
            "run".into()
        ]));
    }

    #[test]
    fn runtime_search_paths_survive_restoring_the_caller_path() {
        let path = |parts: &[&str]| std::env::join_paths(parts).unwrap();
        assert_eq!(
            restore_launch_path(
                &path(&["shim", "tools"]),
                &path(&["deps", "sysroot", "shim", "tools"]),
                &path(&["cargo-proxy", "tools"])
            )
            .unwrap(),
            path(&["deps", "sysroot", "cargo-proxy", "tools"])
        );
        assert_eq!(
            restore_launch_path(
                &path(&["shim", "tools"]),
                &path(&["custom"]),
                &path(&["tools"])
            )
            .unwrap(),
            path(&["custom"])
        );
    }
}
