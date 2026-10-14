use super::*;

/// Only a toolchain's own compiler is pinned: a proxy or shim has no
/// `rustc_driver` beside it, and its bytes say nothing about the toolchain
/// it will pick.
#[test]
fn compiler_pins_name_a_toolchain_rustc_and_nothing_else() {
    let directory = tempfile::tempdir().unwrap();
    let bin = directory.path().join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    let rustc = bin.join("rustc");
    std::fs::write(&rustc, "dispatcher").unwrap();
    assert!(compiler_identity_pins(&rustc).is_empty());

    let lib = directory.path().join("lib");
    std::fs::create_dir_all(&lib).unwrap();
    let driver = lib.join("librustc_driver-0123456789abcdef.so");
    std::fs::write(&driver, "compiler library").unwrap();
    let pins = compiler_identity_pins(&rustc);
    assert_eq!(
        pins.iter().map(|pin| pin.path.clone()).collect::<Vec<_>>(),
        vec![rustc, driver]
    );
    assert!(pins.iter().all(|pin| pin.state.is_some()));
}

#[test]
fn compiler_identity_hashes_sysroot_codegen_backends() {
    let directory = tempfile::tempdir().unwrap();
    let bin = directory.path().join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    let rustc = bin.join("rustc");
    std::fs::write(&rustc, "compiler").unwrap();
    let rustlib = directory.path().join("lib/rustlib");
    let backends = rustlib.join("aarch64-apple-darwin/codegen-backends");
    // Another target's backends are never loaded, so they stay out.
    let other = rustlib.join("x86_64-pc-windows-msvc/codegen-backends");
    std::fs::create_dir_all(&other).unwrap();
    std::fs::write(other.join("librustc_codegen_other.dll"), "unused").unwrap();
    let probe = || codegen_backends(rustc.as_os_str(), "aarch64-apple-darwin").unwrap();

    let (absent, identity) = probe();
    assert!(identity.is_empty());
    assert_eq!(absent.len(), 1);
    assert!(absent[0].state.is_none());

    std::fs::create_dir_all(&backends).unwrap();
    let library = backends.join("librustc_codegen_cranelift-1.99.0-nightly.dylib");
    std::fs::write(&library, "backend one").unwrap();
    assert!(!absent[0].holds());
    let (pins, first) = probe();
    assert!(first.contains(
        "tuist_cargo_cache-codegen-backend: \"librustc_codegen_cranelift-1.99.0-nightly.dylib\" "
    ));
    assert_eq!(
        pins.iter().map(|pin| pin.path.clone()).collect::<Vec<_>>(),
        vec![backends.clone(), library.clone()]
    );

    // A new length: Windows can keep the write time of an immediate rewrite.
    std::fs::write(&library, "backend 2").unwrap();
    assert_ne!(probe().1, first);
    assert!(!pins[1].holds());

    #[cfg(unix)]
    {
        let store = directory.path().join("store/librustc_codegen_gcc.so");
        std::fs::create_dir_all(store.parent().unwrap()).unwrap();
        std::fs::write(&store, "linked backend").unwrap();
        std::os::unix::fs::symlink(&store, backends.join("librustc_codegen_gcc.so")).unwrap();
        std::os::unix::fs::symlink("missing", backends.join("librustc_codegen_gone.so")).unwrap();
        let (_, linked) = probe();
        assert!(linked.contains("tuist_cargo_cache-codegen-backend: \"librustc_codegen_gcc.so\" "));
        assert!(!linked.contains("librustc_codegen_gone.so"));
    }
}

/// `RUSTC_BOOTSTRAP` enters the key only when set, so builds that never set
/// it keep their existing keys.
#[test]
fn compiler_environment_keys_only_what_is_set() {
    assert!(compiler_environment(|_| None).is_empty());
    assert_eq!(
        compiler_environment(|name| (name == "RUSTC_BOOTSTRAP").then(|| "1".into())),
        BTreeMap::from([("RUSTC_BOOTSTRAP".into(), Some("1".into()))])
    );
}

#[test]
fn action_diagnostics_name_key_parts_without_retaining_their_values() {
    let bytes = br#"{"adapter_version":1,"arguments":["--crate-name=example","--codegen=metadata=unit-a","--codegen=opt-level=2","--cfg=feature=\"secret-feature\""],"compiler":{"host":"host","rustc_version":"version","toolchain":"toolchain"},"environment":{"SECRET":"do-not-record"},"inputs":[{"digest":{"algorithm":"blake3","hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":7},"path":"${workspace}/src/lib.rs"}],"kind":"rustc","version":1}"#.to_vec();
    let diagnostic = action_diagnostic(
        &RustcAction {
            digest: CacheDigest::blake3(&bytes),
            bytes,
        },
        "${workspace}/src/lib.rs",
    )
    .unwrap();

    assert!(diagnostic.components.contains_key("compiler toolchain"));
    assert!(diagnostic.components.contains_key("compilation unit"));
    assert!(
        diagnostic
            .components
            .contains_key("argument --codegen opt-level")
    );
    assert!(diagnostic.components.contains_key("environment SECRET"));
    assert!(diagnostic.inputs.contains_key("${workspace}/src/lib.rs"));
    let recorded = serde_json::to_string(&diagnostic).unwrap();
    assert!(!recorded.contains("do-not-record"));
    assert!(!recorded.contains("secret-feature"));
}

#[test]
fn cargo_metadata_changes_are_diffs_within_one_compilation_unit() {
    let action = |metadata: &str| {
        let bytes = format!(
            r#"{{"adapter_version":1,"arguments":["--crate-name=example","--crate-type=lib","--codegen=metadata={metadata}"],"compiler":{{"host":"host","rustc_version":"version","toolchain":"toolchain"}},"environment":{{}},"inputs":[],"kind":"rustc","version":1}}"#
        )
        .into_bytes();
        action_diagnostic(
            &RustcAction {
                digest: CacheDigest::blake3(&bytes),
                bytes,
            },
            "${workspace}/src/lib.rs",
        )
        .unwrap()
    };

    let previous = action("old");
    let current = action("new");
    assert_eq!(
        previous.components["compilation unit"],
        current.components["compilation unit"]
    );
    assert_ne!(
        previous.components["argument --codegen metadata"],
        current.components["argument --codegen metadata"]
    );
}
use crate::materialize::{apply_file_mode, make_owner_writable, stage_verified_cached_output_with};
use std::sync::{Arc, Mutex};

/// A forwarding destination a test can read back after the compiler exits.
#[derive(Clone, Default)]
struct Sink(Arc<Mutex<Vec<u8>>>);

impl Sink {
    fn bytes(&self) -> Vec<u8> {
        self.0.lock().unwrap().clone()
    }
}

