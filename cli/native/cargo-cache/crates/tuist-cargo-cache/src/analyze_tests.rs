use super::*;
use crate::events::ActionDetail;
use tuist_cargo_cache_core::CacheDigest;

const SECOND: u64 = 1_000_000_000;

fn digest(value: &str) -> CacheDigest {
    CacheDigest::blake3(value.as_bytes())
}

/// Key material for `name`, identified as the same compilation unit in every
/// recording so that a later build finds it as a baseline.
fn diagnostic(
    name: &str,
    components: &[(&str, &str)],
    inputs: &[(&str, &str)],
) -> ActionDiagnostic {
    let mut all = BTreeMap::from([("compilation unit".to_string(), digest(name))]);
    all.extend(
        components
            .iter()
            .map(|(component, value)| (component.to_string(), digest(value))),
    );
    let inputs: BTreeMap<_, _> = inputs
        .iter()
        .map(|(path, value)| (path.to_string(), digest(value)))
        .collect();
    let action = digest(&format!("{name}{all:?}{inputs:?}"));
    ActionDiagnostic {
        action,
        components: all,
        inputs,
    }
}

fn action(
    outcome: ActionOutcome,
    name: &str,
    seconds: u64,
    diagnostic: Option<ActionDiagnostic>,
) -> SessionEvent {
    SessionEvent::Action {
        v: 1,
        ts_ms: 0,
        outcome,
        crate_name: Some(name.into()),
        duration_ns: seconds * SECOND,
        detail: ActionDetail::default(),
        diagnostic,
    }
}

fn session(events: Vec<SessionEvent>) -> RecordedSession {
    RecordedSession {
        workspace: "/work".into(),
        identity: Some("project".into()),
        command: vec!["build".into()],
        events,
    }
}

fn analyze(earlier: Vec<SessionEvent>, events: Vec<SessionEvent>) -> Analysis {
    let target = session(events);
    let baselines = Baselines::collect(&[session(earlier)], &target);
    Analysis::of(&target, &baselines)
}

fn group<'a>(analysis: &'a Analysis, cause: &Cause) -> &'a Group {
    analysis
        .groups
        .get(cause)
        .unwrap_or_else(|| panic!("no {cause:?} group in {:?}", analysis.groups))
}

const ENGINE_BEFORE: &str = "target/debug/deps/libengine-0a1b2c3d.rmeta";
const API_BEFORE: &str = "target/debug/deps/libapi-0f0f0f0f.rmeta";

fn engine(source: &str) -> ActionDiagnostic {
    diagnostic("engine", &[], &[("src/lib.rs", source)])
}

fn api(engine_artifact: &str) -> ActionDiagnostic {
    diagnostic(
        "api",
        &[],
        &[("src/api.rs", "api"), (ENGINE_BEFORE, engine_artifact)],
    )
}

fn cli(api_artifact: &str) -> ActionDiagnostic {
    diagnostic(
        "cli",
        &[],
        &[("src/main.rs", "cli"), (API_BEFORE, api_artifact)],
    )
}

#[test]
fn a_change_is_charged_to_the_crate_it_started_in() {
    let analysis = analyze(
        vec![
            action(ActionOutcome::Hit, "engine", 0, Some(engine("v1"))),
            action(ActionOutcome::Hit, "api", 0, Some(api("engine v1"))),
            action(ActionOutcome::Hit, "cli", 0, Some(cli("api v1"))),
        ],
        vec![
            action(ActionOutcome::Miss, "engine", 4, Some(engine("v2"))),
            action(ActionOutcome::Miss, "api", 3, Some(api("engine v2"))),
            // Two levels down: cli consumes only api, and api only moved
            // because engine did.
            action(ActionOutcome::Miss, "cli", 2, Some(cli("api v2"))),
        ],
    );

    assert_eq!(analysis.groups.len(), 1, "{:?}", analysis.groups);
    let changed = group(&analysis, &Cause::Changed("engine".into()));
    assert_eq!(changed.duration_ns, 9 * SECOND);
    assert_eq!(changed.direct_count, 1);
    assert_eq!(changed.dependent_count, 2);
    let text = analysis.text();
    assert!(text.contains("inputs of engine changed (3)"), "{text}");
    assert!(
        text.contains("then 2 crates that depend on it rebuilt: api 3.00s and cli 2.00s"),
        "{text}"
    );
    assert!(
        text.contains("Every crate that depends on engine recompiled"),
        "{text}"
    );
}

