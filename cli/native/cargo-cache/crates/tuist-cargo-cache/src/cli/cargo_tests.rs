use super::*;

/// Verify that placement escapes the target as TOML and preserves both the
/// leading toolchain selector and application arguments after `--`.
#[test]
fn placed_target_config_is_scoped_and_preserves_argument_boundaries() {
    let original = [
        "+nightly",
        "run",
        "--",
        "--target-dir",
        "application argument",
    ]
    .map(String::from);
    let target = Path::new("directory with spaces/quote\"and\\slash");
    let placed = cargo::placed_cargo_arguments(&original, target);
    assert_eq!(placed[0], "+nightly");
    assert_eq!(placed[1], "--config");
    let config: toml::Value = toml::from_str(&placed[2]).unwrap();
    assert_eq!(config["build"]["target-dir"].as_str(), target.to_str());
    assert_eq!(&placed[3..], &original[1..]);
    assert_eq!(super::launch::cargo_subcommand(&placed), Some("run"));
}

#[test]
fn cargo_quiet_only_applies_before_the_argument_separator() {
    assert!(cargo_is_quiet(&["build".into(), "-q".into()]));
    assert!(cargo_is_quiet(&["test".into(), "--quiet".into()]));
    assert!(!cargo_is_quiet(&[
        "run".into(),
        "--".into(),
        "--quiet".into()
    ]));
}

#[test]
fn prefers_the_outermost_lockfile_as_the_workspace_root() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    let member = root.join("crates").join("member");
    std::fs::create_dir_all(&member).unwrap();
    std::fs::write(root.join("Cargo.lock"), "version = 4\n").unwrap();
    std::fs::write(root.join("Cargo.toml"), "[workspace]\n").unwrap();
    std::fs::write(member.join("Cargo.toml"), "[package]\n").unwrap();

    assert_eq!(workspace_root(&member), root);
}

#[test]
fn keeps_workspace_discovery_inside_a_delta_worktree() {
    let directory = tempfile::tempdir().unwrap();
    let repository = directory.path().join("project");
    let worktree = repository.join(".delta/worktrees/thread");
    let member = worktree.join("crates/member");
    std::fs::create_dir_all(&member).unwrap();
    std::fs::write(repository.join("Cargo.lock"), "outer").unwrap();
    std::fs::write(repository.join("Cargo.toml"), "[workspace]\n").unwrap();
    std::fs::write(worktree.join("Cargo.lock"), "inner").unwrap();
    std::fs::write(worktree.join("Cargo.toml"), "[workspace]\n").unwrap();
    std::fs::write(member.join("Cargo.toml"), "[package]\n").unwrap();

    assert_eq!(workspace_root(&member), worktree);
}

#[test]
fn vcs_markers_do_not_override_the_cargo_workspace() {
    for marker in [".git", ".jj", ".hg", ".sl"] {
        let directory = tempfile::tempdir().unwrap();
        let outer = directory.path();
        let member = outer.join("crates/member");
        std::fs::create_dir_all(&member).unwrap();
        std::fs::create_dir(member.join(marker)).unwrap();
        std::fs::write(outer.join("Cargo.lock"), "version = 4\n").unwrap();
        std::fs::write(outer.join("Cargo.toml"), "[workspace]\n").unwrap();
        std::fs::write(member.join("Cargo.toml"), "[package]\n").unwrap();

        assert_eq!(workspace_root(&member), outer, "marker: {marker}");
    }
}

#[test]
fn falls_back_to_a_manifest_without_a_lockfile() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    let nested = root.join("src");
    std::fs::create_dir_all(&nested).unwrap();
    std::fs::write(root.join("Cargo.toml"), "[package]\n").unwrap();

    assert_eq!(workspace_root(&nested), root);
}

#[test]
fn falls_back_to_the_starting_directory() {
    let directory = tempfile::tempdir().unwrap();
    assert_eq!(workspace_root(directory.path()), directory.path());
}

#[test]
fn reads_the_roots_cargo_reports() {
    let metadata = br#"{
            "workspace_root": "/elsewhere/project",
            "target_directory": "/var/cache/shared-target",
            "packages": []
        }"#;

    assert_eq!(
        parse_cargo_roots(metadata).unwrap(),
        Roots {
            workspace_root: PathBuf::from("/elsewhere/project"),
            target_dir: PathBuf::from("/var/cache/shared-target"),
            build_dir: None,
            target_dir_requested: false,
        }
    );
}

