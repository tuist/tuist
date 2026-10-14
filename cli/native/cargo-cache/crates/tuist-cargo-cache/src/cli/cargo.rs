use super::gc::{schedule_sweep, take_sweep_report};
use crate::config::{CliSettings, Config, RetentionSettings, SummaryStyle};
use crate::session::{self, CacheSession};
use crate::{policy, target};
use bytesize::ByteSize;
use eyre::{Context, Result};
use std::cell::Cell;
use std::collections::BTreeMap;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use tuist_cargo_cache_core::AgentStats;

/// Marks that this machine has been told what tuist_cargo_cache set up.
///
/// A stamp of its own rather than a side effect of some other file: whether to
/// explain tuist_cargo_cache and whether to count a run's savings are unrelated questions,
/// and answering both from one file forces every change to one to reason about
/// the other.
const NOTICE_STAMP: &str = "notice/v1/explained";

thread_local! {
    static CARGO_STARTED: Cell<bool> = const { Cell::new(false) };
}

pub(super) fn reset_cargo_started() {
    CARGO_STARTED.set(false);
}
pub(super) fn cargo_started() -> bool {
    CARGO_STARTED.get()
}

pub(super) fn run(
    config: &Config,
    settings: &CliSettings,
    arguments: &[String],
) -> Result<ExitCode> {
    cargo_with_settings_bypass_log_and_roots(config, settings, arguments, None, None)
}

/// Run Cargo with roots an earlier probe already resolved.
///
/// The persistent Cargo shim probes before loading configuration so an
/// invocation outside a usable workspace can pass through untouched. Reusing
/// that result here keeps the shim from running the same `cargo metadata`
/// command twice.
pub(super) fn run_with_roots(
    config: &Config,
    settings: &CliSettings,
    arguments: &[String],
    roots: Roots,
) -> Result<ExitCode> {
    cargo_with_settings_bypass_log_and_roots(config, settings, arguments, None, Some(roots))
}

pub(crate) fn cargo_with_bypass_log(
    config: &Config,
    arguments: &[String],
    bypass_log: Option<&Path>,
) -> Result<ExitCode> {
    cargo_with_settings_bypass_log_and_roots(
        config,
        &CliSettings::default(),
        arguments,
        bypass_log,
        None,
    )
}

pub(crate) fn cargo_with_settings_and_bypass_log(
    config: &Config,
    settings: &CliSettings,
    arguments: &[String],
    bypass_log: Option<&Path>,
) -> Result<ExitCode> {
    cargo_with_settings_bypass_log_and_roots(config, settings, arguments, bypass_log, None)
}

