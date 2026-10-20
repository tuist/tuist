use super::*;
use crate::config::TargetSettings;

fn test_config(root: &Path, views: bool) -> Config {
    Config {
        cache_dir: root.join("cache"),
        shims_dir: root.join("cache").join("shims"),
        stats_report: None,
        ar_determinism: "auto".into(),
        verify: false,
        verify_sample_rate: 0,
        incremental: false,
        eager_incremental: false,
        share_out_dir: false,
        restore_hardlink: true,
        share_workspace_root: false,
        build_script_execution: false,
        events: false,
        cc: false,
        cc_store_path_specific: true,
        forward_compiler_notifications: true,
        remote: Default::default(),
        http: Default::default(),
        gc: Default::default(),
        scheduler: Default::default(),
        linker: Default::default(),
        target: TargetSettings {
            views,
            lanes: true,
            seed: false,
            root: root.join("targets"),
        },
    }
}

/// A checkout with the default target directory, ready to be managed.
fn checkout(root: &Path, name: &str) -> PathBuf {
    let workspace = root.join(name);
    std::fs::create_dir_all(&workspace).unwrap();
    workspace
}

#[test]
fn places_the_default_target_directory_under_the_managed_root() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");

    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();

    assert!(managed.is_absolute(), "the shim maps only absolute roots");
    assert!(managed.starts_with(views_root(&config.target.root)));
    assert!(managed.is_dir());
    assert_eq!(
        std::fs::read_link(workspace.join("target")).unwrap(),
        managed,
        "the workspace should still have a target directory to reach"
    );
    assert_eq!(stats(&config.target.root).unwrap().views, 1);
}

#[test]
fn concurrent_retirements_get_distinct_staging_paths() {
    let directory = tempfile::tempdir().unwrap();
    let view = directory.path().join("v1/0123456789abcdef");

    let (first, second) = std::thread::scope(|scope| {
        let first = scope.spawn(|| removal_path(&view));
        let second = scope.spawn(|| removal_path(&view));
        (first.join().unwrap(), second.join().unwrap())
    });
    assert_ne!(first, second);
}

#[cfg(unix)]
#[test]
fn a_directory_only_gitignore_still_hides_the_managed_link() {
    let directory = tempfile::tempdir().unwrap();
    let spelling = tempfile::tempdir().unwrap();
    let repository = spelling.path().join("repository");
    symlink_dir(directory.path(), &repository).unwrap();
    let workspace = checkout(&repository, "project");
    assert!(
        Command::new("git")
            .current_dir(directory.path())
            .args(["init", "--quiet"])
            .status()
            .unwrap()
            .success()
    );
    std::fs::write(repository.join(".gitignore"), "target/\n").unwrap();
    let config = test_config(directory.path(), true);

    place(&config, &workspace, &workspace.join("target"), false).unwrap();

    assert_eq!(
        std::fs::read_to_string(repository.join(".gitignore")).unwrap(),
        "target/\n",
        "tuist_cargo_cache should not change a tracked project file"
    );
    assert!(
        Command::new("git")
            .current_dir(&repository)
            .args(["check-ignore", "--quiet", "--no-index", "--"])
            .arg("project/target")
            .status()
            .unwrap()
            .success(),
        "the repository-local exclude should match the symlink"
    );
    let exclude = std::fs::read_to_string(directory.path().join(".git/info/exclude")).unwrap();
    assert!(exclude.lines().any(|line| line == "/project/target"));
}

#[test]
fn placing_a_target_directory_twice_reaches_the_same_one() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");

    let first = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    let second = place(&config, &workspace, &workspace.join("target"), false).unwrap();

    assert_eq!(first, second);
    assert_eq!(stats(&config.target.root).unwrap().views, 1);
}

#[test]
fn changing_roots_preserves_a_target_while_cargo_is_writing_diagnostics() {
    let directory = tempfile::tempdir().unwrap();
    let first = test_config(&directory.path().join("first"), true);
    let second = test_config(&directory.path().join("second"), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    let old = place(&first, &workspace, &target, false).unwrap();
    let fingerprint = old.join("release/.fingerprint/example-hash");
    std::fs::create_dir_all(&fingerprint).unwrap();
    let mut cargo_lock = fslock::LockFile::open(&old.join("release/.cargo-lock")).unwrap();
    cargo_lock.lock().unwrap();

    assert!(place(&second, &workspace, &target, false).is_none());

    assert_eq!(std::fs::read_link(&target).unwrap(), old);
    // Cargo may retain the resolved old path while consuming rustc's output.
    std::fs::write(fingerprint.join("output-lib-example"), b"warning\n").unwrap();
    assert!(old.with_extension("json").is_file());
}

#[test]
fn replaces_an_outdated_managed_target_link() {
    let directory = tempfile::tempdir().unwrap();
    let first = test_config(&directory.path().join("first"), true);
    let second = test_config(&directory.path().join("second"), true);
    let workspace = checkout(directory.path(), "project");
    let old = place(&first, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(old.join("artifact"), b"outputs").unwrap();
    // A finished build leaves its lock file behind. Nothing holds it, so the
    // view moves -- and it only can if placement stopped holding it too.
    std::fs::create_dir_all(old.join("release")).unwrap();
    std::fs::write(old.join("release/.cargo-lock"), b"").unwrap();

    let new = place(&second, &workspace, &workspace.join("target"), false).unwrap();

    assert_ne!(old, new);
    assert_eq!(std::fs::read_link(workspace.join("target")).unwrap(), new);
    assert!(new.join("artifact").is_file(), "the old view should move");
    assert!(new.join("release/.cargo-lock").is_file());
    assert!(!old.exists(), "the old root must not retain an orphan");
    assert_eq!(stats(&first.target.root).unwrap(), ViewStats::default());
    assert_eq!(stats(&second.target.root).unwrap().views, 1);
}

#[test]
fn leaves_somebody_elses_dangling_link_alone() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    let elsewhere = directory.path().join("missing");
    symlink_dir(&elsewhere, &target).unwrap();

    assert!(place(&config, &workspace, &target, false).is_none());
    assert_eq!(std::fs::read_link(target).unwrap(), elsewhere);
}

#[test]
fn leaves_another_live_checkouts_view_alone() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let original = checkout(directory.path(), "original");
    let copied = checkout(directory.path(), "copied");
    let managed = place(&config, &original, &original.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), b"outputs").unwrap();
    symlink_dir(&managed, &copied.join("target")).unwrap();

    assert!(place(&config, &copied, &copied.join("target"), false).is_none());

    assert_eq!(std::fs::read_link(copied.join("target")).unwrap(), managed);
    assert!(managed.join("artifact").exists());
    assert_eq!(stats(&config.target.root).unwrap().views, 1);
}

