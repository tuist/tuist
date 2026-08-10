//! The `kura` command-line surface.
//!
//! Resource nouns live at the root (`kura peer list`, `kura runtime inspect`)
//! rather than under a grouping word, matching the shape `consul`, `nomad`,
//! `vault`, and `etcdctl` settled on. Running `kura` with no arguments still
//! serves, because the release image's ENTRYPOINT invokes the binary bare and
//! the Helm chart sets no `command`/`args`.

use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "kura", version, about = "Low-latency cache mesh")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Run the cache node (the default when invoked with no subcommand).
    Serve,
    /// Inspect the live state of a running node.
    #[command(subcommand)]
    Runtime(RuntimeCommand),
    /// Inspect node readiness and rollout state.
    #[command(subcommand)]
    Node(NodeCommand),
    /// Inspect mesh membership.
    #[command(subcommand)]
    Peer(PeerCommand),
    /// Inspect the replication outbox.
    #[command(subcommand)]
    Outbox(OutboxCommand),
    /// Manage in-memory caches.
    #[command(subcommand)]
    Cache(CacheCommand),
    /// Manage namespaces.
    #[command(subcommand)]
    Namespace(NamespaceCommand),
    /// Manage in-flight multipart uploads.
    #[command(subcommand)]
    Upload(UploadCommand),
}

#[derive(Debug, Subcommand)]
pub enum CacheCommand {
    /// Trim an in-memory cache down to a target size. Requires a grant.
    Trim {
        /// Which cache to trim.
        #[arg(long, value_enum)]
        cache: TrimmableCache,
        /// Target size: bytes for the manifest cache, entries for the others.
        #[arg(long = "to")]
        target: usize,
        #[command(flatten)]
        connect: ConnectArgs,
        #[command(flatten)]
        grant: GrantArgs,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum TrimmableCache {
    Manifest,
    Existence,
    SegmentHandle,
}

impl TrimmableCache {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Manifest => "manifest",
            Self::Existence => "existence",
            Self::SegmentHandle => "segment-handle",
        }
    }
}

#[derive(Debug, Subcommand)]
pub enum NamespaceCommand {
    /// Delete a namespace across the mesh. Requires a grant.
    ///
    /// Writes a tombstone and enqueues the delete to every replication target,
    /// so it converges instead of being undone by the next bootstrap pass.
    Delete {
        namespace_id: String,
        #[command(flatten)]
        connect: ConnectArgs,
        #[command(flatten)]
        grant: GrantArgs,
    },
}

#[derive(Debug, Subcommand)]
pub enum UploadCommand {
    /// Abort a multipart upload, releasing its staged parts. Requires a grant.
    Abort {
        upload_id: String,
        #[command(flatten)]
        connect: ConnectArgs,
        #[command(flatten)]
        grant: GrantArgs,
    },
}

/// Proof of elevation for a mutating command.
///
/// Kept separate from `ConnectArgs` so that read commands cannot accidentally
/// accept it and mutating ones cannot accidentally omit it.
#[derive(Debug, Clone, clap::Args)]
pub struct GrantArgs {
    /// A signed grant authorizing this write, from whatever authority the
    /// deployment configured the node to trust.
    #[arg(long, env = "KURA_GRANT")]
    pub grant: Option<String>,
}

#[derive(Debug, Subcommand)]
pub enum RuntimeCommand {
    /// Print a point-in-time report of everything the process holds in memory.
    Inspect(ConnectArgs),
    /// Print the configuration the node actually resolved, with secrets redacted.
    Config(ConnectArgs),
    /// Print counters for the on-disk store (outbox, uploads, segments, caches).
    Store(ConnectArgs),
}

#[derive(Debug, Subcommand)]
pub enum NodeCommand {
    /// Print readiness, traffic state, and the reasons behind them.
    Status(ConnectArgs),
}

#[derive(Debug, Subcommand)]
pub enum PeerCommand {
    /// List every peer the node knows about and how it learned of each one.
    List(ConnectArgs),
}