impl Write for Sink {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

/// A destination that stops accepting bytes after the first line.
struct ClosedAfterOneLine {
    seen: Sink,
    lines: usize,
}

impl Write for ClosedAfterOneLine {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        if self.lines >= 1 {
            return Err(std::io::Error::from(std::io::ErrorKind::BrokenPipe));
        }
        self.lines += 1;
        self.seen.write(buf)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[test]
fn forwarded_lines_are_the_captured_bytes() {
    let mut sink = Sink::default();
    let captured = forward_stream(&b"one\ntwo\n\nthree"[..], &mut sink).unwrap();
    assert_eq!(captured, b"one\ntwo\n\nthree");
    assert_eq!(
        sink.bytes(),
        captured,
        "a final line without a newline is forwarded too"
    );
    assert!(forward_stream(&b""[..], &mut sink).unwrap().is_empty());
}

#[test]
fn a_closed_forwarding_destination_still_drains_the_compiler() {
    let seen = Sink::default();
    let sink = ClosedAfterOneLine {
        seen: seen.clone(),
        lines: 0,
    };
    let captured = forward_stream(&b"first\nsecond\nthird\n"[..], sink).unwrap();
    assert_eq!(captured, b"first\nsecond\nthird\n");
    assert_eq!(seen.bytes(), b"first\n");
}

/// Both streams of a real child, interleaved, with a partial final line on
/// each: what Cargo receives is byte for byte what the cache entry keeps.
#[cfg(unix)]
#[test]
fn a_forwarded_compiler_run_captures_what_it_forwards() {
    let script = concat!(
        "printf 'out one\\n'; ",
        "printf '{\"$message_type\":\"artifact\",\"emit\":\"metadata\"}\\n' >&2; ",
        "printf 'out two\\n'; ",
        "printf 'warning: x\\n' >&2; ",
        "printf 'tail without newline'; ",
        "printf 'err tail' >&2; ",
        "exit 3"
    );
    let mut command = Command::new("sh");
    command.arg("-c").arg(script);
    let stdout_sink = Sink::default();
    let stderr_sink = Sink::default();
    let output =
        run_compiler_forwarding(&mut command, stdout_sink.clone(), stderr_sink.clone(), None)
            .unwrap();
    assert_eq!(output.status.code(), Some(3));
    assert_eq!(
        output.stdout, b"out one\nout two\ntail without newline",
        "standard output is captured whole"
    );
    assert_eq!(
        output.stderr,
        b"{\"$message_type\":\"artifact\",\"emit\":\"metadata\"}\nwarning: x\nerr tail",
        "standard error is captured whole"
    );
    assert_eq!(stdout_sink.bytes(), output.stdout);
    assert_eq!(stderr_sink.bytes(), output.stderr);
    // The plain path returns the same thing Cargo would have seen at the end.
    let mut command = Command::new("sh");
    command.arg("-c").arg(script);
    let held = run_compiler(&mut command, false, false).unwrap();
    assert_eq!(held.stdout, output.stdout);
    assert_eq!(held.stderr, output.stderr);
    assert_eq!(held.status.code(), Some(3));
}

/// A line is handed on as soon as it is complete, not once the process exits:
/// the child prints its notification, then waits for a file the test creates
/// only after the line has been seen.
#[cfg(unix)]
#[test]
fn a_notification_is_forwarded_before_the_compiler_exits() {
    let root = tempfile::tempdir().unwrap();
    let release = root.path().join("release");
    let mut command = Command::new("sh");
    command.arg("-c").arg(format!(
        "printf 'metadata ready\\n' >&2; while [ ! -e '{}' ]; do sleep 0.02; done; printf 'done\\n' >&2",
        release.display()
    ));
    struct Releasing {
        seen: Sink,
        release: PathBuf,
    }
    impl Write for Releasing {
        fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
            let written = self.seen.write(buf)?;
            if self.seen.bytes() == b"metadata ready\n" {
                std::fs::write(&self.release, b"").unwrap();
            }
            Ok(written)
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let seen = Sink::default();
    let sink = Releasing {
        seen: seen.clone(),
        release,
    };
    // Bounded: if forwarding regressed, the child would wait for a file
    // nobody creates. The worker is released and the test fails instead.
    let (done, finished) = std::sync::mpsc::channel();
    let release_on_timeout = root.path().join("release");
    let worker = std::thread::spawn(move || {
        let output = run_compiler_forwarding(&mut command, Sink::default(), sink, None);
        let _ = done.send(());
        output
    });
    if finished
        .recv_timeout(std::time::Duration::from_secs(30))
        .is_err()
    {
        std::fs::write(&release_on_timeout, b"").unwrap();
        let _ = worker.join();
        panic!("the notification was not forwarded while the compiler was still running");
    }
    let output = worker.join().unwrap().unwrap();
    assert!(
        output.status.success(),
        "the child only exits once its first line was forwarded"
    );
    assert_eq!(output.stderr, b"metadata ready\ndone\n");
    assert_eq!(seen.bytes(), output.stderr);
}

fn churn(sources: &str, streak: u32) -> ChurnState {
    ChurnState {
        version: CHURN_STATE_VERSION,
        sources: CacheDigest::blake3(sources.as_bytes()).key(),
        streak,
    }
}

/// The streak is what separates a crate someone is editing from one that merely
/// lost its result, and it only counts while that crate's own sources move.
#[test]
fn only_a_run_of_changed_sources_earns_incremental_state() {
    let now = CacheDigest::blake3(b"current sources");

    // Nothing recorded here yet: a first compilation in a checkout is not
    // evidence of anything, and neither is a wiped target directory.
    assert_eq!(
        learned_plan(None, &now, true, HOT_STREAK_THRESHOLD).streak,
        0
    );

    // Recorded against the sources this compilation already has, so nobody
    // edited it -- something else lost the result, and recompiling normally
    // restores it for everyone.
    let unchanged = churn("current sources", HOT_STREAK_THRESHOLD);
    let plan = learned_plan(Some(&unchanged), &now, true, HOT_STREAK_THRESHOLD);
    assert_eq!(plan.streak, 0);
    assert!(!plan.hot);

    // Changed sources climb the streak, and only its last step is hot.
    for previous in 0..HOT_STREAK_THRESHOLD - 1 {
        let recorded = churn("older sources", previous);
        let plan = learned_plan(Some(&recorded), &now, true, HOT_STREAK_THRESHOLD);
        assert_eq!(plan.streak, previous + 1);
        assert!(!plan.hot);
    }
    let recorded = churn("older sources", HOT_STREAK_THRESHOLD - 1);
    assert!(learned_plan(Some(&recorded), &now, true, HOT_STREAK_THRESHOLD).hot);

    // The streak is a state rather than a tally, so it stops at the threshold.
    let saturated = churn("older sources", HOT_STREAK_THRESHOLD);
    assert_eq!(
        learned_plan(Some(&saturated), &now, true, HOT_STREAK_THRESHOLD).streak,
        HOT_STREAK_THRESHOLD
    );

    // Disabled, the streak is still tracked so that enabling it later works.
    let plan = learned_plan(Some(&saturated), &now, false, HOT_STREAK_THRESHOLD);
    assert_eq!(plan.streak, HOT_STREAK_THRESHOLD);
    assert!(!plan.hot);
}

#[test]
fn one_changed_workspace_source_is_hot() {
    let now = CacheDigest::blake3(b"current sources");
    let recorded = churn("older sources", 0);

    let plan = learned_plan(Some(&recorded), &now, true, WORKSPACE_HOT_STREAK_THRESHOLD);

    assert_eq!(plan.streak, 1);
    assert!(plan.hot);
}

/// A marker names the artifact it was written for and is withdrawn before the
/// artifact is replaced, so only what a hot compilation wrote reads as private.
#[test]
fn private_artifacts_are_recognized_only_while_marked() {
    let root = tempfile::tempdir().unwrap();
    let deps = root.path().join("target/debug/deps");
    let outputs = RustcOutputs {
        directory: deps.clone(),
        files: vec![deps.join("libbase-1.rlib"), deps.join("libbase-1.rmeta")],
        dep_info: deps.join("base-1.d"),
    };
    let links = vec![
        root.path().join("above/src/lib.rs"),
        deps.join("libbase-1.rmeta"),
    ];
    assert!(!links_private_artifact_in(root.path(), &links));

    record_private_artifacts(root.path(), &outputs).unwrap();
    assert!(links_private_artifact_in(root.path(), &links));
    assert!(
        !links_private_artifact_in(root.path(), &[deps.join("libother-1.rlib")]),
        "a marker must not vouch for an artifact it was not written for"
    );

    forget_private_artifacts(root.path(), &outputs);
    assert!(!links_private_artifact_in(root.path(), &links));
    forget_private_artifacts(root.path(), &outputs);
}

/// The record belongs to one checkout, so a sibling worktree that cannot read
/// it simply starts over rather than inheriting somebody else's edit loop.
#[test]
fn an_unreadable_record_is_no_record() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("state.json");
    let sources = CacheDigest::blake3(b"sources");

    write_churn_state(&path, &sources, 2).unwrap();
    assert_eq!(read_churn_state(&path).unwrap().streak, 2);

    std::fs::write(&path, br#"{"version":99,"sources":"x","streak":3}"#).unwrap();
    assert!(read_churn_state(&path).is_none());

    std::fs::write(&path, b"not json").unwrap();
    assert!(read_churn_state(&path).is_none());
}

#[test]
fn compiler_timing_survives_a_changed_action_key() {
    let invocation = CacheDigest::blake3(b"invocation");
    let timing = RustcInputPrediction {
        version: 3,
        inputs: Vec::new(),
        environment: Vec::new(),
        compiler_duration_ns: 42,
        crate_name: "demo".into(),
    };
    let prediction = ActionPrediction {
        invocation: invocation.clone(),
        action: CacheDigest::blake3(b"old action"),
        adapter: "rustc".into(),
        payload: String::from_utf8(canonical_json(&timing).unwrap()).unwrap(),
    };

    let decoded = decode_prediction_timing(&prediction, &invocation).unwrap();
    assert_eq!(decoded.crate_name, "demo");
    assert_eq!(decoded.duration_ns, 42);
}

#[test]
fn prediction_v1_does_not_supply_timing() {
    let invocation = CacheDigest::blake3(b"invocation");
    let timing = RustcInputPrediction {
        version: 1,
        inputs: Vec::new(),
        environment: Vec::new(),
        compiler_duration_ns: 42,
        crate_name: "demo".into(),
    };
    let prediction = ActionPrediction {
        invocation: invocation.clone(),
        action: CacheDigest::blake3(b"old action"),
        adapter: "rustc".into(),
        payload: String::from_utf8(canonical_json(&timing).unwrap()).unwrap(),
    };

    assert!(decode_prediction_timing(&prediction, &invocation).is_err());
}

fn staged_outputs(root: &Path, entries: Vec<(&[u8], PathBuf)>) -> StagedOutputs {
    let directory = tempfile::tempdir_in(root).unwrap();
    let files = entries
        .into_iter()
        .enumerate()
        .map(|(index, (contents, destination))| {
            let path = directory.path().join(format!("output-{index}"));
            std::fs::write(&path, contents).unwrap();
            (
                tempfile::TempPath::try_from_path(path).unwrap(),
                destination,
            )
        })
        .collect();
    StagedOutputs { directory, files }
}

fn test_outputs(root: &Path) -> RustcOutputs {
    let directory = root.join("out");
    RustcOutputs {
        files: vec![directory.join("libdemo.rlib")],
        dep_info: directory.join("demo.d"),
        directory,
    }
}

fn test_file(name: &str) -> CacheFileNode {
    CacheFileNode {
        digest: CacheDigest::blake3(b"artifact"),
        executable: false,
        mode: if cfg!(unix) { 0o644 } else { 0 },
        name: name.into(),
    }
}

fn test_directory(files: Vec<CacheFileNode>) -> CacheDirectory {
    CacheDirectory {
        directories: Vec::new(),
        files,
        symlinks: Vec::new(),
        version: 1,
    }
}

fn test_output_directory(file: CacheFileNode) -> CacheDirectory {
    test_directory(vec![file, test_file("demo.d")])
}

#[test]
fn parses_verbose_rustc_identity() {
    let verbose = "rustc 1.97.0 (abc 2026-08-01)\n\
                       binary: rustc\n\
                       commit-hash: abc\n\
                       commit-date: 2026-08-01\n\
                       host: x86_64-unknown-linux-gnu\n\
                       release: 1.97.0\n\
                       LLVM version: 22.0.0\n";
    assert_eq!(identity_field(verbose, "release").unwrap(), "1.97.0");
    assert_eq!(
        identity_field(verbose, "host").unwrap(),
        "x86_64-unknown-linux-gnu"
    );
}

#[test]
fn mappings_do_not_duplicate_home_placeholders() {
    let directory = tempfile::tempdir().unwrap();
    let mappings = path_mappings(directory.path(), None, None);
    let placeholders = mappings
        .iter()
        .map(|mapping| &mapping.placeholder)
        .collect::<BTreeSet<_>>();
    assert_eq!(placeholders.len(), mappings.len());
}

#[test]
fn standalone_workspace_mapping_wins_beneath_home() {
    let directory = tempfile::tempdir().unwrap();
    let home = directory.path().join("home");
    let workspace = home.join("src/project");
    let mappings = path_mappings_with_env(&workspace, None, None, |name| match name {
        "HOME" => Some(home.as_os_str().to_owned()),
        _ => None,
    });

    assert!(
        mappings
            .iter()
            .any(|mapping| { mapping.placeholder == "workspace" && mapping.root == workspace })
    );
    assert!(
        mappings
            .iter()
            .any(|mapping| mapping.placeholder == "home" && mapping.root == home)
    );
}

#[test]
fn standalone_workspace_mapping_uses_the_outer_workspace_for_members() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    let member = workspace.join("crates/widget");
    std::fs::create_dir_all(&member).unwrap();
    std::fs::write(workspace.join("Cargo.lock"), "").unwrap();
    std::fs::write(member.join("Cargo.toml"), "[package]\nname = \"widget\"\n").unwrap();

    let mappings = path_mappings_with_env(&member, None, None, |_| None);

    assert!(
        mappings
            .iter()
            .any(|mapping| { mapping.placeholder == "workspace" && mapping.root == workspace })
    );
}

#[test]
fn standalone_registry_mapping_uses_the_default_cargo_home() {
    let directory = tempfile::tempdir().unwrap();
    let home = directory.path().join("home");
    let dependency = home.join(".cargo/registry/src/index/widget-1.0.0");
    std::fs::create_dir_all(&dependency).unwrap();
    std::fs::write(
        dependency.join("Cargo.toml"),
        "[package]\nname = \"widget\"\n",
    )
    .unwrap();

    let mappings = path_mappings_with_env(&dependency, None, None, |name| match name {
        "HOME" => Some(home.as_os_str().to_owned()),
        _ => None,
    });

    assert!(mappings.iter().any(|mapping| {
        mapping.placeholder == "cargo_home" && mapping.root == home.join(".cargo")
    }));
    assert!(mappings.iter().any(|mapping| {
        mapping.placeholder == "cargo_registry" && mapping.root == home.join(".cargo/registry")
    }));
    assert!(
        !mappings
            .iter()
            .any(|mapping| mapping.placeholder == "workspace")
    );
}

/// Session mappings for a compilation of `manifest_dir`, with `home` as home.
fn session_mappings(
    workspace: &Path,
    home: &Path,
    manifest_dir: &Path,
    working_dir: &Path,
) -> Vec<PathMapping> {
    PathMapping::ordered(&path_mappings_with_env(
        working_dir,
        None,
        None,
        |name| match name {
            "HOME" => Some(home.as_os_str().to_owned()),
            "CARGO_MANIFEST_DIR" => Some(manifest_dir.as_os_str().to_owned()),
            session::WORKSPACE_ROOT_ENV => Some(workspace.as_os_str().to_owned()),
            _ => None,
        },
    ))
}

#[test]
fn path_dependency_outside_the_workspace_and_home_maps_to_its_package() {
    let directory = tempfile::tempdir().unwrap();
    let home = directory.path().join("home");
    let workspace = directory.path().join("checkout/app");
    let dependency = directory.path().join("checkout/dep");
    std::fs::create_dir_all(dependency.join("src")).unwrap();
    std::fs::create_dir_all(&workspace).unwrap();
    std::fs::create_dir_all(&home).unwrap();
    std::fs::write(dependency.join("src/lib.rs"), "").unwrap();

    let mappings = session_mappings(&workspace, &home, &dependency, &dependency);

    assert_eq!(
        normalize_mapped_path(&dependency.join("src/lib.rs"), &dependency, &mappings).unwrap(),
        "${package}/src/lib.rs"
    );
}

#[test]
fn path_dependency_below_home_maps_to_its_package() {
    let directory = tempfile::tempdir().unwrap();
    let home = directory.path().join("home");
    let workspace = home.join("src/app");
    let dependency = home.join("src/dep");
    std::fs::create_dir_all(dependency.join("src")).unwrap();
    std::fs::create_dir_all(&workspace).unwrap();
    std::fs::write(dependency.join("src/lib.rs"), "").unwrap();

    let mappings = session_mappings(&workspace, &home, &dependency, &dependency);

    assert_eq!(
        normalize_mapped_path(&dependency.join("src/lib.rs"), &dependency, &mappings).unwrap(),
        "${package}/src/lib.rs"
    );
    assert_eq!(
        normalize_mapped_path(&home.join("notes.txt"), &dependency, &mappings).unwrap(),
        "${home}/notes.txt"
    );
}

#[test]
fn workspace_members_and_registry_crates_keep_their_roots() {
    let directory = tempfile::tempdir().unwrap();
    let home = directory.path().join("home");
    let workspace = directory.path().join("app");
    let member = workspace.join("crates/widget");
    let registry = home.join(".cargo/registry/src/index/widget-1.0.0");

    for manifest_dir in [&member, &registry] {
        let mappings = session_mappings(&workspace, &home, manifest_dir, manifest_dir);
        assert!(
            !mappings
                .iter()
                .any(|mapping| mapping.placeholder == "package"),
            "{}",
            manifest_dir.display()
        );
    }
}

#[cfg(unix)]
#[test]
fn cargo_registry_mapping_follows_a_child_symlink() {
    use std::os::unix::fs::symlink;

    let directory = tempfile::tempdir().unwrap();
    let cargo_home = directory.path().join("cargo-home");
    let physical_registry = directory.path().join("host-cargo-registry");
    std::fs::create_dir_all(&cargo_home).unwrap();
    std::fs::create_dir_all(&physical_registry).unwrap();
    symlink(&physical_registry, cargo_home.join("registry")).unwrap();
    let source = physical_registry.join("src/index/widget-1.0.0/src/lib.rs");

    let mappings = PathMapping::ordered(&path_mappings_with_env(
        directory.path(),
        None,
        None,
        |name| match name {
            "CARGO_HOME" => Some(cargo_home.as_os_str().to_owned()),
            _ => None,
        },
    ));

    assert_eq!(
        normalize_mapped_path(&source, directory.path(), &mappings).unwrap(),
        "${cargo_registry}/src/index/widget-1.0.0/src/lib.rs"
    );
}

#[test]
fn standalone_target_mapping_covers_the_profile_tree() {
    assert_eq!(
        standalone_target_root(Path::new("/tmp/target/debug/deps"), None),
        Path::new("/tmp/target")
    );
    assert_eq!(
        standalone_target_root(
            Path::new("/tmp/target/x86_64-unknown-linux-gnu/release/deps"),
            Some("x86_64-unknown-linux-gnu"),
        ),
        Path::new("/tmp/target")
    );
    assert_eq!(
        standalone_target_root(
            Path::new("/tmp/target/custom/release/deps"),
            Some("/tmp/targets/custom.json"),
        ),
        Path::new("/tmp/target")
    );
    // Cargo 1.100 gives every unit its own directory below `build/`.
    assert_eq!(
        standalone_target_root(
            Path::new("/tmp/target/debug/build/widget/0123456789abcdef/out"),
            None,
        ),
        Path::new("/tmp/target")
    );
    assert_eq!(
        standalone_target_root(
            Path::new(
                "/tmp/target/x86_64-unknown-linux-gnu/debug/build/widget/0123456789abcdef/out"
            ),
            Some("x86_64-unknown-linux-gnu"),
        ),
        Path::new("/tmp/target")
    );
    // A pre-1.100 build script's OUT_DIR is not a unit output directory.
    assert_eq!(
        standalone_target_root(
            Path::new("/tmp/target/debug/build/widget-0123456789abcdef/out"),
            None,
        ),
        Path::new("/tmp/target/debug/build/widget-0123456789abcdef/out")
    );
}

#[test]
fn validates_exact_rustc_output_set() {
    let root = tempfile::tempdir().unwrap();
    let outputs = test_outputs(root.path());
    let files =
        validated_outputs(test_output_directory(test_file("libdemo.rlib")), &outputs).unwrap();

    assert_eq!(files.len(), 2);
    assert!(files.iter().any(|(_, path)| path == &outputs.files[0]));
    assert!(files.iter().any(|(_, path)| path == &outputs.dep_info));
}

#[test]
fn rejects_cached_output_path_traversal() {
    let root = tempfile::tempdir().unwrap();
    let outputs = test_outputs(root.path());
    assert!(
        validated_outputs(
            test_output_directory(test_file("../libdemo.rlib")),
            &outputs,
        )
        .is_err()
    );
}

#[test]
fn rejects_executable_rustc_outputs() {
    let root = tempfile::tempdir().unwrap();
    let outputs = test_outputs(root.path());
    let mut file = test_file("libdemo.rlib");
    file.executable = true;
    assert!(validated_outputs(test_output_directory(file), &outputs).is_err());
}

#[test]
fn accepts_wasm_executable_rustc_outputs() {
    let root = tempfile::tempdir().unwrap();
    let mut outputs = test_outputs(root.path());
    outputs.files = vec![outputs.directory.join("demo.wasm")];
    let mut file = test_file("demo.wasm");
    file.executable = true;

    assert!(validated_outputs(test_output_directory(file), &outputs).is_ok());
}

/// A native program has no extension to recognize it by, so the contract has to
/// be what the invocation declared rather than what the name looks like.
#[test]
fn accepts_native_executable_rustc_outputs() {
    let root = tempfile::tempdir().unwrap();
    let mut outputs = test_outputs(root.path());
    outputs.files = vec![outputs.directory.join("demo-abc123")];
    let mut file = test_file("demo-abc123");
    file.executable = true;

    assert!(validated_outputs(test_output_directory(file), &outputs).is_ok());

    // A library artifact under the same roof is still not a program.
    outputs.files = vec![outputs.directory.join("libdemo.rlib")];
    let mut library = test_file("libdemo.rlib");
    library.executable = true;
    assert!(validated_outputs(test_output_directory(library), &outputs).is_err());
}

#[cfg(unix)]
#[test]
fn restores_declared_executable_permissions() {
    use std::os::unix::fs::PermissionsExt as _;

    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source");
    std::fs::write(&source, b"wasm").unwrap();
    let node = CacheFileNode {
        digest: CacheDigest::blake3(b"wasm"),
        executable: true,
        mode: 0o644,
        name: "fixture.wasm".into(),
    };

    // Asked of the cloning path specifically: a restore that has to hard link
    // cannot give one destination a mode of its own, and keeps the object's
    // read-only one instead. That case is covered beside the link itself.
    let (staged, _) =
        stage_verified_cached_output_with(root.path(), 0, &source, &node, |source, destination| {
            std::fs::copy(source, destination).map(|_| ())
        })
        .unwrap();
    assert_eq!(
        std::fs::metadata(staged).unwrap().permissions().mode() & 0o777,
        0o755
    );
}

#[test]
fn rejects_group_or_world_writable_rustc_outputs() {
    let root = tempfile::tempdir().unwrap();
    let outputs = test_outputs(root.path());
    let mut file = test_file("libdemo.rlib");
    file.mode = 0o666;
    assert!(validated_outputs(test_output_directory(file), &outputs).is_err());
}

#[cfg(unix)]
#[test]
fn publication_masks_unsafe_rustc_output_permissions() {
    use std::os::unix::fs::PermissionsExt as _;

    let file = tempfile::NamedTempFile::new().unwrap();
    file.as_file()
        .set_permissions(std::fs::Permissions::from_mode(0o666))
        .unwrap();
    assert_eq!(file_mode(&file.as_file().metadata().unwrap()), 0o644);
}

#[test]
fn rolls_back_outputs_after_a_partial_persist() {
    let root = tempfile::tempdir().unwrap();
    let first_destination = root.path().join("first.rlib");
    let blocked_destination = root.path().join("blocked.rmeta");
    std::fs::create_dir(&blocked_destination).unwrap();
    let staged = staged_outputs(
        root.path(),
        vec![
            (b"first", first_destination.clone()),
            (b"second", blocked_destination.clone()),
        ],
    );

    assert!(persist_outputs(staged).is_err());
    assert!(!first_destination.exists());
    assert!(blocked_destination.is_dir());
}

#[test]
fn qualification_does_not_publish_cached_outputs() {
    let root = tempfile::tempdir().unwrap();
    let destination = root.path().join("cached.rlib");
    let staged = staged_outputs(root.path(), vec![(b"cached", destination.clone())]);

    finalize_restored_outputs(staged, false).unwrap();

    assert!(!destination.exists());
}

/// Nothing a build does to a restored output can reach the object the cache
/// kept, whichever way the output got there. A clone and a copy are private
/// files that happen to have started as the object; a hard link is the object,
/// and is read-only precisely so that the write is refused instead.
#[test]
fn a_cloned_output_is_a_private_file_the_build_may_rewrite() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("cas-blob");
    std::fs::write(&source, b"artifact").unwrap();
    let staging = tempfile::tempdir_in(root.path()).unwrap();
    let node = test_file("artifact.rlib");