#[test]
fn leaves_the_target_directory_alone_when_disabled() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), false);
    let workspace = checkout(directory.path(), "project");

    assert!(place(&config, &workspace, &workspace.join("target"), false).is_none());
    assert!(!workspace.join("target").exists());
}

#[test]
fn only_an_unrequested_real_default_target_can_be_removed() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(&target).unwrap();

    assert!(can_remove_existing(&config, &workspace, &target, false));
    assert!(!can_remove_existing(&config, &workspace, &target, true));
    assert!(!can_remove_existing(
        &config,
        &workspace,
        &workspace.join("somewhere-else"),
        false
    ));
    assert!(!can_remove_existing(
        &test_config(directory.path(), false),
        &workspace,
        &target,
        false
    ));
}

#[test]
fn a_failed_migration_restores_existing_outputs() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("artifact"), b"old output").unwrap();

    let outcome = migrate_existing_with(&config, &workspace, &target, false, || None).unwrap();

    assert_eq!(outcome, MigrationOutcome::default());
    assert_eq!(
        std::fs::read(target.join("artifact")).unwrap(),
        b"old output"
    );
}

#[test]
fn a_preparation_failure_restores_existing_outputs_and_record_state() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("artifact"), b"old output").unwrap();
    let managed = view_dir(&config.target.root, &workspace);
    std::fs::create_dir_all(managed.parent().unwrap()).unwrap();
    std::fs::write(&managed, b"not a directory").unwrap();

    let outcome = migrate_existing(&config, &workspace, &target, false).unwrap();

    assert_eq!(outcome, MigrationOutcome::default());
    assert_eq!(
        std::fs::read(target.join("artifact")).unwrap(),
        b"old output"
    );
    assert_eq!(std::fs::read(&managed).unwrap(), b"not a directory");
    assert!(!view_record_path(&config.target.root, &workspace).exists());
}

#[cfg(unix)]
#[test]
fn a_successful_migration_removes_old_outputs_after_placement() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("artifact"), b"old output").unwrap();
    let elsewhere = directory.path().join("elsewhere");
    std::fs::create_dir_all(&elsewhere).unwrap();
    std::fs::write(elsewhere.join("not-cleaned"), vec![0; 1024]).unwrap();
    symlink_dir(&elsewhere, &target.join("external-link")).unwrap();

    let outcome = migrate_existing(&config, &workspace, &target, false).unwrap();
    let managed = outcome.managed.unwrap();

    assert_eq!(std::fs::read_link(&target).unwrap(), managed);
    assert!(!target.join("artifact").exists());
    assert_eq!(outcome.removed_bytes, Some(10));
    assert!(elsewhere.join("not-cleaned").is_file());
    assert_eq!(stats(&config.target.root).unwrap().views, 1);
}

#[test]
fn adopting_an_existing_target_keeps_its_outputs_under_the_managed_root() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(target.join("debug")).unwrap();
    std::fs::write(target.join("debug/artifact"), b"old output").unwrap();

    assert!(can_move_existing(&config, &workspace, &target));
    let outcome = adopt_existing(&config, &workspace, &target, false).unwrap();
    let managed = outcome.managed.clone().unwrap();

    assert_eq!(outcome.adopted_bytes, 10);
    assert_eq!(std::fs::read_link(&target).unwrap(), managed);
    assert_eq!(
        std::fs::read(managed.join("debug/artifact")).unwrap(),
        b"old output"
    );
    assert_eq!(
        std::fs::read(target.join("debug/artifact")).unwrap(),
        b"old output",
        "the outputs should still be reachable through the link"
    );
    assert!(view_record_path(&config.target.root, &workspace).exists());
    assert_eq!(stats(&config.target.root).unwrap().views, 1);
    let leftovers: Vec<_> = std::fs::read_dir(&workspace)
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .filter(|name| name != "target")
        .collect();
    assert!(
        leftovers.is_empty(),
        "no backup should remain: {leftovers:?}"
    );
}

#[test]
fn a_declined_adoption_restores_existing_outputs() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("artifact"), b"old output").unwrap();

    let outcome = adopt_existing_with(&config, &workspace, &target, false, || None).unwrap();

    assert_eq!(outcome, AdoptionOutcome::default());
    assert!(std::fs::symlink_metadata(&target).unwrap().is_dir());
    assert_eq!(
        std::fs::read(target.join("artifact")).unwrap(),
        b"old output"
    );
    assert!(!view_record_path(&config.target.root, &workspace).exists());
}

