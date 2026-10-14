use super::*;
use std::time::SystemTime;

/// Seed a build's own profiles, outside any lane.
fn seed(
    view: &Path,
    profiles: &[PathBuf],
    packages: &BTreeSet<String>,
    donors: &[Donor],
) -> SeedOutcome {
    super::seed(view, Path::new(""), profiles, packages, donors)
}

const LOCKFILE: &str = r#"
version = 4

[[package]]
name = "app"
version = "0.1.0"
dependencies = ["serde", "local"]

[[package]]
name = "local"
version = "0.1.0"

[[package]]
name = "serde"
version = "1.0.228"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "0000000000000000000000000000000000000000000000000000000000000000"

[[package]]
name = "shared-name"
version = "0.1.0"

[[package]]
name = "shared-name"
version = "2.0.0"
source = "git+https://example.com/shared?rev=abc#abc"
"#;

#[test]
fn registry_packages_leave_out_every_name_a_path_package_uses() {
    assert_eq!(
        registry_packages(LOCKFILE),
        BTreeSet::from(["serde".to_owned()])
    );
    assert!(registry_packages("not toml [").is_empty());
}

#[test]
fn profile_directories_follow_the_profile_and_targets() {
    let arguments = |words: &[&str]| {
        words
            .iter()
            .map(|word| word.to_string())
            .collect::<Vec<_>>()
    };
    assert_eq!(
        profile_directories(&arguments(&["build"])),
        [PathBuf::from("debug")]
    );
    assert_eq!(
        profile_directories(&arguments(&["test"])),
        [PathBuf::from("debug")]
    );
    assert_eq!(
        profile_directories(&arguments(&["bench"])),
        [PathBuf::from("release")]
    );
    assert_eq!(
        profile_directories(&arguments(&["build", "--profile", "fast"])),
        [PathBuf::from("fast")]
    );
    assert_eq!(
        profile_directories(&arguments(&[
            "build",
            "--release",
            "--target",
            "aarch64-unknown-linux-gnu",
            "--target=/specs/custom.json",
        ])),
        [
            PathBuf::from("release"),
            Path::new("aarch64-unknown-linux-gnu").join("release"),
            Path::new("custom").join("release"),
        ]
    );
}

/// Write a Cargo 1.100 unit with a fingerprint, a writable dep-info file,
/// and a read-only rlib like one restored from the store.
fn unit(profile: &Path, package: &str, hash: &str) -> PathBuf {
    let unit = profile.join("build").join(package).join(hash);
    std::fs::create_dir_all(unit.join("fingerprint")).unwrap();
    std::fs::create_dir_all(unit.join("out")).unwrap();
    std::fs::write(unit.join("fingerprint/lib-x"), b"0123456789abcdef").unwrap();
    std::fs::write(unit.join("out/x.d"), b"dep-info").unwrap();
    let rlib = unit.join("out/libx.rlib");
    std::fs::write(&rlib, b"rlib").unwrap();
    let mut permissions = std::fs::metadata(&rlib).unwrap().permissions();
    permissions.set_readonly(true);
    std::fs::set_permissions(&rlib, permissions).unwrap();
    unit
}

fn donor(directory: &Path) -> Donor {
    Donor {
        directory: directory.to_path_buf(),
        workspace_root: PathBuf::from("/checkouts/donor"),
        updated_secs: SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
    }
}

fn registry() -> BTreeSet<String> {
    BTreeSet::from(["serde".to_owned()])
}