#[derive(Debug, Subcommand)]
pub enum OutboxCommand {
    /// Print outbox depth and per-target replication backoff.
    Stats(ConnectArgs),
}

/// How to reach the node, and how to render what it says.
///
/// The data directory has an environment-variable fallback so that an operator
/// who has shelled into a running container needs no arguments at all: the pod
/// spec already exports `KURA_DATA_DIR`.
///
/// Inspecting a *remote* node is deliberately absent for now. It would mean
/// mounting these routes on the internal listener and building an mTLS client,
/// and the case it serves (debugging node B from node A) is covered today by
/// exec'ing into node B.
#[derive(Debug, Clone, clap::Args)]
pub struct ConnectArgs {
    /// Data directory of the node to inspect. Its runtime file names the
    /// control socket to connect to.
    #[arg(long, env = "KURA_DATA_DIR")]
    pub data_dir: Option<PathBuf>,

    /// Output format. Defaults to `text` on a terminal and `json` otherwise, so
    /// piping into `jq` needs no flag.
    #[arg(long, value_enum)]
    pub output: Option<OutputFormat>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum OutputFormat {
    Text,
    Json,
}

impl ConnectArgs {
    /// Resolves the requested format, falling back to whether stdout is a
    /// terminal.
    pub fn resolved_output(&self) -> OutputFormat {
        self.output.unwrap_or_else(|| {
            if stdout_is_terminal() {
                OutputFormat::Text
            } else {
                OutputFormat::Json
            }
        })
    }
}

#[cfg(unix)]
fn stdout_is_terminal() -> bool {
    // SAFETY: `isatty` only reads the descriptor's terminal association.
    unsafe { libc::isatty(libc::STDOUT_FILENO) == 1 }
}

#[cfg(not(unix))]
fn stdout_is_terminal() -> bool {
    false
}

#[cfg(test)]
mod tests {
    use clap::CommandFactory as _;

    use super::*;

    #[test]
    fn command_tree_is_valid() {
        Cli::command().debug_assert();
    }

    #[test]
    fn bare_invocation_has_no_subcommand() {
        let cli = Cli::try_parse_from(["kura"]).expect("bare invocation should parse");
        assert!(
            cli.command.is_none(),
            "bare `kura` must stay serve: the release image ENTRYPOINT passes no arguments"
        );
    }

    #[test]
    fn serve_subcommand_parses() {
        let cli = Cli::try_parse_from(["kura", "serve"]).expect("serve should parse");
        assert!(matches!(cli.command, Some(Command::Serve)));
    }

    #[test]
    fn resource_nouns_live_at_the_root() {
        for arguments in [
            vec!["kura", "runtime", "inspect"],
            vec!["kura", "runtime", "config"],
            vec!["kura", "runtime", "store"],
            vec!["kura", "node", "status"],
            vec!["kura", "peer", "list"],
            vec!["kura", "outbox", "stats"],
        ] {
            Cli::try_parse_from(&arguments)
                .unwrap_or_else(|error| panic!("{arguments:?} should parse: {error}"));
        }
    }

    #[test]
    fn data_dir_is_optional_so_the_environment_can_supply_it() {
        let cli = Cli::try_parse_from(["kura", "runtime", "inspect"])
            .expect("inspect should parse without a data dir");
        let Some(Command::Runtime(RuntimeCommand::Inspect(args))) = cli.command else {
            panic!("expected runtime inspect");
        };
        assert!(args.output.is_none());
    }

    #[test]
    fn explicit_output_overrides_terminal_detection() {
        let cli = Cli::try_parse_from(["kura", "node", "status", "--output", "json"])
            .expect("status should parse");
        let Some(Command::Node(NodeCommand::Status(args))) = cli.command else {
            panic!("expected node status");
        };
        assert_eq!(args.resolved_output(), OutputFormat::Json);
    }
}
