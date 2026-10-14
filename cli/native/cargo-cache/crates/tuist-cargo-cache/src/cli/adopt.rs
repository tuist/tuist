use crate::config::Config;
use crate::target;
use bytesize::ByteSize;
use eyre::{Result, WrapErr as _};
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(usage_rs::Args)]
pub(super) struct AdoptArgs {
    /// Search below each path for Cargo checkouts with a target directory.
    ///
    /// The search skips symbolic links and hidden or `target` directories.
    #[usage(short = 'r', long)]
    pub(super) recursive: bool,
    /// Show what would be adopted without moving anything.
    #[usage(long)]
    pub(super) dry_run: bool,
    /// Cargo checkouts to adopt, or directories to search with `--recursive`.
    ///
    /// Defaults to the current directory.
    #[usage(value_name = "PATH")]
    pub(super) paths: Vec<PathBuf>,
}

/// What happened to one checkout's target directory.
#[derive(Debug, PartialEq, Eq)]
pub(super) enum Adoption {
    /// The outputs now sit under the managed target root, or would after a
    /// dry run.
    Adopted { target: PathBuf, bytes: u64 },
    /// Nothing was changed, for the stated reason.
    Skipped { target: PathBuf, reason: String },
}

pub(super) fn run(config: &Config, args: &AdoptArgs) -> Result<ExitCode> {
    let working_dir = std::env::current_dir()?;
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let paths = if args.paths.is_empty() {
        vec![working_dir.clone()]
    } else {
        args.paths
            .iter()
            .map(|path| {
                if path.is_absolute() {
                    path.clone()
                } else {
                    working_dir.join(path)
                }
            })
            .collect()
    };
    let mut checkouts = Vec::new();
    for path in &paths {
        if args.recursive {
            checkouts.extend(find_checkouts(path)?);
        } else {
            checkouts.push(path.clone());
        }
    }
    if checkouts.is_empty() {
        println!("no target directories to adopt");
        return Ok(ExitCode::SUCCESS);
    }

    let verb = if args.dry_run {
        "would adopt"
    } else {
        "adopted"
    };
    let mut adopted = 0_u64;
    let mut adopted_bytes = 0_u64;
    let mut failures = 0_u64;
    for checkout in &checkouts {
        match adopt_checkout(config, &cargo, checkout, args.dry_run) {
            Ok(Adoption::Adopted { target, bytes }) => {
                adopted += 1;
                adopted_bytes = adopted_bytes.saturating_add(bytes);
                println!(
                    "{verb} {} ({} logical)",
                    target.display(),
                    ByteSize::b(bytes).display().iec()
                );
            }
            Ok(Adoption::Skipped { target, reason }) => {
                println!("left {} alone: {reason}", target.display());
            }
            Err(error) => {
                failures += 1;
                log::error!(
                    "{} was not adopted: {error:#}",
                    checkout.join("target").display()
                );
            }
        }
    }
    if checkouts.len() > 1 {
        println!(
            "{verb} {adopted} target directories ({} logical)",
            ByteSize::b(adopted_bytes).display().iec()
        );
    }
    Ok(if failures == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

/// Bring one checkout's default target directory under management.
///
/// This resolves the checkout as a build run inside it would, so the view
/// recorded here is the one that build will look for. It skips whatever
/// placement would skip and reports the reason instead of logging it: a
/// configured target directory, a workspace member whose outputs belong to its
/// root, a checkout with managed targets turned off, or a directory the managed
/// target root cannot hold without copying.
pub(super) fn adopt_checkout(
    config: &Config,
    cargo: &OsStr,
    checkout: &Path,
    dry_run: bool,
) -> Result<Adoption> {
    let target = checkout.join("target");
    let skipped = |reason: String| {
        Ok(Adoption::Skipped {
            target: target.clone(),
            reason,
        })
    };
    match std::fs::symlink_metadata(&target) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            return skipped("it is a link, not a directory of outputs".to_string());
        }
        Ok(metadata) if metadata.is_dir() => {}
        Ok(_) => return skipped("it is not a directory".to_string()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return skipped("there is no target directory".to_string());
        }
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("could not inspect {}", target.display()));
        }
    }
    if !checkout.join("Cargo.toml").is_file() {
        return skipped("there is no Cargo.toml beside it".to_string());
    }
    // Resolved with the checkout as the working directory, as a build run
    // inside it would resolve, so the workspace root Cargo reports is the one
    // that build will look for and everything below keys on it.
    let target_dir_env = std::env::var_os(super::cargo::CARGO_TARGET_DIR_ENV);
    let Some(roots) =
        tuist_cargo_cache_cargo::resolve_reported(cargo, &[], checkout, target_dir_env)
    else {
        return skipped("Cargo could not describe the checkout".to_string());
    };
    if !same_directory(&roots.workspace_root, checkout) {
        return skipped(format!(
            "it belongs to a member of the workspace at {}, whose target directory is the one Cargo uses",
            roots.workspace_root.display()
        ));
    }
    if roots.target_dir_requested || roots.target_dir != roots.workspace_root.join("target") {
        return skipped(
            "a flag, environment variable, or Cargo configuration names the target directory"
                .to_string(),
        );
    }
    let mut config = config.clone();
    config.apply_workspace_policy(&roots.workspace_root)?;
    if !config.target.views {
        return skipped("managed targets are turned off for this checkout".to_string());
    }
    let target = roots.workspace_root.join("target");
    if !target::can_move_existing(&config, &roots.workspace_root, &target) {
        return skipped(format!(
            "it is not on the same filesystem as the managed target root {}",
            config.target.root.display()
        ));
    }
    crate::storage::require_local(
        &config.target.root,
        "managed target directory",
        "TUIST_CARGO_CACHE_TARGET_ROOT",
    )?;
    if dry_run {
        return Ok(Adoption::Adopted {
            bytes: target::tree_bytes(&target),
            target,
        });
    }
    let outcome = target::adopt_existing(&config, &roots.workspace_root, &target, false)?;
    if outcome.managed.is_none() {
        eyre::bail!("a managed target directory could not be placed for it");
    }
    Ok(Adoption::Adopted {
        target,
        bytes: outcome.adopted_bytes,
    })
}