/// Run Cargo with managed target placement and a cache session, reusing
/// previously resolved roots when supplied. Scope placement to this invocation
/// so tests and build scripts do not inherit an tuist_cargo_cache-selected target directory.
fn cargo_with_settings_bypass_log_and_roots(
    config: &Config,
    settings: &CliSettings,
    arguments: &[String],
    bypass_log: Option<&Path>,
    roots: Option<Roots>,
) -> Result<ExitCode> {
    let retention = &settings.retention;
    let summary = if cargo_is_quiet(arguments) {
        SummaryStyle::Off
    } else {
        settings.summary
    };
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    if super::launch::needs_plain_launch(arguments) {
        return super::launch::plain_launch(&cargo, arguments);
    }
    let os_arguments = arguments
        .iter()
        .map(std::ffi::OsString::from)
        .collect::<Vec<_>>();
    if super::shim::cargo_proxy_passthrough(&os_arguments) {
        return run_cargo(&cargo, arguments, BTreeMap::new());
    }
    // Only where tuist_cargo_cache can identify the linker precisely enough to key what it
    // produced. Said out loud only to somebody who asked for it: this is on
    // by default now, and a platform that cannot do it would otherwise warn
    // every build about a setting nobody chose.
    let cache_links = settings.cache_links && session::cache_links_supported();
    if settings.cache_links && !cache_links && std::env::var_os(session::CACHE_LINKS_ENV).is_some()
    {
        log::warn!("caching native links is not supported on this platform");
    }
    if cargo_help_requested(arguments) {
        return run_cargo(&cargo, arguments, BTreeMap::new());
    }
    crate::storage::check_cache(config)?;
    let working_dir = std::env::current_dir()?;
    let mut roots = match roots {
        Some(roots) => roots,
        None => {
            let target_dir_env = std::env::var_os(CARGO_TARGET_DIR_ENV);
            match cargo_roots(&cargo, arguments, target_dir_env.as_deref()) {
                Some(roots) => roots,
                None => match super::shim::failed_probe(
                    &cargo,
                    &os_arguments,
                    target_dir_env.as_deref(),
                ) {
                    super::shim::FailedProbe::Roots(roots) => *roots,
                    super::shim::FailedProbe::Passthrough => {
                        return run_cargo(&cargo, arguments, BTreeMap::new());
                    }
                    super::shim::FailedProbe::Reject
                        if std::env::var_os("TUIST_CARGO_NATIVE").is_some() =>
                    {
                        return run_cargo(&cargo, arguments, BTreeMap::new());
                    }
                    super::shim::FailedProbe::Reject => eyre::bail!(
                        "could not verify Cargo build storage: metadata probing failed; run cargo metadata --no-deps --format-version 1 with the same manifest and configuration options to diagnose it"
                    ),
                },
            }
        }
    };
    let mut config = config.clone();
    config.apply_workspace_policy(&roots.workspace_root)?;
    let eager_incremental = config.eager_incremental && !config.verify;
    let incremental = if std::env::var_os("TUIST_CARGO_NATIVE").is_some() {
        config.incremental && !eager_incremental
    } else {
        policy::incremental_allowed(config.incremental) && !eager_incremental
    };
    if config.incremental && !incremental && !eager_incremental {
        log::warn!(
            "incremental compilation is disabled here; it needs an earlier build to build on"
        );
    }
    // An enabled build stops overriding CARGO_INCREMENTAL rather than setting
    // it, so a 0 already in the environment still wins -- which CI images and
    // rust-cache set as a matter of course. Say so, because the alternative is
    // a setting that silently does nothing.
    if incremental && std::env::var("CARGO_INCREMENTAL").as_deref() == Ok("0") {
        log::warn!(
            "CARGO_INCREMENTAL=0 is set in the environment, so this build is not incremental after all"
        );
    }
    config.incremental = incremental;
    // Cargo-managed incremental already covers the inner loop, and a shadow
    // compilation has nothing to compare against if its inputs carry
    // incremental state, so learned reuse yields to both.
    let learned_incremental = policy::learned_incremental_allowed(settings.learned_incremental)
        && !incremental
        && !config.verify
        && !eager_incremental;
    let config = &config;

    // Cargo's intermediate directory usually lies outside the target, where
    // placement cannot change it, so reject it before prompting for, migrating,
    // or placing the target. One nested in the target follows the target to
    // its placed destination, so it is checked with the target after placement.
    let require_local_build_dir = |build_dir: &Path| {
        crate::storage::require_local(
            build_dir,
            "Cargo intermediate build directory",
            "CARGO_BUILD_BUILD_DIR or build.build-dir",
        )
    };
    let separate_build_dir = roots
        .build_dir
        .as_deref()
        .filter(|build_dir| **build_dir != *roots.target_dir);
    let nested_build_dir =
        separate_build_dir.filter(|build_dir| build_dir.starts_with(&roots.target_dir));
    if nested_build_dir.is_none()
        && let Some(build_dir) = separate_build_dir
    {
        require_local_build_dir(build_dir)?;
    }
    if std::fs::symlink_metadata(&roots.target_dir).is_ok_and(|metadata| metadata.is_dir()) {
        crate::storage::require_local(
            &roots.target_dir,
            "Cargo target directory",
            "CARGO_TARGET_DIR or build.target-dir",
        )?;
    }
    let existing_target = manage_existing_target(config, &roots, arguments)?;
    let default_target = roots.workspace_root.join("target");
    let placing_editor = roots.target_dir_requested
        && roots.target_dir == roots.workspace_root.join(super::RUST_ANALYZER_TARGET_DIR);
    let placement_candidate = if placing_editor {
        target::placement_candidate(config, &roots.workspace_root, &default_target, false)
    } else {
        target::placement_candidate(
            config,
            &roots.workspace_root,
            &roots.target_dir,
            roots.target_dir_requested,
        )
    };
    if existing_target.is_some() || placement_candidate {
        crate::storage::require_local(
            &config.target.root,
            "managed target directory",
            "TUIST_CARGO_CACHE_TARGET_ROOT",
        )?;
        crate::storage::require_local(
            &target::view_dir(&config.target.root, &roots.workspace_root),
            "managed target directory",
            "TUIST_CARGO_CACHE_TARGET_ROOT",
        )?;
    }
    // Held for the whole command, execution included: Cargo's own lock ends
    // with compilation, and the record refresh above ends with placement,
    // while `cargo test`, `cargo nextest run` and the program `cargo run`
    // starts all keep using the directory after both. Collection needs this
    // lock exclusively before it can remove the view.
    //
    // Taken whenever the checkout has a recorded view, not only when
    // `target.views` is on: with it off, a link an earlier placement left still
    // sends Cargo's writes into the view (see `target::touch_managed`). A
    // checkout that never had a view gets no lock file.
    let view_lease = if existing_target.is_some()
        || placement_candidate
        || target::is_recorded(&config.target.root, &roots.workspace_root)
    {
        match target::ViewLease::acquire(&config.target.root, &roots.workspace_root) {
            Ok(lease) => Some(lease),
            Err(error) => {
                log::warn!(
                    "the managed target directory is not protected from collection: {error:#}"
                );
                None
            }
        }
    } else {
        None
    };
    // Placed before the session starts, because the target directory is what
    // the shim maps out of its cache keys and it has to be the one cargo will
    // actually write to.
    let (placement, removed_target_bytes, adopted_target_bytes) = match existing_target {
        Some(ExistingTarget::Adopt) => {
            match target::adopt_existing(
                config,
                &roots.workspace_root,
                &roots.target_dir,
                roots.target_dir_requested,
            ) {
                Ok(outcome) => {
                    let adopted = outcome.managed.is_some().then_some(outcome.adopted_bytes);
                    (
                        TargetViewPlacement {
                            directory: outcome.managed,
                            touch_path: roots.target_dir.clone(),
                        },
                        None,
                        adopted,
                    )
                }
                Err(error) => {
                    // A move that could not happen is not the build's
                    // failure, so the build goes on either way.
                    match adoption_failure(&error, &roots) {
                        AdoptionFailure::NotMoved => log::debug!("{error:#}"),
                        AdoptionFailure::LeftInPlace => log::warn!(
                            "{error:#}; the build continues in the existing target directory"
                        ),
                        // The error names where the outputs were retained.
                        AdoptionFailure::Stranded => log::warn!("{error:#}"),
                    }
                    (place_target_view(config, &roots), None, None)
                }
            }
        }
        Some(ExistingTarget::Remove) => {
            let outcome = target::migrate_existing(
                config,
                &roots.workspace_root,
                &roots.target_dir,
                roots.target_dir_requested,
            )?;
            (
                TargetViewPlacement {
                    directory: outcome.managed,
                    touch_path: roots.target_dir.clone(),
                },
                outcome.removed_bytes,
                None,
            )
        }
        None => (place_target_view(config, &roots), None, None),
    };
    // Chosen after placement, because it is a directory inside the managed
    // view: a build that could not place `target/` has nowhere to put one.
    let check_lane = check_lane(config, &roots, &placement, &cargo, &working_dir, arguments);
    let lane_arguments = check_lane
        .as_ref()
        .map(|lane| lane_cargo_arguments(arguments, lane));
    if let Some(lane) = &check_lane {
        roots.target_dir.clone_from(lane);
    }
    crate::storage::require_local(
        &roots.target_dir,
        "Cargo target directory",
        "CARGO_TARGET_DIR or build.target-dir",
    )?;
    if let Some(build_dir) = nested_build_dir {
        require_local_build_dir(build_dir)?;
    }
    let managed_linker =
        crate::managed_linker::resolve(&config.linker, &config.cache_dir, &config.http, arguments)?;
    if let Some(bytes) = removed_target_bytes {
        crate::session::note(&format!(
            "tuist_cargo_cache[gc]: removed the existing target/ directory ({} logical)",
            ByteSize::b(bytes).display().iec()
        ));
    }
    if let Some(bytes) = adopted_target_bytes {
        crate::session::note(&format!(
            "tuist_cargo_cache[cache]: moved the existing target/ directory under the managed root ({} logical)",
            ByteSize::b(bytes).display().iec()
        ));
    }
    if config.target.seed
        && let Some(view) = placement.directory.as_deref()
    {
        // A check lane and the editor's checks keep profiles of their own below
        // the managed target, so they start from the same lane in another
        // checkout rather than from its build profiles.
        let lane = if placing_editor {
            super::RUST_ANALYZER_TARGET_DIR
        } else if check_lane.is_some() {
            super::CHECK_LANE_TARGET_DIR
        } else {
            "target"
        };
        let lane = Path::new(lane)
            .strip_prefix("target")
            .unwrap_or(Path::new(""));
        // The editor's placement names its own directory inside the view, so
        // its lane is found from the view itself.
        let view = if placing_editor {
            target::view_dir(&config.target.root, &roots.workspace_root)
        } else {
            view.to_path_buf()
        };
        seed_target_view(
            config,
            &cargo,
            &roots.workspace_root,
            &view,
            lane,
            arguments,
        );
    }
    if placement.directory.is_none() {
        // Placement declined, but an earlier one may have left a link this
        // build is about to write through. Keep that directory's record fresh
        // so collection does not treat it as idle.
        target::touch_managed(config, &roots.workspace_root, &placement.touch_path);
    }

    // Probed rather than assumed, and only on the one run that will say
    // something about it. Placement is best-effort, so wait until it has
    // finished and probe the directory cargo will actually use rather than
    // predicting that a managed target will win.
    if std::env::var_os("TUIST_CARGO_NATIVE").is_none()
        && !policy::is_ci()
        && !cargo_help_requested(arguments)
        && !was_explained(&config.store_dir())
    {
        let target_dir = placement.directory.as_deref().unwrap_or(&roots.target_dir);
        let reflinks = crate::util::reflinks_work(&config.cache_dir, target_dir);
        crate::session::note(&first_run_notice(config, retention, reflinks));
        mark_explained(&config.store_dir());
    }

    let session_dir = tempfile::Builder::new()
        .prefix("tuist_cargo_cache-session-")
        .tempdir()?;
    let launch = super::launch::Launch::prepare(arguments, session_dir.path())?;
    let test_runner = super::test_runner::TestRunner::prepare(
        config,
        arguments,
        &roots.workspace_root,
        session_dir.path(),
    )?;
    let cargo_jobs = cargo_job_limit(arguments);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    let session_outcome = runtime.block_on(async {
        let session = match CacheSession::start_with_jobs(
            session_dir.path(),
            config,
            cargo_jobs,
            settings.events_max_size,
            settings.retention.min_free,
        )
            .await
        {
            Ok(session) => session,
            Err(error) if session::listener_unavailable(&error) => {
                crate::session::note(&format!(
                    "tuist_cargo_cache[warning]: cache session unavailable; running Cargo without tuist_cargo_cache caching: {error:#}"
                ));
                // Protect nested Cargo calls from re-entering tuist_cargo_cache, and ensure
                // compiler wrappers cannot inherit an enclosing session that
                // this build did not start. An empty socket is deliberately
                // equivalent to an absent one to every tuist_cargo_cache shim.
                let mut environment = BTreeMap::from([
                    ("TUIST_CARGO_CACHE_DISABLE".into(), "1".into()),
                    (session::SOCKET_ENV.into(), String::new()),
                ]);
                if settings.plain_output && std::env::var_os("TUIST_CARGO_NATIVE").is_none() {
                    environment.insert("CARGO_TERM_PROGRESS_WHEN".into(), "never".into());
                }
                // The lane still applies: without the session Cargo would
                // otherwise go back to the target a build may be holding.
                let fallback = lane_arguments.as_deref().unwrap_or(arguments);
                return Ok((run_cargo(&cargo, fallback, environment), None));
            }
            Err(error) => return Err(error),
        };
        let mut environment = inherited_environment(|name| std::env::var(name).ok(), &working_dir);
        let _lease = super::launch::lease(session_dir.path(), &mut environment)?;
        if let Some(path) = bypass_log {
            let path = if path.is_absolute() {
                path.to_path_buf()
            } else {
                working_dir.join(path)
            };
            environment.insert(
                crate::session::BYPASS_LOG_ENV.into(),
                path.display().to_string(),
            );
        }
        let run = session
            .begin(
                &roots.workspace_root,
                &roots.target_dir,
                arguments,
                &mut environment,
            )
            .await;
        // Clear inherited selections, including when this build uses the system linker.
        environment.insert(session::MANAGED_LINKER_ENV.into(), String::new());
        environment.insert(session::MANAGED_TARGET_LINKERS_ENV.into(), String::new());
        if let Some(selection) = &managed_linker {
            match selection {
                crate::managed_linker::Selection::Single(executable) => {
                    environment.insert(session::MANAGED_LINKER_ENV.into(), executable.to_string_lossy().into_owned());
                }
                crate::managed_linker::Selection::Targets(executables) => {
                    environment.insert(session::MANAGED_TARGET_LINKERS_ENV.into(), serde_json::to_string(executables)?);
                }
            }
        }
        // Stated explicitly for the same reason as the session's own keys: an
        // unset value would let the shim inherit one from the parent, with no
        // way to turn it off here.
        // Keep resolved session policy separate from the user override so a
        // nested workspace can still apply its own checked-in configuration.
        environment.insert(
            session::EAGER_INCREMENTAL_ENV.into(),
            if eager_incremental { "1" } else { "0" }.into(),
        );
        environment.insert(
            session::LEARNED_INCREMENTAL_ENV.into(),
            if learned_incremental { "1" } else { "0" }.into(),
        );
        environment.insert(
            session::LEARNED_INCREMENTAL_MAX_SIZE_ENV.into(),
            settings
                .learned_incremental_max_size
                .map_or_else(|| "none".to_string(), |bytes| bytes.to_string()),
        );
        environment.insert(
            session::CACHE_LINKS_ENV.into(),
            if cache_links { "1" } else { "0" }.into(),
        );
        environment.insert(
            session::AR_DETERMINISM_ENV.into(),
            config.ar_determinism.clone(),
        );

        if let Some(launch) = &launch {
            launch.environment(&mut environment)?;
        }
        if let Some(test_runner) = &test_runner {
            test_runner.environment(&mut environment)?;
        }
        if settings.plain_output && std::env::var_os("TUIST_CARGO_NATIVE").is_none() {
            environment.insert("CARGO_TERM_PROGRESS_WHEN".into(), "never".into());
        }
        super::launch::record_overlay(&mut environment)?;
        // Placement must affect this Cargo invocation, not the environment
        // inherited by tests and build scripts. Their nested Cargo builds
        // resolve their own targets, including any caller-specified setting.
        let placed_arguments;
        let cargo_arguments = if check_lane.is_some() {
            placed_arguments = lane_cargo_arguments(arguments, &roots.target_dir);
            &placed_arguments
        } else if placement.directory.is_some() {
            placed_arguments = placed_cargo_arguments(arguments, &roots.target_dir);
            &placed_arguments
        } else {
            arguments
        };
        let status = if !settings.plain_output && super::pretty::enabled(arguments) {
            match super::pretty::run(&cargo, cargo_arguments, &environment, settings.pretty_inspect, || session.progress_stats()) {
                Ok(Some(status)) => Ok(status),
                Ok(None) => run_cargo(&cargo, cargo_arguments, environment),
                Err(error) => Err(error),
            }
        } else if super::plain_progress::eligible(arguments, std::env::var("CARGO_TERM_PROGRESS_WHEN").ok().as_deref())
            && !matches!(settings.summary, SummaryStyle::Off)
            && log::max_level() < log::LevelFilter::Debug
            && (settings.plain_output || !std::io::stderr().is_terminal())
        {
            super::plain_progress::run(&cargo, cargo_arguments, environment, || session.progress_stats())
        } else {
            run_cargo(&cargo, cargo_arguments, environment)
        };
        // The shim records a prediction only after a compilation has either
        // been restored or published successfully. Preserve that completed
        // portion even when a later compilation makes cargo fail: it is still
        // useful to the retry, and the collector must know it is reachable.
        if let Some(run) = run
            && let Err(error) = run.commit().await
        {
            log::warn!("the completed build was not fully recorded: {error}");
        }

        let stats = match session.finish().await {
            Ok(stats) => {
                crate::session::display_stats(&stats, config, summary);
                Some(stats)
            }
            Err(error) => {
                log::warn!("the cache session did not shut down cleanly: {error}");
                None
            }
        };
        Ok((status, stats))
    });
    // Finish the build session before the application takes over stderr, but
    // keep the automatic target sweep after it exits: collection must not
    // remove the executable Cargo just selected before we have started it.
    let session_outcome = match session_outcome {
        Ok((Ok(status), stats))
            if status == ExitCode::SUCCESS
                && launch.as_ref().is_some_and(|launch| launch.was_captured()) =>
        {
            Ok((launch.unwrap().run(), stats))
        }
        other => other,
    };
    // Released before the sweep is scheduled, so the collector this command
    // starts does not find the view in use by this very command, and so
    // ordinary policy applies to the view as soon as the command is over.
    drop(view_lease);
    account_session(config, settings, session_outcome, removed_target_bytes)
}

