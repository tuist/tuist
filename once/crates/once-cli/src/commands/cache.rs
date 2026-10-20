//! `once cache` - inspect and mutate the configured cache provider.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::ExitCode;

use anyhow::{Context, Result};
use once_cas::{ActionResult, CacheProvider, Digest};
use serde::Serialize;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use walkdir::WalkDir;

use crate::cli::{Format, Output};
use crate::render;

#[derive(Serialize)]
struct CacheEntry {
    count: u64,
    bytes: u64,
}

#[derive(Serialize)]
struct CacheStats {
    blobs: CacheEntry,
    actions: CacheEntry,
}

#[derive(Serialize)]
struct BlobPutRecord {
    digest: Digest,
}

#[derive(Serialize)]
struct BlobExistsRecord {
    digest: Digest,
    present: bool,
}

#[derive(Serialize)]
struct BlobGetRecord<'a> {
    digest: Digest,
    bytes: usize,
    output: &'a str,
}

#[derive(Serialize)]
struct ActionGetRecord {
    action: Digest,
    hit: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<ActionResult>,
}

#[derive(Serialize)]
struct ActionPutRecord {
    action: Digest,
    stored: bool,
}

#[derive(Serialize)]
struct ActionForgetRecord {
    action: Digest,
    removed: bool,
}

/// Parsed `cache hash` / `--input` argument.
#[derive(Debug)]
enum InputSpec {
    /// A file or directory on disk.
    Path(PathBuf),
    /// A literal string.
    Value(String),
    /// An environment variable, hashed as `NAME\0value`.
    EnvVar(String),
    /// Standard input (allowed at most once across all inputs).
    Stdin,
}

impl InputSpec {
    fn parse(raw: &str) -> Self {
        if raw == "-" {
            Self::Stdin
        } else if let Some(rest) = raw.strip_prefix("path:") {
            Self::Path(PathBuf::from(rest))
        } else if let Some(rest) = raw.strip_prefix("value:") {
            Self::Value(rest.to_string())
        } else if let Some(rest) = raw.strip_prefix("env:") {
            Self::EnvVar(rest.to_string())
        } else {
            Self::Path(PathBuf::from(raw))
        }
    }
}

pub async fn print_stats(cache: &CacheProvider, output: Output) -> Result<()> {
    let s = cache.stats().await?;
    let stats = CacheStats {
        blobs: CacheEntry {
            count: s.blob_count,
            bytes: s.blob_bytes,
        },
        actions: CacheEntry {
            count: s.action_count,
            bytes: s.action_bytes,
        },
    };
    let body = match output.format {
        Format::Human => format!(
            "blobs:   {} ({} bytes)\nactions: {} ({} bytes)\n",
            s.blob_count, s.blob_bytes, s.action_count, s.action_bytes,
        ),
        Format::Json | Format::Toon => render::structured(output.format, &stats)?,
    };
    let mut out = tokio::io::stdout();
    out.write_all(body.as_bytes()).await?;
    out.flush().await?;
    Ok(())
}

pub async fn put_blob(cache: &CacheProvider, path: Option<&Path>, output: Output) -> Result<()> {
    let reader = open_blob_input(path).await?;
    let digest = cache.put_stream(reader).await?;
    let record = BlobPutRecord { digest };
    let body = match output.format {
        Format::Human => format!("{digest}\n"),
        Format::Json | Format::Toon => render::structured(output.format, &record)?,
    };
    write_stdout(body.as_bytes()).await
}

async fn open_blob_input(path: Option<&Path>) -> Result<Pin<Box<dyn AsyncRead + Send + Unpin>>> {
    match path {
        Some(path) if path != Path::new("-") => {
            let file = tokio::fs::File::open(path)
                .await
                .with_context(|| format!("opening blob input {}", path.display()))?;
            Ok(Box::pin(file))
        }
        _ => Ok(Box::pin(tokio::io::stdin())),
    }
}

pub async fn exists_blob(
    cache: &CacheProvider,
    digest: Digest,
    output: Output,
) -> Result<ExitCode> {
    let present = cache.has_blob(&digest).await?;
    match output.format {
        Format::Human => {
            if present {
                Ok(ExitCode::SUCCESS)
            } else {
                Ok(ExitCode::from(1))
            }
        }
        Format::Json | Format::Toon => {
            let record = BlobExistsRecord { digest, present };
            let body = render::structured(output.format, &record)?;
            write_stdout(body.as_bytes()).await?;
            Ok(ExitCode::SUCCESS)
        }
    }
}

