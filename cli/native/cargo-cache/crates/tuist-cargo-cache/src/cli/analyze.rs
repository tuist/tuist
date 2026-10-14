use crate::config::Config;
use eyre::Result;
use std::process::ExitCode;

#[derive(usage_rs::Args)]
pub(super) struct AnalyzeArgs {}

pub(super) fn run(config: &Config, _args: AnalyzeArgs) -> Result<ExitCode> {
    crate::analyze::run(config)
}