#[test]
fn ignores_unusable_cargo_metadata() {
    assert!(parse_cargo_roots(b"not json").is_none());
    assert!(parse_cargo_roots(br#"{"packages": []}"#).is_none());
}

#[test]
fn resolves_a_relative_directory_against_the_working_directory() {
    let cwd = Path::new("/workspace/crates/member");
    assert_eq!(
        absolute(cwd, "out"),
        Path::new("/workspace/crates/member/out")
    );
    assert_eq!(absolute(cwd, "/tmp/out"), Path::new("/tmp/out"));
}

#[test]
fn carries_inherited_wrappers_into_the_session() {
    let cwd = Path::new("/workspace");
    let with = inherited_environment(
        |name| match name {
            "RUSTC_WRAPPER" => Some("/usr/bin/sccache".to_string()),
            "RUSTC_WORKSPACE_WRAPPER" => Some("/usr/bin/workspace-rustc".to_string()),
            _ => None,
        },
        cwd,
    );
    assert_eq!(with.get("RUSTC_WRAPPER").unwrap(), "/usr/bin/sccache");
    assert_eq!(
        with.get("RUSTC_WORKSPACE_WRAPPER").unwrap(),
        "/usr/bin/workspace-rustc"
    );

    // An empty value is how a shell unsets it in practice.
    let empty = inherited_environment(
        |name| matches!(name, "RUSTC_WRAPPER" | "RUSTC_WORKSPACE_WRAPPER").then(String::new),
        cwd,
    );
    assert!(empty.is_empty());
    assert!(inherited_environment(|_| None, cwd).is_empty());
}

#[test]
fn absolutizes_the_bypass_log_before_the_shims_inherit_it() {
    let cwd = Path::new("/workspace");
    let relative = inherited_environment(
        |name| (name == crate::session::BYPASS_LOG_ENV).then(|| "bypass.log".to_string()),
        cwd,
    );
    // Left relative, each shim would resolve this against whichever crate
    // directory cargo happened to give it. Compare as paths: the separator
    // is not the same on every platform.
    assert_eq!(
        Path::new(relative.get(crate::session::BYPASS_LOG_ENV).unwrap()),
        cwd.join("bypass.log")
    );

    // An absolute destination is passed through untouched. Ask the platform
    // for one -- a leading slash is not absolute on Windows.
    let already = std::env::temp_dir().join("bypass.log");
    assert!(
        already.is_absolute(),
        "{} should be absolute",
        already.display()
    );
    let given = already.display().to_string();
    let absolute_path = inherited_environment(
        |name| (name == crate::session::BYPASS_LOG_ENV).then(|| given.clone()),
        cwd,
    );
    assert_eq!(
        Path::new(absolute_path.get(crate::session::BYPASS_LOG_ENV).unwrap()),
        already
    );

    assert!(
        !inherited_environment(
            |name| (name == crate::session::BYPASS_LOG_ENV).then(String::new),
            cwd
        )
        .contains_key(crate::session::BYPASS_LOG_ENV)
    );
}

#[test]
fn forwards_repeated_and_attached_global_flags() {
    let arguments = [
        "build",
        "--config",
        "build.target-dir=\"/one\"",
        "--config=net.offline=true",
        "-Zunstable-options",
        "-C",
        "/tree",
        "--release",
    ]
    .map(String::from);

    assert_eq!(
        forwarded_flags(&arguments, &PROBE_GLOBAL_FLAGS),
        [
            "--config",
            "build.target-dir=\"/one\"",
            "--config",
            "net.offline=true",
            "-Zunstable-options",
            "-C",
            "/tree",
        ]
    );
    // A flag the probe does not understand must not leak into it.
    assert!(
        forwarded_flags(&arguments, &PROBE_GLOBAL_FLAGS)
            .iter()
            .all(|argument| argument != "--release")
    );
}

#[test]
fn cargo_jobs_follow_cargo_cli_and_environment_precedence() {
    let args = |values: &[&str]| {
        values
            .iter()
            .map(|value| (*value).into())
            .collect::<Vec<_>>()
    };

    assert_eq!(
        cargo_job_limit_with(&args(&["build"]), Some("3"), 12),
        Some(3)
    );
    assert_eq!(
        cargo_job_limit_with(&args(&["build", "-j4"]), Some("3"), 12),
        Some(4)
    );
    assert_eq!(
        cargo_job_limit_with(&args(&["build", "--jobs=-2"]), None, 12),
        Some(10)
    );
    assert_eq!(
        cargo_job_limit_with(&args(&["build", "-j", "2"]), Some("7"), 12),
        Some(2)
    );
    assert_eq!(
        cargo_job_limit_with(&args(&["build", "-j1", "-j", "5"]), None, 12),
        Some(5),
        "Cargo's last occurrence wins"
    );
    assert_eq!(
        cargo_job_limit_with(&args(&["build", "--jobs", "default"]), Some("2"), 12),
        None,
        "default resets an environment limit"
    );
    assert_eq!(
        cargo_job_limit_with(&args(&["test", "--", "-j1"]), Some("6"), 12),
        Some(6),
        "test-harness arguments are not Cargo options"
    );
}

#[test]
fn cargo_help_does_not_trigger_target_migration() {
    assert!(cargo_help_requested(&["build".into(), "--help".into()]));
    assert!(cargo_help_requested(&["help".into(), "build".into()]));
    assert!(!cargo_help_requested(&["build".into(), "--release".into()]));
}

#[test]
fn the_first_run_notice_states_the_resolved_caps() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = managed_target_config(directory.path());
    config.gc.max_bytes = 12 * 1024 * 1024 * 1024;
    let retention = RetentionSettings {
        target_max_bytes: Some(25 * 1024 * 1024 * 1024),
        target_max_age: Some(std::time::Duration::from_secs(30 * 86_400)),
        incremental_max_bytes: Some(20 * 1024 * 1024 * 1024),
        incremental_max_age: Some(std::time::Duration::from_secs(30 * 86_400)),
        max_total_bytes: None,
        target_precedence: Default::default(),
        min_free: None,
    };

    let notice = first_run_notice(&config, &retention, false);

    assert!(notice.contains("first build on this machine"));
    assert!(notice.contains(&config.cache_dir.display().to_string()));
    // The budgets scale with the disk, so the notice has to report what was
    // resolved rather than a number written into the sentence.
    assert!(notice.contains("12.0 GiB"), "{notice}");
    assert!(notice.contains("25.0 GiB"), "{notice}");
    assert!(notice.contains("30 days"), "{notice}");
    assert!(notice.contains("its checkout is gone"), "{notice}");
}

#[test]
fn the_first_run_notice_omits_limits_that_are_off() {
    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());
    let retention = RetentionSettings {
        target_max_bytes: None,
        target_max_age: None,
        incremental_max_bytes: None,
        incremental_max_age: None,
        max_total_bytes: None,
        target_precedence: Default::default(),
        min_free: None,
    };

    let notice = first_run_notice(&config, &retention, false);

    assert!(notice.contains("its checkout is gone"), "{notice}");
    assert!(!notice.contains("unused for"), "{notice}");
    assert!(!notice.contains("GiB total"), "{notice}");
}