#[test]
fn dependency_hashes_that_follow_a_flag_change_are_charged_to_it() {
    let opt = |level: &str| {
        diagnostic(
            "engine",
            &[
                ("argument --C opt-level", level),
                ("argument --C metadata", level),
            ],
            &[("src/lib.rs", "same")],
        )
    };
    // Cargo moves a dependent's metadata hash and `--extern` path along with
    // its dependency's, so those changes are consequences.
    let dependent = |level: &str| {
        diagnostic(
            "api",
            &[
                ("argument --C metadata", level),
                ("argument --extern", level),
            ],
            &[(ENGINE_BEFORE, level)],
        )
    };
    let analysis = analyze(
        vec![
            action(ActionOutcome::Hit, "engine", 0, Some(opt("0"))),
            action(ActionOutcome::Hit, "api", 0, Some(dependent("0"))),
        ],
        vec![
            action(ActionOutcome::Miss, "engine", 5, Some(opt("3"))),
            action(ActionOutcome::Miss, "api", 1, Some(dependent("3"))),
        ],
    );

    let flags = group(&analysis, &Cause::Settings(Setting::Flags));
    assert_eq!(flags.duration_ns, 6 * SECOND);
    assert_eq!(flags.dependent_count, 1);
    let text = analysis.text();
    assert!(text.contains("compiler arguments changed (2)"), "{text}");
    assert!(text.contains("changed: -C opt-level (1)"), "{text}");
}

#[test]
fn settings_are_named_by_what_changed() {
    let names = |components: &[&str]| {
        components
            .iter()
            .map(|name| name.to_string())
            .collect::<Vec<_>>()
    };

    assert_eq!(
        setting(&names(&["compiler version", "argument --C opt-level"])),
        (Setting::Toolchain, Vec::new())
    );
    assert_eq!(
        setting(&names(&["action model"])),
        (Setting::ActionModel, Vec::new())
    );
    // rustc's own spelling of `-C` is `--codegen`, and a metadata hash moves
    // with any dependency, so it is not what changed here.
    assert_eq!(
        setting(&names(&[
            "argument --cfg #3",
            "argument #12",
            "argument --codegen rpath",
            "argument --codegen metadata",
        ])),
        (
            Setting::Flags,
            names(&["--cfg", "-C rpath", "argument values"])
        )
    );
    assert_eq!(
        setting(&names(&["environment RUSTFLAGS_EXTRA"])),
        (Setting::Environment, names(&["RUSTFLAGS_EXTRA"]))
    );
    assert_eq!(
        setting(&names(&["linker driver"])),
        (Setting::Linker, Vec::new())
    );
}

#[test]
fn causes_are_ranked_by_time_and_expected_bypasses_are_set_apart() {
    let analysis = analyze(
        vec![action(ActionOutcome::Hit, "small", 0, Some(engine("v1")))],
        vec![
            action(
                ActionOutcome::Bypass {
                    reason: "compiler-query".into(),
                },
                "___",
                0,
                None,
            ),
            action(
                ActionOutcome::Bypass {
                    reason: "native-library".into(),
                },
                "ring",
                7,
                None,
            ),
            action(ActionOutcome::Unconsulted, "fresh", 2, None),
            action(ActionOutcome::Miss, "gone", 1, None),
        ],
    );

    let text = analysis.text();
    let position = |needle: &str| {
        text.find(needle)
            .unwrap_or_else(|| panic!("{needle:?} missing from {text}"))
    };
    assert!(
        position("not cacheable: native-library") < position("first build of these compilations")
    );
    assert!(
        position("first build of these compilations")
            < position("misses with no earlier recording")
    );
    assert!(position("misses with no earlier recording") < position("expected, nothing to cache"));
    assert!(text.contains("expected, nothing to cache: compiler-query (1)"));
    assert!(!text.contains("not cacheable: compiler-query"));
    assert!(text.contains("10.00s in 3 uncached compilations"), "{text}");
}

/// New RUSTFLAGS leave no prediction to look up, so these compilations are
/// unconsulted rather than missed. Their keys still say what changed.
#[test]
fn an_unconsulted_compilation_is_compared_with_its_last_recording() {
    let flags = |value: &str| {
        diagnostic(
            "engine",
            &[("argument --cfg", value)],
            &[("src/lib.rs", "same")],
        )
    };
    let analysis = analyze(
        vec![action(ActionOutcome::Hit, "engine", 0, Some(flags("none")))],
        vec![
            action(
                ActionOutcome::Unconsulted,
                "engine",
                2,
                Some(flags("extra")),
            ),
            action(ActionOutcome::Unconsulted, "fresh", 1, None),
        ],
    );

    let flags = group(&analysis, &Cause::Settings(Setting::Flags));
    assert_eq!(flags.direct_count, 1);
    assert_eq!(flags.details, BTreeMap::from([("--cfg".to_string(), 1)]));
    assert_eq!(group(&analysis, &Cause::FirstBuild).direct_count, 1);
}

