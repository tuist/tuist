//! The tuist_cargo_cache command line.

use crate::config::Config;
#[cfg(test)]
use crate::config::RetentionSettings;
#[cfg(test)]
use crate::util::workspace_root;
use eyre::Result;
#[cfg(test)]
use std::path::Path;
#[cfg(test)]
use std::path::PathBuf;
use std::process::ExitCode;

mod adopt;
mod analyze;
mod cache;
mod cargo;
mod cargo_invocation;
mod clean;
mod doctor;
mod edit;
mod exec;
mod explain;
mod gc;
pub(crate) use gc::{schedule_low_disk_sweep, spawn_collector_from};
pub mod launch;
mod mascot;
mod plain_progress;
mod prefetch;
mod pretty;
mod reserve;
mod settings;
mod setup;
mod shim;
mod stats;
pub mod test_runner;
mod tui;

const CARGO_SHIM_TARGET_FILE: &str = "tuist_cargo_cache-target";
const RUST_ANALYZER_TARGET_DIR: &str = "target/rust-analyzer";
const CHECK_LANE_TARGET_DIR: &str = "target/check";

pub(crate) use cargo::{cargo_with_bypass_log, cargo_with_settings_and_bypass_log};
pub(crate) use setup::{cargo_shim_is_current, setup_install_dir};
pub use shim::{is_cargo_shim, run_cargo_shim};

pub(crate) fn cargo_activation_path() -> Option<std::ffi::OsString> {
    shim::activation_path()
}

pub(crate) use shim::is_mise_command_wrapper_path;

#[cfg(test)]
use prefetch::validate_prefetch_config;
#[cfg(all(test, unix))]
pub(crate) use setup::CARGO_SHIM_LAUNCHER as DOCTOR_CARGO_SHIM_LAUNCHER;
#[cfg(test)]
pub(crate) use setup::{
    MiseScope as DoctorMiseScope, SetupAction as DoctorSetupAction,
    setup_at_action as doctor_setup_at_action,
};
#[cfg(test)]
use {cache::*, cargo::*, exec::*, gc::*, settings::*, setup::*};

#[derive(usage_rs::Cli)]
#[usage(completion = true)]
#[usage(
    bin = "tuist_cargo_cache",
    version,
    config = crate::config::RawConfig,
    about = "A build cache for Rust projects",
    long_about = "Enable mise's `mr_boxington` Rust option, or run `tuist_cargo_cache setup` once, then keep using Cargo normally. Compiled work is shared across every checkout, and build storage prunes itself. Use tuist_cargo_cache directly for its own commands, such as `tui`, `stats`, `cache`, `gc`, and `doctor`, or prefix Cargo commands with `tuist_cargo_cache` for zero-config use.\n\nExamples:\n  tuist_cargo_cache setup\n  cargo build --release\n  cargo test --workspace\n  cargo clippy --all-targets -- -D warnings\n  tuist_cargo_cache gc --dry-run",
    unknown_flags = "error"
)]
struct Cli {
    /// Toolchain to run under, named the way rustup names it: `tuist_cargo_cache +1.91 check`.
    ///
    /// Cargo commands, `tuist_cargo_cache doctor`, `tuist_cargo_cache explain`, and `tuist_cargo_cache prefetch` take a
    /// toolchain. Other tuist_cargo_cache commands reject one, and so does `tuist_cargo_cache explain --last`.
    //
    // Classified by its `+` rather than left to the external subcommand, which
    // is what makes the word mean the same thing in front of an tuist_cargo_cache command as
    // it does in front of a Cargo one. Forwarded as it was typed by everything
    // that ends in cargo, so `tuist_cargo_cache +1.91 check` still reaches rustup's shim the
    // way it always has. A plain comment rather than a doc comment, because the
    // generated CLI reference renders those and this is a note to the next
    // reader here.
    #[usage(sigil = "+", value_name = "TOOLCHAIN")]
    toolchain: Option<String>,
    #[usage(subcommand)]
    command: Commands,
}