#[test]
fn copies_registry_units_and_keeps_their_times() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = from.path().join("debug");
    std::fs::create_dir_all(&profile).unwrap();
    std::fs::write(profile.join(".cargo-lock"), b"").unwrap();
    let serde = unit(&profile, "serde", "0123456789abcdef");
    unit(&profile, "local", "fedcba9876543210");
    let modified = SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000);
    std::fs::File::options()
        .write(true)
        .open(serde.join("out/x.d"))
        .unwrap()
        .set_modified(modified)
        .unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome.units, 1);
    assert_eq!(outcome.donor, Some(PathBuf::from("/checkouts/donor")));
    let copied = to.path().join("debug/build/serde/0123456789abcdef");
    assert_eq!(
        std::fs::read(copied.join("fingerprint/lib-x")).unwrap(),
        b"0123456789abcdef"
    );
    assert_eq!(
        std::fs::metadata(copied.join("out/x.d"))
            .unwrap()
            .modified()
            .unwrap(),
        modified,
        "Cargo compares a unit's times with its dependencies'"
    );
    assert!(
        !to.path().join("debug/build/local").exists(),
        "a path package's unit is never copied"
    );
    assert_eq!(
        std::fs::read_dir(to.path().join("debug/build/serde"))
            .unwrap()
            .count(),
        1,
        "nothing staged is left behind"
    );
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt as _;
        let inode = |path: &Path| std::fs::metadata(path).unwrap().ino();
        assert_eq!(
            inode(&copied.join("out/libx.rlib")),
            inode(&serde.join("out/libx.rlib")),
            "a read-only store object is shared"
        );
        assert_ne!(
            inode(&copied.join("out/x.d")),
            inode(&serde.join("out/x.d")),
            "a writable file is copied, so a later build cannot change the donor's"
        );
    }
}

#[test]
fn a_profile_this_checkout_has_built_is_left_alone() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = from.path().join("debug");
    std::fs::create_dir_all(&profile).unwrap();
    unit(&profile, "serde", "0123456789abcdef");
    std::fs::create_dir_all(to.path().join("debug/build")).unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome, SeedOutcome::default());
    assert!(!to.path().join("debug/build/serde").exists());
}

#[test]
fn a_donor_without_cargo_1_100_units_is_skipped_for_the_next() {
    let old = tempfile::tempdir().unwrap();
    let new = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    // A pre-1.100 profile: units are spread across deps/ and .fingerprint/.
    std::fs::create_dir_all(old.path().join("debug/build/serde-0123456789abcdef")).unwrap();
    std::fs::create_dir_all(old.path().join("debug/.fingerprint/serde-0123456789abcdef")).unwrap();
    let profile = new.path().join("debug");
    unit(&profile, "serde", "0123456789abcdef");

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(old.path()), donor(new.path())],
    );

    assert_eq!(outcome.units, 1);
    assert!(
        to.path()
            .join("debug/build/serde/0123456789abcdef")
            .is_dir()
    );
}

#[test]
fn a_donor_profile_a_build_is_using_is_skipped() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = from.path().join("debug");
    unit(&profile, "serde", "0123456789abcdef");
    let mut building = fslock::LockFile::open(&profile.join(".cargo-lock")).unwrap();
    assert!(building.try_lock().unwrap());

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome, SeedOutcome::default());
    assert!(!to.path().join("debug/build").exists());
}

#[test]
fn the_pinned_build_script_binary_comes_along() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = from.path().join("debug");
    unit(&profile, "serde", "0123456789abcdef");
    let pinned = profile.join(".tuist_cargo_cache-build-script-shims/identity/tuist_cargo_cache");
    std::fs::create_dir_all(pinned.parent().unwrap()).unwrap();
    std::fs::write(&pinned, b"tuist_cargo_cache").unwrap();

    seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(
        std::fs::read(
            to.path()
                .join("debug/.tuist_cargo_cache-build-script-shims/identity/tuist_cargo_cache")
        )
        .unwrap(),
        b"tuist_cargo_cache"
    );
}

#[test]
fn only_units_the_donors_last_build_read_are_copied() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    if !crate::target_units::access_times_tracked(from.path()) {
        return;
    }
    let profile = from.path().join("debug");
    unit(&profile, "serde", "0123456789abcdef");
    let stale = unit(&profile, "serde", "fedcba9876543210");
    let old = SystemTime::now() - Duration::from_secs(10 * 24 * 60 * 60);
    for entry in std::fs::read_dir(stale.join("fingerprint"))
        .unwrap()
        .flatten()
    {
        std::fs::File::options()
            .write(true)
            .open(entry.path())
            .unwrap()
            .set_times(
                std::fs::FileTimes::new()
                    .set_accessed(old)
                    .set_modified(old),
            )
            .unwrap();
    }
    std::fs::File::open(stale.join("fingerprint"))
        .unwrap()
        .set_modified(old)
        .unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome.units, 1);
    assert!(
        to.path()
            .join("debug/build/serde/0123456789abcdef")
            .is_dir()
    );
    assert!(
        !to.path()
            .join("debug/build/serde/fedcba9876543210")
            .exists()
    );
}

