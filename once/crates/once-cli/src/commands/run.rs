//! `once run` - execute the action(s) that produce a target.

mod action;
mod output;
mod runtime_descriptor;
mod session;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result};
use once_cas::CacheProvider;
use once_core::{Action, CacheState, RemoteExecution, RunOpts};

use self::action::action_for;
use self::runtime_descriptor::runtime_descriptor;
use crate::cli::{exit_from, Output};
use crate::commands::util::{cache_tag, find_target};

pub struct RunArgs {
    pub output: Output,
    pub runtime_rpc: bool,
    pub runtime_rpc_socket: Option<PathBuf>,
    pub remote: Option<String>,
}

pub async fn run(
    workspace: &Path,
    cache: &CacheProvider,
    target_id: &str,
    args: RunArgs,
) -> Result<ExitCode> {
    let (targets, idx) = find_target(workspace, target_id)?;
    let target = &targets[idx];

    let mut plan = action_for(workspace, target)?;
    if let Some(provider) = args.remote.as_deref() {
        set_remote(&mut plan.action, provider);
    }
    if let Some(out_dir) = &plan.output_dir {
        tokio::fs::create_dir_all(out_dir)
            .await
            .with_context(|| format!("creating output directory {}", out_dir.display()))?;
    }

    let streams_live =
        action_remote(&plan.action).is_some() && args.output.format == crate::cli::Format::Human;
    let outcome = if streams_live {
        once_core::run_with_cache_streaming(&plan.action, workspace, cache, RunOpts::default())
            .await
            .context("executing action")?
    } else {
        once_core::run_with_cache(&plan.action, workspace, cache, RunOpts::default())
            .await
            .context("executing action")?
    };

    finish_run(
        workspace,
        cache,
        &outcome,
        target_id,
        target,
        &plan.output,
        args,
        streams_live && outcome.cache == CacheState::Miss,
    )
    .await?;
    Ok(exit_from(outcome.result.exit_code))
}

#[allow(clippy::too_many_arguments)]
async fn finish_run(
    workspace: &Path,
    cache: &CacheProvider,
    outcome: &once_core::Outcome,
    target_id: &str,
    target: &once_frontend::Target,
    output_path: &str,
    args: RunArgs,
    streams_live: bool,
) -> Result<()> {
    let RunArgs {
        output,
        runtime_rpc,
        runtime_rpc_socket,
        remote: _,
    } = args;
    let stdout_blob = match outcome.result.stdout {
        Some(digest) => cache.get_blob(&digest).await?,
        None => Vec::new(),
    };
    let stderr_blob = match outcome.result.stderr {
        Some(digest) => cache.get_blob(&digest).await?,
        None => Vec::new(),
    };
    let tag = cache_tag(outcome.cache);
    let mut runtime = runtime_descriptor(target_id, target)?;
    let session = match (&mut runtime, runtime_rpc) {
        (Some(runtime), true) => Some(
            session::prepare(
                workspace,
                target_id,
                runtime,
                runtime_rpc_socket,
                &stdout_blob,
                &stderr_blob,
            )
            .await?,
        ),
        (None, true) => anyhow::bail!("--runtime-rpc requires a target with runtime metadata"),
        (_, false) => None,
    };
    let record = output::RunRecord::new(
        target_id,
        &target.kind,
        outcome,
        tag,
        output_path.to_string(),
        runtime,
    );
    output::render(output, &stdout_blob, &stderr_blob, &record, streams_live).await?;

    if let Some(session) = session {
        crate::commands::runtime::rpc(&session.dir, Some(&session.socket)).await?;
    }

    Ok(())
}

fn set_remote(action: &mut Action, provider: &str) {
    match action {
        Action::RunCommand { remote, .. } => {
            *remote = Some(RemoteExecution {
                provider: provider.to_string(),
            });
        }
    }
}

fn action_remote(action: &Action) -> Option<&RemoteExecution> {
    match action {
        Action::RunCommand { remote, .. } => remote.as_ref(),
    }
}