#[test]
fn the_first_run_notice_explains_the_shared_budget_without_a_target_cap() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = managed_target_config(directory.path());
    let retention = RetentionSettings {
        target_max_bytes: None,
        target_max_age: None,
        max_total_bytes: Some(50 * 1024 * 1024 * 1024),
        min_free: None,
        ..RetentionSettings::default()
    };
    let notice = first_run_notice(&config, &retention, false);
    assert!(notice.contains("target/ is managed: deleted when its checkout is gone or combined managed data exceeds 50.0 GiB logical"), "{notice}");

    config.gc.auto = false;
    let notice = first_run_notice(&config, &retention, false);
    assert!(
        !notice.contains("combined managed data exceeds"),
        "{notice}"
    );
}

#[test]
fn the_first_run_notice_does_not_promise_collection_that_is_off() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = managed_target_config(directory.path());
    config.gc.auto = false;

    let notice = first_run_notice(&config, &RetentionSettings::default(), false);

    assert!(notice.contains("automatic collection is off"), "{notice}");
    assert!(!notice.contains("pruned to"), "{notice}");
    assert!(!notice.contains("target/ is managed"), "{notice}");
}

#[test]
fn the_first_run_notice_skips_targets_it_does_not_manage() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = managed_target_config(directory.path());
    config.target.views = false;

    let notice = first_run_notice(&config, &RetentionSettings::default(), false);

    assert!(!notice.contains("target/ is managed"), "{notice}");
    assert!(notice.contains("pruned to"), "{notice}");
}