/// Anchor public artifact paths in the checkout, while the target link puts
/// the bytes in the managed view. A command-line config value is scoped to
/// Cargo itself; CARGO_TARGET_DIR would leak this choice into nested builds.
pub(super) fn placed_cargo_arguments(arguments: &[String], target: &Path) -> Vec<String> {
    let mut arguments = arguments.to_vec();
    let index = arguments
        .iter()
        .take_while(|arg| arg.starts_with('+'))
        .count();
    arguments.splice(
        index..index,
        [
            "--config".into(),
            format!(
                "build.target-dir={}",
                toml::Value::String(target.to_string_lossy().into_owned())
            ),
        ],
    );
    arguments
}

/// Send a check to its lane. Unlike the placement above, this has to reach
/// `cargo-clippy`: an external subcommand never sees the global `--config`, but
/// it forwards its own flags to the `cargo check` it runs, so the flag goes
/// right after the subcommand and ahead of anything meant for the compiler.
pub(super) fn lane_cargo_arguments(arguments: &[String], lane: &Path) -> Vec<String> {
    let mut arguments = arguments.to_vec();
    let after_subcommand = super::launch::cargo_subcommand_at(&arguments)
        .map_or(arguments.len(), |(index, _)| index + 1);
    arguments.splice(
        after_subcommand..after_subcommand,
        ["--target-dir".into(), lane.to_string_lossy().into_owned()],
    );
    arguments
}