    let (output, _) = stage_verified_cached_output_with(
        staging.path(),
        0,
        &source,
        &node,
        |source, destination| std::fs::copy(source, destination).map(|_| ()),
    )
    .unwrap();
    std::fs::write(&output, b"modified").unwrap();

    assert_eq!(std::fs::read(source).unwrap(), b"artifact");
    assert_eq!(std::fs::read(output).unwrap(), b"modified");
}

#[cfg(unix)]
#[test]
fn a_linked_output_refuses_the_write_rather_than_sharing_it() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("cas-blob");
    std::fs::write(&source, b"artifact").unwrap();
    let staging = tempfile::tempdir_in(root.path()).unwrap();
    let node = test_file("artifact.rlib");

    let (output, materialization) =
        stage_verified_cached_output_with(staging.path(), 0, &source, &node, |_, _| {
            Err(std::io::ErrorKind::Unsupported.into())
        })
        .unwrap();

    assert_eq!(
        materialization,
        crate::materialize::Materialization::Hardlink
    );
    if write_permission_is_enforced(root.path()) {
        assert_eq!(
            std::fs::write(&output, b"modified").unwrap_err().kind(),
            std::io::ErrorKind::PermissionDenied
        );
    }
    assert_eq!(std::fs::read(source).unwrap(), b"artifact");
    assert_eq!(std::fs::read(output).unwrap(), b"artifact");
}

