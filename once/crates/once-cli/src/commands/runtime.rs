//! Runtime session inspection and control.

#[cfg(unix)]
mod protocol;
#[cfg(unix)]
mod query;
#[cfg(unix)]
mod server;
#[cfg(unix)]
mod session;

#[cfg(unix)]
pub use server::rpc;

#[cfg(not(unix))]
pub async fn rpc(
    _session_dir: &std::path::Path,
    _socket: Option<&std::path::Path>,
) -> anyhow::Result<()> {
    anyhow::bail!("runtime JSON-RPC over Unix sockets is only supported on Unix platforms")
}