#[test]
fn the_first_run_notice_promises_reflinks_only_when_proven() {
    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());

    let with = first_run_notice(&config, &RetentionSettings::default(), true);
    let without = first_run_notice(&config, &RetentionSettings::default(), false);

    assert!(with.contains("supports reflinks"), "{with}");
    assert!(with.contains("instead of copying"), "{with}");
    // A machine whose filesystem copies must not be told its restores are
    // free; silence beats a promise the disk will break.
    assert!(!without.contains("reflink"), "{without}");
}

#[test]
fn reasons_read_as_prose() {
    assert_eq!(join_clauses(&["one".to_string()]), "one");
    assert_eq!(
        join_clauses(&["one".to_string(), "two".to_string()]),
        "one or two"
    );
    assert_eq!(
        join_clauses(&["one".to_string(), "two".to_string(), "three".to_string()]),
        "one, two, or three"
    );
}

pub(super) fn managed_target_config(root: &Path) -> Config {
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
        target: crate::config::TargetSettings {
            views: true,
            lanes: true,
            seed: false,
            root: root.join("targets"),
        },
    }
}

#[test]
fn rust_analyzer_target_is_a_child_of_the_managed_view() {
    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());
    let workspace = directory.path().join("project");
    std::fs::create_dir_all(&workspace).unwrap();
    let roots = Roots {
        workspace_root: workspace.clone(),
        target_dir: workspace.join(RUST_ANALYZER_TARGET_DIR),
        build_dir: None,
        target_dir_requested: true,
    };

    let placement = place_target_view(&config, &roots);

    let managed = std::fs::read_link(workspace.join("target")).unwrap();
    assert_eq!(
        placement.directory.unwrap(),
        workspace.join(RUST_ANALYZER_TARGET_DIR)
    );
    assert!(managed.starts_with(&config.target.root));
    assert_eq!(placement.touch_path, workspace.join("target"));
    assert_eq!(crate::target::stats(&config.target.root).unwrap().views, 1);
}

#[test]
fn an_existing_target_the_managed_root_can_hold_is_adopted_without_asking() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("project");
    let target_dir = workspace.join("target");
    std::fs::create_dir_all(&target_dir).unwrap();
    std::fs::write(target_dir.join("artifact"), b"old output").unwrap();
    let config = managed_target_config(directory.path());
    let roots = Roots {
        workspace_root: workspace,
        target_dir: target_dir.clone(),
        build_dir: None,
        target_dir_requested: false,
    };

    // The temporary directory holds both the checkout and the managed root,
    // so a rename between them is possible and nothing is asked.
    let decided = manage_existing_target_with(&config, &roots, |_| {
        panic!("a move that keeps every output must not ask")
    })
    .unwrap();

    assert_eq!(decided, Some(ExistingTarget::Adopt));
    assert!(target_dir.join("artifact").is_file());
}

#[test]
fn a_failed_adoption_warns_only_when_this_build_moved_or_kept_the_outputs() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("project");
    let target_dir = workspace.join("target");
    std::fs::create_dir_all(&workspace).unwrap();
    let roots = Roots {
        workspace_root: workspace,
        target_dir: target_dir.clone(),
        build_dir: None,
        target_dir_requested: false,
    };
    let refused = || eyre::eyre!("refused");

    // Another build has moved the directory and not yet linked it.
    assert_eq!(
        adoption_failure(&refused(), &roots),
        AdoptionFailure::NotMoved
    );

    // This build moved the outputs and could not put them back. The path is
    // just as empty, but the outputs are this build's to report.
    let stranded = refused().wrap_err(crate::target::StrandedAdoption {
        retained: directory.path().join("view"),
    });
    assert_eq!(
        adoption_failure(&stranded, &roots),
        AdoptionFailure::Stranded
    );

    std::fs::create_dir(&target_dir).unwrap();
    assert_eq!(
        adoption_failure(&refused(), &roots),
        AdoptionFailure::LeftInPlace
    );
}

