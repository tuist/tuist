use super::*;
use std::time::Duration;
use tuist_cargo_cache_core::{CacheDigest, LocalCas};

#[test]
fn combined_budget_respects_component_caps_and_occupied_reserves() {
    let retention = RetentionSettings {
        target_max_bytes: Some(80),
        target_max_age: None,
        incremental_max_bytes: Some(20),
        incremental_max_age: None,
        max_total_bytes: Some(100),
        target_precedence: Default::default(),
        min_free: None,
    };

    assert_eq!(target_budget(&retention, 70, 10), Some(20));
    assert_eq!(target_budget(&retention, 120, 10), Some(0));
    assert_eq!(incremental_budget(&retention, 70), Some(20));
    assert_eq!(incremental_budget(&retention, 90), Some(10));
    assert_eq!(incremental_budget(&retention, 120), Some(0));
    assert_eq!(store_budget(&retention, 70, Some(30)), 70);
    assert_eq!(store_budget(&retention, 70, Some(60)), 40);
}

#[test]
fn the_sweep_report_is_said_once() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    crate::util::write_atomic(
        &store.join(SWEEP_REPORT),
        b"removed 2 target directories\n\nevicted 3 objects\n",
    )
    .unwrap();

    assert_eq!(
        take_sweep_report(store),
        vec![
            "removed 2 target directories".to_string(),
            "evicted 3 objects".to_string()
        ]
    );
    assert!(
        take_sweep_report(store).is_empty(),
        "the second reader finds nothing"
    );
    let left = std::fs::read_dir(store.join("gc/v1"))
        .unwrap()
        .filter_map(|entry| entry.ok())
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("last-sweep-report")
        })
        .count();
    assert_eq!(
        left, 0,
        "neither the report nor its claimed copy is left behind"
    );
}

#[test]
fn no_report_means_nothing_to_say() {
    let directory = tempfile::tempdir().unwrap();

    assert!(take_sweep_report(directory.path()).is_empty());
}

#[test]
fn an_automatic_sweep_that_is_not_due_leaves_no_report() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = super::cargo_tests::managed_target_config(directory.path());
    config.gc.auto = true;
    config.gc.interval = std::time::Duration::from_secs(3600);
    assert!(crate::store::claim_sweep(&config.store_dir(), config.gc.interval).unwrap());

    run_automatic(&config, &RetentionSettings::default()).unwrap();

    assert!(!config.store_dir().join(SWEEP_REPORT).exists());
}

#[test]
fn an_automatic_sweep_stands_down_while_another_collector_holds_the_store() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = super::cargo_tests::managed_target_config(directory.path());
    config.gc.auto = true;
    config.gc.interval = std::time::Duration::ZERO;
    let store = config.store_dir();
    let mut other = collector_lock(&store).unwrap();
    assert!(other.try_lock().unwrap());

    run_automatic(&config, &RetentionSettings::default()).unwrap();

    assert!(
        !store.join("gc/v1/last-sweep").exists(),
        "the sweep was neither claimed nor run"
    );
}

#[test]
fn sweep_reports_accumulate_until_a_build_says_them() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    for report in ["first\n", "second\n"] {
        std::fs::create_dir_all(store.join("gc/v1")).unwrap();
        std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(store.join(SWEEP_REPORT))
            .and_then(|mut file| std::io::Write::write_all(&mut file, report.as_bytes()))
            .unwrap();
    }

    assert_eq!(take_sweep_report(store), ["first", "second"]);
}

#[test]
fn a_build_leaves_the_report_alone_while_a_collector_writes_it() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    crate::util::write_atomic(&store.join(SWEEP_REPORT), b"evicted 3 objects\n").unwrap();
    let mut collector = collector_lock(store).unwrap();
    assert!(collector.try_lock().unwrap());

    assert!(
        take_sweep_report(store).is_empty(),
        "not while the collector holds it"
    );

    collector.unlock().unwrap();
    assert_eq!(take_sweep_report(store), ["evicted 3 objects"]);
}

