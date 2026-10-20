use std::env;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result};
use once_cas::CacheProvider;
use once_core::Xdg;

use crate::cli::{self, Cli, Cmd, Output};
use crate::commands;

pub(crate) async fn dispatch(cli: Cli) -> Result<ExitCode> {
    let output = Output::new(cli.format, cli.quiet);
    if cli.list {
        return commands::surface::print(&cli.surface_path(), output)
            .await
            .map(|()| ExitCode::SUCCESS);
    }

    let Some(command) = cli.command else {
        return Ok(ExitCode::SUCCESS);
    };

    let workspace = resolve_workspace(cli.directory)?;
    let xdg = Xdg::from_env();
    Box::pin(run_command(&workspace, &xdg, output, command)).await
}

fn resolve_workspace(directory: Option<PathBuf>) -> Result<PathBuf> {
    let workspace = match directory {
        Some(directory) => {
            once_frontend::absolutize(directory).context("resolving workspace root")?
        }
        None => env::current_dir().context("resolving workspace root")?,
    };

    // A typo'd `-C` filename used to surface as a CAS write failure
    // because the CAS lived under `<workspace>/.once`. With the CAS
    // moved to `$XDG_CACHE_HOME/once/cas`, the bogus path would
    // silently run; explicit validation here keeps the loud error.
    if !workspace.is_dir() {
        anyhow::bail!(
            "once: workspace `{}` is not a directory",
            workspace.display()
        );
    }
    Ok(workspace)
}

async fn run_command(
    workspace: &Path,
    xdg: &Xdg,
    output: Output,
    command: Cmd,
) -> Result<ExitCode> {
    match command {
        Cmd::Auth { cmd } => run_auth_command(workspace, xdg, output, cmd).await,
        Cmd::Run {
            target,
            runtime_rpc,
            runtime_rpc_socket,
            remote,
            compute,
        } => {
            dispatch_run(
                workspace,
                xdg,
                output,
                target,
                runtime_rpc,
                runtime_rpc_socket,
                remote.then_some(compute),
            )
            .await
        }
        Cmd::Exec {
            script,
            env,
            cwd,
            timeout_ms,
            cache_failures,
            remote,
            compute,
            argv,
        } => {
            dispatch_exec(
                workspace,
                xdg,
                output,
                commands::exec::ExecArgs {
                    script,
                    env,
                    cwd,
                    timeout_ms,
                    cache_failures,
                    remote: remote.then_some(compute),
                    argv,
                },
            )
            .await
        }
        Cmd::Cache { cmd } => run_cache_command(workspace, xdg, output, cmd).await,
        Cmd::Toolchain {
            cmd: Some(cli::ToolchainCmd::Inspect { platform }),
        } => commands::toolchain::inspect(workspace, output, platform.as_deref())
            .await
            .map(|()| ExitCode::SUCCESS),
        Cmd::Toolchain { cmd: None } => anyhow::bail!("toolchain subcommand required"),
        Cmd::Runtime {
            cmd:
                Some(cli::RuntimeCmd::Rpc {
                    session_dir,
                    socket,
                }),
        } => commands::runtime::rpc(&session_dir, socket.as_deref())
            .await
            .map(|()| ExitCode::SUCCESS),
        Cmd::Runtime { cmd: None } => anyhow::bail!("runtime subcommand required"),
    }
}

async fn run_auth_command(
    workspace: &Path,
    xdg: &Xdg,
    output: Output,
    command: Option<cli::AuthCmd>,
) -> Result<ExitCode> {
    match command {
        Some(cli::AuthCmd::Login {
            provider,
            no_browser,
        }) => commands::auth::login(workspace, xdg, &provider, !no_browser, output)
            .await
            .map(|()| ExitCode::SUCCESS),
        Some(cli::AuthCmd::Logout { provider }) => {
            commands::auth::logout(workspace, xdg, &provider, output)
                .await
                .map(|()| ExitCode::SUCCESS)
        }
        None => anyhow::bail!("auth subcommand required"),
    }
}