#[test]
fn a_configured_target_directory_is_neither_adopted_nor_asked_about() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("project");
    let target_dir = workspace.join("target");
    std::fs::create_dir_all(&target_dir).unwrap();
    std::fs::write(target_dir.join("artifact"), b"old output").unwrap();
    let config = managed_target_config(directory.path());
    let roots = Roots {
        workspace_root: workspace,
        target_dir: target_dir.clone(),
        build_dir: None,
        target_dir_requested: true,
    };

    let decided = manage_existing_target_with(&config, &roots, |_| {
        panic!("a configured target directory must not be offered for removal")
    })
    .unwrap();

    assert_eq!(decided, None);
    assert!(target_dir.join("artifact").is_file());
}

fn lane_roots(workspace: &Path) -> Roots {
    Roots {
        workspace_root: workspace.to_path_buf(),
        target_dir: workspace.join("target"),
        build_dir: None,
        target_dir_requested: false,
    }
}

fn placed(workspace: &Path) -> TargetViewPlacement {
    TargetViewPlacement {
        directory: Some(workspace.join("managed")),
        touch_path: workspace.join("target"),
    }
}

fn lane(
    working_dir: &Path,
    config: &Config,
    roots: &Roots,
    placement: &TargetViewPlacement,
    arguments: &[String],
) -> Option<PathBuf> {
    check_lane(
        config,
        roots,
        placement,
        std::ffi::OsStr::new("cargo"),
        working_dir,
        arguments,
    )
}

fn arguments(arguments: &[&str]) -> Vec<String> {
    arguments.iter().map(ToString::to_string).collect()
}

#[test]
fn check_and_clippy_get_a_lane_inside_the_managed_target() {
    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());
    let workspace = directory.path().join("project");
    let roots = lane_roots(&workspace);
    let placement = placed(&workspace);

    for command in [
        &["check"][..],
        &["clippy", "--workspace", "--", "-D", "warnings"],
        &["+stable", "clippy"],
        &["--config", "term.color='never'", "check", "--all-targets"],
    ] {
        assert_eq!(
            lane(
                directory.path(),
                &config,
                &roots,
                &placement,
                &arguments(command)
            ),
            Some(workspace.join(CHECK_LANE_TARGET_DIR)),
            "{command:?}"
        );
    }
}

#[test]
fn commands_that_leave_outputs_behind_keep_the_shared_target() {
    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());
    let workspace = directory.path().join("project");
    let roots = lane_roots(&workspace);
    let placement = placed(&workspace);

    for command in [
        &["build"][..],
        &["test"],
        &["run"],
        &["doc"],
        &["nextest", "run"],
        // Program arguments are not subcommands.
        &["run", "--", "check"],
    ] {
        assert_eq!(
            lane(
                directory.path(),
                &config,
                &roots,
                &placement,
                &arguments(command)
            ),
            None,
            "{command:?}"
        );
    }
}

#[test]
fn a_lane_is_only_used_where_cargo_cache_is_placing_an_undirected_target() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = managed_target_config(directory.path());
    let workspace = directory.path().join("project");
    let placement = placed(&workspace);
    let check = arguments(&["check"]);

    // A flag, the environment, or Cargo's configuration named the directory.
    let requested = Roots {
        target_dir_requested: true,
        ..lane_roots(&workspace)
    };
    assert_eq!(
        lane(directory.path(), &config, &requested, &placement, &check),
        None
    );

    // Configuration moved the target somewhere other than the default.
    let elsewhere = Roots {
        target_dir: directory.path().join("elsewhere"),
        ..lane_roots(&workspace)
    };
    assert_eq!(
        lane(directory.path(), &config, &elsewhere, &placement, &check),
        None
    );

    // Cargo keeps its intermediate files, and the lock, out of the target.
    let separate = Roots {
        build_dir: Some(directory.path().join("build")),
        ..lane_roots(&workspace)
    };
    assert_eq!(
        lane(directory.path(), &config, &separate, &placement, &check),
        None
    );

    // A build directory that is the target itself is not separate.
    let same = Roots {
        build_dir: Some(workspace.join("target")),
        ..lane_roots(&workspace)
    };
    assert!(lane(directory.path(), &config, &same, &placement, &check).is_some());

    // Placement declined, so there is no managed view to put a lane in.
    let unplaced = TargetViewPlacement {
        directory: None,
        touch_path: workspace.join("target"),
    };
    assert_eq!(
        lane(
            directory.path(),
            &config,
            &lane_roots(&workspace),
            &unplaced,
            &check
        ),
        None
    );

    config.target.lanes = false;
    assert_eq!(
        lane(
            directory.path(),
            &config,
            &lane_roots(&workspace),
            &placement,
            &check
        ),
        None
    );
}

