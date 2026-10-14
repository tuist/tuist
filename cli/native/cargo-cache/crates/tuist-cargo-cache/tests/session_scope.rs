use std::path::Path;
use std::process::Command;

mod support;

fn project(path: &Path, source: &str) {
    std::fs::create_dir_all(path.join("src")).unwrap();
    std::fs::write(
        path.join("Cargo.toml"),
        "[package]\nname='scope-fixture'\nversion='0.0.0'\nedition='2021'\n",
    )
    .unwrap();
    std::fs::write(path.join("src/main.rs"), source).unwrap();
}

fn tuist_cargo_cache(root: &Path) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_tuist-cargo-cache-model"));
    command.env_clear();
    // rustc's MSVC discovery needs the Visual Studio/SDK environment as well
    // as PATH. Without it Git's unrelated link.exe can win resolution.
    #[cfg(windows)]
    for (name, value) in std::env::vars_os() {
        let key = name.to_string_lossy().to_ascii_uppercase();
        if !key.starts_with("TUIST_CARGO_CACHE_")
            && !matches!(
                key.as_str(),
                "RUSTC_WRAPPER"
                    | "RUSTC_WORKSPACE_WRAPPER"
                    | "RUSTDOC"
                    | "CARGO_TARGET_DIR"
                    | "CARGO_INCREMENTAL"
                    | "CARGO"
            )
        {
            command.env(name, value);
        }
    }
    for name in [
        "PATH",
        "HOME",
        "RUSTUP_HOME",
        "CARGO_HOME",
        "RUSTUP_TOOLCHAIN",
        "SystemRoot",
        "TEMP",
        "TMP",
        "TMPDIR",
    ] {
        if let Some(value) = std::env::var_os(name) {
            let key = if cfg!(windows) && name == "PATH" {
                "Path"
            } else {
                name
            };
            command.env(key, value);
        }
    }
    support::isolate_host(&mut command);
    command
        .current_dir(root)
        .env("TUIST_CARGO_CACHE_DIR", root.join("cache"))
        .env("TUIST_CARGO_CACHE_LINKER", "system")
        .env("CI", "1")
        .env("TUIST_CARGO_CACHE_SUMMARY", "off");
    command
}

