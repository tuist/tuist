use std::{env, net::SocketAddr, path::PathBuf, sync::Arc};

use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::EnvFilter;
use tuist_codebase_search::{AppState, Codebase, Limits, router};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let root = PathBuf::from(required_environment("CODEBASE_ROOT")?);
    let revision = required_environment("CODEBASE_REVISION")?;
    let repository_url = env::var("CODEBASE_REPOSITORY_URL")
        .unwrap_or_else(|_| "https://github.com/tuist/tuist".to_string());
    let bind_address: SocketAddr = env::var("CODEBASE_BIND_ADDRESS")
        .unwrap_or_else(|_| "127.0.0.1:4000".to_string())
        .parse()?;

    let codebase = Arc::new(Codebase::new(
        root,
        revision,
        repository_url,
        Limits::default(),
    )?);
    let state = AppState::new(codebase);
    let listener = TcpListener::bind(bind_address).await?;

    info!(address = %bind_address, "codebase search service listening");

    axum::serve(listener, router(state))
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    Ok(())
}

fn required_environment(name: &str) -> Result<String, Box<dyn std::error::Error>> {
    env::var(name)
        .map_err(|_| format!("{name} must be set").into())
        .and_then(|value| {
            if value.trim().is_empty() {
                Err(format!("{name} must not be empty").into())
            } else {
                Ok(value)
            }
        })
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{SignalKind, signal};

        let mut terminate =
            signal(SignalKind::terminate()).expect("install termination signal handler");
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = terminate.recv() => {}
        }
    }

    #[cfg(not(unix))]
    let _ = tokio::signal::ctrl_c().await;
}