pub async fn get_blob(
    cache: &CacheProvider,
    digest: Digest,
    output_path: Option<&Path>,
    output: Output,
) -> Result<()> {
    let bytes = cache.get_blob(&digest).await?;
    match output_path {
        Some(path) if path != Path::new("-") => {
            write_output_file(path, &bytes).await?;
            let path_text = path.display().to_string();
            let record = BlobGetRecord {
                digest,
                bytes: bytes.len(),
                output: &path_text,
            };
            let body = match output.format {
                Format::Human if output.show_human_trailers() => {
                    format!("wrote {} bytes to {}\n", bytes.len(), path.display())
                }
                Format::Human => String::new(),
                Format::Json | Format::Toon => render::structured(output.format, &record)?,
            };
            write_stdout(body.as_bytes()).await
        }
        _ => write_stdout(&bytes).await,
    }
}

pub async fn get_action(
    cache: &CacheProvider,
    action: Option<Digest>,
    inputs: Vec<String>,
    if_success: bool,
    output: Output,
) -> Result<ExitCode> {
    let action = resolve_action_digest(action, &inputs).await?;
    let result = cache.get_action_result(&action).await?;

    if if_success {
        let succeeded = matches!(&result, Some(r) if r.exit_code == 0);
        return Ok(if succeeded {
            ExitCode::SUCCESS
        } else {
            ExitCode::from(1)
        });
    }

    let record = ActionGetRecord {
        action,
        hit: result.is_some(),
        result,
    };
    let body = match output.format {
        Format::Human => {
            if let Some(result) = &record.result {
                format!("{}\n", serde_json::to_string_pretty(result)?)
            } else {
                format!("action miss: {action}\n")
            }
        }
        Format::Json | Format::Toon => render::structured(output.format, &record)?,
    };
    write_stdout(body.as_bytes()).await?;
    Ok(ExitCode::SUCCESS)
}

#[allow(clippy::too_many_arguments)]
pub async fn put_action(
    cache: &CacheProvider,
    action: Option<Digest>,
    inputs: Vec<String>,
    exit_code: i32,
    stdout: Option<Digest>,
    stderr: Option<Digest>,
    outputs: Vec<(String, Digest)>,
    output: Output,
) -> Result<()> {
    let action = resolve_action_digest(action, &inputs).await?;
    let result = ActionResult {
        exit_code,
        stdout,
        stderr,
        outputs: BTreeMap::from_iter(outputs),
    };
    cache.put_action_result(&action, &result).await?;
    let record = ActionPutRecord {
        action,
        stored: true,
    };
    let body = match output.format {
        Format::Human if output.show_human_trailers() => format!("stored action {action}\n"),
        Format::Human => String::new(),
        Format::Json | Format::Toon => render::structured(output.format, &record)?,
    };
    write_stdout(body.as_bytes()).await
}

pub async fn forget_action(cache: &CacheProvider, action: Digest, output: Output) -> Result<()> {
    let removed = cache.forget_action(&action).await?;
    let record = ActionForgetRecord { action, removed };
    let body = match output.format {
        Format::Human if output.show_human_trailers() && removed => {
            format!("forgot action {action}\n")
        }
        Format::Human if output.show_human_trailers() => format!("action not found: {action}\n"),
        Format::Human => String::new(),
        Format::Json | Format::Toon => render::structured(output.format, &record)?,
    };
    write_stdout(body.as_bytes()).await
}

/// Resolve an action digest from either a pre-computed value or a list
/// of `--input` declarations. Clap's `ArgGroup` already enforces that
/// exactly one of the two is provided, so this never sees both filled
/// or both empty.
async fn resolve_action_digest(action: Option<Digest>, inputs: &[String]) -> Result<Digest> {
    if let Some(digest) = action {
        return Ok(digest);
    }
    let specs: Vec<InputSpec> = inputs.iter().map(|s| InputSpec::parse(s)).collect();
    validate_stdin_uniqueness(&specs)?;
    if specs.len() == 1 {
        let (digest, _) = hash_spec(&specs[0]).await?;
        return Ok(digest);
    }
    let mut parts = Vec::with_capacity(specs.len());
    for spec in &specs {
        let (digest, _) = hash_spec(spec).await?;
        parts.push(digest);
    }
    Ok(combine_digests(&parts))
}

fn validate_stdin_uniqueness(specs: &[InputSpec]) -> Result<()> {
    let stdin_count = specs
        .iter()
        .filter(|s| matches!(s, InputSpec::Stdin))
        .count();
    if stdin_count > 1 {
        anyhow::bail!(
            "`-` (stdin) may appear at most once across inputs; later occurrences would silently hash to empty"
        );
    }
    Ok(())
}