/// Separate fixtures keep a successful direct build from masking a nested
/// build that writes its output into the parent's target directory.
#[test]
fn nested_test_builds_match_plain_cargo_target_directories() {
    for setting in [
        None,
        Some("relative-target"),
        Some("absolute"),
        Some("flag"),
    ] {
        for managed in [false, true] {
            let root = tempfile::tempdir().unwrap();
            let root_path = root.path().canonicalize().unwrap();
            project(
                &root_path,
                r#"
fn main() {}
#[test]
fn nested_build() {
    use std::{path::PathBuf, process::Command};
    let guest = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("guest");
    let target = std::env::var_os("CARGO_TARGET_DIR");
    let expected = std::env::var_os("EXPECTED_CALLER_TARGET");
    let expected_dir = expected.clone().map(PathBuf::from).unwrap_or_else(|| PathBuf::from("target"));
    let artifact = guest.join(expected_dir).join("debug/libnested_guest.rlib");
    // Force the child to produce the artifact even on a warm parent build.
    if artifact.exists() { std::fs::remove_file(&artifact).unwrap(); }
    for cargo in [std::ffi::OsString::from("cargo"), std::env::var_os("CARGO").unwrap()] {
        let output = Command::new(cargo).args(["build", "--offline", "--manifest-path"])
            .arg(guest.join("Cargo.toml")).current_dir(&guest).output().unwrap();
        assert!(output.status.success(), "{output:?}");
        assert!(artifact.is_file(), "missing {}: {output:?}", artifact.display());
        std::fs::remove_file(&artifact).unwrap();
    }
    assert_eq!(target, expected);
}
"#,
            );
            let guest = root_path.join("guest");
            std::fs::create_dir_all(guest.join("src")).unwrap();
            std::fs::write(
                guest.join("Cargo.toml"),
                "[package]\nname='nested-guest'\nversion='0.0.0'\nedition='2021'\n[workspace]\n",
            )
            .unwrap();
            std::fs::write(guest.join("src/lib.rs"), "pub fn guest() {}\n").unwrap();
            let caller_target = setting.filter(|value| *value != "flag").map(|value| {
                if value == "absolute" {
                    root_path.join("absolute-target")
                } else {
                    value.into()
                }
            });
            for pass in 0..3 {
                if pass == 2 {
                    let target = root_path.join(if setting == Some("flag") {
                        Path::new("flag-target")
                    } else {
                        caller_target.as_deref().unwrap_or(Path::new("target"))
                    });
                    // Wipe compiled outputs without leaving a dangling Windows
                    // junction at the managed target directory.
                    std::fs::remove_dir_all(target.join("debug")).unwrap();
                }
                let mut command = tuist_cargo_cache(&root_path);
                // The same shim/environment is used for both cases; disabling
                // tuist_cargo_cache gives Cargo ownership of the entire plain control build.
                command
                    .env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1")
                    .env("TUIST_CARGO_CACHE_DISABLE", if managed { "0" } else { "1" })
                    .env(
                        "TUIST_CARGO_CACHE_TARGET_ROOT",
                        root_path.join("managed-targets"),
                    )
                    .env(
                        "TUIST_CARGO_CACHE_STATS_REPORT",
                        root_path.join("stats.json"),
                    )
                    .args(["test", "--offline"]);
                if setting == Some("flag") {
                    command.args(["--target-dir", "flag-target"]);
                }
                command.args(["--", "--nocapture"]);
                if let Some(target) = &caller_target {
                    command
                        .env("CARGO_TARGET_DIR", target)
                        .env("EXPECTED_CALLER_TARGET", target);
                }
                let output = command.output().unwrap();
                assert!(
                    output.status.success(),
                    "managed={managed}, target={caller_target:?}, pass={pass}:\n{}\n{}",
                    String::from_utf8_lossy(&output.stdout),
                    String::from_utf8_lossy(&output.stderr)
                );
                if managed && pass == 2 {
                    let report: serde_json::Value = serde_json::from_slice(
                        &std::fs::read(root_path.join("stats.json")).unwrap(),
                    )
                    .unwrap();
                    assert!(report["hits"].as_u64().unwrap() > 0, "{report}");
                }
            }
        }
    }
}

