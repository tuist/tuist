use super::cache::cache_workspace_root;
use super::cargo::{absolute, cargo_roots};
use super::exec::discover_project_root;
use crate::config::Config;
use crate::target;
use bytesize::ByteSize;
use eyre::Result;
use std::collections::BTreeSet;
use std::path::{Component, Path, PathBuf};
use std::process::ExitCode;

const MAX_CLEAN_WORKERS: usize = 8;

#[derive(usage_rs::Args)]
#[usage(group("clean_scope"))]
pub(super) struct CleanArgs {
    /// Workspace root whose managed target and learned incremental state are
    /// removed. Defaults to the current workspace.
    #[usage(group = "clean_scope")]
    workspace: Option<PathBuf>,
    /// Remove managed targets and learned incremental state recorded at or
    /// below this absolute path. The path does not need to exist. Mutually
    /// exclusive with WORKSPACE.
    #[usage(long, value_name = "ROOT", group = "clean_scope")]
    under: Option<PathBuf>,
}

pub(super) fn run(config: &Config, args: &CleanArgs) -> Result<ExitCode> {
    if let Some(root) = args.under.as_deref() {
        return run_under(config, root);
    }

    let working_dir = std::env::current_dir()?;
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let workspace = match args.workspace.as_deref() {
        Some(requested) => {
            let requested = absolute(&working_dir, &requested.to_string_lossy());
            cache_workspace_root(&cargo, &requested)
        }
        None => cargo_roots(&cargo, &[], None)
            .map(|roots| roots.workspace_root)
            .unwrap_or_else(|| discover_project_root(&working_dir)),
    };
    let mut config = config.clone();
    config.apply_workspace_policy(&workspace)?;

    let report = clean_workspace(&config, &workspace);
    print_report(&report);
    if !report.errors.is_empty() {
        eyre::bail!("{}", report.errors.join("\n"));
    }
    Ok(ExitCode::SUCCESS)
}

fn run_under(config: &Config, root: &Path) -> Result<ExitCode> {
    let root = normalize_under_root(root)?;
    let workspaces = workspaces_under(config, &root)?;
    if workspaces.is_empty() {
        println!("nothing found under {}", root.display());
        return Ok(ExitCode::SUCCESS);
    }

    // Cleanup only reads cache roots from Config. Workspace policy changes
    // build behavior, not these roots, and deleted checkouts may have no
    // .tuist_cargo_cache.toml left to read.
    let workers = std::thread::available_parallelism()
        .map_or(1, usize::from)
        .min(MAX_CLEAN_WORKERS)
        .min(workspaces.len());
    let chunk_size = workspaces.len().div_ceil(workers);
    let reports = std::thread::scope(|scope| {
        let handles = workspaces
            .chunks(chunk_size)
            .map(|chunk| {
                scope.spawn(move || {
                    chunk
                        .iter()
                        .map(|workspace| clean_workspace(config, workspace))
                        .collect::<Vec<_>>()
                })
            })
            .collect::<Vec<_>>();
        handles
            .into_iter()
            .flat_map(|handle| handle.join().expect("clean worker panicked"))
            .collect::<Vec<_>>()
    });

    let mut failed = false;
    for report in &reports {
        print_report(report);
        for error in &report.errors {
            failed = true;
            eprintln!("tuist_cargo_cache[error]: {error}");
        }
    }
    Ok(if failed {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    })
}

fn workspaces_under(config: &Config, root: &Path) -> Result<Vec<PathBuf>> {
    let mut workspaces = BTreeSet::new();
    for workspace in
        target::workspaces(&config.target.root)?
            .into_iter()
            .chain(crate::incremental::workspaces(
                &config.cache_dir.join("incremental"),
            )?)
    {
        if workspace.is_absolute() && normalize_absolute_path(&workspace).starts_with(root) {
            workspaces.insert(workspace);
        }
    }
    Ok(workspaces.into_iter().collect())
}

fn normalize_under_root(root: &Path) -> Result<PathBuf> {
    if !root.is_absolute() {
        eyre::bail!("--under requires an absolute path: {}", root.display());
    }
    let root = normalize_absolute_path(root);
    if !root
        .components()
        .any(|component| matches!(component, Component::Normal(_)))
    {
        eyre::bail!("--under cannot be a filesystem root");
    }
    Ok(root)
}