#[derive(usage_rs::Subcommands)]
enum Commands {
    /// Generate a self-contained shell completion script.
    Completion {
        /// Shell: bash, zsh, fish, powershell (or pwsh), nu (or nushell), or elvish.
        #[usage(arg)]
        shell: String,
    },
    /// Check the installation, cache, toolchain, and remote cache connection.
    Doctor(doctor::DoctorArgs),
    /// Explain cache bypasses, or replay the last build and diagnose its misses.
    ///
    /// With a Cargo command, tuist_cargo_cache runs it and explains every compilation that
    /// bypassed the cache, grouped by cause, as in `tuist_cargo_cache explain build --workspace`.
    /// With `--last`, tuist_cargo_cache runs nothing: it reads this workspace's most recent
    /// recorded build and explains each miss against an earlier recording of
    /// that compilation unit, preferring this workspace's own.
    Explain(explain::ExplainArgs),
    /// Rank the uncached compiler time of this workspace's last build by cause.
    ///
    /// Each cause comes with what would remove it. tuist_cargo_cache reads the newest recorded
    /// build of the Cargo workspace that contains the current directory, so it
    /// runs nothing. A crate that rebuilt only because a dependency changed is
    /// counted under the change that started it. The report ends with the
    /// critical path (the chain of units the build waited on) and the time only
    /// one unit was running.
    Analyze(analyze::AnalyzeArgs),
    /// Open the global configuration in $VISUAL, $EDITOR, or the platform's default editor.
    Edit,
    /// Make plain Cargo commands run through tuist_cargo_cache.
    ///
    /// tuist_cargo_cache installs a stable Cargo shim and prints its path. When you pick a
    /// mise scope, with a flag or at the prompt, tuist_cargo_cache also adds a
    /// `[wrappers.cargo]` entry to that scope's mise configuration, if it has
    /// none, and runs `mise reshim`; this needs mise 2026.8.16 or newer. Without
    /// a mise scope, put the shim's directory first on `PATH` yourself; tuist_cargo_cache
    /// never edits shell startup files.
    ///
    /// tuist_cargo_cache also writes `check.overrideCommand` to rust-analyzer's user
    /// `rust-analyzer.toml` so editor checks run through the shim, unless that
    /// file already has check settings of its own.
    Setup(setup::SetupArgs),
    /// Read and change settings in the global configuration file.
    Settings(settings::SettingsArgs),
    /// Collect build state and evict store objects to fit the size budgets.
    ///
    /// tuist_cargo_cache collects learned incremental state and managed targets first, then
    /// evicts store objects until the action store fits its budget
    /// (`--max-size`, or `gc.max_size` by default, lowered when
    /// `gc.max_total_size` leaves less room). When a disk has less free space
    /// than `gc.min_free_size`, tuist_cargo_cache also collects past those budgets to free
    /// the shortfall: private state and managed targets go first, then shared
    /// store objects, even below `gc.max_size`. Active and most recently used
    /// state stays, so a disk filled by something else can remain short.
    ///
    /// An evicted object is rebuilt when a build needs it again.
    Gc(gc::GcArgs),
    /// Inspect and manage the local cache.
    ///
    /// Three subcommands change files. `export` writes a cache export. `import`
    /// adds one to the store, consumes a directory export, and can restore
    /// Cargo workspace state into an absent or empty target directory. `remove`
    /// deletes a workspace's managed target, learned incremental state, and
    /// cache claims. The rest only read.
    Cache(cache::CacheArgs),
    /// Remove a workspace's managed target and learned incremental state.
    ///
    /// tuist_cargo_cache also removes the checkout's `target` link when it points at that
    /// managed target. Shared store objects and the workspace's cache claims
    /// stay, so a later build can restore matching outputs; `tuist_cargo_cache cache remove`
    /// also forgets the claims. A managed target or learned incremental state
    /// that a running command is using is kept, with a warning. Use
    /// `tuist_cargo_cache clean --under <ROOT>` to remove every recorded workspace at or
    /// below an absolute path, including nested worktrees. `--under` and the
    /// positional workspace path cannot be used together.
    Clean(clean::CleanArgs),
    /// Move existing target directories under tuist_cargo_cache management, contents intact.
    ///
    /// tuist_cargo_cache moves each directory under the managed target root and leaves a
    /// `target` link in its place. The adopted directory then follows the same
    /// collection policy as any other managed target.
    Adopt(adopt::AdoptArgs),
    /// Watch cache activity across every build that uses this cache directory.
    ///
    /// Builds that use a different cache directory, or that run with the
    /// `events` setting off, do not appear.
    Tui(tui::TuiArgs),
    /// Show lifetime savings, pruning totals, and estimated workspace sharing.
    Stats(stats::StatsArgs),
    /// Download predicted actions from the remote cache without running Cargo.
    ///
    /// The predictions are the actions that earlier builds on this platform
    /// recorded for the same `Cargo.lock`; when that lockfile has none, tuist_cargo_cache
    /// borrows an earlier lockfile's. `tuist_cargo_cache prefetch` needs `remote.url` and a
    /// `remote.mode` that reads (`read-only` or `read-write`).
    Prefetch(prefetch::PrefetchArgs),
    /// Run a build command outside Cargo with its C and C++ compilations cached.
    ///
    /// Options for exec, such as `--project-root`, go before the command.
    /// Everything after the command name belongs to the command, including a
    /// later `--`, as in `tuist_cargo_cache exec cmake --build build -- -j8`.
    Exec(exec::ExecArgs),
    /// Hold scheduler capacity while an external command runs.
    ///
    /// This is for work such as a VM, Docker build, or another compiler that
    /// consumes the same machine resources but does not run through tuist_cargo_cache.
    /// It waits for the requested capacity, runs the command, and releases
    /// that capacity whenever the command or its tuist_cargo_cache parent exits.
    ///
    /// `--memory` is charged against `scheduler.memory`, so it needs that
    /// setting to be enabled. Specify one or both resource flags, as in
    /// `tuist_cargo_cache reserve --memory 6GiB --cpus 4 -- ./run-windows-build-in-vm.sh`.
    Reserve(reserve::ReserveArgs),
    #[usage(external_subcommand)]
    Cargo(Vec<String>),
}