#[test]
fn adoption_refuses_a_directory_cargo_is_using() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(target.join("debug")).unwrap();
    std::fs::write(target.join("debug/artifact"), b"old output").unwrap();
    let lock_path = target.join("debug/.cargo-lock");
    std::fs::write(&lock_path, b"").unwrap();
    let mut build = fslock::LockFile::open(&lock_path).unwrap();
    build.lock().unwrap();

    let error = adopt_existing(&config, &workspace, &target, false).unwrap_err();

    assert!(
        format!("{error:#}").contains("Cargo is using"),
        "unexpected error: {error:#}"
    );
    assert!(std::fs::symlink_metadata(&target).unwrap().is_dir());
    assert_eq!(
        std::fs::read(target.join("debug/artifact")).unwrap(),
        b"old output"
    );
    assert!(!view_record_path(&config.target.root, &workspace).exists());
    assert!(!view_dir(&config.target.root, &workspace).exists());
    // Closed, not merely unlocked: Cargo closes its lock when it finishes,
    // and Windows will not rename a directory holding an open handle.
    drop(build);

    let outcome = adopt_existing(&config, &workspace, &target, false).unwrap();

    assert!(outcome.managed.is_some());
    assert_eq!(
        std::fs::read(target.join("debug/artifact")).unwrap(),
        b"old output"
    );
}

#[test]
fn adoption_sees_a_lock_in_an_editors_cross_compiled_profile() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    // Three levels down: an editor's own target directory, a target triple,
    // and the profile. Cargo's outputs beside a lock are never entered, so a
    // lock hidden inside one of those must not count either way.
    let profile = target.join("rust-analyzer/x86_64-unknown-linux-gnu/debug");
    std::fs::create_dir_all(profile.join("deps")).unwrap();
    std::fs::write(profile.join(".cargo-lock"), b"").unwrap();
    std::fs::write(profile.join("deps/.cargo-lock"), b"").unwrap();
    let mut decoy = fslock::LockFile::open(&profile.join("deps/.cargo-lock")).unwrap();
    decoy.lock().unwrap();
    assert!(
        cargo_locks(&target).unwrap().is_some(),
        "a lock inside an output directory is not Cargo's"
    );
    // The same name directly under the target directory is a custom profile,
    // whose lock counts.
    std::fs::create_dir_all(target.join("deps")).unwrap();
    std::fs::write(target.join("deps/.cargo-lock"), b"").unwrap();
    let mut custom = fslock::LockFile::open(&target.join("deps/.cargo-lock")).unwrap();
    custom.lock().unwrap();
    assert!(
        cargo_locks(&target).unwrap().is_none(),
        "a custom profile named like an output directory still holds Cargo's lock"
    );
    drop(custom);
    let mut build = fslock::LockFile::open(&profile.join(".cargo-lock")).unwrap();
    build.lock().unwrap();

    let error = adopt_existing(&config, &workspace, &target, false).unwrap_err();

    assert!(
        format!("{error:#}").contains("Cargo is using"),
        "unexpected error: {error:#}"
    );
    assert!(std::fs::symlink_metadata(&target).unwrap().is_dir());
}

#[test]
fn an_occupied_view_leaves_the_outputs_where_they_are() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("artifact"), b"old output").unwrap();
    // A view with no record but with contents is not this adoption's to
    // replace, so it must back out before anything has moved.
    let managed = view_dir(&config.target.root, &workspace);
    std::fs::create_dir_all(&managed).unwrap();
    std::fs::write(managed.join("stranded"), b"unrecorded").unwrap();

    let error = adopt_existing(&config, &workspace, &target, false).unwrap_err();

    assert!(
        error.to_string().contains("could not replace"),
        "unexpected error: {error:#}"
    );
    assert!(std::fs::symlink_metadata(&target).unwrap().is_dir());
    assert_eq!(
        std::fs::read(target.join("artifact")).unwrap(),
        b"old output"
    );
    assert_eq!(
        std::fs::read(managed.join("stranded")).unwrap(),
        b"unrecorded"
    );
    assert!(!view_record_path(&config.target.root, &workspace).exists());
}

#[cfg(unix)]
#[test]
fn adopting_an_existing_target_never_follows_a_replacement_link() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    let elsewhere = directory.path().join("elsewhere");
    std::fs::create_dir_all(&elsewhere).unwrap();
    std::fs::write(elsewhere.join("keep"), b"not a build output").unwrap();
    symlink_dir(&elsewhere, &target).unwrap();

    assert!(adopt_existing(&config, &workspace, &target, false).is_err());
    assert!(elsewhere.join("keep").is_file());
    assert_eq!(std::fs::read_link(&target).unwrap(), elsewhere);
}

#[cfg(unix)]
#[test]
fn migrating_an_existing_target_never_follows_a_replacement_link() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let target = workspace.join("target");
    let elsewhere = directory.path().join("elsewhere");
    std::fs::create_dir_all(&elsewhere).unwrap();
    std::fs::write(elsewhere.join("keep"), b"not a build output").unwrap();
    symlink_dir(&elsewhere, &target).unwrap();

    assert!(migrate_existing(&config, &workspace, &target, false).is_err());
    assert!(elsewhere.join("keep").is_file());
}

#[test]
fn leaves_a_requested_target_directory_alone_even_at_the_default_place() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");

    // `--target-dir target` names the default location and still means the
    // caller chose it. Cargo prefers that flag over the CARGO_TARGET_DIR
    // placement would set, so relocating would leave cargo writing one
    // place while the shim mapped another -- measured as a build that
    // looked nothing up and stored almost nothing.
    assert!(place(&config, &workspace, &workspace.join("target"), true).is_none());

    assert!(!workspace.join("target").exists());
    assert_eq!(stats(&config.target.root).unwrap(), ViewStats::default());
}

