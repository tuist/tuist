use super::*;

fn pool_at(dir: &Path, capacity: u64, bytes_per_permit: u64) -> Pool {
    let mut pool = Pool::new(
        dir.to_path_buf(),
        capacity,
        bytes_per_permit,
        SchedulerPriority::Normal,
    );
    // Tests must not depend on how much memory the machine running them has
    // free; anything that wants the gate closed injects its own probe.
    pool.available_memory = || None;
    pool.pressure = false;
    pool
}

#[test]
fn capacity_is_enforced_and_released() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 2, 0);

    let first = pool.try_admit(1, None).unwrap().expect("first permit");
    let second = pool.try_admit(1, None).unwrap().expect("second permit");
    assert!(
        pool.try_admit(1, None).unwrap().is_none(),
        "a full pool must refuse"
    );

    drop(first);
    let third = pool.try_admit(1, None).unwrap();
    assert!(third.is_some(), "a released permit frees capacity");
    drop(second);
    drop(third);

    // Not merely unlocked: a released lease leaves no file behind. Windows
    // refuses to delete a file anyone still holds open, so a permit that only
    // unlocked its handle would leave one of these per compilation there --
    // capacity would stay correct and the directory would grow forever.
    let leases: Vec<_> = std::fs::read_dir(directory.path().join(LEASES_DIR))
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect();
    assert!(leases.is_empty(), "released leases are removed: {leases:?}");
}

#[test]
fn leases_never_collide_with_a_name_already_taken() {
    // This test's own counter: the process-wide one is advanced by every test
    // running in parallel, which could hand the stand-in's name to a lease
    // below or skip past it, and then the test would not exercise a collision.
    static NONCE: AtomicU64 = AtomicU64::new(0);
    let directory = tempfile::tempdir().unwrap();
    let mut pool = pool_at(directory.path(), 8, 0);
    pool.lease_nonce = || NONCE.fetch_add(1, Ordering::Relaxed);
    let leases = directory.path().join(LEASES_DIR);

    let held: Vec<_> = (0..4)
        .map(|_| pool.try_admit(1, None).unwrap().expect("permit"))
        .collect();
    let names: std::collections::BTreeSet<_> = std::fs::read_dir(&leases)
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .collect();
    assert_eq!(names.len(), 4, "every live lease has its own file");

    // A pid is unique only inside its namespace, so a name that is merely
    // "pid plus counter" collides between two containers sharing a cache --
    // silently truncating a live holder's record. Stood in for by a lease
    // somebody else holds the lock on, since that is what makes the name
    // genuinely taken: an unlocked file of the same name is a dead holder's,
    // and reclaiming it is correct.
    let taken = NONCE.load(Ordering::Relaxed);
    let squatted = leases.join(format!(
        "{}-{}-{taken}",
        std::process::id(),
        process_token()
    ));
    std::fs::write(&squatted, b"another namespace's lease").unwrap();
    let mut elsewhere = fslock::LockFile::open(&squatted).unwrap();
    assert!(
        elsewhere.try_lock().unwrap(),
        "the stand-in holds its lease"
    );

    let next = pool.try_admit(1, None).unwrap().expect("permit");
    assert_eq!(
        NONCE.load(Ordering::Relaxed),
        taken + 2,
        "the grant tried the taken name and moved on to the next"
    );
    assert!(
        leases
            .join(format!(
                "{}-{}-{}",
                std::process::id(),
                process_token(),
                taken + 1
            ))
            .exists(),
        "the successful retry uses the next nonce"
    );
    assert_eq!(
        std::fs::read(&squatted).unwrap(),
        b"another namespace's lease",
        "a name in use is left exactly as it was found"
    );
    drop(next);
    drop(held);
}

#[test]
fn weights_count_against_capacity() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 4, 0);

    let heavy = pool.try_admit(3, None).unwrap().expect("heavy permit");
    let light = pool.try_admit(1, None).unwrap().expect("last permit");
    assert!(pool.try_admit(1, None).unwrap().is_none());
    drop(heavy);
    assert!(pool.try_admit(3, None).unwrap().is_some());
    drop(light);
}

#[test]
fn a_reservation_charges_the_larger_of_cpu_and_memory_requests() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 4, 1024);

    let reservation = pool.reserve(Some(1), Some(3 * 1024)).unwrap();
    assert!(
        pool.try_admit(2, None).unwrap().is_none(),
        "three memory permits leave only one"
    );
    drop(reservation);
    assert!(pool.try_admit(4, None).unwrap().is_some());
}

#[test]
fn a_reservation_requires_a_requested_resource() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 4, 1024);

    assert!(pool.reserve(None, None).is_err());
}

#[test]
fn a_memory_reservation_needs_a_memory_budget() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 4, 0);

    assert!(pool.reserve(None, Some(1024)).is_err());
}