#[test]
fn only_cargo_1_100_and_later_keep_units_in_directories() {
    assert!(keeps_units_in_directories(
        "cargo 1.100.0-nightly (98a09e7e7 2026-09-16)\n"
    ));
    assert!(keeps_units_in_directories("cargo 1.101.2 (abc 2027-01-01)"));
    assert!(keeps_units_in_directories("cargo 2.0.0"));
    assert!(!keeps_units_in_directories(
        "cargo 1.99.0-beta.7 (5f94df478 2026-08-27)"
    ));
    assert!(!keeps_units_in_directories(
        "cargo 1.98.1 (797e8a9bc 2026-08-05)"
    ));
    assert!(!keeps_units_in_directories("not cargo"));
    assert!(!keeps_units_in_directories(""));
}

#[test]
fn a_donor_with_nothing_usable_falls_through_to_the_next() {
    let unrelated = tempfile::tempdir().unwrap();
    let matching = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    unit(&unrelated.path().join("debug"), "tokio", "0123456789abcdef");
    unit(&matching.path().join("debug"), "serde", "0123456789abcdef");

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(unrelated.path()), donor(matching.path())],
    );

    assert_eq!(outcome.units, 1);
    assert!(
        to.path()
            .join("debug/build/serde/0123456789abcdef")
            .is_dir()
    );
    assert!(!to.path().join("debug/build/tokio").exists());
}

#[test]
fn recency_follows_the_profiles_own_latest_build() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    unit(&from.path().join("debug"), "serde", "0123456789abcdef");
    // A later build of another profile or project claimed the donor since.
    let mut later = donor(from.path());
    later.updated_secs += 10 * 24 * 60 * 60;

    let outcome = seed(to.path(), &[PathBuf::from("debug")], &registry(), &[later]);

    assert_eq!(outcome.units, 1);
}

#[test]
fn a_target_triple_the_donor_built_is_seeded_too() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    unit(&from.path().join("debug"), "serde", "0123456789abcdef");
    // Chosen by `build.target` or `--target host-tuple`, so the arguments
    // never name it.
    let triple = Path::new("aarch64-unknown-linux-gnu").join("debug");
    unit(&from.path().join(&triple), "serde", "fedcba9876543210");

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome.units, 2);
    assert!(
        to.path()
            .join(&triple)
            .join("build/serde/fedcba9876543210")
            .is_dir()
    );
}

#[test]
fn a_lane_is_seeded_from_the_same_lane_in_the_donor() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    unit(&from.path().join("debug"), "serde", "0123456789abcdef");
    unit(
        &from.path().join("check/debug"),
        "serde",
        "fedcba9876543210",
    );

    let outcome = super::seed(
        to.path(),
        Path::new("check"),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome.units, 1);
    assert!(
        to.path()
            .join("check/debug/build/serde/fedcba9876543210")
            .is_dir()
    );
    assert!(
        !to.path().join("debug").exists(),
        "a lane's build should leave the build profiles alone"
    );
}

#[cfg(unix)]
#[test]
fn symbolic_links_are_recreated_pointing_into_the_copy() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let source = unit(&from.path().join("debug"), "serde", "0123456789abcdef");
    std::fs::write(source.join("out/generated.rs"), b"generated").unwrap();
    std::os::unix::fs::symlink(
        source.join("out/generated.rs"),
        source.join("out/absolute.rs"),
    )
    .unwrap();
    std::os::unix::fs::symlink("generated.rs", source.join("out/relative.rs")).unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome.units, 1);
    let copied = to.path().join("debug/build/serde/0123456789abcdef");
    assert_eq!(
        std::fs::read_link(copied.join("out/absolute.rs")).unwrap(),
        copied.join("out/generated.rs"),
        "a link into the unit should point into this checkout's copy"
    );
    assert_eq!(
        std::fs::read_link(copied.join("out/relative.rs")).unwrap(),
        Path::new("generated.rs")
    );
    assert_eq!(
        std::fs::read(copied.join("out/absolute.rs")).unwrap(),
        b"generated"
    );
}