#[test]
fn leaves_a_target_directory_someone_else_chose_where_it_is() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");

    // A flag, the environment, or a cargo configuration put it here, and
    // that outranks any placement of ours.
    let elsewhere = directory.path().join("chosen");
    assert!(place(&config, &workspace, &elsewhere, false).is_none());
    assert_eq!(stats(&config.target.root).unwrap(), ViewStats::default());
}

#[test]
fn refuses_to_displace_real_build_outputs() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let existing = workspace.join("target");
    std::fs::create_dir_all(existing.join("debug")).unwrap();
    std::fs::write(existing.join("debug/libfixture.rlib"), b"outputs").unwrap();

    assert!(place(&config, &workspace, &existing, false).is_none());

    assert!(
        existing.join("debug/libfixture.rlib").exists(),
        "somebody's build outputs are not ours to move or delete"
    );
    assert_eq!(
        stats(&config.target.root).unwrap(),
        ViewStats::default(),
        "a refusal that leaves a directory and a record behind would report \
             a managed target directory for a checkout nothing manages"
    );
}

#[test]
fn a_refusal_leaves_an_earlier_placement_alone() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), b"outputs").unwrap();

    // Somebody replaced the link with a directory of their own. The
    // placement already on disk still owns a full target directory, and
    // dropping its record would leave that directory untraceable -- which
    // means never collected.
    remove_link(&workspace.join("target")).unwrap();
    std::fs::create_dir_all(workspace.join("target")).unwrap();

    assert!(place(&config, &workspace, &workspace.join("target"), false).is_none());

    assert_eq!(stats(&config.target.root).unwrap().views, 1);
    assert!(managed.join("artifact").exists());
    std::fs::remove_dir_all(&workspace).unwrap();
    assert_eq!(
        prune(&config.target.root).unwrap().removed_views,
        1,
        "the earlier placement must still be collectable"
    );
}

#[test]
fn frees_the_target_directory_of_a_checkout_that_is_gone() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let gone = checkout(directory.path(), "gone");
    let staying = checkout(directory.path(), "staying");

    let removed = place(&config, &gone, &gone.join("target"), false).unwrap();
    let kept = place(&config, &staying, &staying.join("target"), false).unwrap();
    std::fs::write(removed.join("artifact"), vec![0_u8; 512]).unwrap();
    std::fs::write(kept.join("artifact"), vec![0_u8; 256]).unwrap();
    std::fs::remove_dir_all(&gone).unwrap();

    let outcome = prune(&config.target.root).unwrap();

    assert_eq!(
        outcome,
        PruneOutcome {
            removed_views: 1,
            removed_bytes: 512,
        }
    );
    assert!(!removed.exists());
    assert!(kept.join("artifact").exists());
    assert_eq!(stats(&config.target.root).unwrap().views, 1);
}

#[test]
fn explicitly_removes_one_workspaces_managed_target() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), b"outputs").unwrap();

    let bytes = remove_workspace(&config.target.root, &workspace).unwrap();

    assert_eq!(bytes, RemoveOutcome::Removed(7));
    assert!(!managed.exists());
    assert!(!workspace.join("target").exists());
    assert_eq!(stats(&config.target.root).unwrap(), ViewStats::default());
}

#[test]
fn explicit_removal_drops_a_link_left_dangling_by_collection() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::remove_dir_all(&managed).unwrap();
    std::fs::remove_file(view_record_path(&config.target.root, &workspace)).unwrap();

    let bytes = remove_workspace(&config.target.root, &workspace).unwrap();

    assert_eq!(bytes, RemoveOutcome::Removed(0));
    assert!(std::fs::symlink_metadata(workspace.join("target")).is_err());
}

#[test]
fn keeps_the_target_directory_of_an_idle_checkout() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), b"outputs").unwrap();

    let outcome = prune(&config.target.root).unwrap();

    assert_eq!(outcome.removed_views, 0);
    assert!(managed.join("artifact").exists());
}

#[test]
fn target_budget_collects_oldest_live_view_first() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let old_workspace = checkout(directory.path(), "old");
    let new_workspace = checkout(directory.path(), "new");
    let old = place(
        &config,
        &old_workspace,
        &old_workspace.join("target"),
        false,
    )
    .unwrap();
    let new = place(
        &config,
        &new_workspace,
        &new_workspace.join("target"),
        false,
    )
    .unwrap();
    std::fs::write(old.join("artifact"), vec![0_u8; 5]).unwrap();
    std::fs::write(new.join("artifact"), vec![0_u8; 10]).unwrap();
    let old_record = view_record_path(&config.target.root, &old_workspace);
    let mut record: ViewRecord =
        serde_json::from_slice(&std::fs::read(&old_record).unwrap()).unwrap();
    record.updated_secs = 1;
    std::fs::write(&old_record, serde_json::to_vec(&record).unwrap()).unwrap();

    let outcome = collect(&config.target.root, Some(10), None, false).unwrap();

    assert_eq!(outcome.removed_live_views, 1);
    assert_eq!(outcome.removed_bytes, 5);
    assert_eq!(outcome.remaining_bytes, 10);
    assert!(!old.exists());
    assert!(new.exists());
}

#[test]
fn dry_run_leaves_selected_target_views_in_place() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    // Two views, because the most recently used one is never evicted for
    // being over budget; the older one is what a dry run must report and keep.
    let old_workspace = checkout(directory.path(), "old");
    let new_workspace = checkout(directory.path(), "new");
    let old = place(
        &config,
        &old_workspace,
        &old_workspace.join("target"),
        false,
    )
    .unwrap();
    place(
        &config,
        &new_workspace,
        &new_workspace.join("target"),
        false,
    )
    .unwrap();
    std::fs::write(old.join("artifact"), b"outputs").unwrap();
    age_view(&config.target.root, &old_workspace, 1);

    let outcome = collect(&config.target.root, Some(0), None, true).unwrap();

    assert_eq!(outcome.removed_live_views, 1);
    assert!(old.join("artifact").exists());
    assert!(view_record_path(&config.target.root, &old_workspace).exists());
}

