//! `once` CLI entry point. Parses arguments via [`cli`], dispatches
//! to the verb modules under [`commands`], and propagates the
//! resulting exit code.

mod cache_provider;
mod cli;
mod commands;
mod dispatch;
mod render;

use std::process::ExitCode;

use clap::Parser;
use tracing_subscriber::{fmt, EnvFilter};

use cli::Cli;

#[tokio::main]
async fn main() -> ExitCode {
    let cli = Cli::parse();
    init_tracing(cli.verbose);
    match Box::pin(dispatch::dispatch(cli)).await {
        Ok(code) => code,
        Err(e) => {
            eprintln!("once: {e:#}");
            ExitCode::from(2)
        }
    }
}

fn init_tracing(verbose: u8) {
    // RUST_LOG always wins; otherwise -v sets the floor.
    let default = match verbose {
        0 => "warn",
        1 => "info",
        2 => "debug",
        _ => "trace",
    };
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default));
    fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .init();
}