/// Check fresh and warm builds report checkout-local executable paths, and
/// `cargo run` restores the caller's target setting before starting the program.
#[test]
fn build_artifact_paths_and_run_keep_caller_target_settings() {
    for explicit in [false, true] {
        let root = tempfile::Builder::new()
            .prefix("tuist_cargo_cache target ")
            .tempdir()
            .unwrap();
        // Match Cargo's workspace spelling: resolve /var on macOS, but avoid
        // introducing the verbatim \\?\ prefix Cargo omits on Windows.
        let root = if cfg!(windows) {
            root.path().to_path_buf()
        } else {
            root.path().canonicalize().unwrap()
        };
        project(
            &root,
            r#"
fn main() {
    assert_eq!(std::env::var_os("CARGO_TARGET_DIR"), std::env::var_os("EXPECTED_TARGET"));
    assert!(std::env::var_os("TUIST_CARGO_CACHE_SOCKET").is_none());
}
"#,
        );
        let target = if explicit { "caller target" } else { "target" };
        let command = || {
            let mut command = tuist_cargo_cache(&root);
            if explicit {
                command
                    .env("CARGO_TARGET_DIR", target)
                    .env("EXPECTED_TARGET", target);
            }
            command
        };
        for _ in 0..2 {
            let output = command()
                .args(["build", "--offline", "--message-format=json"])
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            let executable = String::from_utf8_lossy(&output.stdout)
                .lines()
                .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
                .find_map(|value| value["executable"].as_str().map(std::path::PathBuf::from))
                .unwrap();
            assert!(
                executable.starts_with(root.join(target)),
                "{}",
                executable.display()
            );
            assert!(executable.is_file());
            let output = command().args(["run", "--offline"]).output().unwrap();
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }
}

#[test]
fn cargo_run_restores_settings_before_starting_application() {
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        r#"
fn main() {
    for key in ["TUIST_CARGO_CACHE_SOCKET", "TUIST_CARGO_CACHE_BUILD", "TUIST_CARGO_CACHE_SESSION_RESTORE", "TUIST_CARGO_CACHE_SESSION_LEASE", "TUIST_CARGO_CACHE_LAUNCH_CAPTURE", "TUIST_CARGO_CACHE_WORKSPACE_ROOT", "TUIST_CARGO_CACHE_TARGET_DIR", "RUSTDOC", "RUSTC_WRAPPER", "CARGO_TARGET_DIR"] {
        assert!(std::env::var_os(key).is_none(), "{key} leaked");
    }
    assert_eq!(std::env::var("CARGO_INCREMENTAL").unwrap(), "1");
    assert_eq!(std::env::var("TUIST_CARGO_CACHE_VERIFY").unwrap(), "0");
    let path: Vec<_> = std::env::split_paths(&std::env::var_os("PATH").unwrap()).collect();
    let expected: Vec<_> = std::env::split_paths(&std::env::var_os("EXPECTED_PATH").unwrap()).collect();
    assert!(path.ends_with(&expected));
    assert!(!std::env::var("CARGO").unwrap().is_empty());
    assert_eq!(std::env::args().nth(1).unwrap(), "argument with spaces");
    println!("application started");
    std::process::exit(23);
}
"#,
    );
    let output = tuist_cargo_cache(root.path())
        .env("CARGO_INCREMENTAL", "1")
        .env("TUIST_CARGO_CACHE_VERIFY", "0")
        .env("EXPECTED_PATH", std::env::var_os("PATH").unwrap())
        .env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1")
        .env("RUSTFLAGS", "-C prefer-dynamic")
        .args([
            "--color",
            "never",
            "run",
            "--offline",
            "--",
            "argument with spaces",
        ])
        .output()
        .unwrap();
    assert_eq!(
        output.status.code(),
        Some(23),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("application started"));
}