pub(super) struct TargetViewPlacement {
    pub(super) directory: Option<PathBuf>,
    pub(super) touch_path: PathBuf,
}

/// The directory a diagnostics-only command writes to, when it should not
/// share `target/` with builds.
///
/// Cargo holds a lock on the target directory while it compiles, so a `cargo
/// clippy` started beside a `cargo build` waits for the build to finish. Checks
/// write metadata rather than the binaries a build leaves in `target/`, so they
/// can live in a directory of their own inside the managed view, the way the
/// editor's checks do. The shared cache warms both.
///
/// Only for a build that tuist_cargo_cache is placing and that nobody has directed
/// elsewhere: a flag, the environment, or Cargo's configuration naming a target
/// or build directory is the caller's choice, and one Cargo keeps outside the
/// target would leave the lock shared anyway.
pub(super) fn check_lane(
    config: &Config,
    roots: &Roots,
    placement: &TargetViewPlacement,
    cargo: &std::ffi::OsStr,
    working_dir: &Path,
    arguments: &[String],
) -> Option<PathBuf> {
    let separate_build_dir = roots
        .build_dir
        .as_deref()
        .is_some_and(|build_dir| *build_dir != *roots.target_dir);
    // The cheap questions first: this runs on every command.
    if !(config.target.lanes
        && placement.directory.is_some()
        && !roots.target_dir_requested
        && !separate_build_dir
        && roots.target_dir == roots.workspace_root.join("target"))
        || build_dir_configured(working_dir, arguments)
    {
        return None;
    }
    // What Cargo will run, not what was typed: an alias can name a target of
    // its own, which the roots probe never sees.
    let expanded = super::cargo_invocation::expanded_arguments(cargo, arguments)?;
    (matches!(
        super::launch::cargo_subcommand(&expanded),
        Some("check" | "clippy")
    ) && !target_dir_named_in(&expanded))
    .then(|| roots.workspace_root.join(super::CHECK_LANE_TARGET_DIR))
}

/// A `--target-dir` among the arguments meant for Cargo.
pub(super) fn target_dir_named_in(arguments: &[String]) -> bool {
    arguments
        .iter()
        .take_while(|argument| *argument != "--")
        .any(|argument| argument == "--target-dir" || argument.starts_with("--target-dir="))
}