fn normalize_absolute_path(path: &Path) -> PathBuf {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(_) | Component::RootDir | Component::Normal(_) => {
                normalized.push(component.as_os_str());
            }
            Component::CurDir => {}
            Component::ParentDir => {
                if matches!(
                    normalized.components().next_back(),
                    Some(Component::Normal(_))
                ) {
                    normalized.pop();
                }
            }
        }
    }
    normalized
}

#[derive(Default)]
struct WorkspaceReport {
    lines: Vec<String>,
    warnings: Vec<String>,
    errors: Vec<String>,
}

fn clean_workspace(config: &Config, workspace: &Path) -> WorkspaceReport {
    let mut report = WorkspaceReport::default();
    match crate::incremental::remove_workspace(&config.cache_dir.join("incremental"), workspace) {
        Ok(crate::incremental::RemoveOutcome::Removed(bytes)) => {
            record_savings(config, bytes);
            report.lines.push(format!(
                "removed learned incremental state for {} ({})",
                workspace.display(),
                ByteSize::b(bytes).display().iec()
            ));
        }
        Ok(crate::incremental::RemoveOutcome::Active) => report.warnings.push(format!(
            "{} is being built, so its learned incremental state was kept",
            workspace.display()
        )),
        Ok(crate::incremental::RemoveOutcome::Missing) => {}
        Err(error) => report.errors.push(format!(
            "could not remove learned incremental state for {}: {error:#}",
            workspace.display()
        )),
    }

    match target::remove_workspace(&config.target.root, workspace) {
        Ok(target::RemoveOutcome::Removed(bytes)) => {
            record_savings(config, bytes);
            report.lines.push(format!(
                "removed the managed target for {} ({})",
                workspace.display(),
                ByteSize::b(bytes).display().iec()
            ));
        }
        Ok(target::RemoveOutcome::Active) => report.warnings.push(format!(
            "{} is in use by a running command, so its managed target was kept",
            workspace.display()
        )),
        Ok(target::RemoveOutcome::Missing) => report
            .lines
            .push(format!("no managed target for {}", workspace.display())),
        Err(error) => report.errors.push(format!(
            "could not remove the managed target for {}: {error:#}",
            workspace.display()
        )),
    }
    report
}

fn record_savings(config: &Config, bytes: u64) {
    if bytes > 0 {
        crate::savings::record_quietly(
            &config.store_dir(),
            &crate::savings::Delta {
                freed_requested_bytes: bytes,
                ..crate::savings::Delta::default()
            },
        );
    }
}