/// Whether a read-only file actually refuses a write here.
///
/// Asked by doing one rather than by checking who is running: root ignores the
/// mode bits, and a suite run in a container as root would otherwise fail on
/// the one protection it cannot observe. What the read-only mode is *for* is
/// still asserted above wherever it is enforced.
#[cfg(unix)]
fn write_permission_is_enforced(directory: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt as _;
    let probe = directory.join("write-permission-probe");
    if std::fs::write(&probe, b"probe").is_err() {
        return false;
    }
    if std::fs::set_permissions(&probe, std::fs::Permissions::from_mode(0o444)).is_err() {
        return false;
    }
    let refused = std::fs::write(&probe, b"again").is_err();
    let _ = std::fs::remove_file(&probe);
    refused
}

/// Direct and build-script input mutations invalidate compiler results, while
/// cache-service failures leave the successful local outputs usable.
#[test]
fn only_compiler_input_mutations_invalidate_local_outputs() {
    let path = PathBuf::from("src/lib.rs");
    let identity = FileIdentity {
        path: path.clone(),
        len: 6,
        modified: SystemTime::UNIX_EPOCH,
        changed: Some((1, 2)),
        object: None,
    };
    let snapshot = FileSnapshot::from(identity);
    let snapshots = Ok(BTreeMap::from([(path.clone(), snapshot)]));
    let changed =
        eyre::Report::new(BypassReason::InputChanged(path.clone())).wrap_err("publication failed");
    let overlapping = eyre::Report::new(BypassReason::InputModifiedDuringCompilation(path));

    assert!(compiler_input_was_modified(&changed, &snapshots));
    assert!(compiler_input_was_modified(
        &eyre::Report::new(BypassReason::BuildScriptInputsChanged(
            "target/debug/build/fixture/output".into()
        )),
        &snapshots
    ));
    assert!(compiler_input_was_modified(&overlapping, &snapshots));
    assert!(!compiler_input_was_modified(
        &eyre::eyre!("the cache is unavailable"),
        &snapshots
    ));
}