/// Whether the caller named Cargo's build directory, where its lock lives.
///
/// The probe reports the directory Cargo will use either way, and one left at
/// its default is the target itself, so a setting that names the target's own
/// path is indistinguishable from none. A lane moves the target but not a
/// build directory that was set, so any setting rules a lane out.
pub(super) fn build_dir_configured(working_dir: &Path, arguments: &[String]) -> bool {
    // Checked by name: the configuration loader below reads files, and Cargo
    // lets this variable stand in for the setting.
    std::env::var_os("CARGO_BUILD_BUILD_DIR").is_some()
        || build_dir_named_in(arguments)
        || match cargo_config2::Config::load_with_cwd(invocation_dir(working_dir, arguments)) {
            Ok(config) => config.build.build_dir.is_some(),
            // Cargo will not run with configuration it cannot read either.
            Err(_) => true,
        }
}

/// The directory Cargo reads its configuration from: where it is run, moved by
/// any `-C` or `--directory`. Cargo takes both as global options, so they count
/// before or after the command, in every spelling clap accepts, and up to the
/// arguments meant for the program.
pub(super) fn invocation_dir(working_dir: &Path, arguments: &[String]) -> PathBuf {
    let mut directory = working_dir.to_path_buf();
    let mut arguments = arguments.iter().take_while(|argument| *argument != "--");
    while let Some(argument) = arguments.next() {
        let moved = if argument == "-C" || argument == "--directory" {
            arguments.next().map(String::as_str)
        } else if let Some(value) = argument.strip_prefix("--directory=") {
            Some(value)
        } else {
            argument
                .strip_prefix("-C")
                .map(|value| value.strip_prefix('=').unwrap_or(value))
        };
        if let Some(moved) = moved {
            directory = directory.join(moved);
        }
    }
    directory
}

/// A `--config` that mentions the build directory, or names a file that could.
pub(super) fn build_dir_named_in(arguments: &[String]) -> bool {
    let mut arguments = arguments.iter().take_while(|argument| *argument != "--");
    while let Some(argument) = arguments.next() {
        let value = match argument.strip_prefix("--config=") {
            Some(value) => value,
            None if argument == "--config" => match arguments.next() {
                Some(value) => value,
                None => return false,
            },
            None => continue,
        };
        if value.contains("build-dir") || !value.contains('=') {
            return true;
        }
    }
    false
}

/// Place the editor's explicit target inside the checkout's managed view.
///
/// Cargo's `--target-dir` normally opts out of placement. The exact path that
/// `tuist_cargo_cache setup` writes is different: placing its `target` parent first prevents
/// an editor-first checkout from creating a real directory that would block
/// managed targets later. Cargo still writes into the requested child, so its
/// directory lock remains independent from terminal builds.
pub(super) fn place_target_view(config: &Config, roots: &Roots) -> TargetViewPlacement {
    let default = roots.workspace_root.join("target");
    if roots.target_dir_requested
        && roots.target_dir == roots.workspace_root.join(super::RUST_ANALYZER_TARGET_DIR)
    {
        let directory = target::place(config, &roots.workspace_root, &default, false)
            .map(|_| roots.target_dir.clone());
        return TargetViewPlacement {
            directory,
            touch_path: default,
        };
    }
    TargetViewPlacement {
        directory: target::place(
            config,
            &roots.workspace_root,
            &roots.target_dir,
            roots.target_dir_requested,
        ),
        touch_path: roots.target_dir.clone(),
    }
}

/// Copy registry build units from another checkout into each profile this
/// build writes that the checkout has not built yet. `lane` is where those
/// profiles sit below the managed target: nowhere for a build, or the check
/// lane's or the editor's directory.
fn seed_target_view(
    config: &Config,
    cargo: &std::ffi::OsStr,
    workspace_root: &Path,
    view: &Path,
    lane: &Path,
    arguments: &[String],
) {
    let profiles = crate::target_seed::profile_directories(arguments);
    if profiles
        .iter()
        .all(|profile| view.join(lane).join(profile).join("build").exists())
    {
        return;
    }
    let donors = target::seed_donors(&config.target.root, workspace_root);
    if donors.is_empty() {
        return;
    }
    let Ok(lockfile) = std::fs::read_to_string(workspace_root.join("Cargo.lock")) else {
        return;
    };
    let packages = crate::target_seed::registry_packages(&lockfile);
    if packages.is_empty() {
        return;
    }
    // An older Cargo never reads units from their own directories, so copying
    // them would only cost space. Asked only on a profile's first build with
    // another checkout to copy from, and with this build's own toolchain.
    let mut version = Command::new(cargo);
    if let Some(toolchain) = arguments
        .first()
        .filter(|argument| argument.starts_with('+'))
    {
        version.arg(toolchain);
    }
    let supported = version
        .arg("-V")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .is_some_and(|version| crate::target_seed::keeps_units_in_directories(&version));
    if !supported {
        return;
    }
    let outcome = crate::target_seed::seed(view, lane, &profiles, &packages, &donors);
    if let Some(donor) = outcome.donor {
        crate::session::note(&format!(
            "tuist_cargo_cache[target]: copied {} registry build units from {}",
            outcome.units,
            donor.display()
        ));
    }
}

