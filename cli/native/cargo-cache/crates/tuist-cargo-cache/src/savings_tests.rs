use super::*;

const GIB: u64 = 1024 * 1024 * 1024;

fn session_delta(hits: u64) -> Delta {
    Delta {
        builds: 1,
        cached_compilations: hits,
        ..Delta::default()
    }
}

#[test]
fn totals_accumulate_across_commands() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();

    let first = record(store, &session_delta(3)).unwrap();
    assert_eq!(first.version, 1);
    assert_eq!(first.builds, 1);
    assert_eq!(first.cached_compilations, 3);

    let second = record(
        store,
        &Delta {
            builds: 1,
            cached_compilations: 4,
            freed_target_bytes: 2 * GIB,
            ..Delta::default()
        },
    )
    .unwrap();
    assert_eq!(second.builds, 2);
    assert_eq!(second.cached_compilations, 7);
    assert_eq!(second.freed_target_bytes, 2 * GIB);
    assert_eq!(
        second.since_secs, first.since_secs,
        "the start of counting is stamped once"
    );
}

#[test]
fn a_tally_nobody_can_parse_starts_over_instead_of_failing() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    record(store, &session_delta(2)).unwrap();
    crate::util::write_atomic(&store.join(TALLY_FILE), b"not json at all").unwrap();

    let tally = record(store, &session_delta(5)).unwrap();

    assert_eq!(tally.builds, 1, "counting restarts from the corrupt file");
    assert_eq!(tally.cached_compilations, 5);
    assert_eq!(tally.version, 1);
}

#[test]
fn a_missing_store_directory_is_created() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("never").join("existed");

    let tally = record(&store, &session_delta(1)).unwrap();

    assert_eq!(tally.builds, 1);
    assert!(store.join(TALLY_FILE).exists());
}

#[test]
fn counters_from_a_newer_cargo_cache_survive_a_write_by_this_one() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    crate::util::write_atomic(
        &store.join(TALLY_FILE),
        br#"{"version":2,"builds":7,"nanoseconds_saved_by_something_new":42}"#,
    )
    .unwrap();

    let tally = record(store, &session_delta(1)).unwrap();

    assert_eq!(tally.builds, 8, "known counters still accumulate");
    let written: serde_json::Value =
        serde_json::from_slice(&std::fs::read(store.join(TALLY_FILE)).unwrap()).unwrap();
    assert_eq!(
        written["nanoseconds_saved_by_something_new"], 42,
        "a counter this binary does not know must not be dropped: {written}"
    );
    assert_eq!(written["version"], 2, "and its version is left alone");
}

#[test]
fn a_sweep_during_a_help_run_still_counts_what_it_freed() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();

    // `build --help` compiles nothing, but an automatic sweep can come due
    // during it and those bytes are gone from the disk for real.
    let line = record_and_describe(
        store,
        &Delta {
            freed_store_bytes: 3 * GIB,
            ..Delta::default()
        },
        &SessionFacts::default(),
        SavingsStyle::Quips,
    );

    assert!(line.is_some(), "3GiB reclaimed is worth reporting");
    let tally = record(store, &Delta::default()).unwrap();
    assert_eq!(tally.freed_store_bytes, 3 * GIB);
    assert_eq!(tally.builds, 0, "but it was not a build");
}

#[test]
fn nothing_is_written_before_the_first_run_that_does_something() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();

    assert_eq!(
        record_and_describe(
            store,
            &Delta::default(),
            &SessionFacts::default(),
            SavingsStyle::Quips
        ),
        None
    );

    assert!(
        !store.join(TALLY_FILE).exists(),
        "an inert run leaves no tally behind"
    );
}

#[test]
fn a_confirmed_removal_is_not_bragged_about_as_collection() {
    // The user said yes to removing this target/; every collection line claims
    // nobody had to do anything. Those bytes are counted, not performed.
    let tally = Tally {
        version: 1,
        builds: 1,
        freed_requested_bytes: 30 * GIB,
        ..Tally::default()
    };
    assert_eq!(
        quip(&tally, &SessionFacts::default(), SavingsStyle::Quips),
        None,
        "consented bytes earn no unattended-cleanup line"
    );
    let recorded = {
        let directory = tempfile::tempdir().unwrap();
        record(
            directory.path(),
            &Delta {
                freed_requested_bytes: 30 * GIB,
                ..Delta::default()
            },
        )
        .unwrap()
    };
    assert_eq!(
        recorded.freed_requested_bytes,
        30 * GIB,
        "but they are still in the ledger"
    );
}

