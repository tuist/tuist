use super::cargo::resolve_roots;
use crate::config::Config;
use crate::session::CacheSession;
use bytesize::ByteSize;
use eyre::Result;
use std::process::ExitCode;

#[derive(usage_rs::Args)]
#[usage(unknown_flags = "value", dont_delimit_trailing_values = true)]
pub(super) struct PrefetchArgs {
    /// Cargo command and arguments, such as `build --workspace --release`.
    ///
    /// tuist_cargo_cache uses them only to find the workspace. It selects the predictions by
    /// the workspace's `Cargo.lock`, not by the command, so `build`, `test`,
    /// and `clippy` share them whatever their profile or features.
    #[usage(value_name = "CARGO_ARGS", required = true)]
    pub(super) cargo_args: Vec<String>,
}

pub(super) fn run(
    config: &Config,
    events_max_size: Option<u64>,
    arguments: &[String],
) -> Result<ExitCode> {
    validate_prefetch_config(config)?;
    crate::storage::check_cache(config)?;
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let working_dir = std::env::current_dir()?;
    let roots = resolve_roots(&cargo, arguments, &working_dir);
    let session_dir = tempfile::Builder::new()
        .prefix("tuist_cargo_cache-prefetch-")
        .tempdir()?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    let stats = runtime.block_on(async {
        let session =
            CacheSession::start_with_events_limit(session_dir.path(), config, events_max_size)
                .await?;
        session.prefetch(&roots.workspace_root, arguments).await?;
        session.finish().await
    })?;
    if stats.prefetch_runs == 0 {
        println!("no recorded actions for this workspace and Cargo command");
    } else {
        println!(
            "prefetched {} actions; {} downloaded and {} stored locally",
            stats.prefetched_actions,
            ByteSize::b(stats.downloaded_bytes).display().iec(),
            ByteSize::b(stats.stored_bytes).display().iec()
        );
    }
    Ok(ExitCode::SUCCESS)
}

pub(super) fn validate_prefetch_config(config: &Config) -> Result<()> {
    if config.remote.url.is_none() {
        eyre::bail!("remote prefetch requires remote.url or TUIST_CARGO_CACHE_REMOTE_URL");
    }
    if !config.remote.mode.reads() {
        eyre::bail!("remote prefetch requires a read-capable remote.mode");
    }
    Ok(())
}