/// Give `unit` a build script's recorded run: `OUT_DIR` and its stdout.
fn run_output(unit: &Path, out_dir: &Path, stdout: &str) {
    std::fs::create_dir_all(unit.join("run")).unwrap();
    std::fs::write(
        unit.join("run/root-output"),
        out_dir.to_string_lossy().as_bytes(),
    )
    .unwrap();
    std::fs::write(unit.join("run/stdout"), stdout).unwrap();
}

#[test]
fn build_script_output_may_name_only_its_own_out_dir() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = from.path().join("debug");
    let own = unit(&profile, "serde", "0123456789abcdef");
    run_output(
        &own,
        &own.join("out"),
        &format!(
            "cargo:rustc-link-search=native={}\n",
            own.join("out").display()
        ),
    );
    let foreign = unit(&profile, "serde", "fedcba9876543210");
    run_output(
        &foreign,
        &foreign.join("out"),
        &format!(
            "cargo:rustc-link-search=native={}\n",
            profile.join("build/other/0000000000000000/out").display()
        ),
    );

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome.units, 1);
    let copied = to.path().join("debug/build/serde");
    assert!(
        copied.join("0123456789abcdef").is_dir(),
        "Cargo rewrites the recorded OUT_DIR itself"
    );
    assert!(
        !copied.join("fedcba9876543210").exists(),
        "any other path into the donor would keep pointing there"
    );
}

#[test]
fn a_build_script_file_naming_the_donor_keeps_the_unit_out() {
    // Cargo rewrites the recorded OUT_DIR only in the stdout it replays. A
    // file the script left, such as CMake's cache, keeps naming the donor.
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = from.path().join("debug");
    let clean = unit(&profile, "serde", "0123456789abcdef");
    run_output(&clean, &clean.join("out"), "cargo:rerun-if-changed=x\n");
    std::fs::write(clean.join("out/note.txt"), "names no checkout").unwrap();
    let naming = unit(&profile, "serde", "fedcba9876543210");
    run_output(&naming, &naming.join("out"), "cargo:rerun-if-changed=x\n");
    std::fs::create_dir(naming.join("out/build")).unwrap();
    std::fs::write(
        naming.join("out/build/CMakeCache.txt"),
        format!("BUILD_DIR:PATH={}/out/build\n", naming.display()),
    )
    .unwrap();
    // A compiler unit has no recorded run, and its outputs are not scanned.
    let compiled = unit(&profile, "serde", "aaaaaaaaaaaaaaaa");
    std::fs::write(
        compiled.join("out/x.d"),
        format!("{}: src/lib.rs\n", compiled.display()),
    )
    .unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome.units, 2);
    let copied = to.path().join("debug/build/serde");
    assert!(copied.join("0123456789abcdef").is_dir());
    assert!(copied.join("aaaaaaaaaaaaaaaa").is_dir());
    assert!(
        !copied.join("fedcba9876543210").exists(),
        "a copied CMakeCache.txt would make the script fail in this checkout"
    );
}

#[cfg(unix)]
#[test]
fn a_link_elsewhere_into_the_donor_keeps_the_unit_out() {
    let from = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = from.path().join("debug");
    let source = unit(&profile, "serde", "0123456789abcdef");
    let sibling = unit(&profile, "tokio", "fedcba9876543210");
    std::os::unix::fs::symlink(
        sibling.join("out/libx.rlib"),
        source.join("out/shared.rlib"),
    )
    .unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(from.path())],
    );

    assert_eq!(outcome, SeedOutcome::default());
    assert!(
        !to.path().join("debug/build").exists(),
        "a unit that could not be copied leaves nothing that looks built"
    );
}

#[cfg(unix)]
#[test]
fn a_donor_whose_units_all_fail_to_copy_does_not_block_the_next() {
    let failing = tempfile::tempdir().unwrap();
    let working = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = failing.path().join("debug");
    let source = unit(&profile, "serde", "0123456789abcdef");
    std::os::unix::fs::symlink(profile.join("elsewhere"), source.join("out/escape")).unwrap();
    unit(&working.path().join("debug"), "serde", "fedcba9876543210");

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(failing.path()), donor(working.path())],
    );

    assert_eq!(outcome.units, 1);
    assert!(
        to.path()
            .join("debug/build/serde/fedcba9876543210")
            .is_dir()
    );
    assert!(
        std::fs::read_dir(to.path().join("debug"))
            .unwrap()
            .flatten()
            .all(|entry| !entry.file_name().to_string_lossy().contains(STAGING_SUFFIX)),
        "nothing staged is left behind"
    );
}

