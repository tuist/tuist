use super::*;
use crate::store;

fn project(workspace_root: PathBuf) -> store::ProjectUsage {
    store::ProjectUsage {
        workspace_root,
        identities: 1,
        action_bytes: 2,
        target_bytes: 3,
        live: true,
    }
}

#[test]
fn interactive_removal_only_removes_selected_workspaces() {
    let selected = PathBuf::from("/workspace/selected");
    let skipped = PathBuf::from("/workspace/skipped");
    let mut removed = Vec::new();

    let exit = cache_remove_interactive_with(
        &[project(selected.clone()), project(skipped)],
        |_| Ok(vec![selected.clone()]),
        |_| Ok(true),
        |workspace| {
            removed.push(workspace.to_owned());
            Ok(())
        },
    )
    .unwrap();

    assert_eq!(exit, ExitCode::SUCCESS);
    assert_eq!(removed, [selected]);
}

#[test]
fn interactive_removal_cancellation_removes_nothing() {
    let selected = PathBuf::from("/workspace/selected");

    let exit = cache_remove_interactive_with(
        &[project(selected.clone())],
        |_| Ok(vec![selected]),
        |_| Ok(false),
        |_| panic!("cancelled removal must not run"),
    )
    .unwrap();

    assert_eq!(exit, ExitCode::SUCCESS);
}

#[test]
fn interactive_removal_with_no_selection_removes_nothing() {
    let exit = cache_remove_interactive_with(
        &[project(PathBuf::from("/workspace/selected"))],
        |_| Ok(Vec::new()),
        |_| panic!("empty selection must not be confirmed"),
        |_| panic!("empty selection must not be removed"),
    )
    .unwrap();

    assert_eq!(exit, ExitCode::SUCCESS);
}

#[test]
fn interactive_removal_with_no_recorded_workspaces_removes_nothing() {
    let exit = cache_remove_interactive_with(
        &[],
        |_| panic!("empty workspace list must not be selected"),
        |_| panic!("empty workspace list must not be confirmed"),
        |_| panic!("empty workspace list must not be removed"),
    )
    .unwrap();

    assert_eq!(exit, ExitCode::SUCCESS);
}

#[test]
fn interactive_removal_continues_after_a_workspace_fails() {
    let first = PathBuf::from("/workspace/first");
    let second = PathBuf::from("/workspace/second");
    let mut attempted = Vec::new();

    let exit = cache_remove_selected_with(&[first.clone(), second.clone()], |workspace| {
        attempted.push(workspace.to_owned());
        if workspace == first {
            eyre::bail!("target is busy");
        }
        Ok(())
    });

    assert_eq!(exit, ExitCode::FAILURE);
    assert_eq!(attempted, [first, second]);
}

#[test]
fn cache_remove_requires_exactly_one_mode() {
    let missing = ["tuist_cargo_cache", "cache", "remove"].map(std::ffi::OsStr::new);
    assert!(Cli::try_parse_from(&missing).is_err());

    let conflicting = [
        "tuist_cargo_cache",
        "cache",
        "remove",
        "--interactive",
        "/workspace",
    ]
    .map(std::ffi::OsStr::new);
    assert!(Cli::try_parse_from(&conflicting).is_err());

    let interactive =
        ["tuist_cargo_cache", "cache", "remove", "--interactive"].map(std::ffi::OsStr::new);
    let cli = Cli::try_parse_from(&interactive).unwrap();
    let Commands::Cache(CacheArgs {
        command: CacheCommands::Remove(_),
    }) = cli.command
    else {
        panic!("interactive cache removal should parse");
    };
}

#[test]
fn cache_removal_uses_the_workspace_identity_reported_by_cargo() {
    let directory = tempfile::tempdir().unwrap();
    let requested = directory.path().join("workspace-alias");
    std::fs::create_dir_all(&requested).unwrap();
    std::fs::write(
        requested.join("Cargo.toml"),
        "[package]\nname = \"cache-remove-root\"\nversion = \"0.0.0\"\n",
    )
    .unwrap();
    std::fs::create_dir(requested.join("src")).unwrap();
    std::fs::write(requested.join("src/lib.rs"), "").unwrap();

    let reported = cache_workspace_root(std::ffi::OsStr::new("cargo"), &requested);

    let metadata = std::process::Command::new("cargo")
        .args([
            "metadata",
            "--no-deps",
            "--format-version",
            "1",
            "--manifest-path",
        ])
        .arg(requested.join("Cargo.toml"))
        .output()
        .unwrap();
    assert!(metadata.status.success());
    assert_eq!(
        reported,
        parse_cargo_roots(&metadata.stdout).unwrap().workspace_root
    );
}

#[test]
fn cache_removal_preserves_the_requested_spelling_when_cargo_cannot_resolve_it() {
    let requested = PathBuf::from("/workspace/that/does/not/exist");

    assert_eq!(
        cache_workspace_root(std::ffi::OsStr::new("definitely-not-cargo"), &requested),
        requested
    );
}
