use eyre::{Context, Result};
use std::ffi::OsStr;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

#[cfg(windows)]
const CARGO_SHIM_STEM: &str = "cargo";
#[cfg(unix)]
pub(crate) const CARGO_SHIM_LAUNCHER: &[u8] = br#"#!/bin/sh
shim_dir=$(dirname "$0")
IFS= read -r cargo_cache_executable <"$shim_dir/tuist_cargo_cache-target"
if [ ! -x "$cargo_cache_executable" ]; then
  cargo_cache_executable=$(command -v tuist_cargo_cache 2>/dev/null)
fi
if [ -z "$cargo_cache_executable" ] || [ ! -x "$cargo_cache_executable" ]; then
  echo 'tuist_cargo_cache cargo shim: tuist_cargo_cache is not active on PATH; activate or install tuist_cargo_cache, then run `tuist_cargo_cache setup`' >&2
  exit 127
fi
TUIST_CARGO_CACHE_CARGO_SHIM_MODE=1
TUIST_CARGO_CACHE_CARGO_SHIM_PATH="$shim_dir/cargo"
export TUIST_CARGO_CACHE_CARGO_SHIM_MODE TUIST_CARGO_CACHE_CARGO_SHIM_PATH
exec "$cargo_cache_executable" "$@"
"#;
const RUST_ANALYZER_CONFIG_FILE: &str = "rust-analyzer.toml";
const MISE_WRAPPERS_MINIMUM_VERSION: (u64, u64, u64) = (2026, 8, 16);
const MISE_WRAPPERS_MINIMUM_VERSION_DISPLAY: &str = "2026.8.16";
const CARGO_WRAPPER_MODE_ENV: &str = "TUIST_CARGO_CACHE_CARGO_SHIM_MODE";
const RUST_ANALYZER_CHECK_ARGUMENTS: [&str; 6] = [
    "check",
    "--workspace",
    "--all-targets",
    "--target-dir",
    super::RUST_ANALYZER_TARGET_DIR,
    "--message-format=json",
];
const LEGACY_RUST_ANALYZER_CHECK_ARGUMENTS: [&str; 4] = [
    "check",
    "--workspace",
    "--all-targets",
    "--message-format=json",
];

#[derive(usage_rs::Args)]
pub(super) struct SetupArgs {
    /// Accept the recommended activation scope without prompting.
    ///
    /// `MISE_CONFIG_FILE` names the scope when it is set. Otherwise, in an
    /// activated mise shell, tuist_cargo_cache picks the mise config whose tools include
    /// `mr-boxington`, then the nearest project mise config, then the global
    /// config; outside one, tuist_cargo_cache installs the Cargo shim and edits no mise
    /// config. Cannot be combined with `--global` or `--local`.
    #[usage(long)]
    pub(super) yes: bool,
    /// Add mise's Cargo wrapper to the global mise configuration.
    #[usage(long)]
    pub(super) global: bool,
    /// Add mise's Cargo wrapper to the current project's mise configuration.
    #[usage(long)]
    pub(super) local: bool,
    /// Check that the Cargo shim and rust-analyzer check command are current.
    ///
    /// tuist_cargo_cache checks what `tuist_cargo_cache setup` writes and exits non-zero when any of it is
    /// missing or out of date. When a mise scope applies (`--global`,
    /// `--local`, `MISE_CONFIG_FILE`, or an activated mise shell), tuist_cargo_cache also
    /// checks that the scope's config has the `[wrappers.cargo]` entry that
    /// `tuist_cargo_cache setup` adds. Existing rust-analyzer check settings that `tuist_cargo_cache setup`
    /// did not write count as a pass.
    ///
    /// The status does not show which `cargo` your shell runs, and it does not
    /// detect mise's native `mr_boxington` option. `tuist_cargo_cache doctor` checks whether
    /// `cargo` on `PATH` resolves to the shim or mise's Cargo wrapper.
    #[usage(long)]
    pub(super) status: bool,
    /// Undo `tuist_cargo_cache setup` for the selected scope, keeping the Cargo shim.
    ///
    /// The scope comes from `--global`, `--local`, `MISE_CONFIG_FILE`, or an
    /// activated mise shell, as for `--status`. tuist_cargo_cache removes the
    /// `[wrappers.cargo]` entry that `tuist_cargo_cache setup` added to that scope's mise
    /// config. For the global scope, or when no mise scope applies, tuist_cargo_cache also
    /// removes the rust-analyzer check command that `tuist_cargo_cache setup` wrote. For a
    /// project scope, tuist_cargo_cache leaves that command for other scopes; remove it
    /// with `tuist_cargo_cache setup --global --uninstall`.
    #[usage(long)]
    pub(super) uninstall: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SetupAction {
    Install,
    Status,
    Uninstall,
}

impl SetupArgs {
    pub(super) fn action(&self) -> Result<SetupAction> {
        let selected = self.status as u8 + self.uninstall as u8;
        if selected > 1 {
            eyre::bail!("--status and --uninstall are mutually exclusive");
        }
        Ok(if self.status {
            SetupAction::Status
        } else if self.uninstall {
            SetupAction::Uninstall
        } else {
            SetupAction::Install
        })
    }