#[test]
fn a_waiting_normal_reservation_holds_low_priority_work_back() {
    let directory = tempfile::tempdir().unwrap();
    let normal = pool_at(directory.path(), 1, 0);
    let held = normal.try_admit(1, None).unwrap().expect("first permit");
    let waiting_dir = directory.path().to_path_buf();
    let waiter = std::thread::spawn(move || {
        let pool = pool_at(&waiting_dir, 1, 0);
        pool.reserve(Some(1), None).unwrap()
    });

    for _ in 0..20 {
        if directory.path().join(PRIORITY_WAIT_STAMP).exists() {
            break;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    assert!(
        directory.path().join(PRIORITY_WAIT_STAMP).exists(),
        "a normal reservation waiting for capacity announces itself"
    );
    drop(held);
    drop(waiter.join().unwrap());
}

#[test]
fn a_build_limit_counts_only_that_builds_leases() {
    let directory = tempfile::tempdir().unwrap();
    let mut other = pool_at(directory.path(), 6, 0);
    other.build = Some(("other".into(), 6));
    let elsewhere = other.try_admit(2, None).unwrap().expect("other build");

    let mut limited = pool_at(directory.path(), 6, 0);
    limited.build = Some(("limited".into(), 2));
    let own = limited
        .try_admit(2, None)
        .unwrap()
        .expect("two permits beside another build");
    assert!(
        limited.try_admit(1, None).unwrap().is_none(),
        "the build cannot exceed its own ceiling even with machine capacity free"
    );

    drop(own);
    assert!(
        limited.try_admit(3, None).unwrap().is_some(),
        "one demand heavier than the build ceiling still makes progress"
    );
    drop(elsewhere);
}

#[test]
fn a_dead_holders_lease_is_reclaimed() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 1, 0);

    // A lease file nobody holds a lock on is what a killed shim leaves behind.
    let leases = directory.path().join(LEASES_DIR);
    std::fs::create_dir_all(&leases).unwrap();
    let stale = leases.join("999999-0");
    std::fs::write(
        &stale,
        serde_json::to_vec(&Lease {
            version: LEASE_VERSION,
            weight: 1,
            priority: "normal".into(),
            build_id: None,
        })
        .unwrap(),
    )
    .unwrap();

    let permit = pool.try_admit(1, None).unwrap();
    assert!(permit.is_some(), "a stale lease must not hold capacity");
    assert!(!stale.exists(), "the stale lease is removed");
}

#[test]
fn a_demand_heavier_than_the_pool_runs_alone_rather_than_never() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 2, 0);

    // Heavier than the whole machine, and gated by a probe that reports no
    // memory at all: it still compiles, alone.
    let mut short = pool_at(directory.path(), 2, 0);
    short.available_memory = || Some(0);
    let permit = short.try_admit(10, Some(u64::MAX)).unwrap();
    assert!(permit.is_some(), "an oversized demand is admitted alone");
    // And while it runs, nothing else fits.
    assert!(pool.try_admit(1, None).unwrap().is_none());
}

#[test]
fn low_priority_leaves_the_reserve_even_on_an_idle_pool() {
    let directory = tempfile::tempdir().unwrap();
    let mut low = Pool::new(directory.path().to_path_buf(), 4, 0, SchedulerPriority::Low);
    low.available_memory = || None;
    std::fs::write(directory.path().join(PRIORITY_WAIT_STAMP), b"").unwrap();

    // An idle pool is the ordinary state between two compilations, so it is
    // no licence to stop yielding: three of the four permits are what a
    // low-priority build may take while somebody is waiting.
    let admitted = low.try_admit(3, None).unwrap();
    assert!(admitted.is_some(), "what fits beside the reserve is taken");
    let leases = std::fs::read_dir(directory.path().join(LEASES_DIR))
        .unwrap()
        .count();
    assert_eq!(leases, 1);
    drop(admitted);
}

#[test]
fn a_weight_the_reserve_would_never_admit_still_runs_alone() {
    let directory = tempfile::tempdir().unwrap();
    let mut low = Pool::new(directory.path().to_path_buf(), 4, 0, SchedulerPriority::Low);
    low.available_memory = || None;
    std::fs::write(directory.path().join(PRIORITY_WAIT_STAMP), b"").unwrap();

    // Four permits out of four never fits beside a reserve of one, and a
    // weight is already clamped to the capacity, so refusing here would not
    // be yielding -- it would be a compilation that never runs at all for as
    // long as anybody keeps waiting. It goes alone instead.
    assert!(
        low.try_admit(4, None).unwrap().is_some(),
        "a demand the reserve excludes outright runs by itself"
    );
}

#[test]
fn a_predicted_heavy_compile_does_not_wait_out_the_gate_on_an_idle_machine() {
    let directory = tempfile::tempdir().unwrap();
    let bytes_per_permit = 1024;
    let mut pool = pool_at(directory.path(), 4, bytes_per_permit);
    // Short of memory, and nothing running that could give any back.
    pool.available_memory = || Some(1);
    // Through `plan`, because that is the only weight production ever asks
    // for -- and it clamps to the capacity, so a rule written against
    // heavier-than-capacity weights would never fire for a real compilation.
    pool.record_peak(&ledger_key("enormous", true), bytes_per_permit * 1000, true)
        .unwrap();
    let (weight, predicted) = pool.plan(&Demand::new("enormous", true));
    assert_eq!(
        weight, 4,
        "a clamped weight is what admission actually sees"
    );

    assert!(
        pool.try_admit(weight, predicted).unwrap().is_some(),
        "an idle machine admits it rather than waiting out the gate deadline"
    );
}

