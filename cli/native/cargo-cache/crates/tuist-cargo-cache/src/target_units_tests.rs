use super::*;
use filetime::FileTime;

const DAY: Duration = Duration::from_secs(24 * 60 * 60);

fn now() -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(1_800_000_000)
}

/// Write `files` below `directory`, then date every file and directory in it
/// `age` before [`now`], as a build that last read them then would leave them.
fn unit(directory: &Path, files: &[&str], age: Duration) {
    for file in files {
        let path = directory.join(file);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, file.as_bytes()).unwrap();
    }
    let time = FileTime::from_system_time(now() - age);
    let mut pending = vec![directory.to_path_buf()];
    while let Some(next) = pending.pop() {
        for entry in std::fs::read_dir(&next).unwrap().flatten() {
            if entry.file_type().unwrap().is_dir() {
                pending.push(entry.path());
            }
            filetime::set_file_times(entry.path(), time, time).unwrap();
        }
        filetime::set_file_times(&next, time, time).unwrap();
    }
}

fn profile(view: &Path) -> PathBuf {
    let profile = view.join("debug");
    std::fs::create_dir_all(&profile).unwrap();
    std::fs::write(profile.join(".cargo-lock"), b"").unwrap();
    profile
}

const NEW_UNIT: &[&str] = &[
    "fingerprint/lib-widget",
    "fingerprint/lib-widget.json",
    "out/libwidget-0123456789abcdef.rlib",
];

#[test]
fn removes_the_units_no_build_used_within_the_age_limit() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    let stale = profile.join("build/widget/0123456789abcdef");
    let fresh = profile.join("build/widget/fedcba9876543210");
    let lonely = profile.join("build/gadget/0123456789abcdef");
    unit(&stale, NEW_UNIT, 40 * DAY);
    unit(&fresh, NEW_UNIT, 2 * DAY);
    unit(&lonely, NEW_UNIT, 40 * DAY);

    let outcome = prune(view.path(), 30 * DAY, now(), false);

    assert_eq!(outcome.removed_units, 2);
    assert!(outcome.removed_bytes > 0);
    assert!(!stale.exists());
    assert!(fresh.join("out/libwidget-0123456789abcdef.rlib").is_file());
    assert!(
        !profile.join("build/gadget").exists(),
        "a package directory with no units left is removed"
    );
    assert!(
        std::fs::read_dir(&profile)
            .unwrap()
            .flatten()
            .all(|entry| !entry
                .file_name()
                .to_string_lossy()
                .starts_with(REMOVAL_PREFIX)),
        "nothing is left moved aside"
    );
}

#[test]
fn a_read_of_the_fingerprint_keeps_an_old_unit() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    let used = profile.join("build/widget/0123456789abcdef");
    unit(&used, NEW_UNIT, 40 * DAY);
    // A fresh build reads the hash and writes nothing.
    filetime::set_file_atime(
        used.join("fingerprint/lib-widget"),
        FileTime::from_system_time(now() - DAY),
    )
    .unwrap();

    let outcome = prune(view.path(), 30 * DAY, now(), false);

    assert_eq!(outcome, UnitOutcome::default());
    assert!(used.join("out/libwidget-0123456789abcdef.rlib").is_file());
}

#[test]
fn the_age_limit_allows_a_day_for_relatime() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    let unit_directory = profile.join("build/widget/0123456789abcdef");
    unit(&unit_directory, NEW_UNIT, 30 * DAY + DAY / 2);

    assert_eq!(prune(view.path(), 30 * DAY, now(), false).removed_units, 0);
    assert!(unit_directory.exists());
}

#[test]
fn retires_an_unused_pre_1_100_layout_whole() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    unit(
        &profile.join(".fingerprint/widget-0123456789abcdef"),
        &["lib-widget", "lib-widget.json"],
        40 * DAY,
    );
    unit(
        &profile.join(".fingerprint/widget-fedcba9876543210"),
        &["build-script-build-script-build"],
        40 * DAY,
    );
    unit(
        &profile.join("deps"),
        &["libwidget-0123456789abcdef.rlib"],
        40 * DAY,
    );
    unit(
        &profile.join("build/widget-fedcba9876543210"),
        &["build-script-build", "out/generated.rs"],
        40 * DAY,
    );
    let current = profile.join("build/widget/0123456789abcdef");
    unit(&current, NEW_UNIT, DAY);

    let outcome = prune(view.path(), 30 * DAY, now(), false);

    assert_eq!(outcome.removed_units, 2);
    assert!(!profile.join(".fingerprint").exists());
    assert!(!profile.join("deps").exists());
    assert!(!profile.join("build/widget-fedcba9876543210").exists());
    assert!(
        current
            .join("out/libwidget-0123456789abcdef.rlib")
            .is_file()
    );
}

