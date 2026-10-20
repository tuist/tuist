use super::*;

fn write_tree(root: &Path, files: &[(&str, &[u8])]) {
    for (name, contents) in files {
        let path = root.join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, contents).unwrap();
    }
}

#[test]
fn a_lease_from_another_pid_namespace_does_not_block_a_compilation() {
    // Other tests restore OUT_DIR and clear the process-wide lease table.
    const CHILD_ENV: &str = "TUIST_CARGO_CACHE_TEST_OUT_DIR_LEASE_COLLISION";
    if std::env::var_os(CHILD_ENV).is_none() {
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "out_dir::tests::a_lease_from_another_pid_namespace_does_not_block_a_compilation",
                "--exact",
                "--test-threads=1",
            ])
            .env(CHILD_ENV, "1")
            .output()
            .unwrap();
        assert!(
            output.status.success()
                && String::from_utf8_lossy(&output.stdout).contains("test result: ok. 1 passed"),
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
        );
        return;
    }

    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let digest = "tree";
    let leases = leases_dir(&root, digest);
    std::fs::create_dir_all(&leases).unwrap();
    let occupied = leases.join(format!("{}.lease", std::process::id()));
    std::fs::write(&occupied, b"another namespace's lease").unwrap();
    let mut other = fslock::LockFile::open(&occupied).unwrap();
    assert!(other.try_lock().unwrap());

    let acquiring_root = root.clone();
    let (sent, received) = std::sync::mpsc::channel();
    let acquiring = std::thread::spawn(move || {
        let result = lease(&acquiring_root, digest).and_then(|()| lease(&acquiring_root, digest));
        let _ = sent.send(result);
    });
    received
        .recv_timeout(Duration::from_secs(5))
        .expect("lease acquisition must not wait for another namespace")
        .unwrap();
    acquiring.join().unwrap();
    assert_eq!(std::fs::read_dir(&leases).unwrap().count(), 2);
    let own = std::fs::read_dir(&leases)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| path != &occupied)
        .unwrap();
    let mut probe = fslock::LockFile::open(&own).unwrap();
    assert!(!probe.try_lock().unwrap());
    drop(probe);
    release(&root, digest);
    assert!(!own.exists());
    assert_eq!(
        std::fs::read(&occupied).unwrap(),
        b"another namespace's lease"
    );
    assert!(leased(&root, digest, false).unwrap());
    drop(other);
    assert!(!leased(&root, digest, true).unwrap());
    assert!(!occupied.exists());
}

#[test]
fn a_released_tree_can_be_leased_again_with_stale_files() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    let digest = "tree";
    let leases = leases_dir(root, digest);
    lease(root, digest).unwrap();
    let stale = std::fs::read_dir(&leases)
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    // Restoring Cargo's OUT_DIR drops the locks but leaves their files behind.
    release_all_under(root);
    std::fs::write(&stale, b"a released lease").unwrap();
    lease(root, digest).unwrap();
    assert_eq!(std::fs::read_dir(&leases).unwrap().count(), 2);
    assert_eq!(std::fs::read(&stale).unwrap(), b"a released lease");
    release_all_under(root);
    assert!(!leased(root, digest, true).unwrap());
    assert_eq!(std::fs::read_dir(&leases).unwrap().count(), 0);
}

#[test]
fn identical_trees_at_different_paths_share_one_stable_directory() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let first = directory.path().join("checkout-a/target/build/x/out");
    let second = directory.path().join("checkout-b/target/build/x/out");
    let files: &[(&str, &[u8])] = &[
        ("generated.rs", b"pub const VALUE: u32 = 7;\n"),
        ("nested/header.h", b"#define X 1\n"),
    ];
    write_tree(&first, files);
    write_tree(&second, files);

    let a = stabilize(&first, &root).unwrap().unwrap();
    let b = stabilize(&second, &root).unwrap().unwrap();

    assert_eq!(a, b, "the same bytes name the same directory");
    assert!(a.starts_with(&root));
    assert_eq!(
        std::fs::read(a.join("generated.rs")).unwrap(),
        b"pub const VALUE: u32 = 7;\n"
    );
    assert_eq!(
        std::fs::read(a.join("nested/header.h")).unwrap(),
        b"#define X 1\n"
    );
    assert!(
        std::fs::metadata(a.join("generated.rs"))
            .unwrap()
            .permissions()
            .readonly(),
        "the shared copy is read-only"
    );
    assert!(
        std::fs::read_dir(&root)
            .unwrap()
            .flatten()
            .all(|entry| !entry
                .file_name()
                .to_string_lossy()
                .starts_with(STAGING_PREFIX)),
        "no staging directory is left behind"
    );
}