    pub(super) fn validate(&self) -> Result<()> {
        if self.global && self.local {
            eyre::bail!("--global and --local are mutually exclusive");
        }
        if self.yes && (self.global || self.local) {
            eyre::bail!("--yes cannot be combined with --global or --local");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum MiseScope {
    File(PathBuf),
    Global,
    Local,
    None,
}

impl std::fmt::Display for MiseScope {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::File(path) => write!(formatter, "{}", path.display()),
            Self::Global => formatter.write_str("global"),
            Self::Local => formatter.write_str("local"),
            Self::None => formatter.write_str("none"),
        }
    }
}

pub(super) fn run(args: &SetupArgs, action: SetupAction) -> Result<ExitCode> {
    args.validate()?;
    let executable =
        std::env::current_exe().wrap_err("failed to locate the tuist_cargo_cache executable")?;
    let install_dir = setup_install_dir()
        .ok_or_else(|| eyre::eyre!("the platform data directory could not be located"))?;
    let scope = setup_scope(args, action)?;
    let rust_analyzer_config = rust_analyzer_config_path()?;
    let project_config = project_rust_analyzer_config_path(&scope)?;
    setup_with_rust_analyzer(
        &executable,
        &install_dir,
        &scope,
        &rust_analyzer_config,
        project_config.as_deref(),
        action,
    )
}

/// The stable directory that holds the Cargo shim installed by setup.
pub(crate) fn setup_install_dir() -> Option<PathBuf> {
    #[cfg(debug_assertions)]
    if let Some(directory) = std::env::var_os("TUIST_CARGO_CACHE_TEST_SHIM_DIR") {
        return Some(directory.into());
    }
    Some(
        dirs::data_local_dir()?
            .join("tuist_cargo_cache")
            .join("bin"),
    )
}

#[cfg(test)]
pub(super) fn setup_at(executable: &Path, install_dir: &Path) -> Result<()> {
    let status = setup_at_action(
        executable,
        install_dir,
        &MiseScope::None,
        SetupAction::Install,
    )?;
    eyre::ensure!(
        status == ExitCode::SUCCESS,
        "tuist_cargo_cache setup failed: {status:?}"
    );
    Ok(())
}

pub(crate) fn setup_at_action(
    executable: &Path,
    install_dir: &Path,
    scope: &MiseScope,
    action: SetupAction,
) -> Result<ExitCode> {
    let shim = install_dir.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
    let was_installed = shim.is_file();

    match action {
        SetupAction::Status => {
            if !shim.is_file() {
                println!(
                    "tuist_cargo_cache setup is not installed: {} is missing",
                    shim.display()
                );
                return Ok(ExitCode::FAILURE);
            }
            if !cargo_shim_is_current(executable, &shim)? {
                println!("tuist_cargo_cache setup is outdated; run `tuist_cargo_cache setup`");
                return Ok(ExitCode::FAILURE);
            }
            if matches!(scope, MiseScope::None)
                || (mise_wrappers_available() && mise_wrapper_is_configured(scope)?)
            {
                println!(
                    "tuist_cargo_cache setup is installed and current: {}",
                    shim.display()
                );
                return Ok(ExitCode::SUCCESS);
            }
            println!(
                "tuist_cargo_cache setup is installed but is not active in the selected mise config"
            );
            return Ok(ExitCode::FAILURE);
        }
        SetupAction::Uninstall => {
            let activation_removed =
                !matches!(scope, MiseScope::None) && update_mise_wrapper(scope, action)?;
            if activation_removed {
                println!(
                    "removed tuist_cargo_cache Cargo activation; {} was left in place for other scopes",
                    shim.display()
                );
            } else {
                println!("{} was left in place for other scopes", shim.display());
            }
            return Ok(ExitCode::SUCCESS);
        }
        SetupAction::Install => {
            std::fs::create_dir_all(install_dir)?;
            #[cfg(windows)]
            crate::session::install_shim_named(
                executable,
                install_dir,
                CARGO_SHIM_STEM,
                crate::session::ShimLink::Tracking,
            )?;
            #[cfg(unix)]
            install_cargo_shim_launcher(&shim)?;
            write_cargo_shim_target(install_dir, executable)?;
        }
    }

    let activated = if !matches!(scope, MiseScope::None) {
        update_mise_wrapper(scope, action)?
    } else {
        false
    };
    if activated {
        println!("plain cargo commands now run through tuist_cargo_cache in this mise scope");
        print_activation_verification(&shim);
    } else if was_installed {
        println!("refreshed the Cargo shim at {}", shim.display());
    } else {
        println!("installed the Cargo shim at {}", shim.display());
        if matches!(scope, MiseScope::None) {
            print_manual_activation(install_dir);
        }
    }
    Ok(ExitCode::SUCCESS)
}

/// Explain how to verify activation, including shells that do not load mise.
fn print_activation_verification(shim: &Path) {
    let directory = shim.parent().unwrap_or(shim);
    #[cfg(windows)]
    println!(
        "verify new shells with `Get-Command cargo` in PowerShell or `where.exe cargo`; it should resolve through mise's command-wrappers directory"
    );
    #[cfg(not(windows))]
    println!(
        "verify new shells with `command -v cargo`; it should resolve through mise's command-wrappers directory"
    );
    println!(
        "tools and non-interactive shells that do not activate mise need {} prepended to PATH",
        directory.display()
    );
}

#[cfg(unix)]
fn install_cargo_shim_launcher(shim: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt as _;

    crate::util::write_atomic(shim, CARGO_SHIM_LAUNCHER)?;
    let mut permissions = std::fs::metadata(shim)?.permissions();
    permissions.set_mode(permissions.mode() | 0o100);
    std::fs::set_permissions(shim, permissions)?;
    Ok(())
}

/// Keep rust-analyzer's private Cargo process in the same tuist_cargo_cache pool as shells.
///
/// The override names the stable Cargo shim by absolute path. Editors launched
/// outside an activated mise shell therefore do not need to inherit its PATH,
/// and upgrading tuist_cargo_cache does not leave the editor pointing at an old executable.
pub(super) fn setup_with_rust_analyzer(
    executable: &Path,
    install_dir: &Path,
    scope: &MiseScope,
    config_path: &Path,
    project_config_path: Option<&Path>,
    action: SetupAction,
) -> Result<ExitCode> {
    let status = setup_at_action(executable, install_dir, scope, action)?;
    if status != ExitCode::SUCCESS {
        return Ok(status);
    }
    let shim = install_dir.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
    if action != SetupAction::Status
        && let Some(project_config) = project_config_path
    {
        remove_inactive_project_override(project_config, &shim, config_path)?;
    }
    if action == SetupAction::Uninstall && override_is_shared_with_other_scopes(scope) {
        if rust_analyzer_override_is_installed(config_path, &shim)? {
            println!(
                "the rust-analyzer check command in {} was left in place for other scopes; remove it with `tuist_cargo_cache setup --global --uninstall`",
                config_path.display()
            );
        }
        return Ok(ExitCode::SUCCESS);
    }
    configure_rust_analyzer(config_path, &shim, action)
}

/// One user-level override serves every mise scope, like the Cargo shim.
///
/// mise has no machine-wide list of project configurations, so uninstalling one
/// project cannot tell whether another still relies on the override. Leave it
/// alone from a project scope, the way `setup_at_action` leaves the shim, and
/// remove it from the machine-wide scope that matches what it covers.
pub(super) fn override_is_shared_with_other_scopes(scope: &MiseScope) -> bool {
    !scope_is_machine_wide(scope)
}

/// `MISE_CONFIG_FILE` can name the global configuration, so a file scope is not
/// automatically a project scope.
fn scope_is_machine_wide(scope: &MiseScope) -> bool {
    match scope {
        MiseScope::Global | MiseScope::None => true,
        MiseScope::Local => false,
        MiseScope::File(path) => mise_scope_config_path(&MiseScope::Global)
            .is_ok_and(|global_config| same_config_path(&global_config, path)),
    }
}

/// Decide whether two mise configuration paths name one file.
///
/// `MISE_CONFIG_FILE` is taken verbatim while the global path is derived from
/// `MISE_GLOBAL_CONFIG_FILE` or the platform default, so one file reaches the
/// two sides under different spellings: a relative path, a `.` component, a
/// symlinked home. Ask the filesystem, and fall back to the literal comparison
/// when it cannot resolve either side.
pub(super) fn same_config_path(left: &Path, right: &Path) -> bool {
    if left == right {
        return true;
    }
    let resolve = |path: &Path| -> Option<PathBuf> {
        if let Ok(resolved) = std::fs::canonicalize(path) {
            return Some(resolved);
        }
        let name = path.file_name()?;
        let parent = match path.parent() {
            Some(parent) if parent.as_os_str().is_empty() => Path::new("."),
            Some(parent) => parent,
            None => return None,
        };
        Some(std::fs::canonicalize(parent).ok()?.join(name))
    };
    match (resolve(left), resolve(right)) {
        (Some(left), Some(right)) => left == right,
        _ => false,
    }
}

pub(super) fn rust_analyzer_override_is_installed(path: &Path, shim: &Path) -> Result<bool> {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    let Ok(document) = contents.parse::<toml_edit::DocumentMut>() else {
        return Ok(false);
    };
    let configured = document
        .get("check")
        .and_then(toml_edit::Item::as_table_like)
        .and_then(|check| check.get("overrideCommand"));
    let expected = rust_analyzer_command(shim, RUST_ANALYZER_CHECK_ARGUMENTS);
    let legacy = rust_analyzer_command(shim, LEGACY_RUST_ANALYZER_CHECK_ARGUMENTS);
    Ok(rust_analyzer_command_matches(configured, &expected)
        || rust_analyzer_command_matches(configured, &legacy))
}

/// rust-analyzer resolves its check command from the user configuration only.
///
/// `check.overrideCommand` is a workspace-scoped setting, and rust-analyzer
/// builds the flycheck command with `Config::flycheck(None)`. Passing no source
/// root skips every workspace `rust-analyzer.toml`, so an override written
/// beside `Cargo.toml` parses and validates but never runs. The override goes
/// to the user-level file whichever mise scope activation uses.
fn rust_analyzer_config_path() -> Result<PathBuf> {
    dirs::config_dir()
        .map(|directory| {
            directory
                .join("rust-analyzer")
                .join(RUST_ANALYZER_CONFIG_FILE)
        })
        .ok_or_else(|| eyre::eyre!("the platform configuration directory could not be located"))
}

/// The project file earlier releases wrote for a project-scoped activation.
///
/// A global or unscoped run still looks at the surrounding Cargo workspace, so
/// switching scopes does not leave the dead file behind.
fn project_rust_analyzer_config_path(scope: &MiseScope) -> Result<Option<PathBuf>> {
    project_rust_analyzer_config_path_from(scope, &std::env::current_dir()?)
}

pub(super) fn project_rust_analyzer_config_path_from(
    scope: &MiseScope,
    cwd: &Path,
) -> Result<Option<PathBuf>> {
    let active_workspace = || -> Option<PathBuf> {
        let root = crate::util::workspace_root(cwd);
        (root.join("Cargo.toml").is_file() || root.join("Cargo.lock").is_file())
            .then(|| root.join(RUST_ANALYZER_CONFIG_FILE))
    };
    if scope_is_machine_wide(scope) {
        return Ok(active_workspace());
    }
    match scope {
        MiseScope::Local => Ok(Some(
            crate::util::workspace_root(cwd).join(RUST_ANALYZER_CONFIG_FILE),
        )),
        MiseScope::File(path) => {
            if let Some(config) = active_workspace() {
                Ok(Some(config))
            } else {
                let directory = path.parent().ok_or_else(|| {
                    eyre::eyre!("mise configuration path has no parent: {}", path.display())
                })?;
                Ok(Some(
                    crate::util::workspace_root(directory).join(RUST_ANALYZER_CONFIG_FILE),
                ))
            }
        }
        MiseScope::Global | MiseScope::None => Ok(active_workspace()),
    }
}

/// Take back a project override that rust-analyzer silently ignored.
///
/// Releases up to 1.12.0 wrote the check command beside `Cargo.toml` when tuist_cargo_cache
/// was activated in a project mise scope. The editor kept calling plain Cargo,
/// so those checks missed the cache and the compiler pool. Remove the dead
/// setting, and remove the file with it when setup wrote the whole thing.
pub(super) fn remove_inactive_project_override(
    path: &Path,
    shim: &Path,
    config_path: &Path,
) -> Result<()> {
    if path == config_path {
        return Ok(());
    }
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    let Ok(mut document) = contents.parse::<toml_edit::DocumentMut>() else {
        return Ok(());
    };
    let expected = rust_analyzer_command(shim, RUST_ANALYZER_CHECK_ARGUMENTS);
    let legacy = rust_analyzer_command(shim, LEGACY_RUST_ANALYZER_CHECK_ARGUMENTS);
    let configured = document
        .get("check")
        .and_then(toml_edit::Item::as_table_like)
        .and_then(|check| check.get("overrideCommand"));
    if !rust_analyzer_command_matches(configured, &expected)
        && !rust_analyzer_command_matches(configured, &legacy)
    {
        return Ok(());
    }
    let check = document
        .get_mut("check")
        .and_then(toml_edit::Item::as_table_like_mut)
        .expect("the configuration was inspected above");
    check.remove("overrideCommand");
    if check.is_empty() {
        document.remove("check");
    }
    let remaining = document.to_string();
    if remaining.trim().is_empty() {
        std::fs::remove_file(path)?;
    } else {
        crate::util::write_atomic(path, remaining.as_bytes())?;
    }
    println!(
        "removed the inactive rust-analyzer check command from {}: rust-analyzer reads check settings from {}",
        path.display(),
        config_path.display()
    );
    Ok(())
}

fn rust_analyzer_command<const N: usize>(shim: &Path, arguments: [&str; N]) -> Vec<String> {
    std::iter::once(shim.to_string_lossy().into_owned())
        .chain(arguments.map(str::to_owned))
        .collect()
}

fn rust_analyzer_command_matches(
    configured: Option<&toml_edit::Item>,
    expected: &[String],
) -> bool {
    configured
        .and_then(toml_edit::Item::as_array)
        .is_some_and(|command| {
            command.len() == expected.len()
                && command
                    .iter()
                    .zip(expected)
                    .all(|(actual, expected)| actual.as_str() == Some(expected))
        })
}

pub(super) fn configure_rust_analyzer(
    path: &Path,
    shim: &Path,
    action: SetupAction,
) -> Result<ExitCode> {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => return Err(error.into()),
    };
    let mut document = contents
        .parse::<toml_edit::DocumentMut>()
        .wrap_err_with(|| format!("failed to parse {}", path.display()))?;
    let expected = rust_analyzer_command(shim, RUST_ANALYZER_CHECK_ARGUMENTS);
    let legacy = rust_analyzer_command(shim, LEGACY_RUST_ANALYZER_CHECK_ARGUMENTS);
    let check = document
        .get("check")
        .and_then(toml_edit::Item::as_table_like);
    let configured = check.and_then(|check| check.get("overrideCommand"));
    let has_check_settings = check.is_some_and(|check| !check.is_empty());
    let owns_configuration = rust_analyzer_command_matches(configured, &expected);
    let owns_legacy_configuration = rust_analyzer_command_matches(configured, &legacy);