#[test]
fn the_reserve_never_swallows_the_whole_pool() {
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(directory.path().join(PRIORITY_WAIT_STAMP), b"").unwrap();

    // A quarter of one permit rounds up to one, which would leave a
    // single-permit machine reserving everything -- and then the only way a
    // low-priority build could ever run would be the oversized-demand escape,
    // which hands it the whole machine at once. Yielding must not invert.
    for capacity in 1..=8 {
        let mut low = Pool::new(
            directory.path().to_path_buf(),
            capacity,
            0,
            SchedulerPriority::Low,
        );
        low.available_memory = || None;
        assert!(
            low.reserved() < capacity,
            "capacity {capacity} reserved all of itself"
        );
        let permit = low.try_admit(1, None).unwrap();
        assert!(
            permit.is_some(),
            "low priority makes progress at capacity {capacity}"
        );
    }
}

#[test]
fn the_memory_gate_defers_predicted_heavy_work() {
    let directory = tempfile::tempdir().unwrap();
    let mut pool = pool_at(directory.path(), 8, 0);
    pool.available_memory = || Some(1024);

    let running = pool.try_admit(1, None).unwrap().expect("first permit");
    assert!(
        pool.try_admit(2, Some(2048)).unwrap().is_none(),
        "a predicted-heavy job defers while memory is short"
    );
    assert!(
        pool.try_admit(2, Some(512)).unwrap().is_some(),
        "a prediction that fits is admitted"
    );
    assert!(
        pool.try_admit(2, None).unwrap().is_some(),
        "an unpredicted job is not gated"
    );
    drop(running);
}

#[test]
fn low_priority_leaves_the_reserve_while_a_normal_build_waits() {
    let directory = tempfile::tempdir().unwrap();
    let normal = pool_at(directory.path(), 4, 0);
    let mut low = Pool::new(directory.path().to_path_buf(), 4, 0, SchedulerPriority::Low);
    low.available_memory = || None;

    let held = normal.try_admit(2, None).unwrap().expect("two permits");
    std::fs::write(directory.path().join(PRIORITY_WAIT_STAMP), b"").unwrap();

    // capacity 4 minus a reserve of 1: the two held plus one more would fit,
    // but low priority must leave the reserve for whoever stamped.
    assert!(low.try_admit(2, None).unwrap().is_none());
    let admitted = low.try_admit(1, None).unwrap();
    assert!(admitted.is_some(), "low priority still uses spare capacity");
    // The normal build takes the reserved permit low priority left alone.
    assert!(normal.try_admit(1, None).unwrap().is_some());
    drop(held);
    drop(admitted);
}

#[test]
fn plans_weigh_history_links_and_nothing() {
    let directory = tempfile::tempdir().unwrap();
    let bytes_per_permit = 1024;
    let pool = pool_at(directory.path(), 8, bytes_per_permit);
    pool.record_peak("heavy", 3500, false).unwrap();
    pool.record_peak("enormous", 1024 * 1024, false).unwrap();

    let (weight, predicted) = pool.plan(&Demand::new("unseen", false));
    assert_eq!((weight, predicted), (1, None));

    let (weight, predicted) = pool.plan(&Demand::new("unseen", true));
    assert_eq!(
        (weight, predicted),
        (LINK_WEIGHT, Some(LINK_WEIGHT * bytes_per_permit)),
        "an unmeasured link starts at the link floor"
    );

    let (weight, predicted) = pool.plan(&Demand::new("heavy", false));
    assert_eq!((weight, predicted), (4, Some(3500)));

    // "heavy" was measured compiling to metadata, and a link of that same
    // crate must not inherit it: `cargo check` and `cargo build` name one
    // crate for two very different workloads, and the metadata-only number
    // is the smaller. Inheriting it retires the link floor with a
    // measurement that was never a link's -- over-admission with a
    // plausible number attached. An unmeasured link keeps the floor.
    let (weight, predicted) = pool.plan(&Demand::new("heavy", true));
    assert_eq!(
        (weight, predicted),
        (LINK_WEIGHT, Some(LINK_WEIGHT * bytes_per_permit)),
        "a metadata-only measurement never speaks for the link beside it"
    );

    // A link measured *as a link* is weighted by what it used, whichever
    // side of the floor that falls on -- above it,
    pool.record_peak(&ledger_key("heavy", true), 9000, true)
        .unwrap();
    let (weight, predicted) = pool.plan(&Demand::new("heavy", true));
    assert_eq!(
        (weight, predicted),
        (8, Some(9000)),
        "a link's own history above the floor wins"
    );
    // and below it, which is the floor being retired rather than raised.
    pool.record_peak(&ledger_key("light-link", true), 700, true)
        .unwrap();
    let (weight, predicted) = pool.plan(&Demand::new("light-link", true));
    assert_eq!(
        (weight, predicted),
        (1, Some(700)),
        "a link's own history below the floor also wins"
    );
    // The two entries are genuinely separate, not one overwriting the other.
    assert_eq!(
        pool.plan(&Demand::new("heavy", false)),
        (4, Some(3500)),
        "the metadata entry survives the link entry beside it"
    );

    let (weight, _) = pool.plan(&Demand::new("enormous", false));
    assert_eq!(weight, 8, "weights clamp to the capacity");

    // Without a memory budget there is no ledger and no prediction; only the
    // static link floor remains.
    let unweighted = pool_at(directory.path(), 8, 0);
    assert_eq!(unweighted.plan(&Demand::new("heavy", false)), (1, None));
    assert_eq!(
        unweighted.plan(&Demand::new("heavy", true)),
        (LINK_WEIGHT, None)
    );
}

