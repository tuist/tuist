use super::*;
use model::{CacheMix, segments};

#[test]
fn segments_partition_exactly_and_handle_extremes() {
    for mix in [
        CacheMix::default(),
        CacheMix {
            hits: 7,
            misses: 2,
            bypasses: 1,
            saved_ns: 0,
            unconsulted: 0,
        },
        CacheMix {
            hits: u64::MAX,
            misses: u64::MAX,
            bypasses: u64::MAX,
            saved_ns: 0,
            unconsulted: 0,
        },
    ] {
        for width in 0..=80 {
            assert_eq!(segments(&mix, width).iter().sum::<usize>(), width);
        }
    }
    assert_eq!(
        segments(
            &CacheMix {
                hits: 7,
                misses: 2,
                bypasses: 1,
                saved_ns: 0,
                unconsulted: 0
            },
            20
        ),
        [14, 4, 2]
    );
}

#[test]
fn cache_mix_matches_existing_stats_and_excludes_probes() {
    let mut stats = AgentStats::default();
    stats.lookups = 10;
    stats.hits = 6;
    stats.verifications = 1;
    stats.compiler = BTreeMap::from([(
        "miss".into(),
        tuist_cargo_cache_core::CompilerStats::new(3, 0),
    )]);
    stats.bypasses = BTreeMap::from([("compiler-query".into(), 4), ("unsupported".into(), 2)]);
    stats.avoided_compiler_duration_ns = 42;
    let mix = CacheMix::from(stats);
    assert_eq!(
        (mix.hits, mix.misses, mix.bypasses, mix.saved_ns),
        (6, 3, 2, 42)
    );
}