#[test]
fn timestamp_only_input_overlap_does_not_invalidate_local_outputs() {
    let overlapping = eyre::Report::new(BypassReason::InputModifiedDuringCompilation(
        "src/module.rs".into(),
    ));

    assert!(!compiler_input_was_modified(
        &overlapping,
        &Ok(BTreeMap::new())
    ));
}

#[test]
fn discards_every_modeled_compiler_output() {
    let directory = tempfile::tempdir().unwrap();
    let metadata = directory.path().join("libfixture.rmeta");
    let library = directory.path().join("libfixture.rlib");
    let dep_info = directory.path().join("fixture.d");
    for path in [&metadata, &library, &dep_info] {
        std::fs::write(path, b"output").unwrap();
    }
    let outputs = RustcOutputs {
        directory: directory.path().to_path_buf(),
        files: vec![metadata.clone(), library.clone()],
        dep_info: dep_info.clone(),
    };

    discard_compiler_outputs(&outputs).unwrap();

    assert!(!metadata.exists());
    assert!(!library.exists());
    assert!(!dep_info.exists());
    discard_compiler_outputs(&outputs).unwrap();
}

#[test]
fn rejects_cached_outputs_with_the_wrong_size() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("cas-blob");
    std::fs::write(&source, b"short").unwrap();
    let staging = tempfile::tempdir_in(root.path()).unwrap();
    let node = test_file("artifact.rlib");

    assert!(stage_verified_cached_output(staging.path(), 0, &source, &node).is_err());
}

#[test]
fn materializes_read_only_cached_outputs() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("cas-blob");
    std::fs::write(&source, b"artifact").unwrap();
    let mut permissions = std::fs::metadata(&source).unwrap().permissions();
    permissions.set_readonly(true);
    std::fs::set_permissions(&source, permissions).unwrap();
    let staging = tempfile::tempdir_in(root.path()).unwrap();
    let node = test_file("artifact.rlib");

    let (output, _) = stage_verified_cached_output(staging.path(), 0, &source, &node).unwrap();

    assert_eq!(std::fs::read(output).unwrap(), b"artifact");
    assert!(std::fs::metadata(&source).unwrap().permissions().readonly());
    make_owner_writable(&source).unwrap();
}

#[test]
fn rejects_same_size_corrupt_cached_metadata() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("cas-blob");
    std::fs::write(&source, b"corrupt!").unwrap();
    let digest = CacheDigest::blake3(b"artifact");

    assert!(read_verified_blob(&source, &digest, "test blob").is_err());
}