#[test]
fn leftovers_of_an_interrupted_collection_are_reported() {
    let units = crate::target::CollectionOutcome {
        removed_units: 3,
        removed_unit_bytes: 2048,
        ..Default::default()
    };
    let leftovers = crate::target::CollectionOutcome {
        removed_unit_bytes: 2048,
        ..Default::default()
    };

    assert_eq!(
        target_removals(&units, false),
        ["removed 3 unused build units from live target directories (2.0 KiB logical)"]
    );
    assert_eq!(
        target_removals(&leftovers, true),
        [
            "would remove build units an interrupted collection left in live target directories (2.0 KiB logical)"
        ]
    );
    assert!(target_removals(&crate::target::CollectionOutcome::default(), false).is_empty());
}

#[test]
fn relief_lowers_a_budget_by_the_shortfall_and_never_raises_it() {
    assert_eq!(
        relieve(Some(50), 80, 0),
        Some(50),
        "no shortfall, no change"
    );
    assert_eq!(
        relieve(Some(50), 80, 10),
        Some(50),
        "the budget already frees more"
    );
    assert_eq!(relieve(Some(50), 80, 40), Some(40));
    assert_eq!(
        relieve(None, 80, 40),
        Some(40),
        "an unlimited budget is limited"
    );
    assert_eq!(
        relieve(Some(50), 30, 40),
        Some(0),
        "everything collectable goes"
    );
}

/// A minimum no disk can meet, so every probe finds the disk short.
fn always_short() -> RetentionSettings {
    RetentionSettings {
        target_max_bytes: None,
        target_max_age: None,
        incremental_max_bytes: None,
        incremental_max_age: None,
        max_total_bytes: None,
        min_free: Some(crate::config::MinFree::Bytes(u64::MAX / 2)),
        target_precedence: Default::default(),
    }
}

#[test]
fn a_short_disk_is_found_only_when_a_minimum_is_set() {
    let directory = tempfile::tempdir().unwrap();
    let disk = low_disk(&always_short(), directory.path()).expect("the disk is short");
    assert!(disk.shortfall() > 0);
    assert!(
        disk.describe(false).contains("under the"),
        "{}",
        disk.describe(false)
    );

    let off = RetentionSettings {
        min_free: None,
        ..always_short()
    };
    assert_eq!(low_disk(&off, directory.path()), None);
    let met = RetentionSettings {
        min_free: Some(crate::config::MinFree::Bytes(0)),
        ..always_short()
    };
    assert_eq!(low_disk(&met, directory.path()), None);
}

#[test]
fn a_short_disk_brings_the_next_sweep_forward() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = super::cargo_tests::managed_target_config(directory.path());
    config.gc.interval = Duration::from_secs(3600);

    assert_eq!(sweep_interval(&config, &always_short()), LOW_DISK_INTERVAL);
    let off = RetentionSettings {
        min_free: None,
        ..always_short()
    };
    assert_eq!(sweep_interval(&config, &off), config.gc.interval);
    config.gc.interval = Duration::ZERO;
    assert_eq!(
        sweep_interval(&config, &always_short()),
        Duration::ZERO,
        "a shorter configured interval stands"
    );
}

#[test]
fn a_short_disk_claims_a_detached_collector_without_running_one_here() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = super::cargo_tests::managed_target_config(directory.path());
    config.target.views = false;
    config.gc.interval = Duration::from_secs(3600);
    let spawned = std::cell::Cell::new(0);
    let disk = |_path: &Path| {
        Some(crate::util::DiskSpace {
            total: 100,
            available: 10,
        })
    };
    let spawn = |_config: &Config| {
        spawned.set(spawned.get() + 1);
        Ok(())
    };

    schedule_low_disk_sweep(&config, crate::config::MinFree::Bytes(90), &disk, &spawn);

    assert_eq!(spawned.get(), 1);
}

