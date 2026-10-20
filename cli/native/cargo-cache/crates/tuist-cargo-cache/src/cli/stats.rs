use crate::config::{Config, SavingsStyle};
use eyre::Result;
use std::process::ExitCode;

#[derive(usage_rs::Args)]
pub(super) struct StatsArgs {
    /// Print a stable machine-readable report, with byte counts and nanoseconds.
    #[usage(long)]
    json: bool,
}

pub(super) fn run(config: &Config, args: StatsArgs, style: SavingsStyle) -> Result<ExitCode> {
    let report = crate::stats::collect(&config.store_dir(), &config.target.root)?;
    if args.json {
        super::cache::print_json(&report)?;
    } else {
        println!("{}", report.text(style == SavingsStyle::Quips));
    }
    Ok(ExitCode::SUCCESS)
}