/// Backdate a view's record so collection sees it as the older one.
fn age_view(root: &Path, workspace_root: &Path, updated_secs: u64) {
    let path = view_record_path(root, workspace_root);
    let mut record: ViewRecord = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    record.updated_secs = updated_secs;
    std::fs::write(&path, serde_json::to_vec(&record).unwrap()).unwrap();
}

#[test]
fn a_budget_smaller_than_one_target_directory_keeps_it() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), vec![0_u8; 4_096]).unwrap();

    // Deleting it could not hold the total down: the next build recreates it.
    // Collecting it anyway would delete the working checkout's outputs after
    // every single build.
    let outcome = collect(&config.target.root, Some(16), None, false).unwrap();

    assert_eq!(outcome.removed_views, 0);
    assert_eq!(outcome.remaining_bytes, 4_096);
    assert!(managed.join("artifact").exists());
}

#[test]
fn an_over_budget_sweep_keeps_the_most_recently_used_view() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let old_workspace = checkout(directory.path(), "old");
    let new_workspace = checkout(directory.path(), "new");
    let old = place(
        &config,
        &old_workspace,
        &old_workspace.join("target"),
        false,
    )
    .unwrap();
    let new = place(
        &config,
        &new_workspace,
        &new_workspace.join("target"),
        false,
    )
    .unwrap();
    std::fs::write(old.join("artifact"), vec![0_u8; 100]).unwrap();
    std::fs::write(new.join("artifact"), vec![0_u8; 100]).unwrap();
    age_view(&config.target.root, &old_workspace, 1);

    // A budget neither view alone fits under: the older one still goes, and
    // the one in use survives.
    let outcome = collect(&config.target.root, Some(10), None, false).unwrap();

    assert_eq!(outcome.removed_live_views, 1);
    assert!(!old.exists(), "the idle view is collected");
    assert!(new.exists(), "the view in use is kept");
}

#[test]
fn a_newer_abandoned_view_does_not_spend_the_live_view_s_protection() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let working = checkout(directory.path(), "working");
    let abandoned = checkout(directory.path(), "abandoned");
    let working_view = place(&config, &working, &working.join("target"), false).unwrap();
    let abandoned_view = place(&config, &abandoned, &abandoned.join("target"), false).unwrap();
    std::fs::write(working_view.join("artifact"), vec![0_u8; 100]).unwrap();
    std::fs::write(abandoned_view.join("artifact"), vec![0_u8; 100]).unwrap();
    // The abandoned checkout was built more recently than the one still in
    // use, so it sorts last -- it must not take the protected place, because
    // it is being deleted either way.
    age_view(&config.target.root, &working, 1);
    age_view(&config.target.root, &abandoned, 2);
    std::fs::remove_dir_all(&abandoned).unwrap();

    let outcome = collect(&config.target.root, Some(10), None, false).unwrap();

    assert!(!abandoned_view.exists(), "the abandoned view is collected");
    assert!(
        working_view.join("artifact").exists(),
        "the checkout in use keeps its outputs"
    );
    assert_eq!(outcome.removed_stale_views, 1);
    assert_eq!(outcome.removed_live_views, 0);
}

#[test]
fn an_abandoned_checkout_is_collected_even_as_the_newest_view() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), vec![0_u8; 100]).unwrap();
    std::fs::remove_dir_all(&workspace).unwrap();

    // Protecting the newest view is about budgets, not about outputs nothing
    // can ask for again.
    let outcome = collect(&config.target.root, Some(10), None, false).unwrap();

    assert_eq!(outcome.removed_stale_views, 1);
    assert!(!managed.exists());
}

#[test]
fn a_build_writing_through_an_existing_link_keeps_its_view_alive() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), b"outputs").unwrap();
    age_view(&config.target.root, &workspace, 1);

    // Placement is off now, but cargo still writes through the link an earlier
    // build left behind, so the directory is anything but idle.
    config.target.views = false;
    assert!(place(&config, &workspace, &workspace.join("target"), false).is_none());
    touch_managed(&config, &workspace, &workspace.join("target"));

    let outcome = collect(
        &config.target.root,
        None,
        Some(std::time::Duration::from_secs(60)),
        false,
    )
    .unwrap();

    assert_eq!(outcome.removed_views, 0, "a view in use is not expired");
    assert!(managed.join("artifact").exists());
}

#[test]
fn a_target_directory_outside_the_managed_root_is_not_touched() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    place(&config, &workspace, &workspace.join("target"), false).unwrap();
    age_view(&config.target.root, &workspace, 1);
    let elsewhere = directory.path().join("elsewhere");
    std::fs::create_dir_all(&elsewhere).unwrap();

    // A checkout that went back to its own directory leaves the managed view
    // genuinely idle, and it should expire on schedule.
    touch_managed(&config, &workspace, &elsewhere);

    let record = view_record_path(&config.target.root, &workspace);
    let record: ViewRecord = serde_json::from_slice(&std::fs::read(&record).unwrap()).unwrap();
    assert_eq!(record.updated_secs, 1, "the record was not refreshed");
}

#[test]
fn leaves_a_target_directory_it_cannot_trace() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::remove_dir_all(&workspace).unwrap();
    // `cargo clean` cannot reach the record, but a corrupt one still must
    // not turn into a licence to delete a directory full of outputs.
    std::fs::write(view_record_path(&config.target.root, &workspace), b"{").unwrap();

    assert_eq!(prune(&config.target.root).unwrap(), PruneOutcome::default());
    assert!(managed.exists());
}