#[test]
#[ignore = "local materialization benchmark"]
fn benchmark_cached_output_materialization() {
    let size_mib = std::env::var("TUIST_CARGO_CACHE_BENCH_MIB")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(128);
    let iterations = std::env::var("TUIST_CARGO_CACHE_BENCH_ITERATIONS")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(4);
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("cas-blob");
    let mut source_file = std::fs::File::create(&source).unwrap();
    let chunk = vec![0x5a; 1024 * 1024];
    for _ in 0..size_mib {
        source_file.write_all(&chunk).unwrap();
    }
    source_file.sync_all().unwrap();
    drop(source_file);
    let digest = CacheDigest::blake3_file(&source).unwrap();
    let node = CacheFileNode {
        digest: digest.clone(),
        executable: false,
        mode: if cfg!(unix) { 0o644 } else { 0 },
        name: "artifact.rlib".into(),
    };

    let staging = tempfile::tempdir_in(root.path()).unwrap();
    let started = std::time::Instant::now();
    for _ in 0..iterations {
        let temporary = staging.path().join("legacy-output");
        reflink_copy::reflink_or_copy(&source, &temporary).unwrap();
        let temporary = tempfile::TempPath::try_from_path(temporary).unwrap();
        make_owner_writable(&temporary).unwrap();
        assert!(digest.matches_file(&temporary).unwrap());
        apply_file_mode(&temporary, node.mode, node.executable).unwrap();
    }
    let legacy = started.elapsed();

    let staging = tempfile::tempdir_in(root.path()).unwrap();
    let started = std::time::Instant::now();
    let mut method = None;
    for _ in 0..iterations {
        let (_, observed) =
            stage_verified_cached_output(staging.path(), 0, &source, &node).unwrap();
        method = Some(observed);
    }
    let materialized = started.elapsed();

    println!(
        "materialized {iterations} x {size_mib} MiB with {method:?}: legacy_reverify={legacy:.2?}, verified_cas={materialized:.2?}, speedup={:.2}x",
        legacy.as_secs_f64() / materialized.as_secs_f64()
    );
}

/// The dep-info writes a path literally; stderr is JSON, where a Windows
/// separator arrives doubled. Both spellings have to round-trip, or every
/// artifact notification on Windows keeps the publishing checkout's path.
#[test]
fn both_spellings_of_a_root_round_trip_through_a_placeholder() {
    let mappings = vec![PathMapping::new(
        if cfg!(windows) {
            r"D:\work\target"
        } else {
            "/work/target"
        },
        "target",
    )];
    let root = mappings[0].root.to_str().unwrap().to_string();
    let escaped = root.replace('\\', r"\\");

    // A dep-info rule and a JSON artifact notification, as rustc writes them.
    let original = format!("{root}/deps/lib.rlib: src/lib.rs\n{{\"artifact\":\"{escaped}\"}}\n");
    let normalized = normalize_output_text(original.as_bytes(), &mappings);

    assert!(
        !String::from_utf8_lossy(&normalized).contains(&root),
        "the literal root survived normalization: {}",
        String::from_utf8_lossy(&normalized)
    );
    if escaped != root {
        assert!(
            !String::from_utf8_lossy(&normalized).contains(&escaped),
            "the escaped root survived normalization: {}",
            String::from_utf8_lossy(&normalized)
        );
    }
    assert_eq!(
        denormalize_output_text(&normalized, &mappings),
        original.as_bytes(),
        "a normalized output did not come back as it went in"
    );
}

/// A restore happens on a machine whose roots differ from the one that
/// published, which is the whole point of the placeholder.
#[test]
fn a_placeholder_is_rewritten_into_the_restoring_checkouts_root() {
    let published = vec![PathMapping::new(
        if cfg!(windows) {
            r"D:\one\target"
        } else {
            "/one/target"
        },
        "target",
    )];
    let restoring = vec![PathMapping::new(
        if cfg!(windows) {
            r"D:\two\target"
        } else {
            "/two/target"
        },
        "target",
    )];
    let published_root = published[0].root.to_str().unwrap();
    let restoring_root = restoring[0].root.to_str().unwrap();

    let original = format!("{published_root}/deps/lib.rlib: src/lib.rs\n");
    let stored = normalize_output_text(original.as_bytes(), &published);
    let restored = denormalize_output_text(&stored, &restoring);

    let restored = String::from_utf8_lossy(&restored).into_owned();
    assert!(
        restored.contains(restoring_root),
        "restore should name the restoring root: {restored}"
    );
    assert!(
        !restored.contains(published_root),
        "restore still names the publishing root: {restored}"
    );
}

/// rustc writes a path with the platform separator in some places and forward
/// slashes in others, which is why `carries` searches both, and stderr is JSON
/// where a Windows separator arrives doubled. A spelling missed here is a path
/// from the publishing checkout left in place.
///
/// The root is spelled the Windows way whatever this platform is, because a
/// unix root has only one spelling and the test would prove nothing there.
#[test]
fn every_spelling_of_a_root_is_normalized() {
    let mappings = vec![PathMapping::new(r"D:\work\target", "target")];
    let root = r"D:\work\target";
    let spellings = [
        root.to_string(),
        root.replace('\\', r"\\"),
        root.replace('\\', "/"),
    ];
    assert_eq!(
        spellings
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        3,
        "the fixture should exercise three distinct spellings"
    );

    for spelling in &spellings {
        let original = format!("{spelling}/deps/lib.rlib: src/lib.rs\n");
        let normalized = normalize_output_text(original.as_bytes(), &mappings);
        assert!(
            !String::from_utf8_lossy(&normalized).contains(spelling.as_str()),
            "{spelling} survived normalization: {}",
            String::from_utf8_lossy(&normalized)
        );
        assert_eq!(
            denormalize_output_text(&normalized, &mappings),
            original.as_bytes(),
            "{spelling} did not come back as it went in"
        );
    }
}

/// A root is a directory, not a text prefix. `/work/target` has nothing to do
/// with `/work/target-backup`, and rewriting the second would hand a restore a
/// directory that never existed.
#[test]
fn a_sibling_sharing_a_prefix_is_left_alone() {
    let mappings = vec![PathMapping::new(
        if cfg!(windows) {
            r"D:\work\target"
        } else {
            "/work/target"
        },
        "target",
    )];
    let root = mappings[0].root.to_str().unwrap().to_string();
    let separator = if cfg!(windows) { '\\' } else { '/' };
    let sibling = format!("{root}-backup{separator}keep.rlib");
    let inside = format!("{root}{separator}deps{separator}lib.rlib");

    let original = format!("{sibling}\n{inside}\n");
    let normalized = normalize_output_text(original.as_bytes(), &mappings);
    let normalized = String::from_utf8_lossy(&normalized).into_owned();

    assert!(
        normalized.contains(&sibling),
        "the sibling directory was rewritten: {normalized}"
    );
    assert!(
        !normalized.contains(&inside),
        "the root itself was not rewritten: {normalized}"
    );
}

/// A root arrives however its environment variable was written, and a
/// trailing separator must not stop the rewrite: the byte after the match
/// would then be a child's first letter rather than the separator before it.
#[test]
fn a_root_written_with_a_trailing_separator_still_rewrites() {
    let plain = vec![PathMapping::new("/work/target", "target")];
    let trailing = vec![PathMapping::new("/work/target/", "target")];
    let original = "/work/target/deps/lib.rlib: src/lib.rs\n";

    let from_trailing = normalize_output_text(original.as_bytes(), &trailing);
    assert!(
        !String::from_utf8_lossy(&from_trailing).contains("/work/target/deps"),
        "a trailing separator left the path unrewritten: {}",
        String::from_utf8_lossy(&from_trailing)
    );
    assert_eq!(
        from_trailing,
        normalize_output_text(original.as_bytes(), &plain),
        "how the root was written should not change what is stored"
    );
    assert_eq!(
        denormalize_output_text(&from_trailing, &trailing),
        original.as_bytes()
    );
}