#[test]
fn different_bytes_name_different_directories() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let first = directory.path().join("a/out");
    let second = directory.path().join("b/out");
    write_tree(
        &first,
        &[("generated.rs", b"pub const WHERE: &str = \"/a\";\n")],
    );
    write_tree(
        &second,
        &[("generated.rs", b"pub const WHERE: &str = \"/b\";\n")],
    );

    let a = stabilize(&first, &root).unwrap().unwrap();
    let b = stabilize(&second, &root).unwrap().unwrap();

    assert_ne!(a, b);
}

#[test]
fn a_renamed_file_names_a_different_directory() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let first = directory.path().join("a/out");
    let second = directory.path().join("b/out");
    write_tree(&first, &[("one.rs", b"x")]);
    write_tree(&second, &[("two.rs", b"x")]);

    assert_ne!(
        stabilize(&first, &root).unwrap(),
        stabilize(&second, &root).unwrap()
    );
}

#[cfg(unix)]
#[test]
fn the_executable_bit_is_part_of_the_name_and_survives_the_copy() {
    use std::os::unix::fs::PermissionsExt as _;
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let plain = directory.path().join("a/out");
    let executable = directory.path().join("b/out");
    write_tree(&plain, &[("tool", b"#!/bin/sh\n")]);
    write_tree(&executable, &[("tool", b"#!/bin/sh\n")]);
    std::fs::set_permissions(
        executable.join("tool"),
        std::fs::Permissions::from_mode(0o755),
    )
    .unwrap();

    let a = stabilize(&plain, &root).unwrap().unwrap();
    let b = stabilize(&executable, &root).unwrap().unwrap();

    assert_ne!(a, b);
    assert_eq!(
        std::fs::metadata(b.join("tool"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o555
    );
    assert_eq!(
        std::fs::metadata(a.join("tool"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o444
    );
}

#[cfg(unix)]
#[test]
fn a_tree_with_a_symlink_is_left_alone() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let out = directory.path().join("a/out");
    write_tree(&out, &[("generated.rs", b"x")]);
    std::os::unix::fs::symlink("generated.rs", out.join("link.rs")).unwrap();

    assert_eq!(stabilize(&out, &root).unwrap(), None);
    assert!(!root.exists(), "nothing was copied");
}

#[test]
fn the_scan_finds_a_mention_and_skips_what_is_not_source() {
    let directory = tempfile::tempdir().unwrap();
    let src = directory.path().join("src");
    write_tree(&src, &[("lib.rs", b"pub fn value() -> u32 { 1 }\n")]);
    assert!(!sources_mention_out_dir(&src));

    write_tree(
        &src,
        &[(
            "deep/generated.rs",
            b"include!(concat!(env!(\"OUT_DIR\"), \"/x.rs\"));\n",
        )],
    );
    assert!(sources_mention_out_dir(&src));

    // A mention under a target directory or in a non-Rust file is not the
    // crate reading it.
    let other = directory.path().join("other");
    write_tree(
        &other,
        &[
            ("target/debug/build/out/generated.rs", b"OUT_DIR"),
            ("notes.md", b"OUT_DIR"),
            (".hidden/lib.rs", b"OUT_DIR"),
            ("lib.rs", b"nothing"),
        ],
    );
    assert!(!sources_mention_out_dir(&other));
}

#[test]
fn unused_trees_are_collected_by_age_and_used_ones_kept() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let old = directory.path().join("a/out");
    let recent = directory.path().join("b/out");
    write_tree(&old, &[("generated.rs", b"old")]);
    write_tree(&recent, &[("generated.rs", b"recent")]);
    let old = stabilize(&old, &root).unwrap().unwrap();
    let recent = stabilize(&recent, &root).unwrap().unwrap();
    // The compilations that used them have exited.
    release_all_under(&root);
    let old_marker = marker_path(&root, &old.file_name().unwrap().to_string_lossy());
    let long_ago = std::time::SystemTime::now() - Duration::from_secs(3 * 24 * 60 * 60);
    std::fs::File::options()
        .write(true)
        .open(&old_marker)
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(long_ago))
        .unwrap();
    // A staging directory a dead process left is finished off too.
    let staging = root.join(format!("{STAGING_PREFIX}abc-1"));
    std::fs::create_dir(&staging).unwrap();
    std::fs::File::options()
        .read(true)
        .open(&staging)
        .ok()
        .map(|file| file.set_times(std::fs::FileTimes::new().set_modified(long_ago)));

    let dry = collect(&root, None, Some(Duration::from_secs(24 * 60 * 60)), true).unwrap();
    assert_eq!(dry.removed_directories, 1);
    assert!(old.exists(), "a dry run removes nothing");

    let outcome = collect(&root, None, Some(Duration::from_secs(24 * 60 * 60)), false).unwrap();

    assert_eq!(outcome.removed_directories, 1);
    assert_eq!(outcome.removed_bytes, 3);
    assert_eq!(outcome.remaining_directories, 1);
    assert!(!old.exists());
    assert!(!old_marker.exists());
    assert!(recent.exists());
    assert_eq!(stats(&root).unwrap().remaining_directories, 1);
}

#[test]
fn a_use_refreshes_the_marker_at_most_hourly() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let out = directory.path().join("a/out");
    write_tree(&out, &[("generated.rs", b"x")]);
    let stable = stabilize(&out, &root).unwrap().unwrap();
    let marker = marker_path(&root, &stable.file_name().unwrap().to_string_lossy());
    let earlier = std::time::SystemTime::now() - Duration::from_secs(10 * 60);
    std::fs::File::options()
        .write(true)
        .open(&marker)
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(earlier))
        .unwrap();

    stabilize(&out, &root).unwrap();
    let within_the_hour = std::fs::metadata(&marker).unwrap().modified().unwrap();
    assert!(
        within_the_hour <= earlier + Duration::from_secs(1),
        "ten minutes old is fresh enough"
    );

    let long_ago = std::time::SystemTime::now() - Duration::from_secs(2 * 60 * 60);
    std::fs::File::options()
        .write(true)
        .open(&marker)
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(long_ago))
        .unwrap();
    stabilize(&out, &root).unwrap();
    assert!(
        std::fs::metadata(&marker).unwrap().modified().unwrap()
            > long_ago + Duration::from_secs(60),
        "two hours old is restamped"
    );
}