/// Hand a named toolchain back to the Cargo command line it was typed on.
///
/// The word is tuist_cargo_cache's to parse and rustup's to answer: `cargo` on `PATH` is the
/// rustup shim, and `+1.91` in front of the subcommand is how it is told which
/// toolchain to run. Every path that ends in cargo puts it back exactly where
/// it was typed, so a build that names a toolchain runs the compiler it named,
/// as it did when tuist_cargo_cache forwarded the word without reading it.
fn with_toolchain(toolchain: Option<&str>, arguments: Vec<String>) -> Vec<String> {
    let Some(toolchain) = toolchain else {
        return arguments;
    };
    std::iter::once(format!("+{toolchain}"))
        .chain(arguments)
        .collect()
}

/// The name of a command that never reaches a compiler, if this is one.
///
/// A toolchain named in front of one of these is refused rather than ignored:
/// `tuist_cargo_cache +1.91 gc` reads as a request tuist_cargo_cache has no way to honour, and collecting
/// the store under whichever toolchain happened to be default is not a smaller
/// version of it. Matched exhaustively, so a command added later has to say
/// which kind it is instead of inheriting an answer.
fn compiles_nothing(command: &Commands) -> Option<&'static str> {
    match command {
        Commands::Completion { .. } => Some("completion"),
        Commands::Edit => Some("edit"),
        Commands::Setup(_) => Some("setup"),
        Commands::Settings(_) => Some("settings"),
        Commands::Gc(_) => Some("gc"),
        Commands::Cache(_) => Some("cache"),
        Commands::Clean(_) => Some("clean"),
        Commands::Adopt(_) => Some("adopt"),
        Commands::Tui(_) => Some("tui"),
        Commands::Stats(_) => Some("stats"),
        Commands::Analyze(_) => Some("analyze"),
        // Its whole subject is the C and C++ compiles of a build cargo is not
        // running, so a Rust toolchain has nothing to select here.
        Commands::Exec(_) => Some("exec"),
        Commands::Reserve(_) => Some("reserve"),
        Commands::Doctor(_) | Commands::Explain(_) | Commands::Prefetch(_) | Commands::Cargo(_) => {
            None
        }
    }
}

/// Parse the command line and run it.
/// The internal Tuist entry point forwards Cargo arguments without an tuist_cargo_cache CLI.
pub fn run_tuist_gc() -> Result<ExitCode> {
    let (config, settings) = Config::load_for_tuist()?;
    gc::run_automatic(&config, &settings.retention).map(|()| ExitCode::SUCCESS)
}

