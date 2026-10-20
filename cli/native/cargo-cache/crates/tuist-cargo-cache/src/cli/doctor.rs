use crate::config::Config;
use eyre::Result;
use std::process::ExitCode;

#[derive(usage_rs::Args)]
pub(super) struct DoctorArgs {
    /// Print a stable machine-readable report.
    #[usage(long)]
    json: bool,
}

pub(super) fn run(args: &DoctorArgs, toolchain: Option<&str>) -> Result<ExitCode> {
    crate::doctor::run_loaded(Config::load(), args.json, toolchain)
}
