//! Hold machine-wide scheduler capacity while an external command runs.

use super::cargo::exit_code;
use crate::config::{Config, SchedulerPriority};
use bytesize::ByteSize;
use eyre::{Result, WrapErr};
use std::process::{Command, ExitCode};

#[derive(usage_rs::Args)]
pub(super) struct ReserveArgs {
    /// CPU permits to hold while the command runs.
    #[usage(long, value_name = "N")]
    cpus: Option<u64>,
    /// Memory to hold from the configured scheduler budget.
    #[usage(long, value_name = "SIZE")]
    memory: Option<ByteSize>,
    /// Whether this reservation yields capacity to normal-priority builds.
    #[usage(long, default = "normal")]
    priority: SchedulerPriority,
    /// Command and arguments to run while capacity is reserved.
    #[usage(value_name = "COMMAND", required = true, double_dash = "automatic")]
    pub(super) command: Vec<String>,
}

pub(super) fn run(config: &Config, args: ReserveArgs) -> Result<ExitCode> {
    if std::env::var_os("TUIST_CARGO_CACHE_RESERVE_WORKER").is_some() {
        return run_direct(config, args);
    }

    let mut worker = Command::new(std::env::current_exe()?);
    worker.arg("reserve");
    if let Some(cpus) = args.cpus {
        worker.args(["--cpus", &cpus.to_string()]);
    }
    if let Some(memory) = args.memory {
        worker.args(["--memory", &format!("{}B", memory.as_u64())]);
    }
    worker.args(["--priority", args.priority.as_str(), "--"]);
    worker.args(&args.command);
    worker.env("TUIST_CARGO_CACHE_RESERVE_WORKER", "1");
    Ok(exit_code(
        worker.status().wrap_err("failed to start reserve worker")?,
    ))
}

fn run_direct(config: &Config, args: ReserveArgs) -> Result<ExitCode> {
    let Some((program, arguments)) = args.command.split_first() else {
        eyre::bail!("reserve needs a command to run")
    };
    let Some(pool) = crate::scheduler::reservation_pool(config, args.priority) else {
        eyre::bail!("reserve needs scheduler.enabled")
    };
    let _permit = pool.reserve(args.cpus, args.memory.map(|memory| memory.as_u64()))?;
    let status = external_command(program, arguments)
        // Nested tuist_cargo_cache work is covered by this reservation. Letting its compiler
        // shims take new permits would deadlock when this lease fills the pool.
        .status()
        .wrap_err_with(|| format!("failed to run {program}"))?;
    Ok(exit_code(status))
}

pub(super) fn external_command(program: &str, arguments: &[String]) -> Command {
    let mut command = Command::new(program);
    command
        .args(arguments)
        // Nested tuist_cargo_cache work is covered by this reservation. Letting its compiler
        // shims take new permits would deadlock when this lease fills the pool.
        .env(crate::scheduler::SCHED_DIR_ENV, "")
        .env(crate::scheduler::SCHED_DISABLE_ENV, "1")
        // The private worker marker applies only to this reservation. A nested
        // `tuist_cargo_cache reserve` must start its own worker so its lease follows its
        // command even when this external command launches it in the background.
        .env_remove("TUIST_CARGO_CACHE_RESERVE_WORKER");
    command
}