/// A test binary is charged for its threads as well as its memory, and never
/// shares a ledger entry with the crate compiled under the same name.
#[test]
fn test_binaries_weigh_their_threads_and_their_own_history() {
    let directory = tempfile::tempdir().unwrap();
    let bytes_per_permit = 1000;
    let pool = pool_at(directory.path(), 8, bytes_per_permit);

    assert_eq!(
        pool.plan(&Demand::test("suite", None)),
        (4, None),
        "an unstated thread count takes half the pool"
    );
    assert_eq!(pool.plan(&Demand::test("suite", Some(3))), (3, None));
    assert_eq!(
        pool.plan(&Demand::test("suite", Some(64))),
        (8, None),
        "threads clamp to the capacity"
    );

    // The compile of `suite` measured light and the run measured heavy; each
    // is planned from its own entry.
    pool.record_peak("suite", 1500, false).unwrap();
    pool.record_peak("suite [test, 1 threads]", 6500, false)
        .unwrap();
    assert_eq!(pool.plan(&Demand::new("suite", false)), (2, Some(1500)));
    assert_eq!(
        pool.plan(&Demand::test("suite", Some(1))),
        (7, Some(6500)),
        "memory outweighs a single thread"
    );

    let odd = pool_at(directory.path(), 5, 0);
    assert_eq!(
        odd.plan(&Demand::test("suite", None)),
        (3, None),
        "half an odd pool rounds up"
    );
    assert_eq!(
        pool_at(directory.path(), 1, 0).plan(&Demand::test("suite", Some(0))),
        (1, None),
        "a demand never weighs nothing"
    );
}

/// A test binary's measured core count replaces the guess, is kept per thread
/// setting, and is never lowered by a reading taken on a busier machine.
#[test]
fn test_binaries_are_weighed_by_the_cores_they_were_measured_using() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 8, 0);

    pool.record_cpu("suite [test]", 2).unwrap();
    assert_eq!(
        pool.plan(&Demand::test("suite", None)),
        (2, None),
        "a measurement replaces half the pool, even without a memory budget"
    );
    assert_eq!(
        pool.plan(&Demand::test("suite", Some(6))),
        (6, None),
        "a stated thread count has its own history"
    );
    assert_eq!(
        pool.plan(&Demand::new("suite", false)),
        (1, None),
        "compilations are not measured for cores"
    );

    pool.record_cpu("suite [test]", 1).unwrap();
    assert_eq!(pool.plan(&Demand::test("suite", None)), (2, None));
    pool.record_cpu("suite [test]", 12).unwrap();
    assert_eq!(
        pool.plan(&Demand::test("suite", None)),
        (8, None),
        "a higher reading raises it, clamped to the capacity"
    );
}

#[test]
fn average_cores_round_to_the_nearest_core() {
    let seconds = Duration::from_secs_f64;
    assert_eq!(average_cores(seconds(0.01), seconds(2.0)), 1);
    assert_eq!(average_cores(seconds(2.8), seconds(2.0)), 1);
    assert_eq!(average_cores(seconds(3.2), seconds(2.0)), 2);
    assert_eq!(average_cores(seconds(15.0), seconds(2.0)), 8);
    assert_eq!(average_cores(seconds(1.0), Duration::ZERO), 1);
}

/// Every test binary is its own crate name, so a cold `cargo test --no-run`
/// never finds a per-crate entry for the link in front of it. What the machine
/// has learned about links in general is what it has to go on instead.
#[test]
fn an_unmeasured_link_is_weighed_by_what_this_machine_s_links_have_cost() {
    let directory = tempfile::tempdir().unwrap();
    let bytes_per_permit = 1000;
    let pool = pool_at(directory.path(), 8, bytes_per_permit);

    // Below the sample floor, one measurement is an anecdote: the static
    // weight still stands.
    pool.record_peak(&ledger_key("first", true), 5000, true)
        .unwrap();
    pool.record_peak(&ledger_key("second", true), 4000, true)
        .unwrap();
    assert_eq!(
        pool.plan(&Demand::new("unseen", true)),
        (LINK_WEIGHT, Some(LINK_WEIGHT * bytes_per_permit)),
        "two measurements are not yet history"
    );

    // The third makes it history, and the heaviest of them is the guess.
    pool.record_peak(&ledger_key("third", true), 3000, true)
        .unwrap();
    assert_eq!(
        pool.plan(&Demand::new("unseen", true)),
        (5, Some(5000)),
        "an unmeasured link is weighed by the heaviest link this machine made"
    );

    // A link this machine has actually measured still speaks for itself.
    pool.record_peak(&ledger_key("known", true), 1500, true)
        .unwrap();
    assert_eq!(
        pool.plan(&Demand::new("known", true)),
        (2, Some(1500)),
        "a crate's own history outranks the machine's"
    );

    // And nothing about this reaches a compilation that never links.
    assert_eq!(pool.plan(&Demand::new("unseen", false)), (1, None));
}