#[cfg(unix)]
#[test]
fn cargo_run_preserves_configured_runner_and_wrapper() {
    use std::os::unix::fs::PermissionsExt;
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        r#"
fn main() {
    assert!(std::env::var_os("TUIST_CARGO_CACHE_SOCKET").is_none());
    assert!(std::env::var("RUSTC_WRAPPER").unwrap().ends_with("caller-wrapper"));
    assert_eq!(std::env::var("RUNNER_ARGUMENT").unwrap(), "runner arg");
}
"#,
    );
    let wrapper = root.path().join("caller-wrapper");
    std::fs::write(&wrapper, "#!/bin/sh\nexec \"$@\"\n").unwrap();
    std::fs::set_permissions(&wrapper, std::fs::Permissions::from_mode(0o755)).unwrap();
    let runner = root.path().join("caller-runner");
    std::fs::write(
        &runner,
        "#!/bin/sh\nexport RUNNER_ARGUMENT=\"$1\"\nshift\nexec \"$@\"\n",
    )
    .unwrap();
    std::fs::set_permissions(&runner, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::create_dir(root.path().join(".cargo")).unwrap();
    std::fs::write(
        root.path().join(".cargo/config.toml"),
        "[target.'cfg(unix)']\nrunner = ['./caller-runner', 'runner arg']\n",
    )
    .unwrap();
    let output = tuist_cargo_cache(root.path())
        .env("RUSTC_WRAPPER", wrapper)
        .args(["run", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(unix)]
#[test]
fn application_daemon_outlives_session_and_captures_an_independent_build() {
    let root = tempfile::tempdir().unwrap();
    let other = root.path().join("other");
    project(&other, "fn main() {}\n");
    project(
        root.path(),
        r#"
use std::process::{Command, Stdio};
fn main() {
    let args: Vec<_> = std::env::args().collect();
    if args.get(1).map(String::as_str) != Some("daemon") {
        assert!(std::os::unix::net::UnixStream::connect(env!("OUTER_SOCKET")).is_err(), "session still alive at application launch");
        Command::new(std::env::current_exe().unwrap()).arg("daemon").args(&args[1..])
            .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();
        return;
    }
    for _ in 0..200 {
        if std::path::Path::new(&args[4]).exists() { break; }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    assert!(std::path::Path::new(&args[4]).exists());
    assert!(std::env::var_os("TUIST_CARGO_CACHE_SOCKET").is_none());
    assert!(std::env::var_os("RUSTC_WRAPPER").is_none());
    let output = Command::new(&args[2]).args(["check", "--offline"])
        .current_dir(&args[3]).env("TUIST_CARGO_CACHE_LOG", "debug").output().unwrap();
    assert!(output.status.success(), "{:?}", output);
    assert!(!output.stderr.is_empty());
    std::fs::write(&args[5], "independent build captured").unwrap();
}
"#,
    );
    std::fs::write(root.path().join("build.rs"),
        "fn main() { println!(\"cargo:rustc-env=OUTER_SOCKET={}\", std::env::var(\"TUIST_CARGO_CACHE_SOCKET\").unwrap()); }\n").unwrap();
    let gate = root.path().join("launcher-exited");
    let result = root.path().join("daemon-result");
    let output = tuist_cargo_cache(root.path())
        .args([
            "run",
            "--offline",
            "--",
            env!("CARGO_BIN_EXE_tuist-cargo-cache-model"),
        ])
        .arg(&other)
        .arg(&gate)
        .arg(&result)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    std::fs::write(&gate, "go").unwrap();
    let mut contents = String::new();
    for _ in 0..200 {
        contents = std::fs::read_to_string(&result).unwrap_or_default();
        if contents == "independent build captured" {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    assert_eq!(contents, "independent build captured");
    assert!(!String::from_utf8_lossy(&output.stderr).contains("Checking scope-fixture"));
}

#[test]
fn stale_session_recovers_original_environment_before_building() {
    use std::ffi::OsString;
    let root = tempfile::tempdir().unwrap();
    project(root.path(), "fn main() {}\n");
    std::fs::write(
        root.path().join("build.rs"),
        r#"
fn main() {
    assert!(!std::env::var("TUIST_CARGO_CACHE_SOCKET").unwrap().contains("missing-session"));
    assert!(std::env::var("TUIST_CARGO_CACHE_WORKSPACE_ROOT").unwrap().contains(".tmp"));
}
"#,
    )
    .unwrap();
    let restore: Vec<(OsString, Option<OsString>)> = [
        "TUIST_CARGO_CACHE_SOCKET",
        "TUIST_CARGO_CACHE_SESSION_LEASE",
        "TUIST_CARGO_CACHE_SESSION_RESTORE",
        "RUSTC_WRAPPER",
        "TUIST_CARGO_CACHE_WORKSPACE_ROOT",
    ]
    .into_iter()
    .map(|key| (key.into(), None))
    .collect();
    let output = tuist_cargo_cache(root.path())
        .env("TUIST_CARGO_CACHE_SOCKET", "missing-session")
        .env(
            "TUIST_CARGO_CACHE_SESSION_LEASE",
            root.path().join("missing-owner"),
        )
        .env(
            "TUIST_CARGO_CACHE_SESSION_RESTORE",
            serde_json::to_string(&restore).unwrap(),
        )
        .env("RUSTC_WRAPPER", "missing-wrapper")
        .env("TUIST_CARGO_CACHE_WORKSPACE_ROOT", "wrong-workspace")
        .args(["check", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(unix)]
#[test]
fn command_line_runner_override_uses_original_environment() {
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        "fn main() { assert!(std::env::var_os(\"TUIST_CARGO_CACHE_SOCKET\").is_none()); }\n",
    );
    let output = tuist_cargo_cache(root.path())
        .args([
            "run",
            "--offline",
            "--config",
            "target.'cfg(unix)'.runner = ['env', 'CALLER_RUNNER=1']",
        ])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(unix)]
#[test]
fn nested_build_orchestrators_keep_the_live_session() {
    use std::os::unix::fs::PermissionsExt;
    for orchestrator in ["watch", "nextest"] {
        let root = tempfile::tempdir().unwrap();
        project(root.path(), "fn main() {}\n");
        std::fs::write(
            root.path().join("build.rs"),
            r#"
fn main() {
    assert_eq!(std::env::var("TUIST_CARGO_CACHE_SOCKET").unwrap(), std::env::var("EXPECTED_SOCKET").unwrap());
    assert_eq!(std::env::var("TUIST_CARGO_CACHE_BUILD").unwrap(), std::env::var("EXPECTED_BUILD").unwrap());
}
"#,
        )
        .unwrap();
        let program = root.path().join(format!("cargo-{orchestrator}"));
        std::fs::write(&program, "#!/bin/sh\nexport EXPECTED_SOCKET=\"$TUIST_CARGO_CACHE_SOCKET\" EXPECTED_BUILD=\"$TUIST_CARGO_CACHE_BUILD\"\nTUIST_CARGO_CACHE_CARGO_SHIM_MODE=1 exec \"$TEST_TUIST_CARGO_CACHE\" check --offline\n").unwrap();
        std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = std::env::join_paths(
            std::iter::once(root.path().to_path_buf())
                .chain(std::env::split_paths(&std::env::var_os("PATH").unwrap())),
        )
        .unwrap();
        let output = tuist_cargo_cache(root.path())
            .env("PATH", path)
            .env(
                "TEST_TUIST_CARGO_CACHE",
                env!("CARGO_BIN_EXE_tuist-cargo-cache-model"),
            )
            .arg(orchestrator)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{orchestrator}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[cfg(unix)]
#[test]
fn launch_preserves_non_unicode_environment_and_temporary_paths_with_spaces() {
    use std::os::unix::ffi::OsStringExt;
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        r#"
use std::os::unix::ffi::OsStrExt;
fn main() { assert_eq!(std::env::var_os("OPAQUE").unwrap().as_bytes(), b"\xff"); }
"#,
    );
    let temporary = tempfile::Builder::new()
        .prefix("tuist_cargo_cache space ")
        .tempdir_in("/tmp")
        .unwrap();
    let output = tuist_cargo_cache(root.path())
        .env("TMPDIR", temporary.path())
        .env("TUIST_CARGO_CACHE_CC", "0")
        .env("OPAQUE", std::ffi::OsString::from_vec(vec![255]))
        .args(["run", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(unix)]
#[test]
fn scheduled_test_binaries_hold_a_permit_and_keep_the_configured_runner() {
    use std::os::unix::fs::PermissionsExt;
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        r#"
fn main() {}
#[test]
fn scheduled() {
    // Long enough to be measured, and idle: the suite keeps one core busy
    // at most, which the next default-width run is weighed by.
    std::thread::sleep(std::time::Duration::from_millis(1100));
    assert_eq!(std::env::var("RUNNER_ARGUMENT").unwrap(), "runner arg");
    let leases = std::path::Path::new(&std::env::var_os("TUIST_CARGO_CACHE_DIR").unwrap())
        .join("scheduler/leases");
    let held: Vec<String> = std::fs::read_dir(&leases)
        .map(|entries| {
            entries
                .map(|entry| std::fs::read_to_string(entry.unwrap().path()).unwrap())
                .collect()
        })
        .unwrap_or_default();
    match std::env::var("EXPECTED_WEIGHT").ok() {
        Some(weight) => {
            assert_eq!(held.len(), 1, "only this test holds a permit: {held:?}");
            assert!(held[0].contains(&format!("\"weight\":{weight},")), "{held:?}");
            // Builds this test starts are charged to its permit, and find
            // the caller's runners rather than the shim.
            assert_eq!(std::env::var("TUIST_CARGO_CACHE_SCHEDULER").unwrap(), "0");
            assert_eq!(std::env::var("TUIST_CARGO_CACHE_SCHED_DIR").unwrap(), "");
            assert!(std::env::var_os("TUIST_CARGO_CACHE_TEST_RUNNERS").is_none());
            for (name, value) in std::env::vars() {
                assert!(!value.contains("tuist_cargo_cache-test-runner"), "{name}={value}");
            }
        }
        None => {
            assert!(held.is_empty(), "{held:?}");
            assert!(std::env::var_os("TUIST_CARGO_CACHE_SCHEDULER").is_none());
        }
    }
}
"#,
    );
    // The library's own, empty test binary finishes at once and is recorded
    // as one core, so it must not share the ledger name of the binary under
    // test.
    std::fs::write(
        root.path().join("Cargo.toml"),
        "[package]\nname='scope-fixture'\nversion='0.0.0'\nedition='2021'\n\n[lib]\nname='scope_lib'\n",
    )
    .unwrap();
    // Rustdoc runs doctests through the same runner; they hold no permit.
    std::fs::write(
        root.path().join("src/lib.rs"),
        r#"
/// ```
/// let leases = std::path::Path::new(&std::env::var_os("TUIST_CARGO_CACHE_DIR").unwrap())
///     .join("scheduler/leases");
/// let held = std::fs::read_dir(&leases).map(|entries| entries.count()).unwrap_or(0);
/// assert_eq!(held, 0, "a doctest holds no permit");
/// ```
pub fn documented() {}
"#,
    )
    .unwrap();
    let runner = root.path().join("caller-runner");
    std::fs::write(
        &runner,
        "#!/bin/sh\nexport RUNNER_ARGUMENT=\"$1\"\nshift\nexec \"$@\"\n",
    )
    .unwrap();
    std::fs::set_permissions(&runner, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::create_dir(root.path().join(".cargo")).unwrap();
    std::fs::write(
        root.path().join(".cargo/config.toml"),
        "[target.'cfg(unix)']\nrunner = ['./caller-runner', 'runner arg']\n",
    )
    .unwrap();
    for (tests, harness, expected) in [
        (Some("1"), &["--test-threads=3"][..], Some("3")),
        // Half of the 8 permits until this binary has been measured,
        (Some("1"), &[][..], Some("4")),
        (None, &[][..], None),
        // then the one core the idle suite was measured using.
        (Some("1"), &[][..], Some("1")),
    ] {
        let mut command = tuist_cargo_cache(root.path());
        command
            .env("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "8")
            .env("TUIST_CARGO_CACHE_SCHEDULER_MEMORY", "none")
            .args(["test", "--offline", "--"])
            .args(harness);
        if let Some(tests) = tests {
            command.env("TUIST_CARGO_CACHE_SCHEDULER_TESTS", tests);
        }
        if let Some(expected) = expected {
            command.env("EXPECTED_WEIGHT", expected);
        }
        let output = command.output().unwrap();
        assert!(
            output.status.success(),
            "{tests:?} {harness:?}: {}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    // Cargo hands the test's package to the runner, and the measured history
    // is kept under it rather than under the bare binary name.
    let ledger = std::fs::read_to_string(root.path().join("cache/scheduler/memory.json")).unwrap();
    assert!(
        ledger.contains("scope-fixture/scope_fixture [test]\":1"),
        "{ledger}"
    );
}

#[cfg(unix)]
#[test]
fn a_test_binary_that_finishes_in_under_a_second_is_weighed_one_core() {
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        r#"
fn main() {}
#[test]
fn quick() {
    let leases = std::path::Path::new(&std::env::var_os("TUIST_CARGO_CACHE_DIR").unwrap())
        .join("scheduler/leases");
    let held: Vec<String> = std::fs::read_dir(&leases)
        .unwrap()
        .map(|entry| std::fs::read_to_string(entry.unwrap().path()).unwrap())
        .collect();
    let weight = std::env::var("EXPECTED_WEIGHT").unwrap();
    assert_eq!(held.len(), 1, "{held:?}");
    assert!(held[0].contains(&format!("\"weight\":{weight},")), "{held:?}");
}
"#,
    );
    std::fs::write(
        root.path().join("Cargo.toml"),
        "[package]\nname='scope-fixture'\nversion='0.0.0'\nedition='2021'\n\n[lib]\nname='scope_lib'\n",
    )
    .unwrap();
    std::fs::write(root.path().join("src/lib.rs"), "").unwrap();
    // Unmeasured, the suite asks for half of the 8 permits; one run that
    // ends well under a second records it as a single core.
    for expected in ["4", "1"] {
        let output = tuist_cargo_cache(root.path())
            .env("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "8")
            .env("TUIST_CARGO_CACHE_SCHEDULER_MEMORY", "none")
            .env("TUIST_CARGO_CACHE_SCHEDULER_TESTS", "1")
            .env("EXPECTED_WEIGHT", expected)
            .args(["test", "--offline"])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "expected weight {expected}: {}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[test]
fn cargo_run_reads_an_empty_rustc_wrapper_as_none() {
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        "fn main() { println!(\"application started\"); }",
    );
    std::fs::create_dir_all(root.path().join(".cargo")).unwrap();
    // A `cfg()` section makes the runner lookup ask rustc for the target's cfg,
    // and an empty wrapper is how a workspace cancels one it inherits.
    std::fs::write(
        root.path().join(".cargo/config.toml"),
        r#"[target.'cfg(all(windows, target_env = "msvc"))']
rustflags = ["-C", "target-feature=+crt-static"]

[target.'cfg(target_os = "macos")']
rustflags = ["-C", "split-debuginfo=unpacked"]

[build]
rustc-wrapper = ""
"#,
    )
    .unwrap();

    let output = tuist_cargo_cache(root.path())
        .args(["run", "--offline"])
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "run failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("application started"));
}

#[cfg(unix)]
#[test]
fn scheduled_test_binaries_hold_a_permit_with_an_empty_rustc_wrapper() {
    let root = tempfile::tempdir().unwrap();
    project(
        root.path(),
        r#"
fn main() {}
#[test]
fn scheduled() {
    let leases = std::path::Path::new(&std::env::var_os("TUIST_CARGO_CACHE_DIR").unwrap())
        .join("scheduler/leases");
    let held = std::fs::read_dir(&leases).map(|entries| entries.count()).unwrap_or(0);
    assert_eq!(held, 1, "this test should hold a permit");
}
"#,
    );
    std::fs::create_dir(root.path().join(".cargo")).unwrap();
    // The runner lookup that schedules tests evaluates `cfg()` sections by
    // asking rustc, and an emptied wrapper used to make that lookup fail. It
    // fails quietly, so a passing `cargo test` alone would not show it: the
    // tests just ran without a permit.
    std::fs::write(
        root.path().join(".cargo/config.toml"),
        r#"[target.'cfg(all(windows, target_env = "msvc"))']
rustflags = ["-C", "target-feature=+crt-static"]

[build]
rustc-wrapper = ""
"#,
    )
    .unwrap();

    let output = tuist_cargo_cache(root.path())
        .env("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "8")
        .env("TUIST_CARGO_CACHE_SCHEDULER_MEMORY", "none")
        .env("TUIST_CARGO_CACHE_SCHEDULER_TESTS", "1")
        .args(["test", "--offline"])
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