/// Hash a single input spec. Returns `(digest, byte_count)` where
/// `byte_count` is the size of the hashed payload when meaningful
/// (file content, value bytes, stdin), or `None` for synthetic inputs
/// (directories and env vars, where "bytes hashed" is less useful as a
/// progress signal).
async fn hash_spec(spec: &InputSpec) -> Result<(Digest, Option<u64>)> {
    match spec {
        InputSpec::Stdin => {
            let (digest, bytes) = hash_reader(tokio::io::stdin()).await?;
            Ok((digest, Some(bytes)))
        }
        InputSpec::Path(path) => {
            let metadata = tokio::fs::metadata(path)
                .await
                .with_context(|| format!("opening hash input {}", path.display()))?;
            if metadata.is_dir() {
                let digest = hash_directory(path).await?;
                Ok((digest, None))
            } else {
                let file = tokio::fs::File::open(path)
                    .await
                    .with_context(|| format!("opening hash input {}", path.display()))?;
                let (digest, bytes) = hash_reader(file).await?;
                Ok((digest, Some(bytes)))
            }
        }
        InputSpec::Value(s) => {
            let mut hasher = blake3::Hasher::new();
            hasher.update(s.as_bytes());
            Ok((
                Digest::from_bytes(*hasher.finalize().as_bytes()),
                Some(s.len() as u64),
            ))
        }
        InputSpec::EnvVar(name) => {
            let value = std::env::var(name).unwrap_or_default();
            let mut hasher = blake3::Hasher::new();
            hasher.update(name.as_bytes());
            hasher.update(b"\0");
            hasher.update(value.as_bytes());
            Ok((Digest::from_bytes(*hasher.finalize().as_bytes()), None))
        }
    }
}

/// Hash a directory tree deterministically. Walks every file under
/// `root` sorted by its relative path, hashes `relpath\0content\0` per
/// entry, and returns the combined BLAKE3.
///
/// Symlinks are followed; permissions are not part of the digest. Two
/// directories with the same file paths and contents produce the same
/// digest regardless of filesystem iteration order.
///
/// The whole walk + read + hash runs on a single `spawn_blocking`
/// worker. Reading each file via `tokio::fs::read` (which itself
/// dispatches to `spawn_blocking` per call) would churn the blocking
/// pool once per entry and serialise on the await; doing the work
/// inline on one blocking thread is one dispatch total and lets the
/// kernel page bytes through without async hops.
async fn hash_directory(root: &Path) -> Result<Digest> {
    let root = root.to_path_buf();
    tokio::task::spawn_blocking(move || -> Result<Digest> {
        let mut entries: Vec<(String, PathBuf)> = Vec::new();
        for entry in WalkDir::new(&root).follow_links(true).sort_by_file_name() {
            let entry = entry.with_context(|| format!("walking directory {}", root.display()))?;
            if !entry.file_type().is_file() {
                continue;
            }
            let rel = entry
                .path()
                .strip_prefix(&root)
                .expect("walkdir entries are under root");
            // Normalise the path separator so the digest is platform
            // independent.
            let rel_str = rel
                .components()
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/");
            entries.push((rel_str, entry.path().to_path_buf()));
        }
        // sort_by_file_name walks in order, but a defensive sort guards
        // against any directory entry that arrives out of order on
        // exotic filesystems.
        entries.sort_by(|a, b| a.0.cmp(&b.0));

        let mut hasher = blake3::Hasher::new();
        hasher.update(b"once.hash.directory.v1\0");
        for (rel, abs) in entries {
            let bytes = std::fs::read(&abs)
                .with_context(|| format!("reading directory entry {}", abs.display()))?;
            hasher.update(rel.as_bytes());
            hasher.update(b"\0");
            hasher.update(&bytes);
            hasher.update(b"\0");
        }
        Ok(Digest::from_bytes(*hasher.finalize().as_bytes()))
    })
    .await
    .context("joining directory walk")?
}

fn combine_digests(parts: &[Digest]) -> Digest {
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"once.hash.combine.v1\0");
    for part in parts {
        hasher.update(part.as_bytes());
    }
    Digest::from_bytes(*hasher.finalize().as_bytes())
}

async fn hash_reader<R: AsyncRead + Unpin>(mut reader: R) -> Result<(Digest, u64)> {
    let mut hasher = blake3::Hasher::new();
    let mut bytes = 0u64;
    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let n = reader.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        bytes += n as u64;
        hasher.update(&buf[..n]);
    }
    Ok((Digest::from_bytes(*hasher.finalize().as_bytes()), bytes))
}

async fn write_stdout(bytes: &[u8]) -> Result<()> {
    let mut out = tokio::io::stdout();
    out.write_all(bytes).await?;
    out.flush().await?;
    Ok(())
}