/// The window is what links cost *lately*, so it forgets in order and keeps
/// recording even when the crate's own entry has nothing to learn.
#[test]
fn the_link_window_is_bounded_and_records_every_link() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 8, 1000);

    for index in 0..MAX_LINK_SAMPLES + 4 {
        pool.record_peak(&ledger_key("crate", true), 1000 + index as u64, true)
            .unwrap();
    }
    let ledger = read_ledger(&pool.ledger_path());
    assert_eq!(ledger.link_peaks.len(), MAX_LINK_SAMPLES);
    assert_eq!(
        ledger.link_peaks.first().copied(),
        Some(1000 + 4),
        "the oldest measurements are the ones dropped"
    );

    // A measurement no higher than the crate's recorded peak leaves the entry
    // alone, but the window still saw a link happen.
    let before = read_ledger(&pool.ledger_path()).link_peaks.len();
    pool.record_peak(&ledger_key("crate", true), 1, true)
        .unwrap();
    let after = read_ledger(&pool.ledger_path());
    assert_eq!(after.link_peaks.len(), before);
    assert_eq!(after.link_peaks.last().copied(), Some(1));
    assert_eq!(
        after.crates.get(&ledger_key("crate", true)).copied(),
        Some(1000 + MAX_LINK_SAMPLES as u64 + 3),
        "a lower measurement never shrinks the recorded peak"
    );
}

/// A repeat compilation that teaches the ledger nothing writes nothing: the
/// file is rewritten under a lock, and every crate in a build would otherwise
/// pay for it on every build after the first.
#[test]
fn a_measurement_that_changes_nothing_leaves_the_ledger_alone() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 8, 1000);
    pool.record_peak("crate", 4000, false).unwrap();

    let written = || {
        std::fs::metadata(pool.ledger_path())
            .and_then(|metadata| metadata.modified())
            .unwrap()
    };
    let before = written();
    // Coarse filesystem timestamps would hide a rewrite that happened within
    // the same tick, so the check is on the bytes as well.
    let bytes = std::fs::read(pool.ledger_path()).unwrap();
    pool.record_peak("crate", 1000, false).unwrap();
    assert_eq!(std::fs::read(pool.ledger_path()).unwrap(), bytes);
    assert_eq!(written().duration_since(before).unwrap().as_nanos(), 0);

    // A link, though, always has a window entry to add.
    pool.record_peak(&ledger_key("crate", true), 1, true)
        .unwrap();
    assert_eq!(
        read_ledger(&pool.ledger_path()).link_peaks,
        vec![1],
        "a link's measurement lands in the window even when it teaches the entry nothing"
    );
}

#[test]
fn the_ledger_only_remembers_what_matters_and_never_shrinks_a_peak() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 4, 1000);

    // Under one permit's worth of memory: not worth a ledger entry.
    assert_eq!(ledger_peak(900, false, false, true, 1000), None);
    // Over it: recorded as measured.
    assert_eq!(ledger_peak(1500, false, false, true, 1000), Some(1500));
    // A link that succeeded is recorded even light, because that is what
    // retires its floor.
    assert_eq!(ledger_peak(900, false, true, true, 1000), Some(900));

    pool.record_peak("crate", 1500, false).unwrap();
    pool.record_peak("crate", 1200, false).unwrap();
    assert_eq!(
        read_ledger(&pool.ledger_path()).crates.get("crate"),
        Some(&1500),
        "a lower later measurement never shrinks the recorded peak"
    );

    let garbage = pool.ledger_path();
    std::fs::write(&garbage, b"not json").unwrap();
    assert!(read_ledger(&garbage).crates.is_empty());
    pool.record_peak("crate", 1500, false).unwrap();
    assert_eq!(read_ledger(&garbage).crates.get("crate"), Some(&1500));
}

#[test]
fn an_oom_kill_escalates_past_what_was_measured() {
    // The killer stopped it at 1500; the record says it needs more than that.
    assert_eq!(ledger_peak(1500, true, false, false, 1000), Some(3000));
    // Even a tiny measurement escalates past one permit, so the weight rises.
    assert_eq!(ledger_peak(10, true, false, false, 1000), Some(1001));
    // A killed link escalates too, rather than recording what it reached.
    assert_eq!(ledger_peak(1500, true, true, false, 1000), Some(3000));
}

#[test]
fn a_link_that_never_reached_the_linker_cannot_cheapen_the_ones_that_do() {
    // Whether an invocation links is its crate type, not its outcome: a
    // binary that dies in type checking is a "link" that never ran one. Its
    // small peak must not retire the floor -- machine-wide, for every later
    // build sharing the cache -- on the strength of a compilation that never
    // did the expensive thing.
    assert_eq!(
        ledger_peak(900, false, true, false, 1000),
        None,
        "a failed link records nothing it could later be admitted on"
    );
    // The failure can still say something is heavy, which is the direction
    // that keeps a link that died reaching for memory from repeating itself.
    assert_eq!(ledger_peak(4000, false, true, false, 1000), Some(4000));
    // And the successful link of the same shape still retires its floor.
    assert_eq!(ledger_peak(900, false, true, true, 1000), Some(900));
}

#[test]
fn the_ledger_drops_its_smallest_entries_at_the_cap() {
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 4, 1);

    for index in 0..MAX_LEDGER_ENTRIES + 10 {
        pool.record_peak(&format!("crate-{index}"), 100 + index as u64, false)
            .unwrap();
    }
    let ledger = read_ledger(&pool.ledger_path());
    assert_eq!(ledger.crates.len(), MAX_LEDGER_ENTRIES);
    assert!(
        !ledger.crates.contains_key("crate-0"),
        "the smallest entries go first"
    );
    let largest = format!("crate-{}", MAX_LEDGER_ENTRIES + 9);
    assert!(ledger.crates.contains_key(&largest));
}

