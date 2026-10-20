use crate::config::Config;
use eyre::Result;
use std::process::ExitCode;

#[derive(usage_rs::Args)]
pub(super) struct TuiArgs {
    /// Print one plain-text snapshot instead of taking over the terminal.
    #[usage(long)]
    once: bool,
}

pub(super) fn run(config: &Config, args: TuiArgs, cheeky: bool) -> Result<ExitCode> {
    crate::tui::run(config, args.once, cheeky)
}
