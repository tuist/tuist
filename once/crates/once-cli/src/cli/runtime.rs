use std::path::PathBuf;

use clap::Subcommand;

#[derive(Subcommand)]
pub enum RuntimeCmd {
    /// Serve the local runtime JSON-RPC endpoint for a session directory.
    Rpc {
        /// Runtime session directory containing session.json and logs.
        session_dir: PathBuf,

        /// Socket path. Defaults to `<session-dir>/control.sock`.
        #[arg(long)]
        socket: Option<PathBuf>,
    },
}

impl RuntimeCmd {
    pub(super) fn surface_path(&self) -> Vec<&'static str> {
        match self {
            Self::Rpc { .. } => vec!["rpc"],
        }
    }
}