/// Record the session's savings and leave the store sweep behind it.
///
/// Shared by every session-running command, and placed after its runtime has
/// been dropped. The sweep itself runs in a process of its own, so a walk of
/// the whole store adds nothing to the build the user is waiting on; what the
/// previous sweep freed is said here, once.
pub(super) fn account_session(
    config: &Config,
    settings: &CliSettings,
    session_outcome: Result<(Result<ExitCode>, Option<AgentStats>)>,
    removed_target_bytes: Option<u64>,
) -> Result<ExitCode> {
    let retention = &settings.retention;
    // A session that never started still leaves collection to do, so the error
    // travels as the build's result rather than short-circuiting past the sweep.
    let (status, stats) = match session_outcome {
        Ok((status, stats)) => (status, stats),
        Err(error) => (Err(error), None),
    };
    for line in take_sweep_report(&config.store_dir()) {
        session::note(&format!("tuist_cargo_cache[gc]: {line}"));
    }
    // Removing the checkout's own `target/` on the way in freed disk too, and
    // it is the largest single reclaim a first build ever reports -- but the
    // user confirmed it, so it must not feed the counters the collection
    // brags read: that directory had not outlived anything.
    let mut delta = crate::savings::Delta {
        freed_requested_bytes: removed_target_bytes.unwrap_or_default(),
        ..crate::savings::Delta::default()
    };
    let facts = stats
        .as_ref()
        .map_or_else(crate::savings::SessionFacts::default, |stats| {
            crate::savings::SessionFacts {
                hits: stats.hits,
                avoided_compiler_ns: stats.avoided_compiler_duration_ns,
            }
        });
    if let Some(stats) = &stats {
        // A session that was never consulted did not build anything worth
        // counting as a build; storing its zeroes would dilute every average.
        if crate::session::session_was_active(stats) {
            delta.builds = 1;
        }
        delta.cached_compilations = stats.hits;
        delta.avoided_compiler_ns = stats.avoided_compiler_duration_ns;
        // Both mechanisms save the same thing: a second copy of bytes the
        // store already holds. The ledger counts them together under the name
        // it has always persisted under.
        delta.reflinked_bytes = stats
            .reflinked_output_bytes
            .saturating_add(stats.hardlinked_output_bytes);
    }
    if let Some(line) =
        crate::savings::record_and_describe(&config.store_dir(), &delta, &facts, settings.savings)
    {
        crate::session::note(&line);
    }
    // Unconditional, including after a run that built nothing: a sweep that
    // comes due during `cargo build --help` is as due as any other.
    schedule_sweep(config, retention);
    status
}

/// Run a build command outside cargo with the C and C++ shims first on PATH.
pub(super) fn was_explained(store: &Path) -> bool {
    store.join(NOTICE_STAMP).exists()
}

/// Written immediately after the notice prints, so a build that fails later
/// does not explain itself again.
pub(super) fn mark_explained(store: &Path) {
    if let Err(error) = crate::util::write_atomic(&store.join(NOTICE_STAMP), b"") {
        // Worth one line at debug: the cost is a repeated notice, and a store
        // this cannot write to has larger problems than that.
        log::debug!("the first-run notice was not recorded: {error}");
    }
}

/// What tuist_cargo_cache has arranged on this machine, said once.
///
/// A cache that manages its own disk should say so before it starts deleting
/// things, and the numbers it prints are the resolved ones rather than the
/// documented ones: budgets scale with the disk, so a fixed sentence here would
/// be wrong on most machines. A limit somebody turned off is left unmentioned
/// rather than described.
pub(super) fn first_run_notice(
    config: &Config,
    retention: &RetentionSettings,
    reflinks: bool,
) -> String {
    let mut lines = vec!["tuist_cargo_cache[setup]: first build on this machine".to_string()];
    // Collection is what the rest of this describes, so a machine that turned
    // it off is told what it has instead of what it does not.
    if config.gc.auto {
        lines.push(format!(
            "tuist_cargo_cache[setup]:   cache is {}, shared by every checkout and worktree, pruned to {}",
            config.cache_dir.display(),
            ByteSize::b(config.gc.max_bytes).display().iec(),
        ));
    } else {
        lines.push(format!(
            "tuist_cargo_cache[setup]:   cache is {}, shared by every checkout and worktree; automatic collection is off, so only `tuist_cargo_cache gc` reclaims it",
            config.cache_dir.display(),
        ));
    }
    // Only when a probe just proved it: this is a promise about what the
    // user's disk will do, and a machine on ext4 must not be promised
    // sharing that every restore will quietly turn into a copy.
    if reflinks {
        lines.push(
            "tuist_cargo_cache[setup]:   this filesystem supports reflinks, so target/ shares disk with the cache instead of copying"
                .to_string(),
        );
    }
    if config.target.views && config.gc.auto {
        let mut reasons = vec!["its checkout is gone".to_string()];
        if let Some(age) = retention.target_max_age {
            reasons.push(format!("unused for {}", crate::util::format_span(age)));
        }
        if let Some(bytes) = retention.target_max_bytes {
            reasons.push(format!("over {} total", ByteSize::b(bytes).display().iec()));
        }
        if let Some(bytes) = retention.max_total_bytes {
            reasons.push(format!(
                "combined managed data exceeds {} logical",
                ByteSize::b(bytes).display().iec(),
            ));
        }
        if retention.min_free.is_some() {
            reasons.push("the disk runs low".to_string());
        }
        lines.push(format!(
            "tuist_cargo_cache[setup]:   target/ is managed: deleted when {}",
            join_clauses(&reasons),
        ));
    }
    lines.push(
        "tuist_cargo_cache[setup]:   `tuist_cargo_cache gc --dry-run` previews cleanup; `tuist_cargo_cache settings ls gc` shows every limit"
            .to_string(),
    );

    lines.join("\n")
}

/// Join reasons as prose: "a", "a or b", "a, b, or c".
pub(super) fn join_clauses(clauses: &[String]) -> String {
    match clauses {
        [] => String::new(),
        [only] => only.clone(),
        [first, second] => format!("{first} or {second}"),
        [rest @ .., last] => format!("{}, or {last}", rest.join(", ")),
    }
}

/// What a failed adoption means for the build that attempted it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum AdoptionFailure {
    /// This build moved nothing, and `target` is no longer a real directory:
    /// a concurrent build adopted it or is partway through doing so.
    NotMoved,
    /// The outputs never moved and Cargo will build into them.
    LeftInPlace,
    /// This build moved the outputs but could not link them or put them back.
    Stranded,
}

/// Classify by what this build did rather than by what is at `target` now,
/// because a concurrent adoption leaves the path briefly empty between its
/// move and its link.
pub(super) fn adoption_failure(error: &eyre::Report, roots: &Roots) -> AdoptionFailure {
    if error.downcast_ref::<target::StrandedAdoption>().is_some() {
        AdoptionFailure::Stranded
    } else if std::fs::symlink_metadata(&roots.target_dir).is_ok_and(|metadata| metadata.is_dir()) {
        AdoptionFailure::LeftInPlace
    } else {
        AdoptionFailure::NotMoved
    }
}

/// What a build does with an existing default target directory.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ExistingTarget {
    /// Rename the directory under the managed root and keep its outputs.
    Adopt,
    /// Delete the outputs and start a managed directory in their place. Only
    /// offered when the directory cannot be renamed into the managed root.
    Remove,
}