    match action {
        SetupAction::Status if owns_configuration => {
            println!(
                "rust-analyzer checks run through tuist_cargo_cache: {}",
                path.display()
            );
            print_rust_analyzer_warning_note();
            Ok(ExitCode::SUCCESS)
        }
        SetupAction::Status if owns_legacy_configuration => {
            println!(
                "rust-analyzer checks share Cargo's target directory; run `tuist_cargo_cache setup` to update {}",
                path.display()
            );
            print_rust_analyzer_warning_note();
            Ok(ExitCode::FAILURE)
        }
        SetupAction::Status if has_check_settings => {
            println!(
                "rust-analyzer keeps its existing check settings in {}",
                path.display()
            );
            Ok(ExitCode::SUCCESS)
        }
        SetupAction::Status => {
            println!(
                "rust-analyzer checks do not use tuist_cargo_cache; run `tuist_cargo_cache setup` to configure {}",
                path.display()
            );
            Ok(ExitCode::FAILURE)
        }
        SetupAction::Uninstall => {
            if owns_configuration || owns_legacy_configuration {
                let check = document
                    .get_mut("check")
                    .and_then(toml_edit::Item::as_table_like_mut)
                    .expect("the configuration was inspected above");
                check.remove("overrideCommand");
                if check.is_empty() {
                    document.remove("check");
                }
                crate::util::write_atomic(path, document.to_string().as_bytes())?;
                println!(
                    "removed tuist_cargo_cache's rust-analyzer check command from {}",
                    path.display()
                );
            }
            Ok(ExitCode::SUCCESS)
        }
        SetupAction::Install if owns_configuration => Ok(ExitCode::SUCCESS),
        SetupAction::Install if owns_legacy_configuration => {
            let mut command = toml_edit::Array::new();
            command.extend(expected);
            document["check"]["overrideCommand"] = toml_edit::value(command);
            crate::util::write_atomic(path, document.to_string().as_bytes())?;
            println!(
                "rust-analyzer background checks now use a separate target directory: {}",
                path.display()
            );
            print_rust_analyzer_warning_note();
            Ok(ExitCode::SUCCESS)
        }
        SetupAction::Install if has_check_settings => {
            println!(
                "left {} unchanged: rust-analyzer check settings are already configured",
                path.display()
            );
            Ok(ExitCode::SUCCESS)
        }
        SetupAction::Install => {
            let mut command = toml_edit::Array::new();
            command.extend(expected);
            document["check"]["overrideCommand"] = toml_edit::value(command);
            crate::util::write_atomic(path, document.to_string().as_bytes())?;
            println!(
                "rust-analyzer background checks now run through tuist_cargo_cache: {}",
                path.display()
            );
            print_rust_analyzer_warning_note();
            Ok(ExitCode::SUCCESS)
        }
    }
}

/// rust-analyzer validates its user file against global and local settings
/// only, so it flags the workspace-scoped `check.overrideCommand` as unknown
/// and then applies it anyway. Warn ahead of the editor so the message does
/// not read as a broken setup.
fn print_rust_analyzer_warning_note() {
    println!(
        "rust-analyzer reports `check/overrideCommand: unexpected field` for this file; the check still runs through tuist_cargo_cache"
    );
}

fn setup_scope(args: &SetupArgs, action: SetupAction) -> Result<MiseScope> {
    if let Some(path) = std::env::var_os("MISE_CONFIG_FILE")
        && (args.yes || (!args.global && !args.local && action != SetupAction::Install))
    {
        return Ok(MiseScope::File(path.into()));
    }
    if args.global {
        return Ok(MiseScope::Global);
    }
    if args.local {
        return Ok(MiseScope::Local);
    }
    if args.yes {
        return Ok(recommended_mise_scope().unwrap_or(MiseScope::None));
    }
    if action != SetupAction::Install {
        return Ok(recommended_mise_scope().unwrap_or(MiseScope::None));
    }
    if !mise_is_activated() {
        return Ok(MiseScope::None);
    }
    if !std::io::stdin().is_terminal() || !std::io::stderr().is_terminal() {
        return Ok(MiseScope::None);
    }
    let recommended = recommended_mise_scope().unwrap_or(MiseScope::Global);
    use demand::{DemandOption, Select};
    let mut select = Select::new("Where should plain cargo commands use tuist_cargo_cache?");
    match &recommended {
        MiseScope::Global => {
            select = select.option(
                DemandOption::new(MiseScope::Global)
                    .label("Everywhere mise is active")
                    .selected(true),
            );
            select =
                select.option(DemandOption::new(MiseScope::Local).label("Only in this project"));
        }
        MiseScope::File(_) => {
            select = select.option(
                DemandOption::new(recommended.clone())
                    .label("The project mise config that applies here")
                    .selected(true),
            );
            select = select
                .option(DemandOption::new(MiseScope::Global).label("Everywhere mise is active"));
        }
        MiseScope::Local | MiseScope::None => unreachable!("recommended scope is concrete"),
    }
    select = select
        .option(DemandOption::new(MiseScope::None).label("Create the shim without activating it"));
    match select.run() {
        Ok(scope) => Ok(scope),
        Err(error) if error.kind() == std::io::ErrorKind::Interrupted => Ok(MiseScope::None),
        Err(error) => Err(error.into()),
    }
}

fn mise_is_activated() -> bool {
    command_exists("mise") && std::env::var_os("MISE_SHELL").is_some()
}

fn recommended_mise_scope() -> Option<MiseScope> {
    if !mise_is_activated() {
        return None;
    }
    if let Some(path) = cargo_cache_mise_config() {
        let global = mise_scope_config_path(&MiseScope::Global).ok();
        return Some(if global.as_deref() == Some(path.as_path()) {
            MiseScope::Global
        } else {
            MiseScope::File(path)
        });
    }
    nearest_project_config()
        .map(MiseScope::File)
        .or(Some(MiseScope::Global))
}

fn cargo_cache_mise_config() -> Option<PathBuf> {
    let output = Command::new("mise")
        .args(["config", "ls", "--json"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    cargo_cache_mise_config_from_json(&output.stdout)
}

pub(super) fn cargo_cache_mise_config_from_json(json: &[u8]) -> Option<PathBuf> {
    let value = serde_json::from_slice::<serde_json::Value>(json).ok()?;
    value.as_array()?.iter().find_map(|config| {
        let tools = config.get("tools")?.as_array()?;
        let defines_cargo_cache = tools
            .iter()
            .filter_map(serde_json::Value::as_str)
            .any(|tool| {
                tool == "mr-boxington"
                    || tool
                        .rsplit([':', '/'])
                        .next()
                        .is_some_and(|name| name == "mr-boxington")
            });
        defines_cargo_cache.then(|| config.get("path")?.as_str().map(PathBuf::from))?
    })
}

fn command_exists(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| {
        std::env::split_paths(&path).any(|directory| {
            directory
                .join(if cfg!(windows) {
                    format!("{name}.exe")
                } else {
                    name.into()
                })
                .is_file()
        })
    })
}

fn update_mise_wrapper(scope: &MiseScope, action: SetupAction) -> Result<bool> {
    if !mise_wrappers_available() {
        return Ok(false);
    }
    let config = mise_scope_config_path(scope)?;
    let contents = match std::fs::read_to_string(&config) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => return Err(error.into()),
    };
    let mut document = contents
        .parse::<toml_edit::DocumentMut>()
        .wrap_err_with(|| format!("failed to parse {}", config.display()))?;
    let configured = mise_wrapper_is_configured_in(&document);

    match action {
        SetupAction::Status => return Ok(configured),
        SetupAction::Install if configured => return Ok(true),
        SetupAction::Install => {
            if document
                .get("wrappers")
                .and_then(toml_edit::Item::as_table_like)
                .and_then(|wrappers| wrappers.get("cargo"))
                .is_some()
            {
                eprintln!(
                    "tuist_cargo_cache[setup]: left {} unchanged because wrappers.cargo is already configured",
                    config.display()
                );
                return Ok(false);
            }
            document["wrappers"]["cargo"]["command"] = toml_edit::value("tuist_cargo_cache");
            document["wrappers"]["cargo"]["env"][CARGO_WRAPPER_MODE_ENV] = toml_edit::value("1");
        }
        SetupAction::Uninstall if !configured => return Ok(false),
        SetupAction::Uninstall => {
            let wrappers = document
                .get_mut("wrappers")
                .and_then(toml_edit::Item::as_table_like_mut)
                .expect("the configured wrapper has a wrappers table");
            wrappers.remove("cargo");
            if wrappers.is_empty() {
                document.remove("wrappers");
            }
        }
    }

    crate::util::write_atomic(&config, document.to_string().as_bytes())?;
    let status = Command::new("mise")
        .arg("reshim")
        .env("MISE_CONFIG_FILE", &config)
        .env("MISE_TRUSTED_CONFIG_PATHS", &config)
        .status()
        .wrap_err("failed to run `mise reshim`")?;
    if !status.success() {
        eyre::bail!("mise could not refresh command wrappers");
    }
    Ok(true)
}

fn mise_supports_wrappers() -> bool {
    Command::new("mise")
        .arg("--version")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| mise_version_from_output(&output.stdout))
        .is_some_and(|version| version >= MISE_WRAPPERS_MINIMUM_VERSION)
}