#[test]
fn missing_selected_directory_counts_as_stale_removal() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::remove_dir_all(&workspace).unwrap();
    std::fs::remove_dir_all(&managed).unwrap();

    let outcome = collect(&config.target.root, None, None, false).unwrap();

    assert_eq!(outcome.removed_views, 1);
    assert_eq!(outcome.removed_stale_views, 1);
    assert_eq!(outcome.removed_live_views, 0);
}

#[test]
fn counts_a_target_directory_it_cannot_trace() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "project");
    let managed = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(managed.join("artifact"), vec![0_u8; 7]).unwrap();
    std::fs::write(view_record_path(&config.target.root, &workspace), b"{").unwrap();

    let outcome = collect(&config.target.root, Some(0), None, false).unwrap();

    assert_eq!(outcome.remaining_bytes, 7);
    assert!(managed.exists());
}

#[test]
fn counts_nothing_before_anything_is_placed() {
    let directory = tempfile::tempdir().unwrap();
    assert_eq!(
        stats(&directory.path().join("targets")).unwrap(),
        ViewStats::default()
    );
    assert_eq!(
        prune(&directory.path().join("targets")).unwrap(),
        PruneOutcome::default()
    );
}

/// Collection runs after the build that scheduled it has returned, so a
/// build can start in a checkout that collection had already picked.
#[test]
fn a_view_a_build_is_compiling_in_is_kept() {
    // Releases a lock and then expects collection to find it free, which the
    // shared test process cannot promise; see `in_own_process`.
    if !super::lease_tests::in_own_process(module_path!(), "a_view_a_build_is_compiling_in_is_kept")
    {
        return;
    }
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let old_workspace = checkout(directory.path(), "old");
    let new_workspace = checkout(directory.path(), "new");
    let old = place(
        &config,
        &old_workspace,
        &old_workspace.join("target"),
        false,
    )
    .unwrap();
    let new = place(
        &config,
        &new_workspace,
        &new_workspace.join("target"),
        false,
    )
    .unwrap();
    std::fs::write(old.join("artifact"), vec![0_u8; 5]).unwrap();
    std::fs::write(new.join("artifact"), vec![0_u8; 10]).unwrap();
    let old_record = view_record_path(&config.target.root, &old_workspace);
    let mut record: ViewRecord =
        serde_json::from_slice(&std::fs::read(&old_record).unwrap()).unwrap();
    record.updated_secs = 1;
    std::fs::write(&old_record, serde_json::to_vec(&record).unwrap()).unwrap();
    // Cargo's lock for the profile it is building.
    std::fs::create_dir_all(old.join("debug")).unwrap();
    let mut cargo = fslock::LockFile::open(&old.join("debug/.cargo-lock")).unwrap();
    assert!(cargo.try_lock().unwrap());

    let outcome = collect(&config.target.root, Some(10), None, false).unwrap();

    assert_eq!(outcome.kept_active_views, 1);
    assert_eq!(outcome.removed_views, 0);
    assert!(old.exists(), "a directory being built in is not removed");
    assert!(new.exists());

    // Once the build is over the next sweep removes it as before. The handle
    // goes with the lock: Windows will not rename a directory while a file
    // inside it is open, which is the same answer as a held lock.
    drop(cargo);
    let outcome = collect(&config.target.root, Some(10), None, false).unwrap();

    assert_eq!(outcome.removed_live_views, 1);
    assert!(!old.exists());
}

#[test]
fn a_view_claimed_since_the_selection_is_kept() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let old_workspace = checkout(directory.path(), "old");
    let new_workspace = checkout(directory.path(), "new");
    let old = place(
        &config,
        &old_workspace,
        &old_workspace.join("target"),
        false,
    )
    .unwrap();
    place(
        &config,
        &new_workspace,
        &new_workspace.join("target"),
        false,
    )
    .unwrap();
    std::fs::write(old.join("artifact"), vec![0_u8; 5]).unwrap();
    let old_record = view_record_path(&config.target.root, &old_workspace);
    let mut record: ViewRecord =
        serde_json::from_slice(&std::fs::read(&old_record).unwrap()).unwrap();
    // Expired at selection time, and refreshed by a build before removal: the
    // record collection reads back is newer than the one it selected on.
    record.updated_secs = 1;
    std::fs::write(&old_record, serde_json::to_vec(&record).unwrap()).unwrap();
    let refreshed = old_record.clone();
    let outcome = collect_with(
        &config.target.root,
        None,
        Some(Duration::from_secs(10)),
        &Precedence::default(),
        false,
        now_secs(),
        move || {
            let mut record: ViewRecord =
                serde_json::from_slice(&std::fs::read(&refreshed).unwrap()).unwrap();
            record.updated_secs = 2;
            std::fs::write(&refreshed, serde_json::to_vec(&record).unwrap()).unwrap();
        },
        |_| {},
        || {},
    )
    .unwrap();

    assert_eq!(outcome.kept_active_views, 1);
    assert!(old.exists());
}

#[test]
fn a_view_a_dead_collector_moved_aside_is_finished_off() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "kept");
    let kept = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    let aside = views_root(&config.target.root).join("abc123.removing-4242");
    std::fs::create_dir_all(aside.join("debug")).unwrap();
    std::fs::write(aside.join("debug/artifact"), b"x").unwrap();

    let outcome = collect(&config.target.root, None, None, false).unwrap();

    assert!(!aside.exists(), "the leftover is removed");
    assert!(kept.exists());
    assert_eq!(outcome.removed_views, 0, "and is not counted as a view");
}