#[test]
fn keeps_a_pre_1_100_layout_any_build_still_uses() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    unit(
        &profile.join(".fingerprint/widget-0123456789abcdef"),
        &["lib-widget"],
        40 * DAY,
    );
    unit(
        &profile.join(".fingerprint/gadget-fedcba9876543210"),
        &["lib-gadget"],
        DAY,
    );
    unit(
        &profile.join("deps"),
        &["libwidget-0123456789abcdef.rlib"],
        40 * DAY,
    );

    assert_eq!(
        prune(view.path(), 30 * DAY, now(), false),
        UnitOutcome::default()
    );
    assert!(
        profile
            .join("deps/libwidget-0123456789abcdef.rlib")
            .is_file()
    );
}

#[test]
fn finds_profiles_below_a_target_triple() {
    let view = tempfile::tempdir().unwrap();
    let cross = profile(&view.path().join("aarch64-unknown-linux-gnu"));
    let stale = cross.join("build/widget/0123456789abcdef");
    unit(&stale, NEW_UNIT, 40 * DAY);

    assert_eq!(prune(view.path(), 30 * DAY, now(), false).removed_units, 1);
    assert!(!stale.exists());
}

#[test]
fn a_dry_run_reports_without_removing() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    let stale = profile.join("build/widget/0123456789abcdef");
    unit(&stale, NEW_UNIT, 40 * DAY);

    let outcome = prune(view.path(), 30 * DAY, now(), true);

    assert_eq!(outcome.removed_units, 1);
    assert!(outcome.removed_bytes > 0);
    assert!(stale.join("out/libwidget-0123456789abcdef.rlib").is_file());
}

#[test]
fn finishes_a_removal_an_interrupted_collection_left() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    let abandoned = profile.join(format!("{REMOVAL_PREFIX}1/0"));
    unit(&abandoned, NEW_UNIT, DAY);

    let outcome = prune(view.path(), 30 * DAY, now(), false);

    assert!(!profile.join(format!("{REMOVAL_PREFIX}1")).exists());
    assert!(
        outcome.removed_bytes > 0,
        "the leftover's bytes were counted in the view's size, so they count as freed"
    );
}

#[test]
fn finishes_a_pre_1_100_layout_an_interrupted_collection_left() {
    let view = tempfile::tempdir().unwrap();
    let profile = profile(view.path());
    // `.fingerprint/` went first; the outputs it vouched for did not follow.
    unit(
        &profile.join("deps"),
        &["libwidget-0123456789abcdef.rlib"],
        DAY,
    );
    unit(
        &profile.join("build/widget-fedcba9876543210"),
        &["build-script-build"],
        DAY,
    );
    let current = profile.join("build/widget/0123456789abcdef");
    unit(&current, NEW_UNIT, DAY);

    let outcome = prune(view.path(), 30 * DAY, now(), false);

    assert!(outcome.removed_bytes > 0);
    assert!(!profile.join("deps").exists());
    assert!(!profile.join("build/widget-fedcba9876543210").exists());
    assert!(
        current
            .join("out/libwidget-0123456789abcdef.rlib")
            .is_file()
    );
}

#[test]
fn finds_an_editors_profile_below_its_own_target_triple() {
    let view = tempfile::tempdir().unwrap();
    let nested = profile(&view.path().join("rust-analyzer/aarch64-unknown-linux-gnu"));
    let stale = nested.join("build/widget/0123456789abcdef");
    unit(&stale, NEW_UNIT, 40 * DAY);

    assert_eq!(prune(view.path(), 30 * DAY, now(), false).removed_units, 1);
    assert!(!stale.exists());
}

#[test]
fn a_directory_outside_any_profile_is_left_alone() {
    let view = tempfile::tempdir().unwrap();
    // No `.cargo-lock`: not a directory Cargo builds in.
    let stray = view.path().join("debug/build/widget/0123456789abcdef");
    unit(&stray, NEW_UNIT, 40 * DAY);

    assert_eq!(
        prune(view.path(), 30 * DAY, now(), false),
        UnitOutcome::default()
    );
    assert!(stray.exists());
}