#[cfg(target_os = "macos")]
#[test]
fn the_shim_appends_an_oso_prefix_for_cached_links() {
    // Test the standalone fallback in a subprocess without racing other tests' environment.
    if std::env::var_os("TUIST_CARGO_CACHE_TEST_OSO_FALLBACK").is_none() {
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .arg("the_shim_appends_an_oso_prefix_for_cached_links")
            .env("TUIST_CARGO_CACHE_TEST_OSO_FALLBACK", "1")
            .env_remove(session::TARGET_DIR_ENV)
            .status()
            .unwrap();
        assert!(status.success());
        return;
    }
    let arguments = |values: &[&str]| values.iter().map(OsString::from).collect::<Vec<_>>();
    let base = arguments(&[
        "--crate-name=app",
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--out-dir",
        "/work/target/debug/deps",
        "src/main.rs",
    ]);
    let extended = with_oso_prefix(&base, true);
    assert_eq!(
        extended.last().unwrap(),
        &OsString::from("-Clink-arg=-Wl,-oso_prefix,/work/target/"),
    );
    let example = arguments(&["--out-dir=/work/target/debug/examples", "examples/app.rs"]);
    assert_eq!(with_oso_prefix(&example, true).last(), extended.last());
    let build_script = arguments(&[
        "--out-dir=/work/target/debug/build/package-hash",
        "build.rs",
    ]);
    assert_eq!(with_oso_prefix(&build_script, true).last(), extended.last());
    // Off when links are not cached, when the caller chose a prefix, and when
    // there is no output directory to cover.
    assert_eq!(with_oso_prefix(&base, false).len(), base.len());
    let mut chosen = base.clone();
    chosen.push("-Clink-arg=-Wl,-oso_prefix,/elsewhere/".into());
    assert_eq!(with_oso_prefix(&chosen, true).len(), chosen.len());
    let query = arguments(&["--print=cfg"]);
    assert_eq!(with_oso_prefix(&query, true).len(), query.len());
    // An explicit `--target` is never a host link, so nothing is appended:
    // handing a wasm link this flag would bypass it as unmodeled.
    let wasm = arguments(&[
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--target=wasm32-unknown-unknown",
        "--out-dir",
        "/work/target/wasm32-unknown-unknown/debug/deps",
        "src/main.rs",
    ]);
    assert_eq!(with_oso_prefix(&wasm, true).len(), wasm.len());
    let split_target = arguments(&[
        "--target",
        "wasm32-unknown-unknown",
        "--out-dir=/work/target/debug/deps",
        "src/main.rs",
    ]);
    assert_eq!(
        with_oso_prefix(&split_target, true).len(),
        split_target.len()
    );
    let relative = arguments(&["--out-dir", "target/debug/deps", "src/main.rs"]);
    assert_eq!(with_oso_prefix(&relative, true).len(), relative.len());
    let split = arguments(&["--out-dir=/work/target/debug/deps", "src/main.rs"]);
    assert_eq!(
        with_oso_prefix(&split, true).last().unwrap(),
        &OsString::from("-Clink-arg=-Wl,-oso_prefix,/work/target/"),
    );
}

fn in_place_node(bytes: &[u8], executable: bool) -> CacheFileNode {
    CacheFileNode {
        digest: CacheDigest::blake3(bytes),
        executable,
        mode: if executable { 0o755 } else { 0o644 },
        name: "libdep.rlib".into(),
    }
}

#[test]
fn an_output_holding_the_cached_bytes_is_already_in_place() {
    use tuist_cargo_cache_core::NoFileDigestCache;
    let directory = tempfile::tempdir().unwrap();
    let destination = directory.path().join("libdep.rlib");
    let bytes = b"cached artifact bytes";
    std::fs::write(&destination, bytes).unwrap();

    assert!(output_already_in_place(
        &in_place_node(bytes, false),
        &destination,
        &NoFileDigestCache,
    ));
    assert!(
        !output_already_in_place(
            &in_place_node(b"different artifact bytes!", false),
            &destination,
            &NoFileDigestCache,
        ),
        "content that hashes differently must be rewritten"
    );
    assert!(
        !output_already_in_place(
            &in_place_node(b"cached artifact byte", false),
            &destination,
            &NoFileDigestCache,
        ),
        "a length mismatch must refuse before reading"
    );
    assert!(
        !output_already_in_place(
            &in_place_node(bytes, false),
            &directory.path().join("absent.rlib"),
            &NoFileDigestCache,
        ),
        "a missing output must be materialized"
    );
    #[cfg(unix)]
    assert!(
        !output_already_in_place(
            &in_place_node(bytes, true),
            &destination,
            &NoFileDigestCache
        ),
        "an executable node must not keep a non-executable file"
    );
}

#[test]
fn a_ledger_answer_decides_in_place_without_reading() {
    use tuist_cargo_cache_core::{
        FileDigestCache, FileDigestScope, FileIdentity, RecordedFileDigest,
    };

    /// Vouches one digest for every identity it is asked about.
    struct FixedLedger(CacheDigest);
    impl FileDigestCache for FixedLedger {
        fn find(
            &self,
            _scope: FileDigestScope,
            files: &[FileIdentity],
        ) -> Vec<Option<CacheDigest>> {
            vec![Some(self.0.clone()); files.len()]
        }
        fn record(&self, _scope: FileDigestScope, _entries: Vec<RecordedFileDigest>) {}
    }

    let directory = tempfile::tempdir().unwrap();
    let destination = directory.path().join("libdep.rlib");
    let bytes = b"cached artifact bytes";
    std::fs::write(&destination, bytes).unwrap();
    let node = in_place_node(bytes, false);

    assert!(output_already_in_place(
        &node,
        &destination,
        &FixedLedger(node.digest.clone()),
    ));
    // A ledger that names other bytes of the same length refuses the keep
    // without falling back to a read that would say otherwise: the recorded
    // identity is the fresher claim about what is on disk.
    let mut other = CacheDigest::blake3(b"other bytes entirely here");
    other.size = node.digest.size;
    assert!(!output_already_in_place(
        &node,
        &destination,
        &FixedLedger(other),
    ));
}

/// The budget is a backstop, so it removes state only once the state has
/// actually passed it. A budget lower than what one compilation leaves behind
/// would discard the state before every compile, and the edit loop would be a
/// full recompilation labelled incremental.
#[test]
fn incremental_state_is_discarded_only_past_its_budget() {
    let root = tempfile::tempdir().unwrap();
    let directory = root.path().join("unit");
    let session = directory.join("s-session");
    std::fs::create_dir_all(&session).unwrap();
    std::fs::write(session.join("dep-graph.bin"), vec![0_u8; 4096]).unwrap();

    // Inside the budget, and without one, the state stays where it is.
    assert_eq!(
        prepare_incremental_directory(&directory, Some(1 << 20)).unwrap(),
        None
    );
    assert!(session.join("dep-graph.bin").is_file());
    assert_eq!(
        prepare_incremental_directory(&directory, None).unwrap(),
        None
    );
    assert!(session.join("dep-graph.bin").is_file());

    // Past it, the state goes and the caller is told how much went, with the
    // directory left ready for the compilation that follows.
    assert_eq!(
        prepare_incremental_directory(&directory, Some(1024)).unwrap(),
        Some(4096)
    );
    assert!(directory.is_dir());
    assert!(!session.exists());

    // A directory that does not exist yet is simply created.
    let fresh = root.path().join("fresh");
    assert_eq!(
        prepare_incremental_directory(&fresh, Some(1)).unwrap(),
        None
    );
    assert!(fresh.is_dir());
}