/// A checkout deleted after its last build and cloned again at the same path
/// keeps the same view, so the clone's first build lands in the directory an
/// earlier selection marked abandoned.
#[test]
fn a_checkout_recreated_since_the_selection_is_kept() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "gone");
    let view = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(view.join("artifact"), vec![0_u8; 5]).unwrap();
    std::fs::remove_dir_all(&workspace).unwrap();

    let rebuilt = view.clone();
    let outcome = collect_with(
        &config.target.root,
        None,
        None,
        &Precedence::default(),
        false,
        now_secs(),
        move || {
            // The clone's build: Cargo holds its lock in the same view.
            std::fs::create_dir_all(rebuilt.join("debug")).unwrap();
            let mut cargo = fslock::LockFile::open(&rebuilt.join("debug/.cargo-lock")).unwrap();
            assert!(cargo.try_lock().unwrap());
            std::mem::forget(cargo);
        },
        |_| {},
        || {},
    )
    .unwrap();

    assert_eq!(outcome.kept_active_views, 1);
    assert_eq!(outcome.removed_views, 0);
    assert!(view.exists());
}

/// Records carry whole seconds, so a build that refreshed the record in the
/// same second as the selection cannot be told apart by comparing them; a
/// record refreshed within the last couple of seconds is a build starting.
#[test]
fn a_view_refreshed_within_the_last_seconds_is_kept() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "fresh");
    let view = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    let record_path = view_record_path(&config.target.root, &workspace);
    let mut record: ViewRecord =
        serde_json::from_slice(&std::fs::read(&record_path).unwrap()).unwrap();
    // One second old: expired against a zero age, and just refreshed. The
    // sweep gets that same second as its clock, so what the ages mean here
    // does not depend on how long the machine takes to reach the check.
    record.updated_secs -= 1;
    let now = record.updated_secs + 1;
    std::fs::write(&record_path, serde_json::to_vec(&record).unwrap()).unwrap();

    let outcome = collect_with(
        &config.target.root,
        None,
        Some(Duration::ZERO),
        &Precedence::default(),
        false,
        now,
        || {},
        |_| {},
        || {},
    )
    .unwrap();

    assert_eq!(outcome.kept_active_views, 1);
    assert!(view.exists());
}

/// A build that places the checkout after its old directory was moved aside
/// writes a new record and a new directory. The record it wrote is not the one
/// collection selected on, and stays.
#[test]
fn a_record_rewritten_during_the_removal_is_kept() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let workspace = checkout(directory.path(), "gone");
    let view = place(&config, &workspace, &workspace.join("target"), false).unwrap();
    std::fs::write(view.join("artifact"), vec![0_u8; 5]).unwrap();
    std::fs::remove_dir_all(&workspace).unwrap();
    let record_path = view_record_path(&config.target.root, &workspace);
    let mut record: ViewRecord =
        serde_json::from_slice(&std::fs::read(&record_path).unwrap()).unwrap();
    record.updated_secs = 1;
    std::fs::write(&record_path, serde_json::to_vec(&record).unwrap()).unwrap();

    let rebuilt = view.clone();
    let rewritten = record_path.clone();
    let root = config.target.root.clone();
    let outcome = collect_with(
        &config.target.root,
        None,
        None,
        &Precedence::default(),
        false,
        now_secs(),
        || {},
        |_| {},
        move || {
            // The clone's placement: a fresh record, then a fresh directory.
            record_view(&root, &workspace).unwrap();
            std::fs::create_dir_all(&rebuilt).unwrap();
            assert!(rewritten.exists());
        },
    )
    .unwrap();

    assert_eq!(outcome.removed_views, 1, "the old directory still went");
    assert!(record_path.exists(), "the record the build wrote stays");
    assert!(view.exists(), "and so does the directory it made");
}

#[test]
fn precedence_matches_absolute_directories_and_relative_names() {
    let precedence = Precedence {
        keep: vec![PathBuf::from("/src/app")],
        evict_first: vec![PathBuf::from(".claude/worktrees")],
    };

    assert_eq!(precedence.standing(Path::new("/src/app")), Standing::Keep);
    assert_eq!(
        precedence.standing(Path::new("/src/app/crates/cli")),
        Standing::Keep,
        "an absolute entry covers what is under it"
    );
    assert_eq!(
        precedence.standing(Path::new("/src/application")),
        Standing::Normal,
        "by component, not by prefix of the name"
    );
    assert_eq!(
        precedence.standing(Path::new("/elsewhere/.claude/worktrees/fix")),
        Standing::EvictFirst,
        "a relative entry matches in any repository"
    );
    assert_eq!(
        precedence.standing(Path::new("/src/app/.claude/worktrees/fix")),
        Standing::EvictFirst,
        "the entry naming more of the path wins"
    );
    assert_eq!(
        precedence.standing(Path::new("/src/claude/worktrees/fix")),
        Standing::Normal
    );

    let named = Precedence {
        keep: vec![PathBuf::from("/src/app/.claude/worktrees/bisect")],
        ..precedence.clone()
    };
    assert_eq!(
        named.standing(Path::new("/src/app/.claude/worktrees/bisect")),
        Standing::Keep,
        "keeping one worktree by name outranks evicting its siblings"
    );
    let tie = Precedence {
        keep: vec![PathBuf::from("worktrees")],
        evict_first: vec![PathBuf::from("worktrees")],
    };
    assert_eq!(
        tie.standing(Path::new("/src/worktrees")),
        Standing::Keep,
        "a tie keeps"
    );
    assert_eq!(
        Precedence::default().standing(Path::new("/src/app")),
        Standing::Normal
    );
    let spelled_out = Precedence {
        keep: vec![PathBuf::from("worktrees")],
        evict_first: vec![PathBuf::from("/src/app/.claude/worktrees")],
    };
    assert_eq!(
        spelled_out.standing(Path::new("/src/app/.claude/worktrees")),
        Standing::EvictFirst,
        "ending at the same place, the entry naming more of the path wins"
    );
}