#[test]
fn a_tree_a_compilation_holds_a_lease_on_is_not_collected() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let out = directory.path().join("a/out");
    write_tree(&out, &[("generated.rs", b"x")]);
    let stable = stabilize(&out, &root).unwrap().unwrap();
    let digest = stable.file_name().unwrap().to_string_lossy().into_owned();
    // A lease of this test's own, standing in for the shim of another
    // process: the leases this process took above are shared with every
    // other test in it, and released by whichever of them finishes first.
    let mut compiling =
        fslock::LockFile::open(&leases_dir(&root, &digest).join("other.lease")).unwrap();
    compiling.lock().unwrap();
    let marker = marker_path(&root, &digest);
    let long_ago = std::time::SystemTime::now() - Duration::from_secs(3 * 24 * 60 * 60);
    std::fs::File::options()
        .write(true)
        .open(&marker)
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(long_ago))
        .unwrap();

    let projected = collect(&root, None, Some(Duration::ZERO), true).unwrap();
    assert_eq!(projected.removed_directories, 0, "a dry run keeps it too");
    assert_eq!(projected.remaining_directories, 1);

    let outcome = collect(&root, None, Some(Duration::ZERO), false).unwrap();

    assert_eq!(outcome.removed_directories, 0, "a leased tree is kept");
    assert_eq!(outcome.remaining_directories, 1);
    assert!(stable.exists());

    // The compilations exit: their leases are nobody's, and the tree goes.
    drop(compiling);
    release_all_under(&root);
    let outcome = collect(&root, None, Some(Duration::ZERO), false).unwrap();

    assert_eq!(outcome.removed_directories, 1);
    assert!(!stable.exists());
    assert!(!leases_dir(&root, &digest).exists());
}

#[cfg(unix)]
#[test]
fn the_shared_copy_cannot_be_altered_through_its_directories() {
    use std::os::unix::fs::PermissionsExt as _;
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let out = directory.path().join("a/out");
    write_tree(&out, &[("nested/generated.rs", b"x")]);
    let stable = stabilize(&out, &root).unwrap().unwrap();

    for path in [stable.clone(), stable.join("nested")] {
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o555,
            "{}",
            path.display()
        );
    }
    // Collection still removes it, opening the directories up first.
    release_all_under(&root);
    let marker = marker_path(&root, &stable.file_name().unwrap().to_string_lossy());
    let long_ago = std::time::SystemTime::now() - Duration::from_secs(3 * 24 * 60 * 60);
    std::fs::File::options()
        .write(true)
        .open(&marker)
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(long_ago))
        .unwrap();
    collect(&root, None, Some(Duration::ZERO), false).unwrap();
    assert!(!stable.exists());
}