#[test]
fn durations_keep_their_remainders() {
    let cases = [
        (6 * 3600 + 14 * 60, "6h 14m"),
        (86_400 + 5 * 60, "1d 5m"),
        (6 * 3600, "6h"),
        (61, "1m 1s"),
        (86_400 + 3600 + 60, "1d 1h"),
        (45, "45s"),
    ];
    for (seconds, expected) in cases {
        assert_eq!(
            nanos(crate::util::duration_ns(Duration::from_secs(seconds))),
            expected,
            "for {seconds}s"
        );
    }
}

#[test]
fn a_quiet_machine_has_nothing_to_say() {
    let tally = Tally {
        version: 1,
        builds: 3,
        cached_compilations: 4,
        ..Tally::default()
    };
    assert_eq!(
        quip(&tally, &SessionFacts::default(), SavingsStyle::Quips),
        None
    );
}

/// A tally that clears every threshold, so all facts are on the table.
fn boastful_tally() -> Tally {
    Tally {
        version: 1,
        builds: 87,
        cached_compilations: 4_312,
        avoided_compiler_ns: crate::util::duration_ns(Duration::from_secs(6 * 3600 + 14 * 60)),
        reflinked_bytes: 22 * GIB,
        freed_target_bytes: 41 * GIB,
        freed_store_bytes: 6 * GIB,
        ..Tally::default()
    }
}

fn busy_session() -> SessionFacts {
    SessionFacts {
        hits: 143,
        avoided_compiler_ns: crate::util::duration_ns(Duration::from_secs(171)),
    }
}

#[test]
fn every_line_names_the_number_that_earned_it() {
    let tally = boastful_tally();
    let candidates = facts_worth_telling(&tally, &busy_session());
    // In declaration order; every telling of a fact must carry its figure,
    // or a random draw could produce a brag with nothing behind it.
    let figures: [&[&str]; 6] = [
        &["143", "2m 51s"],
        &["6h 14m", "87 builds"],
        &["47.0 GiB"],
        &["41.0 GiB"],
        &["22.0 GiB"],
        &["4312"],
    ];
    assert_eq!(candidates.len(), figures.len());
    for (candidate, expected) in candidates.iter().zip(figures) {
        for line in candidate.cheeky.iter().chain([&candidate.plain]) {
            for figure in expected {
                assert!(line.contains(figure), "{line:?} should contain {figure:?}");
            }
        }
    }
}

#[test]
fn the_random_draw_can_reach_every_line() {
    let tally = boastful_tally();
    let facts = busy_session();
    let candidates = facts_worth_telling(&tally, &facts);
    let pool: usize = candidates.iter().map(|fact| fact.cheeky.len()).sum();

    let widest = candidates
        .iter()
        .map(|fact| fact.cheeky.len())
        .max()
        .unwrap();
    let mut seen = std::collections::HashSet::new();
    for fact in 0..candidates.len() {
        for variant in 0..widest {
            let mut draws = [fact, variant].into_iter();
            let line = quip_choosing(&tally, &facts, SavingsStyle::Quips, |_| {
                draws.next().unwrap_or(0)
            })
            .unwrap();
            seen.insert(line);
        }
    }

    assert_eq!(seen.len(), pool, "every variant is reachable: {seen:#?}");
}

#[test]
fn thresholds_gate_facts_not_the_whole_mouth() {
    // Only the lifetime-count fact qualifies here; whichever draw happens,
    // that is the fact reported.
    let tally = Tally {
        version: 1,
        builds: 30,
        cached_compilations: 9_000,
        ..Tally::default()
    };
    for _ in 0..20 {
        let line = quip(&tally, &SessionFacts::default(), SavingsStyle::Quips).unwrap();
        assert!(line.contains("9000"), "{line:?}");
    }
}