async fn write_output_file(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        tokio::fs::create_dir_all(parent)
            .await
            .with_context(|| format!("creating output directory {}", parent.display()))?;
    }
    tokio::fs::write(path, bytes)
        .await
        .with_context(|| format!("writing blob output {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn input_spec_parses_known_prefixes() {
        assert!(matches!(InputSpec::parse("-"), InputSpec::Stdin));
        assert!(matches!(
            InputSpec::parse("path:a:b"),
            InputSpec::Path(p) if p == PathBuf::from("a:b")
        ));
        assert!(matches!(
            InputSpec::parse("value:hello"),
            InputSpec::Value(s) if s == "hello"
        ));
        assert!(matches!(
            InputSpec::parse("env:FOO"),
            InputSpec::EnvVar(s) if s == "FOO"
        ));
        assert!(matches!(
            InputSpec::parse("src/lib.rs"),
            InputSpec::Path(p) if p == PathBuf::from("src/lib.rs")
        ));
    }

    #[tokio::test]
    async fn value_input_hashes_string_bytes() {
        let (d1, _) = hash_spec(&InputSpec::Value("hello".into())).await.unwrap();
        let mut hasher = blake3::Hasher::new();
        hasher.update(b"hello");
        let expected = Digest::from_bytes(*hasher.finalize().as_bytes());
        assert_eq!(d1, expected);
    }

    #[tokio::test]
    async fn env_input_includes_name_in_digest() {
        std::env::set_var("ONCE_TEST_ENV_INPUT_A", "shared-value");
        std::env::set_var("ONCE_TEST_ENV_INPUT_B", "shared-value");
        let (a, _) = hash_spec(&InputSpec::EnvVar("ONCE_TEST_ENV_INPUT_A".into()))
            .await
            .unwrap();
        let (b, _) = hash_spec(&InputSpec::EnvVar("ONCE_TEST_ENV_INPUT_B".into()))
            .await
            .unwrap();
        assert_ne!(
            a, b,
            "different env var names with the same value must hash differently"
        );
    }

    #[tokio::test]
    async fn env_input_with_unset_variable_hashes_empty_value() {
        // The variable must not exist; pick a name that's vanishingly
        // unlikely to leak in from the parent environment.
        std::env::remove_var("ONCE_TEST_ENV_INPUT_DEFINITELY_UNSET");
        let (unset, _) = hash_spec(&InputSpec::EnvVar(
            "ONCE_TEST_ENV_INPUT_DEFINITELY_UNSET".into(),
        ))
        .await
        .unwrap();
        std::env::set_var("ONCE_TEST_ENV_INPUT_DEFINITELY_UNSET", "");
        let (empty, _) = hash_spec(&InputSpec::EnvVar(
            "ONCE_TEST_ENV_INPUT_DEFINITELY_UNSET".into(),
        ))
        .await
        .unwrap();
        std::env::remove_var("ONCE_TEST_ENV_INPUT_DEFINITELY_UNSET");
        assert_eq!(unset, empty, "unset and empty must hash identically");
    }

    #[tokio::test]
    async fn directory_hash_is_deterministic_across_iterations() {
        let tmp = TempDir::new().unwrap();
        let root = tmp.path().join("tree");
        std::fs::create_dir_all(root.join("nested")).unwrap();
        std::fs::write(root.join("a.txt"), b"alpha").unwrap();
        std::fs::write(root.join("b.txt"), b"beta").unwrap();
        std::fs::write(root.join("nested/c.txt"), b"gamma").unwrap();

        let d1 = hash_directory(&root).await.unwrap();
        let d2 = hash_directory(&root).await.unwrap();
        assert_eq!(d1, d2);
    }

    #[tokio::test]
    async fn directory_hash_changes_when_content_changes() {
        let tmp = TempDir::new().unwrap();
        let root = tmp.path().join("tree");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("a.txt"), b"first").unwrap();
        let before = hash_directory(&root).await.unwrap();

        std::fs::write(root.join("a.txt"), b"second").unwrap();
        let after = hash_directory(&root).await.unwrap();
        assert_ne!(before, after);
    }

    #[tokio::test]
    async fn directory_hash_changes_when_layout_changes() {
        let tmp = TempDir::new().unwrap();
        let root = tmp.path().join("tree");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("a.txt"), b"x").unwrap();
        let before = hash_directory(&root).await.unwrap();

        // Same content but at a different path - digest must differ.
        std::fs::rename(root.join("a.txt"), root.join("b.txt")).unwrap();
        let after = hash_directory(&root).await.unwrap();
        assert_ne!(before, after);
    }

    #[test]
    fn stdin_uniqueness_rejects_duplicates() {
        let specs = vec![InputSpec::Stdin, InputSpec::Stdin];
        assert!(validate_stdin_uniqueness(&specs).is_err());
    }

    #[test]
    fn stdin_uniqueness_allows_at_most_one() {
        let specs = vec![InputSpec::Stdin, InputSpec::Value("x".into())];
        assert!(validate_stdin_uniqueness(&specs).is_ok());
    }
}