#[test]
fn a_disk_with_room_does_not_start_a_collector() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = super::cargo_tests::managed_target_config(directory.path());
    config.target.views = false;
    let spawned = std::cell::Cell::new(0);
    let disk = |_path: &Path| {
        Some(crate::util::DiskSpace {
            total: 100,
            available: 100,
        })
    };
    let spawn = |_config: &Config| {
        spawned.set(spawned.get() + 1);
        Ok(())
    };

    schedule_low_disk_sweep(&config, crate::config::MinFree::Bytes(90), &disk, &spawn);

    assert_eq!(spawned.get(), 0);
}

#[test]
fn low_disk_collection_respects_auto_off_and_the_sweep_stamp() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = super::cargo_tests::managed_target_config(directory.path());
    config.target.views = false;
    config.gc.interval = Duration::from_secs(3600);
    let spawned = std::cell::Cell::new(0);
    let disk = |_path: &Path| {
        Some(crate::util::DiskSpace {
            total: 100,
            available: 10,
        })
    };
    let spawn = |_config: &Config| {
        spawned.set(spawned.get() + 1);
        Ok(())
    };

    config.gc.auto = false;
    schedule_low_disk_sweep(&config, crate::config::MinFree::Bytes(90), &disk, &spawn);
    assert_eq!(
        spawned.get(),
        0,
        "auto=false must avoid even the disk probe"
    );

    config.gc.auto = true;
    assert!(crate::store::claim_sweep(&config.store_dir(), config.gc.interval).unwrap());
    schedule_low_disk_sweep(&config, crate::config::MinFree::Bytes(90), &disk, &spawn);
    assert_eq!(spawned.get(), 0, "a fresh sweep stamp is not due");
}

#[test]
fn a_short_disk_collects_live_targets_past_their_budget() {
    let directory = tempfile::tempdir().unwrap();
    let config = super::cargo_tests::managed_target_config(directory.path());
    let mut views = Vec::new();
    for (name, updated_secs) in [("older", 1), ("newer", 2)] {
        let workspace = directory.path().join(name);
        std::fs::create_dir_all(&workspace).unwrap();
        let view = crate::target::place(&config, &workspace, &workspace.join("target"), false)
            .expect("the target is managed");
        std::fs::write(view.join("artifact"), vec![0_u8; 64]).unwrap();
        // Long ago, so neither reads as a build that is starting, and in
        // order, so `newer` is the most recently used.
        let record = view.with_extension("json");
        let mut fields: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&record).unwrap()).unwrap();
        fields["updated_secs"] = updated_secs.into();
        std::fs::write(&record, serde_json::to_vec(&fields).unwrap()).unwrap();
        views.push(view);
    }

    let unlimited = RetentionSettings {
        min_free: None,
        ..always_short()
    };
    let report = prune_targets(&config, &unlimited, config.gc.max_bytes);
    assert_eq!(report.freed_bytes, 0, "no budget and room to spare");
    assert!(views.iter().all(|view| view.exists()));

    let report = prune_targets(&config, &always_short(), config.gc.max_bytes);

    assert!(!views[0].exists(), "the older checkout's target went");
    assert!(views[1].exists(), "the most recently used one is kept");
    assert_eq!(report.freed_bytes, 64);
    assert!(
        report.removals[0].contains("under the"),
        "the report says why: {:?}",
        report.removals
    );
}

