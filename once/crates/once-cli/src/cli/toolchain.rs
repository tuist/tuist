use clap::Subcommand;

#[derive(Subcommand)]
pub enum ToolchainCmd {
    /// Print the toolchain contract derived from mise.toml.
    Inspect {
        /// Mise platform key to inspect, e.g. linux-x64. Defaults to
        /// the current host platform.
        #[arg(long)]
        platform: Option<String>,
    },
}

impl ToolchainCmd {
    pub(super) fn surface_path(&self) -> Vec<&'static str> {
        match self {
            Self::Inspect { .. } => vec!["inspect"],
        }
    }
}
