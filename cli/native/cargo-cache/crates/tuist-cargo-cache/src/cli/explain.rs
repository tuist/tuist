use super::with_toolchain;
use crate::config::{CliSettings, Config};
use eyre::Result;
use std::process::ExitCode;

#[derive(usage_rs::Args)]
#[usage(unknown_flags = "value")]
pub(super) struct ExplainArgs {
    /// Explain this workspace's most recent recorded build without running Cargo.
    ///
    /// tuist_cargo_cache reads the newest build recorded for the Cargo workspace that contains
    /// the current directory and fails when there is none; it never picks a newer
    /// build from another checkout. It compares each miss with the most recent
    /// earlier recording of that compilation unit: from this workspace when it
    /// has one, otherwise from another checkout of the same project (one whose
    /// `Cargo.lock` is identical).
    #[usage(long)]
    last: bool,
    /// Cargo subcommand, such as `build`, to run and check for cache bypasses.
    #[usage(value_name = "CARGO_COMMAND")]
    cargo_command: Option<String>,
    /// Arguments to pass to the Cargo subcommand.
    #[usage(double_dash = "preserve", value_name = "CARGO_ARGS")]
    cargo_args: Vec<String>,
}

impl ExplainArgs {
    #[cfg(test)]
    pub(super) fn is_last(&self) -> bool {
        self.last
    }

    pub(super) fn arguments(self) -> Result<Vec<String>> {
        let command = self
            .cargo_command
            .ok_or_else(|| eyre::eyre!("a Cargo command is required unless `--last` is used"))?;
        Ok(std::iter::once(command).chain(self.cargo_args).collect())
    }
}

pub(super) fn run(
    config: &Config,
    settings: &CliSettings,
    args: ExplainArgs,
    toolchain: Option<&str>,
) -> Result<ExitCode> {
    if args.last {
        if args.cargo_command.is_some() || !args.cargo_args.is_empty() {
            eyre::bail!("`--last` replays a recorded build and does not accept a Cargo command");
        }
        if let Some(toolchain) = toolchain {
            eyre::bail!(
                "+{toolchain} cannot select a toolchain for `tuist_cargo_cache explain --last`"
            );
        }
        return crate::explain::last(config);
    }
    let arguments = args.arguments()?;
    crate::explain::run_with_settings(config, settings, &with_toolchain(toolchain, arguments))
}