fn mise_wrappers_available() -> bool {
    let available = mise_supports_wrappers();
    if !available {
        eprintln!(
            "tuist_cargo_cache[setup]: mise {MISE_WRAPPERS_MINIMUM_VERSION_DISPLAY} or newer is required for [wrappers]; upgrade mise to activate plain cargo commands"
        );
    }
    available
}

pub(super) fn mise_version_from_output(output: &[u8]) -> Option<(u64, u64, u64)> {
    let version = String::from_utf8_lossy(output);
    let version = version.split_whitespace().next()?.trim_start_matches('v');
    let mut parts = version.split('.').map(str::parse);
    Some((
        parts.next()?.ok()?,
        parts.next()?.ok()?,
        parts.next()?.ok()?,
    ))
}

fn mise_scope_config_path(scope: &MiseScope) -> Result<PathBuf> {
    match scope {
        MiseScope::File(path) => Ok(path.clone()),
        MiseScope::Global => {
            if let Some(path) = std::env::var_os("MISE_GLOBAL_CONFIG_FILE") {
                return Ok(path.into());
            }
            if let Some(path) = std::env::var_os("XDG_CONFIG_HOME") {
                return Ok(PathBuf::from(path).join("mise/config.toml"));
            }
            let home = dirs::home_dir()
                .ok_or_else(|| eyre::eyre!("the home directory could not be located"))?;
            Ok(home.join(".config/mise/config.toml"))
        }
        MiseScope::Local => {
            let cwd = std::env::current_dir()?;
            if let Some(config) = nearest_project_config() {
                return Ok(config);
            }
            let filename = std::env::var_os("MISE_DEFAULT_CONFIG_FILENAME")
                .unwrap_or_else(|| "mise.toml".into());
            Ok(cwd.join(filename))
        }
        MiseScope::None => eyre::bail!("mise activation has no selected config"),
    }
}