#[cfg(target_os = "linux")]
#[test]
fn a_flight_leaves_its_prediction_for_the_next_build() {
    let directory = tempfile::tempdir().unwrap();

    let first = flight_at(directory.path(), "rustc", "abc123").unwrap();
    assert!(!first.waited(), "an empty pool has nothing to wait on");
    assert_eq!(first.inherited(), None, "nothing was left before");
    first.leave("the prediction");
    drop(first);

    let second = flight_at(directory.path(), "rustc", "abc123").unwrap();
    assert!(!second.waited(), "the first flight released its lock");
    assert_eq!(
        second.inherited(),
        Some("the prediction"),
        "what a flight leaves outlives it"
    );
}

#[test]
fn a_waiter_wakes_to_what_its_holder_left() {
    let directory = tempfile::tempdir().unwrap();
    let dir = directory.path().to_path_buf();

    let holder = flight_at(&dir, "rustc", "abc123").unwrap();
    let waiter = std::thread::spawn(move || flight_at(&dir, "rustc", "abc123").unwrap());
    // Long enough for the thread to block on the lock; a race the other way
    // only weakens the `waited` assertion into a flake-free pass.
    std::thread::sleep(std::time::Duration::from_millis(100));
    holder.leave("freshly published");
    drop(holder);

    let waiter = waiter.join().unwrap();
    assert!(waiter.waited(), "the second flight blocked on the first");
    assert_eq!(waiter.inherited(), Some("freshly published"));
}

#[test]
fn a_record_that_does_not_describe_this_flight_is_not_inherited() {
    let directory = tempfile::tempdir().unwrap();

    let holder = flight_at(directory.path(), "rustc", "abc123").unwrap();
    holder.leave("a rustc prediction");
    drop(holder);

    // Same file name could never collide across these, but the record itself
    // must also say what it is: a version bump or a corrupt write reads as
    // nothing rather than as a prediction.
    let other = flight_at(directory.path(), "cc", "abc123").unwrap();
    assert_eq!(other.inherited(), None);
    drop(other);

    let path = directory
        .path()
        .join(INFLIGHT_DIR)
        .join("rustc-abc123.prediction");
    std::fs::write(&path, b"not json").unwrap();
    let corrupt = flight_at(directory.path(), "rustc", "abc123").unwrap();
    assert_eq!(corrupt.inherited(), None, "garbage reads as nothing");
}

#[test]
fn the_sweep_keeps_fresh_and_held_flights_and_drops_the_rest() {
    let cache = tempfile::tempdir().unwrap();
    let scheduler = cache.path().join(SCHEDULER_DIR);
    let inflight = scheduler.join(INFLIGHT_DIR);

    let old = flight_at(&scheduler, "rustc", "old").unwrap();
    old.leave("stale");
    drop(old);
    let fresh = flight_at(&scheduler, "rustc", "fresh").unwrap();
    fresh.leave("current");
    drop(fresh);
    let held = flight_at(&scheduler, "rustc", "held").unwrap();

    let backdate = |name: &str| {
        let ancient = std::time::SystemTime::now() - FLIGHT_MAX_AGE - Duration::from_secs(60);
        for path in [
            inflight.join(name),
            inflight.join(format!("{name}.prediction")),
        ] {
            if path.exists() {
                std::fs::File::options()
                    .write(true)
                    .open(&path)
                    .unwrap()
                    .set_modified(ancient)
                    .unwrap();
            }
        }
    };
    backdate("rustc-old");
    backdate("rustc-held");

    prune_flights(cache.path());

    assert!(!inflight.join("rustc-old").exists(), "stale flights go");
    assert!(!inflight.join("rustc-old.prediction").exists());
    assert!(inflight.join("rustc-fresh").exists(), "fresh flights stay");
    assert!(inflight.join("rustc-fresh.prediction").exists());
    assert!(
        inflight.join("rustc-held").exists(),
        "a lock that cannot be taken is a live compilation, whatever its age"
    );
    drop(held);
}

#[test]
fn an_oversized_payload_is_not_left_behind() {
    let directory = tempfile::tempdir().unwrap();

    let holder = flight_at(directory.path(), "rustc", "abc123").unwrap();
    holder.leave(&"x".repeat(MAX_FLIGHT_PAYLOAD + 1));
    drop(holder);

    let next = flight_at(directory.path(), "rustc", "abc123").unwrap();
    assert_eq!(next.inherited(), None);
}

#[test]
fn session_environment_states_off_explicitly() {
    let config = crate::config::Config::for_test(Path::new("/cache"));
    assert_eq!(
        session_environment_with_jobs(&config, None),
        vec![(SCHED_DIR_ENV.to_string(), String::new())]
    );

    let mut config = crate::config::Config::for_test(Path::new("/cache"));
    config.scheduler.enabled = true;
    config.scheduler.cpus = 8;
    config.scheduler.reserve_cpus = 2;
    config.scheduler.memory_bytes = Some(8000);
    let environment = session_environment_with_jobs(&config, None);
    let value = |name: &str| {
        environment
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
            .unwrap()
    };
    assert_eq!(
        value(SCHED_DIR_ENV),
        Path::new("/cache").join("scheduler").to_str().unwrap()
    );
    assert_eq!(value(SCHED_SLOTS_ENV), "6");
    assert_eq!(value(SCHED_SLOT_BYTES_ENV), "1333");
    assert_eq!(value(SCHED_PRIORITY_ENV), "normal");
    assert!(!value(SCHED_BUILD_ID_ENV).is_empty());
    assert_eq!(value(SCHED_BUILD_SLOTS_ENV), "6");

    let environment = session_environment_with_jobs(&config, Some(3));
    let value = |name: &str| {
        environment
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
            .unwrap()
    };
    assert_eq!(value(SCHED_SLOTS_ENV), "6", "the machine pool stays global");
    assert_eq!(value(SCHED_SLOT_BYTES_ENV), "1333");
    assert_eq!(value(SCHED_BUILD_SLOTS_ENV), "3");
}