#[test]
fn probes_are_not_counted_as_uncached_work() {
    let probe = || {
        action(
            ActionOutcome::Bypass {
                reason: "compiler-query".into(),
            },
            "___",
            0,
            None,
        )
    };
    let text = analyze(Vec::new(), vec![probe(), probe()]).text();

    assert!(text.contains("0s in 0 uncached compilations\n"), "{text}");
    assert!(text.contains("Cargo found every unit up to date"), "{text}");
}

#[test]
fn an_unchanged_key_that_missed_is_a_missing_result() {
    let analysis = analyze(
        vec![action(ActionOutcome::Hit, "engine", 0, Some(engine("v1")))],
        vec![action(ActionOutcome::Miss, "engine", 3, Some(engine("v1")))],
    );

    assert_eq!(group(&analysis, &Cause::Unavailable).direct_count, 1);
}

#[test]
fn a_bypass_without_recorded_time_says_so() {
    let analysis = analyze(
        Vec::new(),
        vec![action(
            ActionOutcome::Bypass {
                reason: "rustdoc".into(),
            },
            "docs",
            0,
            None,
        )],
    );

    let text = analysis.text();
    assert!(text.contains("-  not cacheable: rustdoc (1)"), "{text}");
    assert!(text.contains("compiler time was not recorded"), "{text}");
}

#[test]
fn a_build_with_nothing_uncached_says_so() {
    let analysis = analyze(
        Vec::new(),
        vec![action(ActionOutcome::Hit, "engine", 0, Some(engine("v1")))],
    );

    let text = analysis.text();
    assert!(
        text.contains("0s in 0 uncached compilations; 1 hit avoided"),
        "{text}"
    );
    assert!(text.contains("every compilation that could be cached was restored"));
}

#[test]
fn prose_wraps_at_word_boundaries() {
    assert_eq!(wrap("one two three four", 9), ["one two", "three", "four"]);
}

#[test]
fn the_report_ends_with_the_critical_path() {
    let mut timing = tuist_cargo_cache_core::WrapperTiming::default();
    timing.unit = Some("engine".into());
    timing.unit_id = Some("a1".into());
    timing.duration_ns = 2 * SECOND;
    let text = analyze(
        Vec::new(),
        vec![
            action(ActionOutcome::Unconsulted, "engine", 2, None),
            SessionEvent::WrapperTiming {
                v: 1,
                ts_ms: 0,
                timing,
            },
        ],
    )
    .text();

    assert!(
        text.contains("critical path: 2.00s, 100% of the 2.00s between the first unit starting"),
        "{text}"
    );
    assert!(text.contains("  2.00s  engine\n"), "{text}");
    assert!(
        text.contains("only one recorded unit running for 2.00s: engine 2.00s"),
        "{text}"
    );
}

/// A crate edited in the same build as one of its dependencies started a
/// change of its own. The metadata and `--extern` arguments its dependency
/// moved are not what changed.
#[test]
fn an_edit_alongside_a_changed_dependency_is_charged_to_the_edited_crate() {
    let edited = |source: &str, engine_artifact: &str| {
        diagnostic(
            "api",
            &[
                ("argument --codegen metadata", engine_artifact),
                ("argument --extern", engine_artifact),
            ],
            &[("src/api.rs", source), (ENGINE_BEFORE, engine_artifact)],
        )
    };
    let analysis = analyze(
        vec![
            action(ActionOutcome::Hit, "engine", 0, Some(engine("v1"))),
            action(ActionOutcome::Hit, "api", 0, Some(edited("a1", "e1"))),
        ],
        vec![
            action(ActionOutcome::Miss, "engine", 2, Some(engine("v2"))),
            action(ActionOutcome::Miss, "api", 3, Some(edited("a2", "e2"))),
        ],
    );

    assert_eq!(
        group(&analysis, &Cause::Changed("api".into())).direct_count,
        1
    );
    assert_eq!(
        group(&analysis, &Cause::Changed("engine".into())).direct_count,
        1
    );
    assert!(
        !analysis
            .groups
            .contains_key(&Cause::Settings(Setting::Other))
    );
}