fn nearest_project_config() -> Option<PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    let filename =
        std::env::var_os("MISE_DEFAULT_CONFIG_FILENAME").unwrap_or_else(|| "mise.toml".into());
    for directory in cwd.ancestors() {
        let candidate = directory.join(&filename);
        if candidate.is_file() {
            return Some(candidate);
        }
        for alternate in ["mise.toml", ".mise.toml"] {
            let candidate = directory.join(alternate);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

fn mise_wrapper_is_configured(scope: &MiseScope) -> Result<bool> {
    let config = mise_scope_config_path(scope)?;
    let contents = match std::fs::read_to_string(&config) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    let document = contents
        .parse::<toml_edit::DocumentMut>()
        .wrap_err_with(|| format!("failed to parse {}", config.display()))?;
    Ok(mise_wrapper_is_configured_in(&document))
}

pub(super) fn mise_wrapper_is_configured_in(document: &toml_edit::DocumentMut) -> bool {
    let Some(cargo) = document
        .get("wrappers")
        .and_then(toml_edit::Item::as_table_like)
        .and_then(|wrappers| wrappers.get("cargo"))
        .and_then(toml_edit::Item::as_table_like)
    else {
        return false;
    };
    let command_is_cargo_cache =
        cargo.get("command").and_then(toml_edit::Item::as_str) == Some("tuist_cargo_cache");
    let shim_mode_is_set = cargo
        .get("env")
        .and_then(toml_edit::Item::as_table_like)
        .and_then(|env| env.get(CARGO_WRAPPER_MODE_ENV))
        .and_then(toml_edit::Item::as_str)
        == Some("1");
    command_is_cargo_cache && shim_mode_is_set
}

fn print_manual_activation(path: &Path) {
    let path = path.display().to_string();
    if cfg!(windows) {
        println!("prepend the shim for this PowerShell session:");
        println!("  $env:Path = \"{path};$env:Path\"");
    } else {
        let shell_path = std::env::var_os("SHELL");
        let shell = shell_path
            .as_deref()
            .and_then(|shell| Path::new(shell).file_stem())
            .and_then(OsStr::to_str);
        println!("prepend the Cargo shim to PATH in your shell:");
        match shell {
            Some("fish") => println!("  set -gx PATH {} $PATH", fish_quote(&path)),
            Some("nu") | Some("nushell") => {
                println!("  $env.PATH = ($env.PATH | prepend '{path}')")
            }
            _ => println!("  export PATH=\"{path}:$PATH\""),
        }
    }
    println!("tuist_cargo_cache does not edit shell startup files");
}

fn fish_quote(value: &str) -> String {
    format!("'{}'", value.replace('\\', "\\\\").replace('\'', "\\'"))
}

pub(super) fn same_file_contents(left: &Path, right: &Path) -> Result<bool> {
    let left_metadata = std::fs::metadata(left)?;
    let right_metadata = std::fs::metadata(right)?;
    if left_metadata.len() != right_metadata.len() {
        return Ok(false);
    }
    Ok(tuist_cargo_cache_core::CacheDigest::blake3_file(left)?
        == tuist_cargo_cache_core::CacheDigest::blake3_file(right)?)
}

#[cfg(windows)]
pub(crate) fn cargo_shim_target(install_dir: &Path) -> Option<PathBuf> {
    if let Some(target) = std::env::var_os("PATH").and_then(|path| {
        std::env::split_paths(&path)
            .filter(|directory| !same_path(directory, install_dir))
            .map(|directory| directory.join("tuist_cargo_cache.exe"))
            .find(|candidate| candidate.is_file())
    }) {
        return Some(target);
    }
    configured_cargo_shim_target(install_dir).filter(|target| target.is_file())
}

#[cfg(windows)]
fn configured_cargo_shim_target(install_dir: &Path) -> Option<PathBuf> {
    use std::os::windows::ffi::OsStringExt as _;

    let bytes = std::fs::read(install_dir.join(super::CARGO_SHIM_TARGET_FILE)).ok()?;
    let mut chunks = bytes.chunks_exact(2);
    let target = std::ffi::OsString::from_wide(
        &chunks
            .by_ref()
            .map(|bytes| u16::from_le_bytes([bytes[0], bytes[1]]))
            .collect::<Vec<_>>(),
    );
    if !chunks.remainder().is_empty() {
        return None;
    }
    let target = PathBuf::from(target);
    target.is_absolute().then_some(target)
}

/// The launcher only falls back to `tuist_cargo_cache` on PATH when its recorded target is
/// gone, and the shells that need the shim usually do not have tuist_cargo_cache on PATH.
/// A target left behind by a removed install therefore makes the shim fail.
#[cfg(unix)]
fn configured_cargo_shim_target_is_executable(install_dir: &Path) -> bool {
    use std::os::unix::ffi::OsStrExt as _;

    let Ok(bytes) = std::fs::read(install_dir.join(super::CARGO_SHIM_TARGET_FILE)) else {
        return false;
    };
    let line = bytes
        .split(|byte| *byte == b'\n')
        .next()
        .unwrap_or_default();
    let target = Path::new(OsStr::from_bytes(line));
    if !target.is_absolute() || !target.is_file() {
        return false;
    }
    // Ask the kernel, like the launcher's `[ -x ]`, so an execute bit that only
    // applies to another user does not count.
    let Ok(target) = std::ffi::CString::new(line) else {
        return false;
    };
    unsafe { libc::access(target.as_ptr(), libc::X_OK) == 0 }
}

fn write_cargo_shim_target(install_dir: &Path, executable: &Path) -> Result<()> {
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt as _;

        let target = executable
            .as_os_str()
            .encode_wide()
            .flat_map(u16::to_le_bytes)
            .collect::<Vec<_>>();
        std::fs::write(install_dir.join(super::CARGO_SHIM_TARGET_FILE), target)?;
    }
    #[cfg(not(windows))]
    {
        let mut target = executable.as_os_str().as_encoded_bytes().to_vec();
        target.push(b'\n');
        crate::util::write_atomic(&install_dir.join(super::CARGO_SHIM_TARGET_FILE), &target)?;
    }
    Ok(())
}

pub(crate) fn cargo_shim_is_current(_executable: &Path, shim: &Path) -> Result<bool> {
    #[cfg(windows)]
    if let Some(install_dir) = shim.parent()
        && let Some(configured) = configured_cargo_shim_target(install_dir)
    {
        return Ok(same_path(&configured, _executable)
            || cargo_shim_target(install_dir)
                .is_some_and(|target| same_path(&target, _executable)));
    }
    #[cfg(unix)]
    {
        return Ok(std::fs::read(shim)? == CARGO_SHIM_LAUNCHER
            && shim
                .parent()
                .is_some_and(configured_cargo_shim_target_is_executable));
    }
    #[allow(unreachable_code)]
    same_file_contents(_executable, shim)
}

#[cfg(windows)]
fn same_path(left: &Path, right: &Path) -> bool {
    let left = std::fs::canonicalize(left).unwrap_or_else(|_| left.to_path_buf());
    let right = std::fs::canonicalize(right).unwrap_or_else(|_| right.to_path_buf());
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
