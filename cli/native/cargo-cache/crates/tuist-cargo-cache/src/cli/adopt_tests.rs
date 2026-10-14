use super::adopt::{Adoption, adopt_checkout, find_checkouts};
use super::cargo_tests::managed_target_config;
use std::path::Path;

/// A directory holding a manifest and, when asked, a real target directory.
fn checkout(root: &Path, name: &str, with_target: bool) -> std::path::PathBuf {
    let directory = root.join(name);
    std::fs::create_dir_all(&directory).unwrap();
    std::fs::write(directory.join("Cargo.toml"), "[package]\n").unwrap();
    if with_target {
        std::fs::create_dir_all(directory.join("target/debug")).unwrap();
    }
    directory
}

#[test]
fn a_search_finds_checkouts_with_outputs_in_path_order() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    let b_nested = checkout(root, "b/nested", true);
    let a = checkout(root, "a", true);
    checkout(root, "b", false);
    checkout(root, ".hidden/c", true);
    // A project inside a target directory is a build output, not a checkout.
    checkout(root, "a/target/inner", true);
    // Outputs alone, with nothing to build them from, are not a checkout.
    std::fs::create_dir_all(root.join("stray/target")).unwrap();

    assert_eq!(find_checkouts(root).unwrap(), vec![a, b_nested]);
}

#[test]
fn a_search_includes_its_own_root_and_ignores_links() {
    let directory = tempfile::tempdir().unwrap();
    let root = checkout(directory.path(), "project", true);
    let elsewhere = checkout(directory.path(), "elsewhere", true);
    #[cfg(unix)]
    std::os::unix::fs::symlink(&elsewhere, root.join("link")).unwrap();
    #[cfg(windows)]
    std::os::windows::fs::symlink_dir(&elsewhere, root.join("link")).unwrap();

    assert_eq!(find_checkouts(&root).unwrap(), vec![root.clone()]);
}

#[test]
fn a_search_of_a_missing_directory_is_an_error() {
    let directory = tempfile::tempdir().unwrap();

    assert!(find_checkouts(&directory.path().join("missing")).is_err());
}

#[test]
fn a_checkout_without_outputs_or_a_manifest_is_left_alone() {
    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());
    let cargo = std::ffi::OsStr::new("cargo");
    let bare = directory.path().join("bare");
    std::fs::create_dir_all(bare.join("target")).unwrap();
    let empty = checkout(directory.path(), "empty", false);
    let linked = checkout(directory.path(), "linked", false);
    #[cfg(unix)]
    std::os::unix::fs::symlink(&bare, linked.join("target")).unwrap();
    #[cfg(windows)]
    std::os::windows::fs::symlink_dir(&bare, linked.join("target")).unwrap();

    for (checkout, reason) in [
        (&bare, "there is no Cargo.toml beside it"),
        (&empty, "there is no target directory"),
        (&linked, "it is a link, not a directory of outputs"),
    ] {
        assert_eq!(
            adopt_checkout(&config, cargo, checkout, false).unwrap(),
            Adoption::Skipped {
                target: checkout.join("target"),
                reason: reason.to_string(),
            }
        );
    }
    assert!(bare.join("target").is_dir());
}
