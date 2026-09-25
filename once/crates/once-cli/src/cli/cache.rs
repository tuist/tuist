use std::path::PathBuf;

use clap::{ArgGroup, Subcommand};
use once_cas::Digest;

#[derive(Subcommand)]
pub enum CacheCmd {
    /// Print blob and action counts plus on-disk size.
    Stats,

    /// Read and write content-addressed blobs.
    #[command(arg_required_else_help = true)]
    Blob {
        #[command(subcommand)]
        cmd: Option<CacheBlobCmd>,
    },

    /// Read and write cached action results.
    #[command(arg_required_else_help = true)]
    Action {
        #[command(subcommand)]
        cmd: Option<CacheActionCmd>,
    },
}

#[derive(Subcommand)]
pub enum CacheBlobCmd {
    /// Store bytes from a file or stdin and print their BLAKE3 digest.
    Put {
        /// File to store. Use `-` or omit the path to read stdin.
        path: Option<PathBuf>,
    },

    /// Fetch blob bytes by content digest.
    Get {
        /// Blob digest to fetch.
        #[arg(value_parser = parse_digest)]
        digest: Digest,

        /// File to write. Defaults to stdout; use `-` for stdout.
        #[arg(short, long)]
        output: Option<PathBuf>,
    },

    /// Check whether a blob exists. Exits 0 on hit, 1 on miss; with
    /// `--format json|toon`, always exits 0 and reports `present` in
    /// the structured output.
    Exists {
        /// Blob digest to probe.
        #[arg(value_parser = parse_digest)]
        digest: Digest,
    },
}

#[derive(Subcommand)]
pub enum CacheActionCmd {
    /// Fetch an action result.
    ///
    /// Identify the action either by passing its digest directly, or
    /// by declaring its inputs with `--input`; the same declaration
    /// must be used on `put` to write under the same key.
    #[command(group(
        ArgGroup::new("action_key")
            .required(true)
            .args(["action", "inputs"])
            .multiple(false)
    ))]
    Get {
        /// Pre-computed action digest.
        #[arg(value_parser = parse_digest)]
        action: Option<Digest>,

        /// Input spec (see `cache hash` for the grammar). Repeatable;
        /// inputs are hashed in order and combined into the action
        /// digest.
        #[arg(long = "input", value_name = "SPEC")]
        inputs: Vec<String>,

        /// Exit 0 only when there is a hit AND the recorded exit code
        /// is 0. On miss or on a cached failure, exit non-zero.
        #[arg(long)]
        if_success: bool,
    },

    /// Store an action result.
    ///
    /// Identify the action either by passing its digest directly, or
    /// by declaring its inputs with `--input`; the same declaration
    /// can be used on `get` to read back the result.
    #[command(group(
        ArgGroup::new("action_key")
            .required(true)
            .args(["action", "inputs"])
            .multiple(false)
    ))]
    Put {
        /// Pre-computed action digest.
        #[arg(value_parser = parse_digest)]
        action: Option<Digest>,

        /// Input spec (see `cache hash` for the grammar). Repeatable.
        #[arg(long = "input", value_name = "SPEC")]
        inputs: Vec<String>,

        /// Process exit code captured for the action. Defaults to 0
        /// since the common case is recording a success.
        #[arg(long, default_value_t = 0)]
        exit_code: i32,

        /// Optional blob digest containing captured stdout.
        #[arg(long, value_parser = parse_digest)]
        stdout: Option<Digest>,

        /// Optional blob digest containing captured stderr.
        #[arg(long, value_parser = parse_digest)]
        stderr: Option<Digest>,

        /// Declared output as `workspace/path=blob_digest`. Repeatable.
        #[arg(long = "output", value_parser = parse_output_digest)]
        outputs: Vec<(String, Digest)>,
    },

    /// Delete one cached action result.
    Forget {
        /// Action digest to remove.
        #[arg(value_parser = parse_digest)]
        action: Digest,
    },
}

impl CacheCmd {
    pub(super) fn surface_path(&self) -> Vec<&'static str> {
        match self {
            Self::Stats => vec!["stats"],
            Self::Blob { cmd } => {
                let mut path = vec!["blob"];
                if let Some(cmd) = cmd {
                    path.extend(cmd.surface_path());
                }
                path
            }
            Self::Action { cmd } => {
                let mut path = vec!["action"];
                if let Some(cmd) = cmd {
                    path.extend(cmd.surface_path());
                }
                path
            }
        }
    }
}

impl CacheBlobCmd {
    fn surface_path(&self) -> Vec<&'static str> {
        match self {
            Self::Put { .. } => vec!["put"],
            Self::Get { .. } => vec!["get"],
            Self::Exists { .. } => vec!["exists"],
        }
    }
}

impl CacheActionCmd {
    fn surface_path(&self) -> Vec<&'static str> {
        match self {
            Self::Get { .. } => vec!["get"],
            Self::Put { .. } => vec!["put"],
            Self::Forget { .. } => vec!["forget"],
        }
    }
}

fn parse_digest(raw: &str) -> std::result::Result<Digest, String> {
    Digest::from_hex(raw).ok_or_else(|| "expected a 64-character lowercase BLAKE3 digest".into())
}

fn parse_output_digest(raw: &str) -> std::result::Result<(String, Digest), String> {
    let (path, digest) = raw
        .split_once('=')
        .ok_or_else(|| "expected workspace/path=blob_digest".to_string())?;
    if path.is_empty() {
        return Err("output path must not be empty".into());
    }
    Ok((path.to_string(), parse_digest(digest)?))
}