/// Environment-wide, so it runs in one test with the others' state cleared.
#[test]
fn a_bypassed_compilation_gets_cargos_out_dir_back_and_holds_no_lease() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let real = directory.path().join("target/build/x/out");
    write_tree(&real, &[("generated.rs", b"x")]);
    let stable = stabilize(&real, &root).unwrap().unwrap();
    let digest = stable.file_name().unwrap().to_string_lossy().into_owned();
    *ORIGINAL.lock().unwrap() = Some(real.clone().into_os_string());
    unsafe { std::env::set_var("OUT_DIR", &stable) };
    assert!(
        LEASES
            .lock()
            .unwrap()
            .keys()
            .any(|path| path.starts_with(leases_dir(&root, &digest)))
    );

    restore();

    assert_eq!(
        std::env::var_os("OUT_DIR").as_deref(),
        Some(real.as_os_str())
    );
    assert!(ORIGINAL.lock().unwrap().is_none());
    let _registrar = registrar(&root).unwrap();
    assert!(
        !leased(&root, &digest, true).unwrap(),
        "the lease went with the value"
    );
    unsafe { std::env::remove_var("OUT_DIR") };
}

#[cfg(unix)]
#[test]
fn a_name_that_spells_like_a_path_keeps_cargos_out_dir() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let nested = directory.path().join("a/out");
    let flat = directory.path().join("b/out");
    // `sub/dir` in one tree, a file literally named `sub\dir` in the other:
    // the same spelling with the separator replaced.
    write_tree(&nested, &[("sub/dir", b"")]);
    std::fs::create_dir_all(flat.join("sub")).unwrap();
    std::fs::write(flat.join("sub\\dir"), b"").unwrap();

    assert!(stabilize(&nested, &root).unwrap().is_some());
    assert_eq!(stabilize(&flat, &root).unwrap(), None);
}

#[test]
fn a_budget_evicts_the_least_recently_used_trees_first() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let mut trees = Vec::new();
    for (name, age_secs) in [("old", 300), ("older", 600), ("recent", 0)] {
        let out = directory.path().join(name).join("out");
        write_tree(&out, &[("generated.rs", format!("{name:>10}").as_bytes())]);
        let stable = stabilize(&out, &root).unwrap().unwrap();
        let marker = marker_path(&root, &stable.file_name().unwrap().to_string_lossy());
        let when = std::time::SystemTime::now() - Duration::from_secs(age_secs);
        std::fs::File::options()
            .write(true)
            .open(&marker)
            .unwrap()
            .set_times(std::fs::FileTimes::new().set_modified(when))
            .unwrap();
        trees.push((name, stable));
    }
    release_all_under(&root);

    // Ten bytes each: a budget of fifteen keeps one.
    let outcome = collect(&root, Some(15), None, false).unwrap();

    assert_eq!(outcome.removed_directories, 2);
    assert_eq!(outcome.remaining_bytes, 10);
    for (name, stable) in &trees {
        assert_eq!(stable.exists(), *name == "recent", "{name}");
    }
}

#[test]
fn a_failed_copy_leaves_no_lease_behind() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let out = directory.path().join("a/out");
    write_tree(&out, &[("generated.rs", b"x")]);
    // The root is a file, so nothing can be copied under it.
    std::fs::write(&root, b"").unwrap();

    assert!(stabilize(&out, &root).is_err());
    assert!(
        LEASES.lock().unwrap().is_empty()
            || !LEASES.lock().unwrap().keys().any(|p| p.starts_with(&root))
    );
}

#[test]
fn leases_of_a_tree_that_is_gone_are_swept() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    let out = directory.path().join("a/out");
    write_tree(&out, &[("generated.rs", b"x")]);
    let stable = stabilize(&out, &root).unwrap().unwrap();
    let digest = stable.file_name().unwrap().to_string_lossy().into_owned();
    release_all_under(&root);
    // The tree went without its leases, as when a copy failed after the
    // lease was taken and the process died.
    remove_tree(&stable).unwrap();
    assert!(leases_dir(&root, &digest).exists());

    collect(&root, None, None, false).unwrap();

    assert!(!leases_dir(&root, &digest).exists());
    assert!(!publish_lock_path(&root, &digest).exists());
}

#[test]
fn an_unlistable_root_measures_as_unknown_not_empty() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("out-dirs");
    std::fs::write(&root, b"not a directory").unwrap();

    assert_eq!(stats(&root), None);
    assert_eq!(
        stats(&directory.path().join("absent")),
        Some(PruneOutcome::default()),
        "a root that does not exist yet holds nothing"
    );
}