/// Bring an existing default target directory under management.
///
/// A rename keeps every output, so it needs nobody's agreement and happens
/// whether or not anyone is at a terminal: a refusal typed into one would
/// otherwise be undone by the next build an agent runs. CI is left alone,
/// because a job's cache step saves and restores `target/` itself and would
/// save only the link. Removal loses outputs, so it is only ever asked, and a
/// non-interactive run must never wait for input.
pub(super) fn manage_existing_target(
    config: &Config,
    roots: &Roots,
    arguments: &[String],
) -> Result<Option<ExistingTarget>> {
    if cargo_help_requested(arguments) || policy::is_ci() {
        return Ok(None);
    }
    manage_existing_target_with(config, roots, |directory| {
        if !std::io::stdin().is_terminal() || !std::io::stderr().is_terminal() {
            return Ok(false);
        }
        let description = format!(
            "tuist_cargo_cache can remove {} and replace it with a managed target that is pruned after this checkout is deleted. It cannot be moved there: the managed root is on another filesystem.",
            directory.display()
        );
        // Removal deletes outputs, so a hurried Enter keeps them.
        match demand::Confirm::new("Use a managed target directory?")
            .description(&description)
            .affirmative("Remove target/")
            .negative("Keep it")
            .selected(false)
            .run()
        {
            Ok(answer) => Ok(answer),
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => Ok(false),
            Err(error) => Err(error.into()),
        }
    })
}

pub(super) fn cargo_help_requested(arguments: &[String]) -> bool {
    arguments.first().is_some_and(|argument| argument == "help")
        || arguments
            .iter()
            .any(|argument| argument == "--help" || argument == "-h")
}

/// Decide what to do with an existing target directory: move it when a
/// rename can, and otherwise ask whether to remove it.
pub(super) fn manage_existing_target_with(
    config: &Config,
    roots: &Roots,
    ask_to_remove: impl FnOnce(&Path) -> Result<bool>,
) -> Result<Option<ExistingTarget>> {
    if !target::can_remove_existing(
        config,
        &roots.workspace_root,
        &roots.target_dir,
        roots.target_dir_requested,
    ) {
        return Ok(None);
    }
    if target::can_move_existing(config, &roots.workspace_root, &roots.target_dir) {
        return Ok(Some(ExistingTarget::Adopt));
    }
    Ok(ask_to_remove(&roots.target_dir)?.then_some(ExistingTarget::Remove))
}

pub(super) fn run_cargo(
    cargo: &std::ffi::OsStr,
    arguments: &[impl AsRef<std::ffi::OsStr>],
    environment: BTreeMap<String, String>,
) -> Result<ExitCode> {
    let mut command = Command::new(cargo);
    command.args(arguments);
    command.envs(environment);
    let mut child = command
        .spawn()
        .wrap_err_with(|| format!("failed to run {}", cargo.to_string_lossy()))?;
    CARGO_STARTED.set(true);
    let status = child
        .wait()
        .wrap_err_with(|| format!("failed to wait for {}", cargo.to_string_lossy()))?;
    Ok(exit_code(status))
}

/// Cargo's quiet flag applies to tuist_cargo_cache's build summary as well as Cargo's own
/// progress. Arguments after `--` belong to rustc or the program being run.
pub(super) fn cargo_is_quiet(arguments: &[String]) -> bool {
    arguments
        .iter()
        .take_while(|argument| argument.as_str() != "--")
        .any(|argument| matches!(argument.as_str(), "-q" | "--quiet"))
}

#[cfg(unix)]
pub(super) fn exit_code(status: std::process::ExitStatus) -> ExitCode {
    use std::os::unix::process::ExitStatusExt as _;
    // A signalled cargo has no exit code of its own; report the conventional
    // 128 + signal so callers can tell it apart from a clean failure.
    match (status.code(), status.signal()) {
        (Some(code), _) => ExitCode::from(code as u8),
        (None, Some(signal)) => ExitCode::from(128u8.saturating_add(signal as u8)),
        (None, None) => ExitCode::FAILURE,
    }
}

#[cfg(not(unix))]
pub(super) fn exit_code(status: std::process::ExitStatus) -> ExitCode {
    match status.code() {
        Some(code) => ExitCode::from(code as u8),
        None => ExitCode::FAILURE,
    }
}

/// Settings the shim maps out of its cache keys.
#[derive(Debug, PartialEq, Eq)]
pub(super) struct Roots {
    pub(super) workspace_root: PathBuf,
    pub(super) target_dir: PathBuf,
    pub(super) build_dir: Option<PathBuf>,
    /// Whether a flag, environment variable, or Cargo configuration named the
    /// target directory outright.
    ///
    /// Cargo prefers `--target-dir` over `CARGO_TARGET_DIR`, so a build carrying
    /// that flag cannot be moved by setting the environment: cargo would write
    /// where the flag says while the shim had been told the managed path, and
    /// the whole build would stop keying against anything it could reuse. The
    /// value can equal the default location and still have been asked for, so
    /// comparing paths cannot answer this.
    pub(super) target_dir_requested: bool,
}

/// Carry rustc wrappers the caller already configured into the session.
///
/// The session records them so the shim can defer to them; without this a
/// workspace wrapper is mistaken for rustc because Cargo nests it inside
/// `RUSTC_WRAPPER`.
pub(super) fn inherited_environment(
    get_env: impl Fn(&str) -> Option<String>,
    working_dir: &Path,
) -> BTreeMap<String, String> {
    let mut environment = BTreeMap::new();
    if let Some(wrapper) = get_env("RUSTC_WRAPPER").filter(|value| !value.is_empty()) {
        environment.insert("RUSTC_WRAPPER".into(), wrapper);
    }
    if let Some(wrapper) = get_env("RUSTC_WORKSPACE_WRAPPER").filter(|value| !value.is_empty()) {
        environment.insert("RUSTC_WORKSPACE_WRAPPER".into(), wrapper);
    }
    // Cargo gives every shim its own working directory, so a relative
    // destination would scatter records across crate directories -- or fail
    // outright in a read-only registry checkout. Resolve it here, against the
    // directory the user typed it in, like every other path the shim receives.
    if let Some(log) = get_env(crate::session::BYPASS_LOG_ENV).filter(|value| !value.is_empty()) {
        environment.insert(
            crate::session::BYPASS_LOG_ENV.into(),
            absolute(working_dir, &log).display().to_string(),
        );
    }
    environment
}