/// Whether two paths name one directory.
///
/// Both sides are compared in resolved form, because neither can be compared
/// to the other as spelled. Cargo reports the workspace root as a physical
/// path, while the checkout may have been named through a link. On Windows, a
/// resolved path also carries a verbatim prefix that Cargo's answer omits.
/// Each side resolves on its own, so a path that cannot be resolved is still
/// compared to the other's resolved form rather than dragging both back to
/// their spelling.
fn same_directory(a: &Path, b: &Path) -> bool {
    let resolve = |path: &Path| std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    resolve(a) == resolve(b)
}

/// Every directory under `root` holding a `Cargo.toml` and a real `target`
/// directory, `root` itself included, in path order.
///
/// The search skips hidden directories, `target` directories, and anything
/// reached through a link. That keeps a search of a home directory out of
/// hidden editor caches and package registries, and stops it from following a
/// link back up the tree. A directory below `root` that cannot be read is
/// logged as a warning and skipped rather than ending the search, but an
/// unreadable `root` is an error.
pub(super) fn find_checkouts(root: &Path) -> Result<Vec<PathBuf>> {
    let mut found = Vec::new();
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        let entries = match std::fs::read_dir(&directory) {
            Ok(entries) => entries,
            Err(error) if directory == root => {
                return Err(error)
                    .wrap_err_with(|| format!("could not search {}", directory.display()));
            }
            Err(error) => {
                log::warn!("{} was not searched: {error}", directory.display());
                continue;
            }
        };
        let mut has_manifest = false;
        let mut has_target = false;
        let mut children = Vec::new();
        for entry in entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(error) => {
                    log::warn!("{} was not fully searched: {error}", directory.display());
                    continue;
                }
            };
            let name = entry.file_name();
            let Ok(kind) = entry.file_type() else {
                continue;
            };
            if name == "Cargo.toml" && kind.is_file() {
                has_manifest = true;
            } else if name == "target" && kind.is_dir() {
                has_target = true;
            } else if kind.is_dir() && !name.to_string_lossy().starts_with('.') {
                children.push(entry.path());
            }
        }
        if has_manifest && has_target {
            found.push(directory);
        }
        // Popped from the back, so reverse order here yields path order.
        children.sort();
        pending.extend(children.into_iter().rev());
    }
    Ok(found)
}