/// A donor whose checkout reaches its managed directory through `target`.
fn linked_donor(view: &Path, checkout: &Path) -> Donor {
    Donor {
        directory: view.to_path_buf(),
        workspace_root: checkout.to_path_buf(),
        updated_secs: donor(view).updated_secs,
    }
}

#[test]
fn paths_spelled_through_the_donors_target_link_are_checked_too() {
    let view = tempfile::tempdir().unwrap();
    let checkout = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = view.path().join("debug");
    let linked = checkout.path().join("target/debug");
    // Cargo records these through `<checkout>/target`, not the managed path.
    let own = unit(&profile, "serde", "0123456789abcdef");
    let own_out = linked.join("build/serde/0123456789abcdef/out");
    run_output(
        &own,
        &own_out,
        &format!("cargo:rustc-link-search=native={}\n", own_out.display()),
    );
    let foreign = unit(&profile, "serde", "fedcba9876543210");
    run_output(
        &foreign,
        &linked.join("build/serde/fedcba9876543210/out"),
        &format!(
            "cargo:rustc-link-search=native={}\n",
            linked.join("build/other/0000000000000000/out").display()
        ),
    );

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[linked_donor(view.path(), checkout.path())],
    );

    assert_eq!(outcome.units, 1);
    assert!(
        to.path()
            .join("debug/build/serde/0123456789abcdef")
            .is_dir()
    );
    assert!(
        !to.path()
            .join("debug/build/serde/fedcba9876543210")
            .exists()
    );
}

#[cfg(unix)]
#[test]
fn links_spelled_through_the_donors_target_link_are_handled() {
    let view = tempfile::tempdir().unwrap();
    let checkout = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = view.path().join("debug");
    let linked = checkout.path().join("target/debug");
    let inside = unit(&profile, "serde", "0123456789abcdef");
    std::os::unix::fs::symlink(
        linked.join("build/serde/0123456789abcdef/out/x.d"),
        inside.join("out/alias.d"),
    )
    .unwrap();
    let escaping = unit(&profile, "serde", "fedcba9876543210");
    std::os::unix::fs::symlink(
        linked.join("build/tokio/0000000000000000/out/libx.rlib"),
        escaping.join("out/shared.rlib"),
    )
    .unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[linked_donor(view.path(), checkout.path())],
    );

    assert_eq!(outcome.units, 1);
    let copied = to.path().join("debug/build/serde/0123456789abcdef");
    assert_eq!(
        std::fs::read_link(copied.join("out/alias.d")).unwrap(),
        copied.join("out/x.d"),
        "a link into the unit through the checkout's target link points into the copy"
    );
    assert!(
        !to.path()
            .join("debug/build/serde/fedcba9876543210")
            .exists()
    );
}

#[cfg(unix)]
#[test]
fn a_relative_link_out_of_its_unit_keeps_the_unit_out() {
    let view = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = view.path().join("debug");
    let inside = unit(&profile, "serde", "0123456789abcdef");
    std::os::unix::fs::symlink("x.d", inside.join("out/alias.d")).unwrap();
    let escaping = unit(&profile, "serde", "fedcba9876543210");
    // Resolves to a sibling unit here; from the copy it would resolve into
    // whatever sits at the same place relative to this checkout.
    std::os::unix::fs::symlink(
        "../../../tokio/0000000000000000/out/libx.rlib",
        escaping.join("out/shared.rlib"),
    )
    .unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(view.path())],
    );

    assert_eq!(outcome.units, 1);
    let copied = to.path().join("debug/build/serde/0123456789abcdef");
    assert_eq!(
        std::fs::read_link(copied.join("out/alias.d")).unwrap(),
        Path::new("x.d")
    );
    assert!(
        !to.path()
            .join("debug/build/serde/fedcba9876543210")
            .exists()
    );
}