#[test]
fn pressure_blocks_unknown_demands_but_keeps_idle_progress() {
    use std::sync::atomic::{AtomicU64, Ordering};
    static CLOCK: AtomicU64 = AtomicU64::new(1_000);
    let dir = tempfile::tempdir().unwrap();
    let mut pool = pool_at(dir.path(), 4, 100);
    pool.pressure = true;
    pool.clock = || CLOCK.load(Ordering::SeqCst);
    pool.pressure_probe = || crate::pressure::Reading {
        total: Some(100),
        available: Some(0),
        ..Default::default()
    };
    let first = pool.try_admit(1, None).unwrap().unwrap();
    CLOCK.store(1_500, Ordering::SeqCst);
    assert!(pool.try_admit(1, None).unwrap().is_none());
    // Even a demand with no history, or an expired prediction gate, waits.
    CLOCK.store(2_000, Ordering::SeqCst);
    assert!(pool.try_admit(1, None).unwrap().is_none());
    drop(first);
    let first = pool.try_admit(1, None).unwrap().unwrap();
    pool.pressure = false;
    let second = pool.try_admit(1, None).unwrap().unwrap();
    drop((first, second));
}

#[test]
fn recovery_spaces_admissions_and_probe_failure_fails_open() {
    use std::sync::atomic::{AtomicU64, Ordering};
    static CLOCK: AtomicU64 = AtomicU64::new(1_000);
    let dir = tempfile::tempdir().unwrap();
    let mut pool = pool_at(dir.path(), 8, 100);
    pool.pressure = true;
    pool.clock = || CLOCK.load(Ordering::SeqCst);
    pool.pressure_probe = || crate::pressure::Reading {
        total: Some(100),
        available: Some(0),
        ..Default::default()
    };
    let first = pool.try_admit(1, None).unwrap().unwrap();
    CLOCK.store(1_500, Ordering::SeqCst);
    assert!(pool.try_admit(1, None).unwrap().is_none());
    pool.pressure_probe = || crate::pressure::Reading {
        total: Some(100),
        available: Some(50),
        ..Default::default()
    };
    for now in (2_000..7_000).step_by(500) {
        CLOCK.store(now, Ordering::SeqCst);
        assert!(pool.try_admit(1, None).unwrap().is_none());
    }
    CLOCK.store(7_000, Ordering::SeqCst);
    let second = pool.try_admit(1, None).unwrap().unwrap();
    assert!(pool.try_admit(1, None).unwrap().is_none());
    CLOCK.store(7_500, Ordering::SeqCst);
    let third = pool.try_admit(1, None).unwrap().unwrap();
    pool.pressure_probe = Default::default;
    CLOCK.store(8_000, Ordering::SeqCst);
    assert!(pool.try_admit(1, None).unwrap().is_some());
    drop((first, second, third));
}

#[test]
fn containers_sharing_a_pool_are_gated_by_their_own_pressure() {
    use std::sync::atomic::{AtomicU64, Ordering};
    static CLOCK: AtomicU64 = AtomicU64::new(1_000);
    fn container(counter: u64) -> crate::pressure::Reading {
        crate::pressure::Reading {
            total: Some(100),
            available: Some(50),
            // The same pathname names a different cgroup in each container.
            stalls: [("/sys/fs/cgroup/memory.pressure".into(), counter)].into(),
        }
    }
    let directory = tempfile::tempdir().unwrap();
    let container_pool = |domain, probe| {
        let mut pool = pool_at(directory.path(), 64, 100);
        pool.pressure = true;
        pool.pressure_domain = domain;
        pool.pressure_probe = probe;
        pool.clock = || CLOCK.load(Ordering::SeqCst);
        pool
    };
    // Three idle containers whose stall counters never move, as in the
    // reported build, plus one that is genuinely short of memory.
    let idle = [
        container_pool("one", || container(21_764_622)),
        container_pool("two", || container(200_000_000)),
        container_pool("three", || container(393_795_795)),
    ];
    let short = container_pool("short", || crate::pressure::Reading {
        total: Some(100),
        available: Some(0),
        ..Default::default()
    });
    let held = short
        .try_admit(1, None)
        .unwrap()
        .expect("an idle pool admits");
    CLOCK.store(1_500, Ordering::SeqCst);
    assert!(short.try_admit(1, None).unwrap().is_none());
    for (step, now) in (2_000..60_000).step_by(500).enumerate() {
        CLOCK.store(now, Ordering::SeqCst);
        let permit = idle[step % 3].try_admit(1, None).unwrap();
        assert!(
            permit.is_some(),
            "another container's pressure gated this one"
        );
        assert!(short.try_admit(1, None).unwrap().is_none());
    }
    drop(held);
}