pub fn run_tuist_cargo() -> Result<ExitCode> {
    cargo::reset_cargo_started();
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let (config, mut settings) = match Config::load_for_tuist().and_then(|settings| {
        crate::storage::check_cache(&settings.0)?;
        Ok(settings)
    }) {
        Ok(settings) => settings,
        Err(error) => {
            log::debug!(
                "cache setup failed before Cargo started; running ordinary Cargo: {error:#}"
            );
            let executable = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
            return cargo::run_cargo(&executable, &arguments, std::collections::BTreeMap::new());
        }
    };
    settings.savings = crate::config::SavingsStyle::Off;
    settings.summary = crate::config::SummaryStyle::Off;
    settings.plain_output = true;
    // Executable shadow verification found a divergence on macOS. Keep libraries
    // cached, but compile native links until that boundary is qualified.
    settings.cache_links = false;
    match cargo::run(&config, &settings, &arguments) {
        Err(error) if !cargo::cargo_started() => {
            log::debug!(
                "cache setup failed before Cargo started; running ordinary Cargo: {error:#}"
            );
            let executable = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
            cargo::run_cargo(&executable, &arguments, std::collections::BTreeMap::new())
        }
        result => result,
    }
}

pub fn run() -> Result<ExitCode> {
    let original = std::env::args_os().collect::<Vec<_>>();
    if let Some(answer) = Cli::completion_request(&original[1..]) {
        print!("{answer}");
        return Ok(ExitCode::SUCCESS);
    }
    let mut cli = Cli::parse();
    let toolchain = cli.toolchain.take();
    let toolchain = toolchain.as_deref();
    if let Some(toolchain) = toolchain
        && let Some(command) = compiles_nothing(&cli.command)
    {
        eyre::bail!(
            "+{toolchain} names a toolchain to compile with, and `tuist_cargo_cache {command}` compiles nothing"
        );
    }
    if let Commands::Prefetch(args) = &mut cli.command {
        args.cargo_args = with_toolchain(toolchain, original_prefetch_arguments(&original)?);
    }
    if let Commands::Exec(args) = &mut cli.command {
        args.command = original_exec_arguments(&original)?;
    }
    if let Commands::Reserve(args) = &mut cli.command {
        args.command = original_reserve_arguments(&original)?;
    }
    if let Commands::Doctor(args) = &cli.command {
        // Doctor describes the toolchain selected at this invocation site.
        // In particular, a mise Cargo wrapper is what resolves a project-local
        // toolchain; excluding it first would make the version check fall
        // through to an unrelated Cargo later on PATH.
        return doctor::run(args, toolchain);
    }
    if let Commands::Completion { shell } = &cli.command {
        let shell = usage_rs::complete::Shell::from_name(shell)
            .ok_or_else(|| eyre::eyre!("unsupported shell: {shell}"))?;
        print!("{}", Cli::completion_script(shell));
        return Ok(ExitCode::SUCCESS);
    }
    if let Commands::Edit = cli.command {
        return edit::run();
    }
    // Settings resolve the configuration themselves, so a broken file can
    // still be read and repaired.
    if let Commands::Settings(args) = cli.command {
        return settings::run(args);
    }
    let (config, settings) = Config::load_for_cli()?;
    match cli.command {
        Commands::Completion { .. } => {
            unreachable!("completion was handled before configuration loading")
        }
        Commands::Doctor(_) => unreachable!("doctor was handled before configuration loading"),
        Commands::Edit => unreachable!("edit was handled before configuration loading"),
        Commands::Settings(_) => {
            unreachable!("settings were handled before configuration loading")
        }
        Commands::Explain(args) => {
            shim::prepare_explicit_cargo()?;
            explain::run(&config, &settings, args, toolchain)
        }
        Commands::Analyze(args) => analyze::run(&config, args),
        Commands::Setup(args) => setup::run(&args, args.action()?),
        Commands::Gc(args) if args.automatic => {
            if args.json || args.dry_run || args.max_size.is_some() {
                eyre::bail!("--automatic runs the configured sweep and takes no other option");
            }
            gc::run_automatic(&config, &settings.retention).map(|()| ExitCode::SUCCESS)
        }
        Commands::Gc(args) => gc::run(
            &config,
            args.max_size
                .map_or(config.gc.max_bytes, |requested| requested.as_u64()),
            args.dry_run,
            args.json,
            &settings.retention,
        )
        .map(|()| ExitCode::SUCCESS),
        Commands::Cache(args) => cache::run(&config, args.command),
        Commands::Clean(args) => clean::run(&config, &args),
        Commands::Adopt(args) => adopt::run(&config, &args),
        Commands::Tui(args) => tui::run(
            &config,
            args,
            settings.savings == crate::config::SavingsStyle::Quips,
        ),
        Commands::Stats(args) => stats::run(&config, args, settings.savings),
        Commands::Prefetch(args) => {
            shim::prepare_explicit_cargo()?;
            prefetch::run(&config, settings.events_max_size, &args.cargo_args)
        }
        Commands::Exec(args) => exec::run(&config, &settings, &args),
        Commands::Reserve(args) => reserve::run(&config, args),
        Commands::Cargo(arguments) => {
            shim::prepare_explicit_cargo()?;
            cargo::run(&config, &settings, &with_toolchain(toolchain, arguments))
        }
    }
}