fn print_report(report: &WorkspaceReport) {
    for line in &report.lines {
        println!("{line}");
    }
    for warning in &report.warnings {
        log::warn!("{warning}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(cache: &Path) -> Config {
        Config::for_test(cache)
    }

    fn workspace(path: &Path) -> PathBuf {
        std::fs::create_dir_all(path).unwrap();
        path.to_path_buf()
    }

    fn add_incremental(config: &Config, workspace: &Path) -> PathBuf {
        let state =
            crate::incremental::touch(&config.cache_dir.join("incremental"), workspace).unwrap();
        let directory = state.directory.clone();
        std::fs::write(directory.join("state"), b"learned state").unwrap();
        drop(state);
        directory
    }

    fn add_target(config: &Config, workspace: &Path) -> PathBuf {
        let directory = target::place(config, workspace, &workspace.join("target"), false)
            .expect("target view should be placed");
        std::fs::write(directory.join("artifact"), b"managed target").unwrap();
        directory
    }

    fn clean_under(config: &Config, root: &Path) -> Result<ExitCode> {
        run_under(config, root)
    }

    #[test]
    fn cleans_nested_worktrees_and_keeps_a_sibling_with_a_shared_prefix() {
        let directory = tempfile::tempdir().unwrap();
        let config = config(&directory.path().join("cache"));
        let root = directory.path().join("workspace/abc");
        let first = workspace(&root.join("lanes/goldenfix"));
        let second = workspace(&root.join("bifrost/.claude/worktrees/x"));
        let sibling = workspace(&directory.path().join("workspace/abcd/lanes/other"));
        let first_incremental = add_incremental(&config, &first);
        let second_incremental = add_incremental(&config, &second);
        let sibling_incremental = add_incremental(&config, &sibling);
        let first_target = add_target(&config, &first);
        let second_target = add_target(&config, &second);
        let sibling_target = add_target(&config, &sibling);

        let root = normalize_under_root(&root).unwrap();
        let matched = workspaces_under(&config, &root).unwrap();
        assert_eq!(matched.len(), 2);
        assert!(matched.contains(&first));
        assert!(matched.contains(&second));
        assert_eq!(clean_under(&config, &root).unwrap(), ExitCode::SUCCESS);

        assert!(!first_incremental.exists());
        assert!(!second_incremental.exists());
        assert!(sibling_incremental.exists());
        assert!(!first_target.exists());
        assert!(!second_target.exists());
        assert!(sibling_target.exists());
    }

    #[test]
    fn cleans_a_workspace_recorded_only_by_incremental_state() {
        let directory = tempfile::tempdir().unwrap();
        let config = config(&directory.path().join("cache"));
        let root = directory.path().join("deleted/session");
        let workspace = workspace(&root.join("bifrost/.claude/worktrees/x"));
        let incremental = add_incremental(&config, &workspace);

        assert_eq!(clean_under(&config, &root).unwrap(), ExitCode::SUCCESS);
        assert!(!incremental.exists());
        assert!(target::workspaces(&config.target.root).unwrap().is_empty());
    }

    #[test]
    fn an_active_target_is_kept_while_other_targets_are_removed() {
        let directory = tempfile::tempdir().unwrap();
        let config = config(&directory.path().join("cache"));
        let root = directory.path().join("session");
        let active = workspace(&root.join("active"));
        let inactive = workspace(&root.join("inactive"));
        let active_target = add_target(&config, &active);
        let inactive_target = add_target(&config, &inactive);
        let active_lease = target::ViewLease::acquire(&config.target.root, &active).unwrap();

        assert_eq!(clean_under(&config, &root).unwrap(), ExitCode::SUCCESS);

        assert!(active_target.exists());
        assert!(std::fs::read_link(active.join("target")).is_ok());
        assert!(!inactive_target.exists());
        assert!(std::fs::symlink_metadata(inactive.join("target")).is_err());
        drop(active_lease);
    }

    #[test]
    fn a_removal_error_fails_after_the_other_workspaces_are_cleaned() {
        let directory = tempfile::tempdir().unwrap();
        let config = config(&directory.path().join("cache"));
        let root = directory.path().join("session");
        let broken = workspace(&root.join("broken"));
        let healthy = workspace(&root.join("healthy"));
        let broken_incremental = add_incremental(&config, &broken);
        let broken_target = add_target(&config, &broken);
        let healthy_target = add_target(&config, &healthy);
        std::fs::remove_dir_all(&broken_target).unwrap();
        std::fs::write(&broken_target, b"not a directory").unwrap();

        assert_eq!(clean_under(&config, &root).unwrap(), ExitCode::FAILURE);

        assert!(!broken_incremental.exists());
        assert!(!healthy_target.exists());
        assert!(target::workspaces(&config.target.root).unwrap().is_empty());
    }

    #[test]
    fn rejects_relative_roots_and_the_filesystem_root() {
        let directory = tempfile::tempdir().unwrap();
        let config = config(&directory.path().join("cache"));

        assert!(clean_under(&config, Path::new("relative/root")).is_err());
        assert!(clean_under(&config, Path::new("/")).is_err());
    }

    #[test]
    fn normalizes_under_roots_lexically() {
        let directory = tempfile::tempdir().unwrap();
        let expected = directory.path().join("session");
        let root = directory.path().join("outer/../session/.");

        assert_eq!(normalize_under_root(&root).unwrap(), expected);
    }

    #[test]
    fn cleans_recorded_workspaces_when_the_root_no_longer_exists() {
        let directory = tempfile::tempdir().unwrap();
        let config = config(&directory.path().join("cache"));
        let root = directory.path().join("deleted/session");
        let workspace = workspace(&root.join("lanes/goldenfix"));
        let incremental = add_incremental(&config, &workspace);
        let managed = add_target(&config, &workspace);
        std::fs::remove_dir_all(&root).unwrap();
        assert!(!root.exists());

        assert_eq!(clean_under(&config, &root).unwrap(), ExitCode::SUCCESS);
        assert!(!incremental.exists());
        assert!(!managed.exists());
        assert!(
            crate::incremental::workspaces(&config.cache_dir.join("incremental"))
                .unwrap()
                .is_empty()
        );
        assert!(target::workspaces(&config.target.root).unwrap().is_empty());
    }
}