#[test]
fn plain_style_states_the_fact_without_the_bit() {
    let tally = boastful_tally();
    for _ in 0..20 {
        let line = quip(&tally, &busy_session(), SavingsStyle::Plain).unwrap();
        assert!(
            line.starts_with("tuist_cargo_cache[savings]: "),
            "plain lines read like the cache/gc notes: {line:?}"
        );
    }
}

#[test]
fn off_keeps_quiet_even_with_plenty_to_say() {
    assert_eq!(
        quip(&boastful_tally(), &busy_session(), SavingsStyle::Off),
        None
    );
}

#[test]
fn consecutive_builds_do_not_recite_one_line() {
    // Probabilistic, but with a pool this size, 200 draws repeating one line
    // means the randomness is broken, not unlucky.
    let tally = boastful_tally();
    let facts = busy_session();
    let distinct: std::collections::HashSet<_> = (0..200)
        .map(|_| quip(&tally, &facts, SavingsStyle::Quips).unwrap())
        .collect();
    assert!(distinct.len() > 1, "200 draws produced one line");
}

#[test]
fn a_build_that_did_nothing_stays_silent() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    // Seed totals large enough that every lifetime threshold is met.
    record(
        store,
        &Delta {
            builds: 10,
            cached_compilations: 5_000,
            reflinked_bytes: 20 * GIB,
            ..Delta::default()
        },
    )
    .unwrap();

    let before = std::fs::read(store.join(TALLY_FILE)).unwrap();
    let silent = record_and_describe(
        store,
        &Delta::default(),
        &SessionFacts::default(),
        SavingsStyle::Quips,
    );
    assert_eq!(silent, None, "a no-op run reports nothing");
    assert_eq!(
        std::fs::read(store.join(TALLY_FILE)).unwrap(),
        before,
        "and does not even touch the totals"
    );

    let spoken = record_and_describe(
        store,
        &Delta {
            builds: 1,
            cached_compilations: 6,
            ..Delta::default()
        },
        &SessionFacts {
            hits: 6,
            ..SessionFacts::default()
        },
        SavingsStyle::Quips,
    );
    assert!(spoken.is_some(), "a run that used the cache reports");
}

#[test]
fn quips_can_be_turned_off_without_stopping_the_tally() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path();
    let delta = Delta {
        builds: 1,
        cached_compilations: 5_000,
        ..Delta::default()
    };

    let line = record_and_describe(
        store,
        &delta,
        &SessionFacts {
            hits: 20,
            ..SessionFacts::default()
        },
        SavingsStyle::Off,
    );

    assert_eq!(line, None);
    let tally = record(store, &Delta::default()).unwrap();
    assert_eq!(
        tally.cached_compilations, 5_000,
        "the totals are kept even when nothing is printed"
    );
}

/// Not an assertion so much as a proofreading bench: run with `--nocapture`
/// to read the whole pool the way users will, with lifelike numbers.
#[test]
fn the_full_pool_reads_like_a_person_wrote_it() {
    for candidate in facts_worth_telling(&boastful_tally(), &busy_session()) {
        for line in &candidate.cheeky {
            println!("{line}");
        }
        println!("  ({})", candidate.plain);
        println!();
    }
}

#[test]
fn automatic_pruning_gets_its_own_start_date_without_reclassifying_old_gc() {
    let directory = tempfile::tempdir().unwrap();
    let first = record(
        directory.path(),
        &Delta {
            freed_store_bytes: 100,
            ..Delta::default()
        },
    )
    .unwrap();
    assert!(first.auto_pruned_since_secs > 0);
    assert_eq!(first.auto_pruned_bytes, 0);
    let second = record(
        directory.path(),
        &Delta {
            freed_target_bytes: 40,
            auto_pruned_bytes: 40,
            ..Delta::default()
        },
    )
    .unwrap();
    assert_eq!(second.auto_pruned_bytes, 40);
    assert_eq!(second.auto_pruned_since_secs, first.auto_pruned_since_secs);
    assert_eq!(second.freed_store_bytes + second.freed_target_bytes, 140);
}