/// Recover `tuist_cargo_cache exec`'s command exactly as it was typed.
///
/// `double_dash = "automatic"` already stops flag interpretation once the
/// command is named, which is what keeps exec from reading a `--project-root`
/// meant for the command. What it does not do is hand over the first `--` that
/// follows: the parser still consumes one, deliberately, so that a `--` can
/// unlock an argument declared as requiring one. exec declares no such
/// argument, and `cmake --build build -- -j8` needs that separator, so it is
/// taken back from the raw argv, past exec's own options.
fn original_exec_arguments(arguments: &[std::ffi::OsString]) -> Result<Vec<String>> {
    let Some(index) = arguments
        .iter()
        .position(|argument| argument == std::ffi::OsStr::new("exec"))
    else {
        eyre::bail!("could not recover exec arguments");
    };
    let mut rest = &arguments[index + 1..];
    while let Some(first) = rest.first().and_then(|argument| argument.to_str()) {
        if first == "--project-root" {
            rest = rest.get(2..).unwrap_or_default();
        } else if first.starts_with("--project-root=") {
            rest = &rest[1..];
        } else {
            break;
        }
    }
    // A separator before the command belongs to exec, and running it would
    // look for a program named `--`.
    if rest.first().is_some_and(|argument| argument == "--") {
        rest = &rest[1..];
    }
    strings(rest)
}

/// Recover `tuist_cargo_cache reserve`'s command exactly as it was typed.
///
/// Like `exec`, reserve has a command that may itself use `--`. The parser
/// consumes the first separator, so find the first non-option after reserve's
/// own options and hand every remaining word to the external command.
fn original_reserve_arguments(arguments: &[std::ffi::OsString]) -> Result<Vec<String>> {
    let Some(index) = arguments
        .iter()
        .position(|argument| argument == std::ffi::OsStr::new("reserve"))
    else {
        eyre::bail!("could not recover reserve arguments");
    };
    let mut rest = &arguments[index + 1..];
    while let Some(first) = rest.first().and_then(|argument| argument.to_str()) {
        if matches!(first, "--cpus" | "--memory" | "--priority") {
            rest = rest.get(2..).unwrap_or_default();
        } else if first.starts_with("--cpus=")
            || first.starts_with("--memory=")
            || first.starts_with("--priority=")
        {
            rest = &rest[1..];
        } else {
            break;
        }
    }
    if rest.first().is_some_and(|argument| argument == "--") {
        rest = &rest[1..];
    }
    strings(rest)
}

fn original_prefetch_arguments(arguments: &[std::ffi::OsString]) -> Result<Vec<String>> {
    let Some(index) = arguments
        .iter()
        .position(|argument| argument == std::ffi::OsStr::new("prefetch"))
    else {
        eyre::bail!("could not recover prefetch arguments");
    };
    strings(&arguments[index + 1..])
}

fn strings(arguments: &[std::ffi::OsString]) -> Result<Vec<String>> {
    arguments
        .iter()
        .map(|argument| {
            argument
                .to_str()
                .map(str::to_owned)
                .ok_or_else(|| eyre::eyre!("Cargo arguments must be valid UTF-8"))
        })
        .collect()
}

#[cfg(test)]
mod adopt_tests;
#[cfg(test)]
mod cache_tests;
#[cfg(test)]
mod cargo_tests;
#[cfg(test)]
mod dispatch_tests;
#[cfg(test)]
mod exec_tests;
#[cfg(test)]
mod gc_tests;
#[cfg(test)]
mod prefetch_tests;
#[cfg(test)]
mod reserve_tests;
#[cfg(test)]
mod settings_tests;
#[cfg(test)]
mod setup_tests;