/// `app` depends on `left` and `right`, and `right` depends on `left` too, so
/// `left` is reached twice on the way to `engine`. Meeting it the second time
/// must not make it look like a place a change started.
#[test]
fn a_diamond_is_charged_to_its_one_origin() {
    let dependent = |name: &str, on: &[(&str, &str)]| {
        let mut inputs = vec![("src/lib.rs", name)];
        inputs.extend_from_slice(on);
        diagnostic(name, &[], &inputs)
    };
    const LEFT: &str = "target/debug/deps/libleft-1a1a.rmeta";
    const RIGHT: &str = "target/debug/deps/libright-2b2b.rmeta";
    let build = |version: &str, seconds: [u64; 4], outcome: fn() -> ActionOutcome| {
        vec![
            action(outcome(), "engine", seconds[0], Some(engine(version))),
            action(
                outcome(),
                "left",
                seconds[1],
                Some(dependent("left", &[(ENGINE_BEFORE, version)])),
            ),
            action(
                outcome(),
                "right",
                seconds[2],
                Some(dependent("right", &[(LEFT, version)])),
            ),
            action(
                outcome(),
                "app",
                seconds[3],
                Some(dependent("app", &[(LEFT, version), (RIGHT, version)])),
            ),
        ]
    };
    // `left` costs more than `engine`, which is what would make a stray
    // intermediate root win.
    let analysis = analyze(
        build("v1", [0; 4], || ActionOutcome::Hit),
        build("v2", [1, 5, 1, 1], || ActionOutcome::Miss),
    );

    assert_eq!(analysis.groups.len(), 1, "{:?}", analysis.groups);
    assert_eq!(
        group(&analysis, &Cause::Changed("engine".into())).dependent_count,
        3
    );
}

/// A compilation another checkout already built, run here with no prediction
/// to look it up by, is not a first build.
#[test]
fn an_unconsulted_key_seen_before_was_not_looked_up() {
    let analysis = analyze(
        vec![action(ActionOutcome::Hit, "engine", 0, Some(engine("v1")))],
        vec![action(
            ActionOutcome::Unconsulted,
            "engine",
            2,
            Some(engine("v1")),
        )],
    );

    assert_eq!(group(&analysis, &Cause::Unpredicted).direct_count, 1);
    assert!(
        analysis
            .text()
            .contains("keys built before, but not looked up")
    );
}

/// Nothing is left to cache in a compilation read from standard input, but
/// one that took compiler time was still work the build did.
#[test]
fn expected_work_that_took_time_is_counted() {
    let text = analyze(
        Vec::new(),
        vec![action(
            ActionOutcome::Bypass {
                reason: "standard-input".into(),
            },
            "piped",
            2,
            None,
        )],
    )
    .text();

    assert!(text.contains("2.00s in 1 uncached compilation"), "{text}");
    assert!(
        !text.contains("Cargo found every unit up to date"),
        "{text}"
    );
    assert!(!text.contains("was restored\n"), "{text}");
    assert!(
        text.contains("nothing was restored; only work with nothing to cache ran"),
        "{text}"
    );
    assert!(text.contains("expected, nothing to cache: standard-input (1)"));
}

/// A verification restores a hit and rebuilds it to check it, so a build
/// with nothing else cacheable still restored something.
#[test]
fn a_verification_counts_as_restored_work() {
    let text = analyze(
        Vec::new(),
        vec![
            action(
                ActionOutcome::Bypass {
                    reason: "standard-input".into(),
                },
                "piped",
                2,
                None,
            ),
            action(
                ActionOutcome::Verification { matched: true },
                "engine",
                1,
                None,
            ),
        ],
    )
    .text();

    assert!(text.contains("; 1 hit rebuilt to verify\n"), "{text}");
    assert!(!text.contains("nothing was restored"), "{text}");
    assert!(text.contains("every compilation that could be cached was restored"));
}

/// A rebuild that did not match its cached result is a cache-integrity
/// warning, never a quiet success.
#[test]
fn a_divergent_verification_is_reported() {
    let text = analyze(
        Vec::new(),
        vec![
            action(ActionOutcome::Verification { matched: true }, "a", 1, None),
            action(ActionOutcome::Verification { matched: false }, "b", 1, None),
        ],
    )
    .text();

    assert!(
        text.contains("; 2 hits rebuilt to verify, 1 diverged\n"),
        "{text}"
    );
    assert!(
        text.contains("warning: 1 verified hit did not match its cached result: the rebuild failed or produced different output"),
        "{text}"
    );
    assert!(text.contains("TUIST_CARGO_CACHE_VERIFY=1"), "{text}");
}