#[test]
fn a_kept_most_recent_target_does_not_spare_an_older_one() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let [oldest, agent, human, newest] = ranked_views(directory.path(), &config);
    let precedence = Precedence {
        keep: vec![newest.0.clone()],
        ..Precedence::default()
    };

    // Only the kept, most recent target fits: sparing `human` as well would
    // leave the budget unmet for nothing.
    let outcome = collect_by(&config.target.root, Some(1), None, &precedence, false).unwrap();

    assert_eq!(outcome.removed_views, 3);
    assert_eq!(outcome.remaining_bytes, 1);
    assert!(!oldest.1.exists() && !agent.1.exists() && !human.1.exists());
    assert!(newest.1.exists());
}

/// Three live checkouts, oldest to newest: `kept`, `agent`, `human`, each with
/// a 10-byte target, and the most recent one, `newest`, with 1 byte.
fn ranked_views(root: &Path, config: &Config) -> [(PathBuf, PathBuf); 4] {
    [
        ("kept", 1, 10),
        ("agent", 2, 10),
        ("human", 3, 10),
        ("newest", 4, 1),
    ]
    .map(|(name, updated, size)| {
        let workspace = checkout(root, name);
        let view = place(config, &workspace, &workspace.join("target"), false).unwrap();
        std::fs::write(view.join("artifact"), vec![0_u8; size]).unwrap();
        age_view(&config.target.root, &workspace, updated);
        (workspace, view)
    })
}

#[test]
fn over_budget_takes_evict_first_targets_before_older_ones_and_never_kept_ones() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let [kept, agent, human, newest] = ranked_views(directory.path(), &config);
    let precedence = Precedence {
        keep: vec![kept.0.clone()],
        evict_first: vec![agent.0.clone()],
    };

    // 31 bytes against 21: one 10-byte target has to go.
    let outcome = collect_by(&config.target.root, Some(21), None, &precedence, false).unwrap();

    assert_eq!(outcome.removed_views, 1);
    assert!(!agent.1.exists(), "evict-first goes before an older target");
    assert!(human.1.exists());
    assert!(kept.1.exists());
    assert!(newest.1.exists());

    // Nothing but the kept one and the most recent left to take.
    let outcome = collect_by(&config.target.root, Some(0), None, &precedence, false).unwrap();
    assert_eq!(outcome.removed_views, 1);
    assert!(!human.1.exists());
    assert!(kept.1.exists(), "a kept target is never collected for size");
    assert!(newest.1.exists(), "the most recently used one is spared");
}

#[test]
fn the_most_recent_target_is_spared_even_when_it_is_evict_first() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let [_, agent, human, newest] = ranked_views(directory.path(), &config);
    let precedence = Precedence {
        evict_first: vec![agent.0.clone(), newest.0.clone()],
        ..Precedence::default()
    };

    let outcome = collect_by(&config.target.root, Some(0), None, &precedence, false).unwrap();

    assert_eq!(outcome.removed_views, 3);
    assert!(!agent.1.exists());
    assert!(!human.1.exists());
    assert!(newest.1.exists());
}

#[test]
fn a_kept_target_outlives_its_age_but_not_its_checkout() {
    let directory = tempfile::tempdir().unwrap();
    let config = test_config(directory.path(), true);
    let [kept, agent, human, newest] = ranked_views(directory.path(), &config);
    let precedence = Precedence {
        keep: vec![kept.0.clone()],
        ..Precedence::default()
    };
    let unit = kept.1.join("debug/build/dep/0123456789abcdef");
    std::fs::create_dir_all(&unit).unwrap();

    let outcome = collect_by(
        &config.target.root,
        None,
        Some(Duration::from_secs(60)),
        &precedence,
        false,
    )
    .unwrap();

    assert_eq!(outcome.removed_views, 3, "every other target has expired");
    assert!(kept.1.exists());
    assert!(unit.exists(), "nor are a kept target's units pruned");
    assert!(!agent.1.exists() && !human.1.exists() && !newest.1.exists());

    std::fs::remove_dir_all(&kept.0).unwrap();
    let outcome = collect_by(&config.target.root, None, None, &precedence, false).unwrap();
    assert_eq!(outcome.removed_stale_views, 1);
    assert!(!kept.1.exists(), "a checkout that is gone takes its target");
}

#[test]
fn parallel_tree_sizing_matches_the_serial_walk() {
    let directory = tempfile::tempdir().unwrap();
    let empty = directory.path().join("empty");
    std::fs::create_dir(&empty).unwrap();
    let mut roots = vec![empty, directory.path().join("missing")];
    for root in 0..3 {
        let base = directory.path().join(format!("root{root}"));
        for branch in 0..4 {
            let nested = base.join(format!("a{branch}")).join("b").join("c");
            std::fs::create_dir_all(&nested).unwrap();
            for file in 0..5 {
                std::fs::write(nested.join(format!("f{file}")), vec![0; 10 * (file + 1)]).unwrap();
            }
            std::fs::write(base.join(format!("top{branch}")), vec![0; 7]).unwrap();
        }
        roots.push(base);
    }
    #[cfg(unix)]
    {
        // A link is neither followed nor counted, as in the serial walk.
        let linked = directory.path().join("root0").join("link");
        std::os::unix::fs::symlink(directory.path().join("root1"), linked).unwrap();
    }
    let serial = roots.iter().map(|root| tree_bytes(root)).sum::<u64>();
    assert!(serial > 0);
    assert_eq!(trees_bytes(roots), serial);
    assert_eq!(trees_bytes(Vec::new()), 0);
}