/// A bare `--target` is a custom specification when rustc would find a file
/// for it: in the sysroot given by `--sysroot`, in the one implied by the
/// compiler's location, but not for a name with no such file. A path target
/// is the parser's case and never reported here.
#[test]
fn custom_target_resolution_follows_the_sysroot() {
    let directory = tempfile::tempdir().unwrap();
    let sysroot = directory.path().join("toolchain");
    std::fs::create_dir_all(sysroot.join("bin")).unwrap();
    std::fs::create_dir_all(sysroot.join("lib/rustlib/my-custom-target")).unwrap();
    std::fs::write(
        sysroot.join("lib/rustlib/my-custom-target/target.json"),
        "{}",
    )
    .unwrap();
    let rustc: OsString = sysroot.join("bin/rustc").into();
    let args = |list: &[&str]| -> Vec<OsString> { list.iter().map(OsString::from).collect() };

    assert!(custom_target_may_resolve(
        &rustc,
        &args(&["--target=my-custom-target", "src.rs"])
    ));
    assert!(custom_target_may_resolve(
        &rustc,
        &args(&["--target", "my-custom-target", "src.rs"])
    ));
    assert!(!custom_target_may_resolve(
        &rustc,
        &args(&["--target=x86_64-unknown-linux-gnu", "src.rs"])
    ));
    assert!(!custom_target_may_resolve(&rustc, &args(&["src.rs"])));
    assert!(!custom_target_may_resolve(
        &rustc,
        &args(&["--target=/somewhere/custom.json", "src.rs"])
    ));

    // A non-UTF-8 argument earlier in the line does not hide the target.
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt as _;
        let odd = OsString::from_vec(vec![b'-', b'-', b'c', b'f', b'g', b'=', 0xff]);
        assert!(custom_target_may_resolve(
            &rustc,
            &[odd, "--target=my-custom-target".into(), "src.rs".into()]
        ));
    }

    // The target may arrive through a response file; the shim scans the
    // expanded line, as the parser does.
    let argfile = directory.path().join("rustc.args");
    std::fs::write(&argfile, "--target=my-custom-target\n").unwrap();
    let expanded =
        RustcInvocation::expand_arguments(&args(&[&format!("@{}", argfile.display()), "src.rs"]))
            .unwrap();
    assert!(custom_target_may_resolve(&rustc, &expanded));

    // A compiler outside a toolchain directory, such as a rustup proxy, does
    // not imply a sysroot, and this one cannot be asked either. With nowhere
    // to look, the name is not proven built in.
    let elsewhere: OsString = directory.path().join("other/bin/rustc").into();
    assert!(custom_target_may_resolve(
        &elsewhere,
        &args(&["--target=my-custom-target", "src.rs"])
    ));
    // A built-in name with no spec file under an explicit sysroot is built in.
    let empty_sysroot = format!("--sysroot={}", directory.path().join("other").display());
    assert!(!custom_target_may_resolve(
        &elsewhere,
        &args(&["--target=my-custom-target", &empty_sysroot, "src.rs"])
    ));
    let sysroot_flag = format!("--sysroot={}", sysroot.display());
    assert!(custom_target_may_resolve(
        &elsewhere,
        &args(&["--target=my-custom-target", &sysroot_flag, "src.rs"])
    ));
}

#[test]
fn a_stable_out_dir_is_mapped_by_name_beneath_its_root() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("cache/out-dirs/v1");
    let out_dir = root.join("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
    let workspace = directory.path().join("src/project");
    let mappings = path_mappings_with_env(&workspace, None, None, |name| match name {
        "OUT_DIR" => Some(out_dir.as_os_str().to_owned()),
        crate::out_dir::ROOT_ENV => Some(root.as_os_str().to_owned()),
        _ => None,
    });

    assert!(
        mappings
            .iter()
            .any(|mapping| mapping.placeholder == "out_dir" && mapping.root == out_dir),
        "{mappings:?}"
    );

    // Cargo's own OUT_DIR, under the target directory, is not a root of its
    // own: it normalizes under `${target}` as it always did.
    let checkout_out_dir = workspace.join("target/debug/build/x/out");
    let mappings = path_mappings_with_env(&workspace, None, None, |name| match name {
        "OUT_DIR" => Some(checkout_out_dir.as_os_str().to_owned()),
        crate::out_dir::ROOT_ENV => Some(root.as_os_str().to_owned()),
        _ => None,
    });
    assert!(
        !mappings
            .iter()
            .any(|mapping| mapping.placeholder == "out_dir")
    );
}

#[test]
fn external_native_mappings_preserve_installation_identity() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    let native = directory.path().join("openssl/lib");
    let invocation = RustcInvocation::parse(&[
        "--crate-type=lib".into(),
        "--emit=metadata,link".into(),
        format!("-Lnative={}", native.display()).into(),
        format!("-Lnative={}", native.display()).into(),
        "src.rs".into(),
    ])
    .unwrap();
    let mut portable = Portable {
        mappings: vec![PathMapping::new(&workspace, "workspace")],
        arguments: vec![],
        build_script_inputs: None,
    };
    portable.map_external_native_paths(&invocation, &workspace);
    assert_eq!(portable.mappings.len(), 2);
    let mapped =
        normalize_mapped_path(&native.join("libssl.a"), &workspace, &portable.mappings).unwrap();
    assert!(mapped.starts_with("${native_"));
    assert!(mapped.ends_with("/libssl.a"));
    assert!(
        portable.arguments.is_empty(),
        "external paths are not remapped in compiler output"
    );
    let other = directory.path().join("other/lib");
    let invocation = RustcInvocation::parse(&[
        "--crate-type=lib".into(),
        "--emit=metadata,link".into(),
        format!("-Lnative={}", other.display()).into(),
        "src.rs".into(),
    ])
    .unwrap();
    portable.map_external_native_paths(&invocation, &workspace);
    assert_ne!(
        mapped,
        normalize_mapped_path(&other.join("libssl.a"), &workspace, &portable.mappings).unwrap()
    );
}

#[test]
fn relative_external_native_paths_are_mapped_from_the_working_directory() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    let native = directory.path().join("external/lib");
    std::fs::create_dir_all(&workspace).unwrap();
    std::fs::create_dir_all(&native).unwrap();
    let invocation = RustcInvocation::parse(&[
        "--crate-type=lib".into(),
        "--emit=metadata,link".into(),
        "-Lnative=../external/lib".into(),
        "src.rs".into(),
    ])
    .unwrap();
    let mut portable = Portable {
        mappings: vec![PathMapping::new(&workspace, "workspace")],
        arguments: vec![],
        build_script_inputs: None,
    };
    portable.map_external_native_paths(&invocation, &workspace);
    assert_eq!(portable.mappings.len(), 2);
    let mapped =
        normalize_mapped_path(&native.join("libssl.a"), &workspace, &portable.mappings).unwrap();
    assert!(mapped.starts_with("${native_"));
    assert!(mapped.ends_with("/libssl.a"));
    assert_eq!(
        mapped,
        normalize_mapped_path(
            Path::new("../external/lib/libssl.a"),
            &workspace,
            &portable.mappings,
        )
        .unwrap()
    );
    assert!(portable.arguments.is_empty());
    let absolute_invocation = RustcInvocation::parse(&[
        "--crate-type=lib".into(),
        "--emit=metadata,link".into(),
        format!("-Lnative={}", native.display()).into(),
        "src.rs".into(),
    ])
    .unwrap();
    let mut absolute_portable = Portable {
        mappings: vec![PathMapping::new(&workspace, "workspace")],
        arguments: vec![],
        build_script_inputs: None,
    };
    absolute_portable.map_external_native_paths(&absolute_invocation, &workspace);
    assert_eq!(
        mapped,
        normalize_mapped_path(
            &native.join("libssl.a"),
            &workspace,
            &absolute_portable.mappings
        )
        .unwrap()
    );
}