async fn run_cache_command(
    workspace: &Path,
    xdg: &Xdg,
    output: Output,
    command: Option<cli::CacheCmd>,
) -> Result<ExitCode> {
    match command {
        Some(cli::CacheCmd::Stats) => {
            let cache = crate::cache_provider::resolve(workspace, xdg)?;
            commands::cache::print_stats(&cache, output)
                .await
                .map(|()| ExitCode::SUCCESS)
        }
        Some(cli::CacheCmd::Blob { cmd }) => {
            let cache = crate::cache_provider::resolve(workspace, xdg)?;
            match cmd {
                Some(cli::CacheBlobCmd::Put { path }) => {
                    commands::cache::put_blob(&cache, path.as_deref(), output)
                        .await
                        .map(|()| ExitCode::SUCCESS)
                }
                Some(cli::CacheBlobCmd::Get {
                    digest,
                    output: output_path,
                }) => commands::cache::get_blob(&cache, digest, output_path.as_deref(), output)
                    .await
                    .map(|()| ExitCode::SUCCESS),
                Some(cli::CacheBlobCmd::Exists { digest }) => {
                    commands::cache::exists_blob(&cache, digest, output).await
                }
                None => anyhow::bail!("cache blob subcommand required"),
            }
        }
        Some(cli::CacheCmd::Action { cmd }) => {
            let cache = crate::cache_provider::resolve(workspace, xdg)?;
            match cmd {
                Some(cli::CacheActionCmd::Get {
                    action,
                    inputs,
                    if_success,
                }) => commands::cache::get_action(&cache, action, inputs, if_success, output).await,
                Some(cli::CacheActionCmd::Put {
                    action,
                    inputs,
                    exit_code,
                    stdout,
                    stderr,
                    outputs,
                }) => commands::cache::put_action(
                    &cache, action, inputs, exit_code, stdout, stderr, outputs, output,
                )
                .await
                .map(|()| ExitCode::SUCCESS),
                Some(cli::CacheActionCmd::Forget { action }) => {
                    commands::cache::forget_action(&cache, action, output)
                        .await
                        .map(|()| ExitCode::SUCCESS)
                }
                None => anyhow::bail!("cache action subcommand required"),
            }
        }
        None => anyhow::bail!("cache subcommand required"),
    }
}

async fn dispatch_run(
    workspace: &Path,
    xdg: &Xdg,
    output: Output,
    target: Option<String>,
    runtime_rpc: bool,
    runtime_rpc_socket: Option<PathBuf>,
    remote: Option<String>,
) -> Result<ExitCode> {
    let cache = crate::cache_provider::resolve(workspace, xdg)?;
    run_target_command(
        workspace,
        &cache,
        output,
        target,
        runtime_rpc,
        runtime_rpc_socket,
        remote,
    )
    .await
}

async fn dispatch_exec(
    workspace: &Path,
    xdg: &Xdg,
    output: Output,
    args: commands::exec::ExecArgs,
) -> Result<ExitCode> {
    let cache = crate::cache_provider::resolve(workspace, xdg)?;
    commands::exec::exec(workspace, &cache, args, output).await
}

async fn run_target_command(
    workspace: &Path,
    cache: &CacheProvider,
    output: Output,
    target: Option<String>,
    runtime_rpc: bool,
    runtime_rpc_socket: Option<PathBuf>,
    remote: Option<String>,
) -> Result<ExitCode> {
    let target = resolve_required_target(workspace, target)?;
    commands::run::run(
        workspace,
        cache,
        &target,
        commands::run::RunArgs {
            output,
            runtime_rpc,
            runtime_rpc_socket,
            remote,
        },
    )
    .await
}

fn resolve_required_target(workspace: &Path, target: Option<String>) -> Result<String> {
    let raw = target.context("missing target")?;
    resolve_target_arg(workspace, &raw)
}

fn resolve_target_arg(workspace: &Path, raw: &str) -> Result<String> {
    once_frontend::normalize_cli_target(workspace, raw).context("resolving target argument")
}
