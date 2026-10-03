use clap::Subcommand;

#[derive(Subcommand)]
pub enum AuthCmd {
    /// Sign in to a provider so Once can reuse its cache session.
    Login {
        /// Provider reference. Use `workspace` for the effective workspace provider.
        #[arg(long)]
        provider: String,

        /// Print the authorization URL instead of opening the browser automatically.
        #[arg(long)]
        no_browser: bool,
    },

    /// Remove the stored session for a provider.
    Logout {
        /// Provider reference. Use `workspace` for the effective workspace provider.
        #[arg(long)]
        provider: String,
    },
}

impl AuthCmd {
    pub(super) fn surface_path(&self) -> Vec<&'static str> {
        match self {
            Self::Login { .. } => vec!["login"],
            Self::Logout { .. } => vec!["logout"],
        }
    }
}