#[test]
fn a_lane_is_named_right_after_the_subcommand() {
    let lane = Path::new("/work/project/target/check");

    assert_eq!(
        lane_cargo_arguments(
            &arguments(&["+stable", "clippy", "--workspace", "--", "-D", "warnings"]),
            lane
        ),
        arguments(&[
            "+stable",
            "clippy",
            "--target-dir",
            "/work/project/target/check",
            "--workspace",
            "--",
            "-D",
            "warnings",
        ])
    );
    assert_eq!(
        lane_cargo_arguments(
            &arguments(&["--config", "term.color='never'", "check"]),
            lane
        ),
        arguments(&[
            "--config",
            "term.color='never'",
            "check",
            "--target-dir",
            "/work/project/target/check",
        ])
    );
}

#[test]
fn a_config_naming_the_build_directory_rules_out_a_lane() {
    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());
    let workspace = directory.path().join("project");
    std::fs::create_dir_all(workspace.join(".cargo")).unwrap();
    // The same path as the target, so the probe reports nothing unusual, yet
    // the lock lives where the caller put it and no lane can move it.
    std::fs::write(
        workspace.join(".cargo/config.toml"),
        "[build]\nbuild-dir = \"target\"\n",
    )
    .unwrap();
    let roots = Roots {
        build_dir: Some(workspace.join("target")),
        ..lane_roots(&workspace)
    };
    let check = arguments(&["check"]);

    assert!(build_dir_configured(&workspace, &check));
    assert_eq!(
        lane(&workspace, &config, &roots, &placed(&workspace), &check),
        None
    );
}

#[test]
fn a_config_flag_that_could_name_the_build_directory_rules_out_a_lane() {
    for named in [
        &["--config", "build.build-dir='target'", "check"][..],
        &["--config=build.build-dir='target'", "check"],
        // A file can set anything, including the build directory.
        &["--config", "extra.toml", "check"],
    ] {
        assert!(build_dir_named_in(&arguments(named)), "{named:?}");
    }
    for unrelated in [
        &["--config", "term.color='never'", "check"][..],
        &["check", "--", "--config", "extra.toml"],
        &["check"],
        &["--config"],
    ] {
        assert!(!build_dir_named_in(&arguments(unrelated)), "{unrelated:?}");
    }
}

#[test]
fn a_plain_command_name_is_not_expanded() {
    let cargo = std::ffi::OsStr::new("cargo");
    for typed in [
        &["check"][..],
        &["+stable", "clippy", "--workspace"],
        &["build", "--release"],
        &["test"],
    ] {
        let typed = arguments(typed);
        assert_eq!(
            super::cargo_invocation::expanded_arguments(cargo, &typed),
            Some(typed.clone()),
        );
    }
}

#[test]
fn a_target_dir_ahead_of_the_program_arguments_rules_out_a_lane() {
    for named in [
        &["check", "--target-dir", "elsewhere"][..],
        &["clippy", "--target-dir=elsewhere", "--workspace"],
        &["--target-dir", "elsewhere", "check"],
    ] {
        assert!(target_dir_named_in(&arguments(named)), "{named:?}");
    }
    for unrelated in [
        &["check", "--workspace"][..],
        &["clippy", "--", "--target-dir", "elsewhere"],
    ] {
        assert!(!target_dir_named_in(&arguments(unrelated)), "{unrelated:?}");
    }

    let directory = tempfile::tempdir().unwrap();
    let config = managed_target_config(directory.path());
    let workspace = directory.path().join("project");
    let roots = lane_roots(&workspace);
    let check = arguments(&["check", "--target-dir", "elsewhere"]);
    assert_eq!(
        lane(
            directory.path(),
            &config,
            &roots,
            &placed(&workspace),
            &check
        ),
        None
    );
}