#[cfg(unix)]
#[test]
fn a_link_through_dot_dot_keeps_the_unit_out() {
    let view = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = view.path().join("debug");
    // Harmless by name, but `out/` could itself be a link that `..` climbs
    // back out of somewhere else.
    let roundabout = unit(&profile, "serde", "0123456789abcdef");
    std::os::unix::fs::symlink(
        roundabout.join("out/../out/x.d"),
        roundabout.join("out/alias.d"),
    )
    .unwrap();
    let escaping = unit(&profile, "serde", "fedcba9876543210");
    std::os::unix::fs::symlink(
        escaping.join("out/../../../tokio/0000000000000000/out/libx.rlib"),
        escaping.join("out/shared.rlib"),
    )
    .unwrap();
    let plain = unit(&profile, "serde", "1111111111111111");
    std::os::unix::fs::symlink(plain.join("out/x.d"), plain.join("out/alias.d")).unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(view.path())],
    );

    assert_eq!(outcome.units, 1);
    let copied = to.path().join("debug/build/serde/1111111111111111");
    assert_eq!(
        std::fs::read_link(copied.join("out/alias.d")).unwrap(),
        copied.join("out/x.d")
    );
}

#[cfg(unix)]
#[test]
fn a_relative_link_that_climbs_out_and_back_keeps_the_unit_out() {
    let view = tempfile::tempdir().unwrap();
    let to = tempfile::tempdir().unwrap();
    let profile = view.path().join("debug");
    let source = unit(&profile, "serde", "0123456789abcdef");
    // Leaves the unit by `..` and names the donor's own unit on the way back
    // down: the same file here, but the donor's copy from any other checkout.
    let view_name = view.path().file_name().unwrap().to_str().unwrap();
    std::os::unix::fs::symlink(
        format!("../../../../../../{view_name}/debug/build/serde/0123456789abcdef/out/x.d"),
        source.join("out/roundabout.d"),
    )
    .unwrap();

    let outcome = seed(
        to.path(),
        &[PathBuf::from("debug")],
        &registry(),
        &[donor(view.path())],
    );

    assert_eq!(outcome, SeedOutcome::default());
}

#[test]
fn a_donor_path_deep_in_a_large_output_file_is_found() {
    let directory = tempfile::tempdir().unwrap();
    let mut contents = vec![b'x'; 3 * 1024 * 1024];
    // Straddle a read boundary so a path split across two chunks is caught.
    let at = 64 * 1024 - 5;
    contents.splice(at..at, b"/donor/checkout/target".iter().copied());
    std::fs::write(directory.path().join("big.bin"), contents).unwrap();

    let found = donor_path_in_files(directory.path(), &["/donor/checkout/target".to_string()]);

    assert_eq!(found.as_deref(), Some("/donor/checkout/target"));
}

#[test]
fn a_donor_path_spelled_with_forward_slashes_is_found() {
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(
        directory.path().join("cache.txt"),
        "DIR=C:/work/donor/target/debug\n",
    )
    .unwrap();

    let found = donor_path_in_files(directory.path(), &[r"C:\work\donor\target".to_string()]);

    assert!(found.is_some());
}

#[test]
fn output_past_the_scan_budget_keeps_the_unit_out() {
    let directory = tempfile::tempdir().unwrap();
    let file = directory.path().join("huge.bin");
    let handle = std::fs::File::create(&file).unwrap();
    handle.set_len(SCAN_BUDGET + 1).unwrap();

    let found = donor_path_in_files(directory.path(), &["/donor".to_string()]);

    assert!(found.is_some_and(|reason| reason.contains("scan budget")));
}

#[test]
fn a_donor_path_in_stdout_spelled_with_forward_slashes_is_found() {
    let from = tempfile::tempdir().unwrap();
    let unit = from.path().join("unit");
    std::fs::create_dir_all(unit.join("run")).unwrap();
    std::fs::write(
        unit.join("run/stdout"),
        "cargo:rustc-link-search=C:/work/donor/target/x\n",
    )
    .unwrap();
    let donor = Donor {
        directory: PathBuf::from(r"C:\work\donor\target"),
        workspace_root: PathBuf::from(r"C:\work\donor"),
        ..donor(from.path())
    };

    assert!(foreign_path_in_output(&unit, &donor).is_some());
}