#[test]
fn json_report_includes_low_disk_target_removals() {
    let directory = tempfile::tempdir().unwrap();
    let config = super::cargo_tests::managed_target_config(directory.path());
    let mut views = Vec::new();
    for (name, updated_secs) in [("older", 1), ("newer", 2)] {
        let workspace = directory.path().join(name);
        std::fs::create_dir_all(&workspace).unwrap();
        let view = crate::target::place(&config, &workspace, &workspace.join("target"), false)
            .expect("the target is managed");
        std::fs::write(view.join("artifact"), vec![0_u8; 64]).unwrap();
        let record = view.with_extension("json");
        let mut fields: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&record).unwrap()).unwrap();
        fields["updated_secs"] = updated_secs.into();
        std::fs::write(&record, serde_json::to_vec(&fields).unwrap()).unwrap();
        views.push(view);
    }

    let retention = always_short();
    let low_disk = collect_low_disk(&config, &retention);
    assert!(
        !views[0].exists(),
        "low-disk collection removed the older target"
    );

    let report = low_disk.target_report(&Default::default());
    assert!(report.removed_directories > 0);
    assert!(report.removed_bytes > 0);
}

#[test]
fn a_short_disk_reaches_the_store_after_private_collections() {
    let directory = tempfile::tempdir().unwrap();
    let config = super::cargo_tests::managed_target_config(directory.path());
    let store = config.store_dir();
    let contents = b"an unrooted shared cache object";
    let digest = CacheDigest::blake3(contents);
    LocalCas::new(&store)
        .store_bytes(&digest, contents)
        .unwrap();
    assert_eq!(
        crate::store::stats(&store).unwrap().total_bytes(),
        contents.len() as u64
    );

    gc::run(&config, config.gc.max_bytes, false, false, &always_short()).unwrap();

    assert_eq!(
        crate::store::stats(&store).unwrap().total_bytes(),
        0,
        "low-disk collection reaches the shared store after private tiers"
    );
}

#[test]
fn a_claim_error_still_runs_the_full_automatic_sweep() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = super::cargo_tests::managed_target_config(directory.path());
    config.gc.auto = true;
    config.gc.interval = Duration::ZERO;
    let store = config.store_dir();
    let contents = b"an unrooted shared cache object";
    let digest = CacheDigest::blake3(contents);
    LocalCas::new(&store)
        .store_bytes(&digest, contents)
        .unwrap();
    let stamp = store.join("gc/v1/last-sweep");
    std::fs::create_dir_all(&stamp).unwrap();

    let sweep = sweep_store(&config, &always_short());

    assert!(
        sweep.delta.freed_store_bytes > 0,
        "a failed stamp claim still reaches store collection"
    );
    assert!(
        sweep.lines.iter().any(|line| {
            line.contains("below gc.max_size")
                && line.contains("under gc.min_free_size")
                && line.contains("logical freed")
        }),
        "store relief explains why it went below its budget: {:?}",
        sweep.lines
    );
    assert_eq!(crate::store::stats(&store).unwrap().total_bytes(), 0);
}

#[test]
fn a_directory_and_one_inside_it_are_on_the_same_disk() {
    let directory = tempfile::tempdir().unwrap();
    let nested = directory.path().join("not/created/yet");

    assert!(crate::util::same_disk(directory.path(), &nested));
    #[cfg(target_os = "linux")]
    assert!(
        !crate::util::same_disk(directory.path(), Path::new("/proc")),
        "procfs is a filesystem of its own"
    );
}