#[test]
fn configuration_is_read_from_the_directory_the_command_moves_to() {
    let directory = tempfile::tempdir().unwrap();
    let project = directory.path().join("project");
    std::fs::create_dir_all(project.join(".cargo")).unwrap();
    std::fs::write(
        project.join(".cargo/config.toml"),
        "[build]\nbuild-dir = \"target\"\n",
    )
    .unwrap();
    let elsewhere = directory.path().join("elsewhere");
    std::fs::create_dir_all(&elsewhere).unwrap();

    for moved in [
        &["-C", "../project", "check"][..],
        &["-C../project", "check"],
        &["--directory", "../project", "check"],
        &["--directory=../project", "check"],
        &["-C", "..", "-C", "project", "check"],
        &["-C", project.to_str().unwrap(), "check"],
        // Global options may follow the command, and clap takes `=` after `-C`.
        &["check", "-C", "../project"],
        &["check", "--directory=../project", "--workspace"],
        &["-C=../project", "check"],
        &["check", "-C=../project"],
    ] {
        let moved = arguments(moved);
        assert_eq!(
            invocation_dir(&elsewhere, &moved).canonicalize().unwrap(),
            project.canonicalize().unwrap(),
            "{moved:?}"
        );
        // The setting is in the project, not where the command was typed.
        assert!(build_dir_configured(&elsewhere, &moved), "{moved:?}");
    }

    // Arguments after `--` belong to the program, not to Cargo.
    let unmoved = arguments(&["check", "--", "-C", "../project"]);
    assert_eq!(invocation_dir(&elsewhere, &unmoved), elsewhere);
}

fn config_with_wrappers(
    root: &Path,
    wrapper: Option<&str>,
    workspace_wrapper: Option<&str>,
) -> cargo_config2::Config {
    let mut text = String::from("[build]\n");
    if let Some(wrapper) = wrapper {
        text.push_str(&format!("rustc-wrapper = \"{wrapper}\"\n"));
    }
    if let Some(wrapper) = workspace_wrapper {
        text.push_str(&format!("rustc-workspace-wrapper = \"{wrapper}\"\n"));
    }
    std::fs::create_dir_all(root.join(".cargo")).unwrap();
    std::fs::write(root.join(".cargo/config.toml"), text).unwrap();
    // An empty environment and a Cargo home of its own: the RUSTC_WRAPPER that
    // tuist_cargo_cache sets for this very process would otherwise outrank the file.
    cargo_config2::Config::load_with_options(
        root,
        cargo_config2::ResolveOptions::default()
            .env(Vec::<(String, String)>::new())
            .cargo_home(root.join("cargo-home")),
    )
    .unwrap()
}

#[test]
fn an_empty_rustc_wrapper_is_no_wrapper() {
    let directory = tempfile::tempdir().unwrap();
    // Left alone, the empty string becomes the program that would run rustc.
    let unfixed = config_with_wrappers(directory.path(), Some(""), Some(""));
    assert!(unfixed.rustc().path.as_os_str().is_empty());

    let config = super::launch::without_empty_wrappers(config_with_wrappers(
        directory.path(),
        Some(""),
        Some(""),
    ));

    assert_eq!(config.build.rustc_wrapper, None);
    assert_eq!(config.build.rustc_workspace_wrapper, None);
    assert!(!config.rustc().path.as_os_str().is_empty());
}

#[test]
fn a_real_rustc_wrapper_is_kept() {
    let directory = tempfile::tempdir().unwrap();
    let config = super::launch::without_empty_wrappers(config_with_wrappers(
        directory.path(),
        Some("sccache"),
        Some("workspace-wrapper"),
    ));

    assert_eq!(
        config.build.rustc_wrapper,
        Some(std::path::PathBuf::from("sccache"))
    );
    assert_eq!(
        config.build.rustc_workspace_wrapper,
        Some(std::path::PathBuf::from("workspace-wrapper"))
    );
}
