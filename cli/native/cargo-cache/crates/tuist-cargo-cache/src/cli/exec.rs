use super::cargo::{absolute, account_session, inherited_environment, run_cargo};
use crate::config::{CliSettings, Config};
use crate::session::{self, CacheSession};
use crate::util::is_checkout_root;
use eyre::Result;
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(usage_rs::Args)]
pub(super) struct ExecArgs {
    /// Directory that identifies the project across checkouts.
    ///
    /// Defaults to the enclosing Git, Jujutsu, Mercurial, or Sapling checkout,
    /// or to the working directory outside one.
    #[usage(long, value_name = "DIR")]
    project_root: Option<String>,
    /// Build command and its arguments.
    // `automatic` is the wrapper spelling: once the command is named, the rest
    // of the line belongs to it, so an option exec knows is not taken from the
    // command that meant it. A plain comment rather than a doc comment,
    // because the generated CLI reference renders those and this is a note to
    // the next reader here.
    #[usage(value_name = "COMMAND", required = true, double_dash = "automatic")]
    pub(super) command: Vec<String>,
}

pub(super) fn run(config: &Config, settings: &CliSettings, args: &ExecArgs) -> Result<ExitCode> {
    let Some((program, arguments)) = args.command.split_first() else {
        eyre::bail!("exec needs a command to run");
    };
    let program: OsString = program.into();
    let working_dir = std::env::current_dir()?;
    let project_root = match &args.project_root {
        Some(root) => absolute(&working_dir, root),
        None => discover_project_root(&working_dir),
    };
    let mut config = config.clone();
    config.apply_workspace_policy(&project_root)?;
    let config = &config;
    if !config.cc {
        log::warn!("the C and C++ cache is disabled, so this command is not cached");
        return run_cargo(&program, arguments, BTreeMap::new());
    }

    crate::storage::check_cache(config)?;
    let session_dir = tempfile::Builder::new()
        .prefix("tuist_cargo_cache-session-")
        .tempdir()?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    let session_outcome = runtime.block_on(async {
        // Outside the session directory, and outside the store the collector
        // sweeps: a configure step records these paths and expects to find
        // them on the next build.
        let mut arguments: Vec<OsString> = arguments.iter().map(OsString::from).collect();
        let shims = session::install_path_shims(&config.shims_dir)?;
        // CMake is still worth a session without them: the launchers a
        // configure records reach a compiler named by path or by a versioned
        // name, and a later `cmake --build` needs the session to use them.
        if shims.is_none() && !session::cmake::is_cmake(&program) {
            log::warn!("no C or C++ compiler was found on PATH, so this command is not cached");
            return Ok((run_cargo(&program, &arguments, BTreeMap::new()), None));
        }
        let session = CacheSession::start_with_events_limit_and_gc(
            session_dir.path(),
            config,
            settings.events_max_size,
            settings.retention.min_free,
        )
        .await?;
        let mut environment = inherited_environment(|name| std::env::var(name).ok(), &working_dir);
        let run = session
            .begin_exec(
                &project_root,
                &args.command,
                shims.as_ref(),
                &mut environment,
            )
            .await;
        session.prepare_exec_cmake(&program, &mut arguments, &mut environment);

        let status = run_cargo(&program, &arguments, environment);

        // As in a cargo build: a compilation that was restored or published
        // before a later one failed is still worth remembering.
        if let Some(run) = run
            && let Err(error) = run.commit().await
        {
            log::warn!("the completed build was not fully recorded: {error}");
        }
        let stats = match session.finish().await {
            Ok(stats) => {
                crate::session::display_stats(&stats, config, settings.summary);
                Some(stats)
            }
            Err(error) => {
                log::warn!("the cache session did not shut down cleanly: {error}");
                None
            }
        };
        Ok((status, stats))
    });
    account_session(config, settings, session_outcome, None)
}

/// The root `tuist_cargo_cache exec` keys paths against: the enclosing VCS checkout, so every
/// subdirectory of one project agrees on it, or the working directory outside
/// one.
pub(super) fn discover_project_root(working_dir: &Path) -> PathBuf {
    let mut directory = working_dir;
    loop {
        if is_checkout_root(directory) {
            return directory.to_path_buf();
        }
        match directory.parent() {
            Some(parent) => directory = parent,
            None => return working_dir.to_path_buf(),
        }
    }
}