/// Resolve the workspace root and target directory cargo will actually use.
///
/// Cargo is the only authority: the target directory can come from the
/// environment, a flag, or cargo's own configuration, and `--manifest-path` can
/// move the whole build elsewhere. Inference is kept as a fallback, and costs
/// only cache hits when it is wrong, since an unmapped path bypasses.
pub(super) fn resolve_roots(
    cargo: &std::ffi::OsStr,
    arguments: &[String],
    working_dir: &Path,
) -> Roots {
    resolve_roots_with(
        cargo,
        arguments,
        working_dir,
        std::env::var_os(CARGO_TARGET_DIR_ENV),
    )
}

/// The environment name cargo reads for the target directory. It outranks a
/// config-set `build.target-dir`, so both the probe and the fallback below have
/// to agree on one value for it.
pub(super) const CARGO_TARGET_DIR_ENV: &str = "CARGO_TARGET_DIR";

/// [`resolve_roots`] with the ambient `CARGO_TARGET_DIR` passed in rather than
/// read here, so a caller can resolve as if the variable were unset.
pub(super) fn resolve_roots_with(
    cargo: &std::ffi::OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<std::ffi::OsString>,
) -> Roots {
    let resolved = tuist_cargo_cache_cargo::resolve(cargo, arguments, working_dir, target_dir_env);
    Roots {
        workspace_root: resolved.workspace_root,
        target_dir: resolved.target_dir,
        build_dir: resolved.build_dir,
        target_dir_requested: resolved.target_dir_requested,
    }
}

/// Cargo resolves a relative directory against the invocation directory.
pub(super) fn absolute(working_dir: &Path, value: &str) -> PathBuf {
    let path = PathBuf::from(value);
    if path.is_absolute() {
        path
    } else {
        working_dir.join(path)
    }
}

/// Cargo options that belong before the subcommand and change what `cargo
/// metadata` would report. `-C` moves the whole invocation, and `--config` can
/// set `build.target-dir` outright, so a probe that drops them describes a
/// different tree than the one being built.
#[cfg(test)]
pub(super) const PROBE_GLOBAL_FLAGS: [&str; 3] = ["-C", "--config", "-Z"];

/// Collect the occurrences of `flags` from `arguments`, preserving order and
/// repeats. Cargo allows `--flag value`, `--flag=value`, and, for the short
/// forms, `-Zvalue`.
#[cfg(test)]
pub(super) fn forwarded_flags(arguments: &[String], flags: &[&str]) -> Vec<String> {
    let mut forwarded = Vec::new();
    let mut remaining = arguments.iter();
    while let Some(argument) = remaining.next() {
        if let Some((flag, value)) = argument
            .split_once('=')
            .filter(|(flag, _)| flags.contains(flag))
        {
            forwarded.push(flag.to_string());
            forwarded.push(value.to_string());
        } else if flags.contains(&argument.as_str()) {
            if let Some(value) = remaining.next() {
                forwarded.push(argument.clone());
                forwarded.push(value.clone());
            }
        } else if flags
            .iter()
            .any(|flag| flag.len() == 2 && argument.len() > 2 && argument.starts_with(flag))
        {
            forwarded.push(argument.clone());
        }
    }
    forwarded
}

pub(super) fn cargo_roots(
    cargo: &std::ffi::OsStr,
    arguments: &[String],
    target_dir_env: Option<&std::ffi::OsStr>,
) -> Option<Roots> {
    let working_dir = std::env::current_dir().ok()?;
    let resolved = tuist_cargo_cache_cargo::resolve_reported(
        cargo,
        arguments,
        &working_dir,
        target_dir_env.map(std::ffi::OsStr::to_os_string),
    )?;
    Some(Roots {
        workspace_root: resolved.workspace_root,
        target_dir: resolved.target_dir,
        build_dir: resolved.build_dir,
        target_dir_requested: resolved.target_dir_requested,
    })
}

#[cfg(test)]
pub(super) fn parse_cargo_roots(metadata: &[u8]) -> Option<Roots> {
    let metadata: serde_json::Value = serde_json::from_slice(metadata).ok()?;
    Some(Roots {
        workspace_root: PathBuf::from(metadata.get("workspace_root")?.as_str()?),
        target_dir: PathBuf::from(metadata.get("target_directory")?.as_str()?),
        build_dir: metadata
            .get("build_directory")
            .and_then(|value| value.as_str())
            .map(PathBuf::from),
        // What cargo reports has folded configuration in already, so it cannot
        // say whether anyone asked. The caller's flags, environment, and Cargo
        // configuration answer that, and `resolve_roots_with` reads them itself.
        target_dir_requested: false,
    })
}
/// Cargo's own compiler-process limit, when it narrows the scheduler pool.
///
/// The CLI wins over `CARGO_BUILD_JOBS`, including `default`, just as it does
/// in Cargo. Invalid values are left for Cargo to diagnose and do not make tuist_cargo_cache
/// invent a second interpretation.
fn cargo_job_limit(arguments: &[String]) -> Option<u64> {
    cargo_job_limit_with(
        arguments,
        std::env::var("CARGO_BUILD_JOBS").ok().as_deref(),
        std::thread::available_parallelism().map_or(1, |cpus| cpus.get() as u64),
    )
}

pub(super) fn cargo_job_limit_with(
    arguments: &[String],
    environment: Option<&str>,
    logical_cpus: u64,
) -> Option<u64> {
    let mut cli_value = None;
    let mut cli_seen = false;
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        if argument == "--" {
            break;
        }
        let value = if argument == "-j" || argument == "--jobs" {
            index += 1;
            arguments.get(index).map(String::as_str)
        } else if let Some(value) = argument.strip_prefix("--jobs=") {
            Some(value)
        } else if let Some(value) = argument.strip_prefix("-j=") {
            Some(value)
        } else {
            argument
                .strip_prefix("-j")
                .filter(|value| !value.is_empty())
        };
        if let Some(value) = value {
            cli_seen = true;
            cli_value = resolve_cargo_jobs(value, logical_cpus);
        }
        index += 1;
    }
    if cli_seen {
        cli_value
    } else {
        environment.and_then(|value| resolve_cargo_jobs(value, logical_cpus))
    }
}

fn resolve_cargo_jobs(value: &str, logical_cpus: u64) -> Option<u64> {
    if value == "default" {
        return None;
    }
    let jobs = value.parse::<i64>().ok()?;
    if jobs > 0 {
        return Some(jobs as u64);
    }
    if jobs < 0 {
        return i128::from(logical_cpus)
            .checked_add(i128::from(jobs))
            .filter(|jobs| *jobs > 0)
            .and_then(|jobs| u64::try_from(jobs).ok());
    }
    None
}