#[test]
fn a_combined_budget_shares_unoccupied_store_capacity() {
    for automatic in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let mut config = super::cargo_tests::managed_target_config(directory.path());
        config.gc.auto = true;
        config.gc.interval = Duration::ZERO;
        config.gc.max_bytes = 160;
        let retention = RetentionSettings {
            max_total_bytes: Some(160),
            min_free: None,
            ..always_short()
        };
        let mut views = Vec::new();
        for (name, updated_secs) in [("older", 1), ("newer", 2)] {
            let workspace = directory.path().join(name);
            std::fs::create_dir_all(&workspace).unwrap();
            let view = crate::target::place(&config, &workspace, &workspace.join("target"), false)
                .unwrap();
            std::fs::write(view.join("artifact"), [0_u8; 64]).unwrap();
            let record = view.with_extension("json");
            let mut fields: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&record).unwrap()).unwrap();
            fields["updated_secs"] = updated_secs.into();
            std::fs::write(&record, serde_json::to_vec(&fields).unwrap()).unwrap();
            views.push(view);
        }
        let collect = || {
            if automatic {
                sweep_store(&config, &retention);
            } else {
                gc::run(&config, config.gc.max_bytes, false, false, &retention).unwrap();
            }
        };
        collect();
        assert!(
            views.iter().all(|view| view.exists()),
            "an empty store leaves all 128 target bytes within budget"
        );

        // Store occupancy, rather than its potential 160-byte allowance,
        // now puts the combined cache over budget.
        let objects = config.store_dir().join("cas/v1");
        std::fs::create_dir_all(&objects).unwrap();
        std::fs::write(objects.join("object"), [0_u8; 64]).unwrap();
        assert_eq!(occupied_store_budget(&config, &retention, 160), 64);
        assert_eq!(occupied_store_budget(&config, &retention, 32), 32);
        gc::run(&config, config.gc.max_bytes, true, false, &retention).unwrap();
        assert!(
            views.iter().all(|view| view.exists()),
            "dry runs preserve targets"
        );
        collect();
        assert!(
            !views[0].exists(),
            "the older target makes room for the occupied store"
        );
        assert!(views[1].exists(), "the newest target remains protected");
        let tight = RetentionSettings {
            max_total_bytes: Some(32),
            ..retention
        };
        let sweep = sweep_store(&config, &tight);
        assert!(
            views[1].exists(),
            "even an impossible budget preserves the newest target"
        );
        assert!(
            sweep
                .lines
                .iter()
                .any(|line| line.contains("over gc.max_total_size")),
            "the next build receives the budget warning: {:?}",
            sweep.lines
        );
    }
}

#[test]
fn unavailable_component_sizes_do_not_leave_room_in_a_combined_budget() {
    for component in ["targets", "incremental", "generated"] {
        for automatic in [false, true] {
            for combined in [false, true] {
                let directory = tempfile::tempdir().unwrap();
                let mut config = super::cargo_tests::managed_target_config(directory.path());
                config.gc.auto = true;
                config.gc.interval = Duration::ZERO;
                config.gc.max_bytes = 160;
                let retention = RetentionSettings {
                    max_total_bytes: combined.then_some(160),
                    min_free: None,
                    ..always_short()
                };
                let broken = match component {
                    "targets" => config.target.root.join("v1"),
                    "incremental" => config.cache_dir.join("incremental"),
                    _ => config.cache_dir.join(crate::out_dir::ROOT),
                };
                // A file where a directory is required fails listing on every
                // platform, including when the tests run with root privileges.
                std::fs::create_dir_all(broken.parent().unwrap()).unwrap();
                std::fs::write(&broken, b"not a directory").unwrap();
                let objects = config.store_dir().join("cas/v1");
                std::fs::create_dir_all(&objects).unwrap();
                std::fs::write(objects.join("object"), [0_u8; 64]).unwrap();

                if automatic {
                    let sweep = sweep_store(&config, &retention);
                    assert_eq!(
                        sweep
                            .lines
                            .iter()
                            .any(|line| line.contains("could not be verified")),
                        combined,
                        "{component}: {:?}",
                        sweep.lines
                    );
                } else {
                    // Even a failed preview must leave shared objects alone.
                    let _ = gc::run(&config, 160, true, false, &retention);
                    assert_eq!(
                        crate::store::stats(&config.store_dir())
                            .unwrap()
                            .total_bytes(),
                        64
                    );
                    let result = gc::run(&config, 160, false, false, &retention);
                    assert_eq!(result.is_err(), component == "targets");
                }
                assert_eq!(
                    crate::store::stats(&config.store_dir())
                        .unwrap()
                        .total_bytes(),
                    if combined { 0 } else { 64 },
                    "{component}, automatic={automatic}, combined={combined}"
                );
                assert!(broken.exists(), "the unmeasurable component is left alone");
            }
        }
    }
}