#[test]
fn an_oversized_idle_grant_spaces_the_next_pools_admission() {
    let directory = tempfile::tempdir().unwrap();
    let mut low = pool_at(directory.path(), 4, 100);
    low.pressure = true;
    low.priority = SchedulerPriority::Low;
    low.clock = || 7_000;
    std::fs::write(directory.path().join(PRIORITY_WAIT_STAMP), b"").unwrap();
    // Establish a recovered state without granting a compilation in the ramp.
    let state = crate::pressure::domain_state(directory.path(), low.pressure_domain);
    crate::pressure::sample(&state, 1_000, || crate::pressure::Reading {
        total: Some(100),
        available: Some(0),
        ..Default::default()
    })
    .unwrap();
    crate::pressure::sample(&state, 1_500, || crate::pressure::Reading {
        total: Some(100),
        available: Some(0),
        ..Default::default()
    })
    .unwrap();
    for now in (2_000..=7_000).step_by(500) {
        crate::pressure::sample(&state, now, || crate::pressure::Reading {
            total: Some(100),
            available: Some(50),
            ..Default::default()
        })
        .unwrap();
    }
    let first = low.try_admit(4, None).unwrap().unwrap();
    let mut wider = pool_at(directory.path(), 8, 100);
    wider.pressure = true;
    wider.clock = || 7_000;
    assert!(wider.try_admit(1, None).unwrap().is_none());
    drop(first);
}

#[test]
fn frozen_work_has_admission_priority_until_its_heartbeat_expires() {
    let directory = tempfile::tempdir().unwrap();
    let mut pool = pool_at(directory.path(), 4, 100);
    pool.pressure = true;
    pool.pressure_probe = Default::default;
    pool.clock = || 1_000;
    let first = pool.try_admit(1, None).unwrap().unwrap();
    let pending = directory.path().join("suspended");
    std::fs::create_dir(&pending).unwrap();
    std::fs::write(pending.join("generation"), "1000").unwrap();
    assert!(pool.try_admit(1, None).unwrap().is_none());
    // A dead supervisor cannot hold admissions closed indefinitely.
    pool.clock = || 4_000;
    assert!(pool.try_admit(1, None).unwrap().is_some());
    drop(first);
}

#[test]
fn link_profile_separates_release_from_dev_links() {
    let args = |flags: &[&str]| -> Vec<std::ffi::OsString> {
        flags.iter().map(std::ffi::OsString::from).collect()
    };
    let release = args(&["-C", "opt-level=3", "-C", "lto", "-C", "codegen-units=1"]);
    let dev = args(&["-C", "debuginfo=0", "-C", "opt-level=0"]);
    let release_demand = Demand::new("fallow", true).with_link_profile(&release);
    let dev_demand = Demand::new("fallow", true).with_link_profile(&dev);
    assert_ne!(
        ledger_key(&release_demand.name, true),
        ledger_key(&dev_demand.name, true)
    );

    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 8, 1024);
    pool.record_peak(&ledger_key(&release_demand.name, true), 10_000_000, true)
        .unwrap();
    let (_, predicted) = pool.plan(&dev_demand);
    assert_ne!(
        predicted,
        Some(10_000_000),
        "a release peak must not charge a dev link"
    );
    let (_, predicted) = pool.plan(&release_demand);
    assert_eq!(predicted, Some(10_000_000));

    // Spelled `-Clto=fat` or as separate arguments, the profile is the same;
    // non-links are untouched.
    assert_eq!(
        link_profile(&args(&["-Clto=fat", "-Copt-level=3", "-Ccodegen-units=1"])),
        link_profile(&release)
    );
    assert_eq!(
        Demand::new("lib", false).with_link_profile(&release).name,
        "lib"
    );
}

#[test]
fn link_profile_reads_every_spelling_and_keeps_windows_apart() {
    let args = |flags: &[&str]| -> Vec<std::ffi::OsString> {
        flags.iter().map(std::ffi::OsString::from).collect()
    };
    assert_eq!(
        link_profile(&args(&["-O"])),
        link_profile(&args(&["-C", "opt-level=3"]))
    );
    assert_eq!(
        link_profile(&args(&["--codegen=lto", "--codegen", "codegen-units=1"])),
        link_profile(&args(&["-Clto", "-Ccodegen-units=1"]))
    );
    assert_ne!(
        link_profile(&args(&[])),
        link_profile(&args(&["-C", "lto=off"])),
        "an absent lto setting is not an explicit off"
    );

    // Three release links must not make a never-measured dev link
    // inherit a release-sized prediction.
    let directory = tempfile::tempdir().unwrap();
    let pool = pool_at(directory.path(), 8, 1024);
    let release = Demand::new("bin", true).with_link_profile(&args(&["-Clto", "-Copt-level=3"]));
    for _ in 0..3 {
        pool.record_link_peak(
            &ledger_key(&release.name, true),
            1_000_000,
            true,
            release.profile.as_deref(),
        )
        .unwrap();
    }
    let dev = Demand::new("bin", true).with_link_profile(&args(&["-Copt-level=0"]));
    let (_, predicted) = pool.plan(&dev);
    assert_eq!(predicted, Some(LINK_WEIGHT * 1024));
    let (_, predicted) = pool.plan(&release);
    assert_eq!(predicted, Some(1_000_000));
}