#[test]
fn fresh_artifacts_are_not_cache_hits_and_missing_timings_stay_unknown() {
    let mut model = Model::new(&["build".into()]);
    assert!(model.cargo(r##"{"reason":"compiler-artifact","package_id":"registry+url#demo@1.0.0","target":{"name":"demo"},"fresh":true}"##));
    assert_eq!(model.fresh, 1);
    assert_eq!(model.mix.hits, 0);
    assert_eq!(model.done[0].duration, None);
    assert_eq!(model.units_total, None);
    assert!(model.status("    Building [======> ] 2/10: demo"));
    assert_eq!((model.units_done, model.units_total), (2, Some(10)));
}

#[test]
fn native_test_output_tracks_suites_and_failures_without_fabricated_times() {
    let mut model = Model::new(&["test".into()]);
    assert!(model.test_line("running 2 tests"));
    assert!(model.test_line("test good ... ok"));
    assert!(model.test_line("test bad ... FAILED"));
    model.test_line("failures:");
    assert!(!model.test_line("---- bad stdout ----"));
    model.test_line("panic at src/lib.rs:3:4");
    model.test_line("failures:");
    assert_eq!((model.tests_passed, model.tests_failed), (1, 1));
    assert!(model.failures[0].1.contains("panic at"));
    assert_eq!(model.done[0].duration, None);
    assert!(model.test_line("running 1 test"));
    assert_eq!((model.suite_done, model.suite_total), (0, 1));
    assert!(!model.test_line("custom harness output"));
}

/// On a terminal, libtest colours each result and resets with the terminal's
/// sgr0, which on xterm starts with a charset escape.
#[test]
fn coloured_test_results_count_as_they_arrive() {
    assert_eq!(strip_ansi("a\x1b(Bb\x1b=c\x1b[1;31md\x1b"), "abcd");
    let mut model = Model::new(&["test".into()]);
    assert!(model.test_line("running 2 tests"));
    for line in [
        "test a ... \x1b[31mFAILED\x1b(B\x1b[m",
        "test b ... \x1b[32mok\x1b(B\x1b[m",
    ] {
        assert!(model.test_line(&strip_ansi(line)), "{line:?}");
    }
    assert_eq!(
        (model.tests_failed, model.tests_passed, model.suite_done),
        (1, 1, 2)
    );
}

/// Check that display options leave application arguments untouched and that
/// toolchain selectors and placement configuration do not hide the Cargo verb.
#[test]
fn argument_injection_preserves_command_and_program_arguments() {
    let args = vec![
        "run".into(),
        "--bin=server".into(),
        "--".into(),
        "--message-format=custom".into(),
    ];
    assert_eq!(
        cargo_arguments(&args),
        [
            "run",
            "--bin=server",
            "--message-format=json,json-diagnostic-rendered-ansi",
            "--",
            "--message-format=custom"
        ]
    );
    assert!(eligible(&args));
    let prefixed = vec!["+stable".into(), "test".into(), "--".into(), "works".into()];
    assert!(eligible(&prefixed));
    assert_eq!(cargo_verb(&prefixed), Some("test"));
    let placed = vec![
        "--config".into(),
        "build.target-dir='checkout/target'".into(),
        "test".into(),
    ];
    // Eligibility is checked before tuist_cargo_cache adds its own placement config, but
    // the renderer still needs the verb from the final Cargo arguments.
    assert_eq!(cargo_verb(&placed), Some("test"));
    assert_eq!(
        cargo_arguments(&prefixed),
        [
            "+stable",
            "test",
            "--message-format=json,json-diagnostic-rendered-ansi",
            "--",
            "works"
        ]
    );
    for args in [
        vec!["test", "--message-format=json"],
        vec!["build", "-q"],
        vec!["check", "--config=foo"],
        vec!["metadata"],
    ] {
        assert!(!eligible(
            &args.iter().map(|s| s.to_string()).collect::<Vec<_>>()
        ));
    }
}

#[test]
fn seeding_replaces_the_builders_base_environment_with_the_process_environment() {
    let mut command = CommandBuilder::new("cargo");
    // Stand-ins for what portable-pty reads from the Windows registry.
    command.env("PATH", "registry-path");
    command.env("OS", "Windows_NT");
    command.env("REMOVED_BY_SHELL", "registry-value");

    seed_process_environment(
        &mut command,
        [
            ("PATH".into(), "process-only;registry-path".into()),
            ("OS".into(), "tuist_cargo_cache-process-only-os".into()),
        ],
    );
    command.env("CARGO_TERM_PROGRESS_WHEN", "always");

    assert_eq!(
        command.get_env("PATH"),
        Some(OsStr::new("process-only;registry-path"))
    );
    assert_eq!(
        command.get_env("OS"),
        Some(OsStr::new("tuist_cargo_cache-process-only-os"))
    );
    assert_eq!(command.get_env("REMOVED_BY_SHELL"), None);
    assert_eq!(
        command.get_env("CARGO_TERM_PROGRESS_WHEN"),
        Some(OsStr::new("always"))
    );
}

/// Runs `command` in a PTY and returns what it printed up to its `done` line.
fn output_through_pty(command: CommandBuilder) -> String {
    let pair = NativePtySystem::default()
        .openpty(PtySize {
            rows: 24,
            cols: 500,
            pixel_width: 0,
            pixel_height: 0,
        })
        .unwrap();
    let mut reader = pair.master.try_clone_reader().unwrap();
    let mut input = pair.master.take_writer().unwrap();
    let mut child = pair.slave.spawn_command(command).unwrap();
    drop(pair.slave);
    let (send, receive) = mpsc::channel();
    std::thread::spawn(move || {
        const QUERY: &[u8] = b"\x1b[6n";
        let mut bytes = [0; 4096];
        // The query can straddle two reads, so keep the last few bytes.
        let mut seen = Vec::new();
        while let Ok(n @ 1..) = reader.read(&mut bytes) {
            // ConPTY asks for the cursor position and emits nothing more until
            // the host answers.
            seen.extend_from_slice(&bytes[..n]);
            if seen.windows(QUERY.len()).any(|window| window == QUERY) {
                let _ = input.write_all(b"\x1b[1;1R").and_then(|()| input.flush());
            }
            seen.drain(..seen.len().saturating_sub(QUERY.len() - 1));
            if send.send(bytes[..n].to_vec()).is_err() {
                break;
            }
        }
    });
    let mut output = Vec::new();
    while !String::from_utf8_lossy(&output).contains("\ndone") {
        match receive.recv_timeout(Duration::from_secs(30)) {
            Ok(chunk) => output.extend(chunk),
            Err(_) => break,
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    String::from_utf8_lossy(&output).into_owned()
}

#[test]
fn pty_child_inherits_the_seeded_environment_not_the_registry() {
    let probe = "cargo_cacheprobe-process-only";
    // `OS` and `TEMP` are registry-backed on Windows: override one, remove the
    // other, and prepend to `PATH`, as a calling shell might.
    let process: Vec<(OsString, OsString)> = std::env::vars_os()
        .filter(|(key, _)| !key.eq_ignore_ascii_case("TEMP") && !key.eq_ignore_ascii_case("OS"))
        .map(|(key, value)| {
            if key.eq_ignore_ascii_case("PATH") {
                let paths = std::env::split_paths(&value);
                let joined = std::env::join_paths(
                    std::iter::once(std::path::PathBuf::from(probe)).chain(paths),
                );
                (key, joined.unwrap())
            } else {
                (key, value)
            }
        })
        .chain([("OS".into(), "tuist_cargo_cache-process-only-os".into())])
        .collect();

    #[cfg(windows)]
    let (mut command, unset) = {
        let mut command = CommandBuilder::new("cmd");
        command.args([
            "/d",
            "/c",
            "echo path=%PATH%& echo os=%OS%& echo temp=%TEMP%& echo done",
        ]);
        (command, "temp=%TEMP%")
    };
    #[cfg(not(windows))]
    let (mut command, unset) = {
        let mut command = CommandBuilder::new("sh");
        command.args([
            "-c",
            "echo path=$PATH; echo os=$OS; echo temp=${TEMP-unset}; echo done",
        ]);
        (command, "temp=unset")
    };
    seed_process_environment(&mut command, process);

    let output = output_through_pty(command);
    assert!(output.contains(&format!("path={probe}")), "{output}");
    assert!(
        output.contains("os=tuist_cargo_cache-process-only-os"),
        "{output}"
    );
    assert!(output.contains(unset), "{output}");
}

#[cfg(unix)]
#[test]
fn preserves_signalled_exit_status() {
    use std::os::unix::process::ExitStatusExt;
    let status = portable_pty::ExitStatus::from(std::process::ExitStatus::from_raw(libc::SIGTERM));
    assert_eq!(status_code(&status), 143);
}

#[test]
fn presentation_keeps_reserved_rows_and_clips_diagnostics() {
    let mut model = Model::new(&["build".into()]);
    let empty = view::render(&mut model, None, 80, 27);
    assert_eq!(empty.size().1, 27);
    assert!(strip_ansi(&empty.to_string()).contains("total unknown"));
    assert!(model.status("   Compiling a-crate v0.1.0 (/tmp/a-crate)"));
    assert!(model.cargo(r##"{"reason":"compiler-artifact","package_id":"path+file:///tmp/a-crate#0.1.0","target":{"name":"a_crate"},"fresh":false}"##));
    assert!(model.live.is_empty());
    assert!(model.done[0].duration.is_some());
    let populated = view::render(&mut model, None, 80, 27);
    assert_eq!(populated.size().1, 27);
    model.warnings.push(model::Warning {
        message: "warning".into(),
        rendered: "wide 文本\n".repeat(100),
        location: None,
        help: None,
    });
    let mut browser = view::Browser {
        inspecting: true,
        scroll: usize::MAX,
        selected: 0,
    };
    let block = view::render(&mut model, Some(&mut browser), 20, 12);
    assert!(block.size().0 <= 20);
    assert_eq!(block.size().1, 12);
    assert!(browser.scroll < 200);
}

#[test]
fn terse_and_ignored_test_summaries_remain_accurate() {
    let mut model = Model::new(&["test".into()]);
    model.test_line("running 3 tests");
    model.test_line("..i");
    model.test_line("test result: ok. 2 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0.00s");
    assert_eq!(
        (
            model.tests_passed,
            model.tests_failed,
            model.tests_ignored,
            model.suite_done
        ),
        (2, 0, 1, 3)
    );
}

#[test]
fn failed_build_does_not_fill_unfinished_units() {
    let mut model = Model::new(&["build".into()]);
    model.units_total = Some(10);
    model.units_done = 3;
    model.build_finished = true;
    model.build_ok = Some(false);
    let text = strip_ansi(&view::render(&mut model, None, 110, 30).to_string());
    assert!(text.contains("3/10 units"));
    assert!(text.contains(&"░".repeat(20)));
    model.units_total = None;
    model.build_ok = Some(true);
    let text = strip_ansi(&view::render(&mut model, None, 110, 30).to_string());
    assert!(text.contains("total unknown"));
}

#[test]
fn status_words_in_child_output_are_preserved() {
    let mut model = Model::new(&["build".into()]);
    for line in [
        "Compiling assets",
        "Checking configuration",
        "   Compiling assets",
        "    Checking configuration",
        "Finished generating assets",
        "Building [assets] 1/2: images",
    ] {
        assert!(!model.status(line), "consumed child output: {line}");
    }
    assert!(model.live.is_empty());
    assert!(model.status("   Compiling demo v1.2.3 (/tmp/demo)"));
    assert!(model.status("    Checking demo v1.2.3"));
    assert!(model.status("    Finished `dev` profile [unoptimized] target(s) in 0.2s"));
}

#[test]
fn final_summary_keeps_only_its_content_rows() {
    let mut model = Model::new(&["build".into()]);
    model.finished = Some((true, Duration::from_secs(2)));
    let block = view::render(&mut model, None, 80, 27);
    assert_eq!(block.size().1, view::summary(&model).size().1);
    assert!(block.size().1 < 10);
}

#[test]
fn passing_test_stdout_does_not_open_failure_browser() {
    let mut model = Model::new(&["test".into()]);
    for line in [
        "running 1 test",
        "test works ... ok",
        "successes:",
        "---- works stdout ----",
        "hello",
        "test result: ok. 1 passed; 0 failed; 0 ignored;",
    ] {
        model.test_line(line);
    }
    assert!(model.failures.is_empty());
    for line in [
        "running 1 test",
        "test fails ... FAILED",
        "failures:",
        "---- fails stdout ----",
        "panic detail",
    ] {
        model.test_line(line);
    }
    assert_eq!(model.failures.len(), 1);
    assert!(model.failures[0].1.contains("panic detail"));
}

#[test]
fn active_rows_keep_slots_and_cache_outcomes_remain_explicit() {
    let mut model = Model::new(&["build".into()]);
    model.status("   Compiling zeta v1.0.0");
    model.status("   Compiling alpha v1.0.0");
    let original = model.slots.clone();
    assert!(model.cargo(r#"{"reason":"compiler-artifact","package_id":"path+file:///zeta#zeta@1.0.0","target":{"name":"zeta"},"filenames":["/tmp/libzeta-1111111111111111.rmeta"],"fresh":false}"#));
    assert_eq!(model.slots[1], original[1]);
    let mut stats = AgentStats::default();
    stats
        .unit_outcomes
        .insert("zeta:1111111111111111".into(), ["hit".into()].into());
    model.update_stats(stats.clone());
    assert!(strip_ansi(&view::render(&mut model, None, 110, 27).to_string()).contains("hit"));
    stats
        .unit_outcomes
        .get_mut("zeta:1111111111111111")
        .unwrap()
        .insert("miss".into());
    model.update_stats(stats);
    assert!(strip_ansi(&view::render(&mut model, None, 110, 27).to_string()).contains("mixed"));
}

#[test]
fn malformed_versions_and_large_exit_codes_stay_failures_or_passthrough() {
    let mut model = Model::new(&["build".into()]);
    assert!(!model.status("   Compiling assets v1.2.not-a-version"));
    assert_eq!(
        status_code(&portable_pty::ExitStatus::with_exit_code(256)),
        1
    );
}

#[test]
fn small_viewports_promote_waiting_crates_without_moving_visible_crates() {
    let mut model = Model::new(&["build".into()]);
    for name in ["first", "second", "third", "fourth", "fifth", "sixth"] {
        model.status(&format!("   Compiling {name} v1.0.0"));
    }
    view::render(&mut model, None, 80, 14);
    assert_eq!(model.slots.len(), 1);
    assert!(model.cargo(r#"{"reason":"compiler-artifact","package_id":"path+file:///first#first@1.0.0","target":{"name":"first"},"fresh":false}"#));
    assert_eq!(model.slots[0].as_deref(), Some("second v1.0.0"));
    let text = strip_ansi(&view::render(&mut model, None, 80, 14).to_string());
    assert!(text.contains("second"));
    view::render(&mut model, None, 80, 24);
    assert_eq!(model.slots[0].as_deref(), Some("second v1.0.0"));
    assert_eq!(model.slots.len(), 6);
}

#[test]
fn a_long_build_is_summarized_in_minutes_rather_than_hundreds_of_seconds() {
    let mut model = Model::new(&["build".into()]);
    model.finished = Some((true, std::time::Duration::from_secs(813)));
    model.mix.saved_ns = 6_600_000_000_000;
    let text = strip_ansi(&view::summary(&model).to_string());
    assert!(text.contains("Built in 13m 33s"), "{text}");
    assert!(text.contains("saved ~1h 50m compiler work"), "{text}");
}

#[test]
fn summary_uses_the_cargo_verb_and_build_scripts_normalize_like_rustc() {
    for (arguments, expected) in [
        (vec!["c".into()], "Checked"),
        (vec!["+stable".into(), "check".into()], "Checked"),
        (
            vec!["build".into(), "--features".into(), "unchecked".into()],
            "Built",
        ),
    ] {
        let model = Model::new(&arguments);
        assert!(strip_ansi(&view::summary(&model).to_string()).contains(expected));
    }
    let mut model = Model::new(&["build".into()]);
    model.cargo(r#"{"reason":"compiler-artifact","package_id":"path+file:///demo#demo@1.0.0","target":{"name":"build-script-build","kind":["custom-build"]},"filenames":["/tmp/demo-1111111111111111/build-script-build"],"fresh":false}"#);
    assert_eq!(
        model.done[0].cache_target.as_deref(),
        Some("build_script_build:1111111111111111")
    );
}

#[test]
fn cargo_fingerprints_isolate_versions_and_match_compiler_arguments() {
    let mut model = Model::new(&["build".into()]);
    for (version, hash) in [("1.0.0", "1111111111111111"), ("2.0.0", "2222222222222222")] {
        model.cargo(&serde_json::json!({"reason":"compiler-artifact", "package_id":format!("serde@{version}"), "target":{"name":"serde"}, "filenames":[format!("/tmp/libserde-{hash}.rmeta")], "fresh":false}).to_string());
    }
    assert_ne!(model.done[0].cache_target, model.done[1].cache_target);
    assert_eq!(
        model.done[0].cache_target,
        crate::session::compiler_unit_key(
            "serde",
            ["-C".into(), "extra-filename=-1111111111111111".into()]
        )
    );
    assert!(
        crate::session::compiler_unit_key("serde", ["--crate-name".into(), "serde".into()])
            .is_none()
    );
}

#[test]
fn uplifted_artifacts_match_shim_outcomes_without_merging_packages_or_tests() {
    use std::path::Path;
    for (name, kind, filename) in [
        ("my-app", "bin", "/tmp/target/debug/my-app"),
        ("foo", "lib", "/tmp/target/debug/libfoo.rlib"),
        ("foo", "cdylib", "/tmp/target/debug/libfoo.dylib"),
    ] {
        let mut model = Model::new(&["build".into()]);
        let manifest = "/tmp/project/Cargo.toml";
        let message = serde_json::json!({
            "reason":"compiler-artifact", "package_id":"project@1.0.0",
            "manifest_path":manifest, "target":{"name":name,"crate_types":[kind]},
            "profile":{"test":false}, "filenames":[filename], "fresh":false
        });
        model.cargo(&message.to_string());
        let arguments = vec![
            "--crate-type".into(),
            kind.into(),
            "--out-dir=/tmp/target/debug/deps".into(),
            "-Cextra-filename=-1111111111111111".into(),
        ];
        let shim = crate::session::compiler_uplifted_unit_key(
            &name.replace('-', "_"),
            Path::new(manifest),
            &arguments,
        )
        .unwrap();
        assert_eq!(model.done[0].cache_target.as_deref(), Some(shim.as_str()));
        assert_ne!(
            Some(shim.clone()),
            crate::session::compiler_uplifted_unit_key(
                name,
                Path::new("/tmp/other-version/Cargo.toml"),
                &arguments,
            )
        );
        let mut test_arguments = arguments.clone();
        test_arguments.push("--test".into());
        assert!(
            crate::session::compiler_uplifted_unit_key(name, Path::new(manifest), &test_arguments,)
                .is_none()
        );
        model.outcomes.insert(shim, ["hit".into()].into());
        let text = strip_ansi(&view::render(&mut model, None, 80, 24).to_string());
        assert!(text.contains("hit"), "{text}");
    }
}

#[test]
fn mascot_keeps_progress_readable_and_leaves_successful_builds() {
    let mut model = Model::new(&["build".into()]);
    model.units_total = Some(100);
    model.units_done = 91;
    for width in [50, 80, 95, 96, 110] {
        let block = view::render(&mut model, None, width, 27);
        assert!(block.size().0 <= width);
        assert_eq!(block.size().1, 27);
        let text = strip_ansi(&block.to_string());
        // Only the mascot draws half blocks.
        assert_eq!(text.contains('▀'), width >= 96, "{text}");
        if width >= 80 {
            assert!(text.contains("91/100 units"), "{text}");
        }
    }
    // A compiler error shows the failure pose, and its monocle chain, before
    // Cargo reports the build.
    let chain = "189;125;35";
    assert!(
        !view::render(&mut model, None, 110, 27)
            .to_string()
            .contains(chain)
    );
    model
        .errors
        .push("error[E0425]: cannot find value `x` in this scope".into());
    assert!(
        view::render(&mut model, None, 110, 27)
            .to_string()
            .contains(chain)
    );
    // A failed build keeps the knocked-over box beside its summary.
    model.finished = Some((false, Duration::from_secs(1)));
    let failed = view::render(&mut model, None, 110, 27);
    assert_eq!(failed.size().1, 9);
    assert!(strip_ansi(&failed.to_string()).contains("Failed"));
    // Each mascot cell reaches the terminal with its own glyph, fg and bg.
    use crate::cli::mascot::{self, Pose};
    use norimel::Color;
    let paint =
        |color: Option<mascot::Rgb>| color.map_or(Color::Reset, |(r, g, b)| Color::Rgb(r, g, b));
    let mut painted = vec![Vec::new(); mascot::HEIGHT];
    let mascot_x = failed.size().0 - mascot::WIDTH as u16;
    for (x, y, text, style) in failed.runs() {
        for (i, glyph) in text.chars().enumerate() {
            if usize::from(x) + i >= usize::from(mascot_x) {
                painted[usize::from(y)].push((glyph, style.fg, style.bg));
            }
        }
    }
    let knocked = mascot::draw(Pose {
        failed: true,
        ..Pose::default()
    });
    let expected: Vec<Vec<_>> = knocked
        .iter()
        .map(|row| {
            row.iter()
                .map(|cell| (cell.glyph, paint(cell.fg), paint(cell.bg)))
                .collect()
        })
        .collect();
    assert_eq!(painted, expected);
    // A successful build leaves only its summary.
    model.errors.clear();
    model.finished = Some((true, Duration::from_secs(1)));
    let done = view::render(&mut model, None, 110, 27);
    let text = strip_ansi(&done.to_string());
    assert!(text.contains("Built"), "{text}");
    assert!(!text.contains('▀'), "{text}");
    assert_eq!(done.size().1, view::summary(&model).size().1);
}

/// Cargo's counts arrive in jumps: an incremental build's first progress line
/// is already 97/98, and a burst of cache hits finishes many units between two
/// frames. The drawn lid still comes down a pixel at a time and never rises,
/// including through the test phase, whose suite counts restart per binary.
#[test]
fn mascot_lid_descends_a_pixel_per_frame_through_jumps_in_progress() {
    use crate::cli::mascot::LID_MAX;
    let replay = |lines: &[&str]| {
        let mut model = Model::new(&["test".into()]);
        let mut lids = vec![model.lid_shown];
        let mut frame = |model: &mut Model| {
            view::render(model, None, 110, 27);
            lids.push(model.lid_shown);
        };
        frame(&mut model);
        for line in lines {
            // As the decoder routes lines: Cargo's until the build finishes.
            if model.build_finished || !(model.cargo(line) || model.status(line)) {
                model.test_line(line);
            }
            frame(&mut model);
            frame(&mut model);
        }
        lids
    };
    let finished = r#"{"reason":"build-finished","success":true}"#;
    for lines in [
        &[
            "    Building [=======================> ] 97/98: tuist_cargo_cache(bin)",
            finished,
            "running 2 tests",
            "test first ... ok",
        ][..],
        &[
            "    Building [          ] 0/60",
            "    Building [          ] 3/60",
            "    Building [========> ] 58/60",
            "    Building [========> ] 59/60",
            finished,
        ],
        &[
            "    Building [   ] 0/3",
            "    Building [=> ] 3/3",
            finished,
            "running 0 tests",
        ],
    ] {
        let lids = replay(lines);
        assert_eq!(lids[0], LID_MAX);
        // Each render holds the lid or lowers it by one pixel.
        let steps = lids.windows(2).map(|pair| pair[0].checked_sub(pair[1]));
        assert!(
            steps.clone().all(|step| matches!(step, Some(0 | 1))),
            "{lids:?}"
        );
        let moves = steps.filter(|step| *step == Some(1)).count();
        assert_eq!(moves, usize::from(LID_MAX), "{lids:?}");
        assert_eq!(lids.last(), Some(&0), "{lids:?}");
    }
}

const ERASE: &str = "\r\x1b[2A\x1b[J";

fn drawn_frame() -> Frame {
    let mut frame = Frame::default();
    frame.draw(b"", "block\r\nrows\r\n".into(), 2);
    frame
}

#[test]
fn finished_lines_wait_and_reach_the_terminal_with_the_block_repainted() {
    let mut frame = drawn_frame();
    // Nothing is erased until the replacement is ready to go out with it.
    assert!(frame.write(b"warning: one\r\n").is_empty());
    assert!(frame.write(b"warning: two\r\n").is_empty());
    assert_eq!(
        String::from_utf8(frame.present(true)).unwrap(),
        format!("{ERASE}warning: one\r\nwarning: two\r\nblock\r\nrows\r\n")
    );
    assert_eq!(frame.drawn, 2);
    assert!(frame.present(true).is_empty(), "nothing left to repaint");
}

#[test]
fn partial_lines_are_shown_at_once_and_keep_the_block_away() {
    let mut frame = drawn_frame();
    assert!(frame.write(b"held\r\n").is_empty());
    assert_eq!(
        String::from_utf8(frame.write(b"Password: ")).unwrap(),
        format!("{ERASE}held\r\nPassword: ")
    );
    assert_eq!(frame.drawn, 0);
    assert!(frame.present(true).is_empty(), "no block to repaint");
}

#[test]
fn a_new_frame_carries_held_output_and_diagnostics_above_the_block() {
    let mut frame = drawn_frame();
    assert!(frame.write(b"line\r\n").is_empty());
    assert_eq!(
        String::from_utf8(frame.draw(b"note\n", "next\r\n".into(), 1)).unwrap(),
        format!("{ERASE}line\r\nnote\r\nnext\r\n")
    );
    assert_eq!(frame.drawn, 1);
}

#[test]
fn output_after_the_block_is_committed_passes_through_untouched() {
    let mut frame = drawn_frame();
    frame.commit();
    assert_eq!(frame.write(b"output\r\n"), b"output\r\n");
    assert!(frame.present(true).is_empty());
}

#[test]
fn a_crlf_split_across_chunks_is_written_together() {
    let mut frame = drawn_frame();
    // The PTY's CRLF reaches the decoder as `text\r` and then `\n`.
    assert!(frame.write(b"Finished\r").is_empty());
    assert!(frame.write(b"\n").is_empty());
    assert_eq!(
        String::from_utf8(frame.present(true)).unwrap(),
        format!("{ERASE}Finished\r\nblock\r\nrows\r\n")
    );
}

#[test]
fn a_crlf_split_across_reads_keeps_the_block_until_the_lf_arrives() {
    let mut frame = drawn_frame();
    assert!(frame.write(b"Finished\r").is_empty());
    // The read ended between CR and LF: nothing is erased yet.
    assert!(frame.present(true).is_empty());
    assert_eq!(frame.drawn, 2);
    assert!(frame.write(b"\n").is_empty());
    assert_eq!(
        String::from_utf8(frame.present(true)).unwrap(),
        format!("{ERASE}Finished\r\nblock\r\nrows\r\n")
    );
}

#[test]
fn a_bare_carriage_return_is_shown_above_the_next_frame_not_overwritten_by_it() {
    let mut frame = drawn_frame();
    assert!(frame.write(b"progress\r").is_empty());
    assert!(frame.present(true).is_empty());
    assert_eq!(
        String::from_utf8(frame.draw(b"", "next\r\n".into(), 1)).unwrap(),
        format!("{ERASE}progress\r\nnext\r\n")
    );
}

#[test]
fn only_output_ending_in_a_cr_makes_a_frame_wait() {
    let mut frame = drawn_frame();
    assert!(!frame.trailing_cr());
    frame.write(b"Finished\r");
    assert!(frame.trailing_cr());
    frame.write(b"\n");
    assert!(!frame.trailing_cr());
}

#[test]
fn the_lf_after_a_bare_cr_that_a_frame_already_ended_is_not_written_twice() {
    let mut frame = drawn_frame();
    assert!(frame.write(b"50%\r").is_empty());
    assert_eq!(
        String::from_utf8(frame.draw(b"", "next\r\n".into(), 1)).unwrap(),
        format!("{ERASE}50%\r\nnext\r\n")
    );
    // The child's LF arrives after the grace period, once the line has ended.
    assert!(frame.write(b"\n").is_empty());
    assert!(frame.present(true).is_empty(), "no blank row");
    // Only one LF is owed; the next is ordinary output.
    assert!(frame.write(b"\n").is_empty());
    assert_eq!(
        String::from_utf8(frame.present(true)).unwrap(),
        "\r\x1b[1A\x1b[J\nnext\r\n"
    );
}

#[test]
fn clearing_the_block_ends_a_held_bare_cr_line() {
    let mut frame = drawn_frame();
    assert!(frame.write(b"progress\r").is_empty());
    assert_eq!(
        String::from_utf8(frame.clear()).unwrap(),
        format!("{ERASE}progress\r\n")
    );
    assert_eq!(frame.drawn, 0);
    assert!(frame.write(b"\n").is_empty(), "the LF is already owed");
}

#[test]
fn each_carriage_return_gets_its_own_grace_period() {
    let start = Instant::now();
    let mut frame = drawn_frame();
    assert!(!frame.awaiting_lf(start), "nothing held");
    assert!(frame.write(b"a\r").is_empty());
    assert!(frame.awaiting_lf(start));
    assert!(frame.awaiting_lf(start + CR_GRACE / 2));
    let expired = start + CR_GRACE;
    assert!(!frame.awaiting_lf(expired), "no LF came: draw the line");
    frame.draw(b"", "next\r\n".into(), 1);
    // A new CR after the flush must not inherit the expired timer.
    assert!(frame.write(b"b\r").is_empty());
    assert!(frame.awaiting_lf(expired + Duration::from_millis(1)));
    assert!(!frame.awaiting_lf(expired + Duration::from_millis(1) + CR_GRACE));
}
