//! End-to-end coverage for cached cargo commands.
//!
//! Each test drives the real binary over a throwaway project with no
//! dependencies, so nothing here needs the network.

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};
use std::process::Command;
#[cfg(unix)]
use std::process::{Child, Output, Stdio};

#[cfg(unix)]
struct BuildChildGuard(Option<Child>);

#[cfg(unix)]
impl BuildChildGuard {
    fn new(child: Child) -> Self {
        Self(Some(child))
    }

    fn try_wait(&mut self) -> std::io::Result<Option<std::process::ExitStatus>> {
        self.0
            .as_mut()
            .expect("build child was already consumed")
            .try_wait()
    }

    fn wait_with_output(mut self) -> std::io::Result<Output> {
        self.0
            .take()
            .expect("build child was already consumed")
            .wait_with_output()
    }
}

#[cfg(unix)]
impl Drop for BuildChildGuard {
    fn drop(&mut self) {
        let Some(child) = self.0.as_mut() else {
            return;
        };
        if child.try_wait().ok().flatten().is_none() {
            let _ = child.kill();
        }
        let _ = child.wait();
    }
}

#[path = "build/semantic_oracle.rs"]
mod semantic_oracle;
mod support;

fn write_project(directory: &Path) {
    write_named_project(directory, "fixture");
}

/// Write the fixture under `name`.
///
/// The name reaches the lockfile, and the lockfile is what the build identity
/// is keyed on, so two differently named fixtures are two different identities
/// -- which is what it takes to tell one checkout's artifacts from another's.
fn write_named_project(directory: &Path, name: &str) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        format!("[package]\nname = \"{name}\"\nversion = \"0.1.0\"\nedition = \"2021\"\n"),
    )
    .unwrap();
    std::fs::write(
        directory.join("src/lib.rs"),
        "pub fn double(value: u32) -> u32 {\n    value * 2\n}\n",
    )
    .unwrap();
    // Manifest identity follows the lockfile, and cargo would otherwise write
    // it during the first build -- changing the identity between two runs that
    // are supposed to share a manifest.
    generate_lockfile(directory);
}

/// Write a workspace where one member depends on another.
fn write_dependent_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("base/src")).unwrap();
    std::fs::create_dir_all(directory.join("above/src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[workspace]\nmembers = [\"base\", \"above\"]\nresolver = \"2\"\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("README.md"),
        "shared workspace documentation\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("base/Cargo.toml"),
        "[package]\nname = \"base\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("base/src/lib.rs"),
        "#![doc = include_str!(\"../../README.md\")]\npub fn value() -> u32 { 0 }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("above/Cargo.toml"),
        "[package]\nname = \"above\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\nbase = { path = \"../base\" }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("above/src/lib.rs"),
        "pub fn doubled() -> u32 { base::value() * 2 }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// Write a workspace whose dependency builds before a member that fails.
fn write_partially_failing_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("good/src")).unwrap();
    std::fs::create_dir_all(directory.join("bad/src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[workspace]\nmembers = [\"good\", \"bad\"]\nresolver = \"2\"\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("good/Cargo.toml"),
        "[package]\nname = \"good\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(directory.join("good/src/lib.rs"), "pub fn good() {}\n").unwrap();
    std::fs::write(
        directory.join("bad/Cargo.toml"),
        "[package]\nname = \"bad\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\ngood = { path = \"../good\" }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("bad/src/lib.rs"),
        "use good as _;\ncompile_error!(\"expected failure\");\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

fn cargo() -> std::ffi::OsString {
    std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into())
}

/// Start tuist_cargo_cache with the developer's own configuration hidden.
fn cargo_cache_command() -> Command {
    isolated_command(env!("CARGO_BIN_EXE_tuist-cargo-cache-model"))
}

/// Start `program`, such as an installed shim, with the developer's own
/// configuration hidden.
fn isolated_command(program: impl AsRef<std::ffi::OsStr>) -> Command {
    let mut command = Command::new(program);
    support::isolate_host(&mut command);
    command
}

/// Generate a fixture lockfile without contending on the developer or CI
/// runner's package cache. The integration tests run concurrently and these
/// registry-free fixtures do not need anything from the shared Cargo home.
fn generate_lockfile(directory: &Path) {
    let cargo_home = tempfile::tempdir().unwrap();
    let status = Command::new(cargo())
        .current_dir(directory)
        .args(["generate-lockfile", "--offline"])
        .env("CARGO_HOME", cargo_home.path())
        .status()
        .expect("cargo should run");
    assert!(status.success(), "the fixture should resolve offline");
}

/// Every file under `root` that `matches` accepts, in a stable order.
///
/// Cargo's build-dir layout decides where a unit's files land: before 1.100
/// they are `deps/<name>-<hash>` and `build/<pkg>-<hash>/`, and from 1.100
/// each unit owns `build/<pkg>/<hash>/`. Searching the whole tree lets a test
/// name the file it needs rather than the layout that holds it.
fn find_files(root: &Path, matches: impl Fn(&Path) -> bool) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        let entries = std::fs::read_dir(&directory)
            .unwrap_or_else(|error| panic!("{} should be readable: {error}", directory.display()));
        for entry in entries {
            let entry = entry.unwrap();
            let file_type = entry.file_type().unwrap();
            if file_type.is_dir() {
                pending.push(entry.path());
            } else if file_type.is_file() && matches(&entry.path()) {
                found.push(entry.path());
            }
        }
    }
    found.sort();
    found
}

/// Whether `path`'s file name satisfies `matches`.
fn file_name_is(path: &Path, matches: impl FnOnce(&str) -> bool) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(matches)
}

#[cfg(unix)]
#[test]
fn a_fatal_rustc_shim_error_survives_an_unavailable_agent() {
    let directory = tempfile::tempdir().unwrap();
    let shim = tuist_cargo_cache::session::install_shim(
        Path::new(env!("CARGO_BIN_EXE_tuist-cargo-cache-model")),
        directory.path(),
        tuist_cargo_cache::session::ShimLink::Tracking,
    )
    .unwrap();
    let output = isolated_command(shim)
        .arg(directory.path().join("missing-rustc"))
        .env(
            "TUIST_CARGO_CACHE_SOCKET",
            directory.path().join("missing-agent.sock"),
        )
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!output.status.success(), "a missing compiler must fail");
    assert!(
        stderr.contains("tuist_cargo_cache[error]: the rustc shim failed to execute rustc:"),
        "the fatal reason must survive a failed delivery: {stderr}"
    );
    assert!(!stderr.contains("tuist_cargo_cache[warning]"), "{stderr}");
}

#[cfg(unix)]
#[test]
fn transparent_rustc_replaces_the_shim_process() {
    let directory = tempfile::tempdir().unwrap();
    let shim = tuist_cargo_cache::session::install_shim(
        Path::new(env!("CARGO_BIN_EXE_tuist-cargo-cache-model")),
        directory.path(),
        tuist_cargo_cache::session::ShimLink::Tracking,
    )
    .unwrap();
    let pid_file = directory.path().join("compiler.pid");

    // Retried because exec of the binary behind the shim can transiently fail
    // with ETXTBSY: anyone holding it open for write blocks the exec, and a
    // sibling test that forks while cargo is writing it counts, since until
    // that child reaches its own exec the inherited descriptor (cloexec or not)
    // is a writer of this file too.
    let mut child = {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        loop {
            let attempt = isolated_command(&shim)
                .arg("/bin/sh")
                .args(["-c", "printf '%s' \"$$\" > \"$1\"", "sh"])
                .arg(&pid_file)
                .spawn();
            match attempt {
                Err(error)
                    if error.kind() == std::io::ErrorKind::ExecutableFileBusy
                        && std::time::Instant::now() < deadline =>
                {
                    std::thread::sleep(std::time::Duration::from_millis(20));
                }
                other => break other.unwrap(),
            }
        }
    };
    let shim_pid = child.id();
    let status = child.wait().unwrap();

    assert!(status.success());
    assert_eq!(
        std::fs::read_to_string(pid_file).unwrap(),
        shim_pid.to_string()
    );
}

#[cfg(unix)]
#[test]
fn rustc_workspace_wrapper_is_preserved_without_becoming_the_compiler() {
    use std::os::unix::fs::PermissionsExt as _;

    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_project(project.path());

    let wrapper = project.path().join("workspace-rustc");
    let log = project.path().join("workspace-rustc.log");
    std::fs::write(
        &wrapper,
        "#!/bin/sh\nprintf 'called\\n' >> \"$TUIST_CARGO_CACHE_TEST_WORKSPACE_WRAPPER_LOG\"\nexec \"$@\"\n",
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&wrapper).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&wrapper, permissions).unwrap();

    let (stats, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("stats.json"),
        &[
            ("RUSTC_WORKSPACE_WRAPPER", wrapper.to_str().unwrap()),
            (
                "TUIST_CARGO_CACHE_TEST_WORKSPACE_WRAPPER_LOG",
                log.to_str().unwrap(),
            ),
        ],
    );

    assert!(
        std::fs::read_to_string(log).unwrap().contains("called"),
        "Cargo should still invoke the configured workspace wrapper"
    );
    assert!(
        stderr.contains("RUSTC_WORKSPACE_WRAPPER is already set"),
        "the uncached workspace compilation should be disclosed: {stderr}"
    );
    assert!(
        stats["bypasses"].get("multiple-inputs").is_none(),
        "the workspace wrapper must not be parsed as rustc: {stats}"
    );
}

#[cfg(unix)]
#[test]
fn a_mid_compilation_input_edit_discards_the_result() {
    use std::os::unix::fs::PermissionsExt as _;

    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_dependent_project(project.path());

    // Let rustc produce the old metadata, then hold the wrapper open until the
    // test edits both the crate and its dependent. This makes the race exact
    // without depending on how long a real compilation happens to take.
    let wrapper = project.path().join("delayed-rustc");
    let compiled = project.path().join("compiler-finished");
    let release = project.path().join("release-compiler");
    std::fs::write(
        &wrapper,
        "#!/bin/sh\n\"$TEST_REAL_RUSTC\" \"$@\"\nstatus=$?\ncase \" $* \" in\n  *\" --crate-name base \"*)\n    if [ \"$status\" -eq 0 ]; then\n      : > \"$TEST_COMPILER_FINISHED\"\n      while [ ! -e \"$TEST_RELEASE_COMPILER\" ]; do sleep 0.02; done\n    fi\n    ;;\nesac\nexit \"$status\"\n",
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&wrapper).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&wrapper, permissions).unwrap();

    let mut child = cargo_cache_command();
    child
        .current_dir(project.path())
        .args(["check", "--offline", "--verbose"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_TARGET_VIEWS", "0")
        .env("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0")
        .env("CARGO_INCREMENTAL", "0")
        .env("RUSTC", &wrapper)
        .env("TEST_REAL_RUSTC", which::which("rustc").unwrap())
        .env("TEST_COMPILER_FINISHED", &compiled)
        .env("TEST_RELEASE_COMPILER", &release)
        .env_remove("TUIST_CARGO_CACHE_SOCKET")
        .env_remove("CARGO_TARGET_DIR")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = child.spawn().expect("tuist_cargo_cache should run");

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while !compiled.exists() && std::time::Instant::now() < deadline {
        assert!(
            child.try_wait().unwrap().is_none(),
            "the build exited before the compiler could be released"
        );
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert!(
        compiled.exists(),
        "the compiler did not reach the test barrier"
    );

    std::fs::write(
        project.path().join("base/src/lib.rs"),
        "pub fn value() -> u32 { 1 }\npub fn added() -> u32 { 2 }\n",
    )
    .unwrap();
    std::fs::write(
        project.path().join("above/src/lib.rs"),
        "pub fn value() -> u32 { base::added() }\n",
    )
    .unwrap();
    std::fs::write(&release, b"").unwrap();

    let output = child.wait_with_output().unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !output.status.success(),
        "the invalid compilation must fail"
    );
    assert!(
        stderr
            .contains("tuist_cargo_cache[error]: compilation result was discarded: compiler input was modified"),
        "the mutation should be diagnosed as an error: {stderr}"
    );
    assert!(
        !stderr.contains("tuist_cargo_cache[warning]: compilation result was discarded"),
        "a fatal rejection must retain its severity: {stderr}"
    );
    assert!(
        !stderr.contains("Checking above"),
        "Cargo must not compile a dependent against the stale metadata: {stderr}"
    );

    // Cargo keeps a unit's fingerprint in `.fingerprint/<unit>/` before 1.100
    // and in `build/<pkg>/<hash>/fingerprint/` from 1.100.
    let target = project.path().join("target/debug");
    let fingerprint_outputs = find_files(&target, |path| {
        file_name_is(path, |name| name.starts_with("output-"))
            && path.ancestors().nth(1).is_some_and(|unit| {
                unit.file_name() == Some("fingerprint".as_ref())
                    || unit.parent().and_then(Path::file_name) == Some(".fingerprint".as_ref())
            })
    });
    let fingerprint_replays = fingerprint_outputs
        .into_iter()
        .filter(|path| {
            std::fs::read_to_string(path)
                .is_ok_and(|output| output.contains("compilation result was discarded"))
        })
        .collect::<Vec<_>>();
    assert!(
        fingerprint_replays.is_empty(),
        "the rejected-result diagnostic must not enter Cargo fingerprints: {fingerprint_replays:?}"
    );

    let stale_outputs = find_files(&target, |path| {
        file_name_is(path, |name| {
            (name.starts_with("libbase-") && name.ends_with(".rmeta"))
                || (name.starts_with("base-") && name.ends_with(".d"))
        })
    });
    assert!(
        stale_outputs.is_empty(),
        "the stale compiler outputs should be removed: {stale_outputs:?}"
    );

    // A shim diagnostic is delivered by the live session rather than through
    // the compiler stream. Cargo must therefore have no rejected-result
    // message to replay when the same source is compiled successfully.
    let retry = cargo_cache_command()
        .current_dir(project.path())
        .args(["check", "--offline"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_TARGET_VIEWS", "0")
        .env("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0")
        .env("CARGO_INCREMENTAL", "0")
        .env("RUSTC", &wrapper)
        .env("TEST_REAL_RUSTC", which::which("rustc").unwrap())
        .env("TEST_COMPILER_FINISHED", &compiled)
        .env("TEST_RELEASE_COMPILER", &release)
        .env_remove("TUIST_CARGO_CACHE_SOCKET")
        .env_remove("CARGO_TARGET_DIR")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .output()
        .unwrap();
    let retry_stderr = String::from_utf8_lossy(&retry.stderr);
    assert!(
        retry.status.success(),
        "the unchanged retry should succeed: {retry_stderr}"
    );
    assert!(
        !retry_stderr.contains("compilation result was discarded"),
        "Cargo must not replay the rejected-result diagnostic: {retry_stderr}"
    );
}

#[cfg(unix)]
#[test]
fn a_mid_compilation_build_script_edit_discards_the_execution_only_result() {
    use std::os::unix::fs::PermissionsExt as _;

    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_execution_cached_project(project.path(), true);

    let wrapper = project.path().join("delayed-rustc");
    let compiled = project.path().join("compiler-finished");
    let release = project.path().join("release-compiler");
    std::fs::write(
        &wrapper,
        "#!/bin/sh\n\"$TEST_REAL_RUSTC\" \"$@\"\nstatus=$?\ncase \" $* \" in\n  *\" --crate-name build_script_build \"*)\n    if [ \"$status\" -eq 0 ]; then\n      : > \"$TEST_COMPILER_FINISHED\"\n      while [ ! -e \"$TEST_RELEASE_COMPILER\" ]; do sleep 0.02; done\n    fi\n    ;;\nesac\nexit \"$status\"\n",
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&wrapper).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&wrapper, permissions).unwrap();

    let mut child = cargo_cache_command();
    child
        .current_dir(project.path())
        .args(["build", "--offline", "--verbose"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_CACHE_LINKS", "0")
        .env("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "1")
        .env("TUIST_CARGO_CACHE_TARGET_VIEWS", "0")
        .env("RUSTC", &wrapper)
        .env("TEST_REAL_RUSTC", which::which("rustc").unwrap())
        .env("TEST_COMPILER_FINISHED", &compiled)
        .env("TEST_RELEASE_COMPILER", &release)
        .env_remove("TUIST_CARGO_CACHE_SOCKET")
        .env_remove("CARGO_TARGET_DIR")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = child.spawn().expect("tuist_cargo_cache should run");

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while !compiled.exists() && std::time::Instant::now() < deadline {
        assert!(
            child.try_wait().unwrap().is_none(),
            "the build exited before the build-script compiler could be released"
        );
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert!(
        compiled.exists(),
        "the build-script compiler did not reach the test barrier"
    );

    let build_script = project.path().join("build.rs");
    let mut source = std::fs::read_to_string(&build_script).unwrap();
    source.push_str("\n// edited while rustc was running\n");
    std::fs::write(build_script, source).unwrap();
    std::fs::write(&release, b"").unwrap();

    let output = child.wait_with_output().unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !output.status.success(),
        "the invalid build-script compilation must fail"
    );
    assert!(
        stderr.contains("compilation result was discarded: compiler input was modified"),
        "the build-script mutation should be diagnosed: {stderr}"
    );
}

/// Build `project` against `store`, returning the run's statistics.
fn build(project: &Path, store: &Path, report: &Path) -> serde_json::Value {
    build_with(project, store, report, &[]).0
}

fn document(project: &Path, store: &Path, report: &Path) -> serde_json::Value {
    let output = cargo_cache_command()
        .current_dir(project)
        .args(["doc", "--offline", "--no-deps"])
        .env("TUIST_CARGO_CACHE_DIR", store)
        .env("TUIST_CARGO_CACHE_STATS_REPORT", report)
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env_remove("TUIST_CARGO_CACHE_SOCKET")
        // This suite may itself be run through tuist_cargo_cache. The fixture needs a fresh
        // session rather than chaining the outer test build's compiler shim.
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("tuist_cargo_cache should run");
    assert!(
        output.status.success(),
        "documentation failed ({}): {}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&std::fs::read(report).unwrap()).unwrap()
}

/// Build as `build` does, with `settings` added to the environment.
///
/// Returns what the build said on stderr alongside its statistics, because some
/// of what tuist_cargo_cache reports -- a sweep, for one -- is only ever said there.
fn build_with(
    project: &Path,
    store: &Path,
    report: &Path,
    settings: &[(&str, &str)],
) -> (serde_json::Value, String) {
    cargo_with(project, store, report, &["build", "--offline"], settings)
}

fn cargo_with(
    project: &Path,
    store: &Path,
    report: &Path,
    arguments: &[&str],
    settings: &[(&str, &str)],
) -> (serde_json::Value, String) {
    cargo_with_command(
        cargo_cache_command(),
        project,
        store,
        report,
        arguments,
        settings,
    )
}

/// Prepare `command` to run `arguments` in `project` against `store`, with the
/// settings a test does not name taken out of the machine's hands and
/// `settings` applied on top.
///
/// Separate from running it so a test can start the command and act while it
/// is still running.
fn isolated_cargo_command(
    mut command: Command,
    project: &Path,
    store: &Path,
    report: &Path,
    arguments: &[&str],
    settings: &[(&str, &str)],
) -> Command {
    command
        .current_dir(project)
        .args(arguments)
        .env("TUIST_CARGO_CACHE_DIR", store)
        .env("TUIST_CARGO_CACHE_STATS_REPORT", report)
        // The automatic sweep runs in a process the build leaves behind, and a
        // fresh store is always due one. It would race whatever the test does
        // next to the store, so only the tests about it turn it on.
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        // Cargo's own environment for this test would otherwise redirect the
        // fixture's output into this crate's target directory.
        .env_remove("CARGO_TARGET_DIR")
        // All three decide whether cargo compiles incrementally, so a test that
        // says nothing about it must not inherit an answer from the machine it
        // runs on. CARGO_INCREMENTAL is the one that bites: an enabled build
        // defers to it, and `Swatinem/rust-cache` sets it to 0 for the whole
        // job, so leaving it would make this suite pass locally and fail in CI.
        .env_remove("TUIST_CARGO_CACHE_INCREMENTAL")
        .env_remove("CARGO_INCREMENTAL")
        .env_remove("CI")
        .env_remove("GITHUB_ACTIONS")
        .env_remove("TUIST_CARGO_CACHE_RELEASE")
        // Same reason: a test asserting the default cross-checkout behaviour
        // must not read an answer out of the developer's environment.
        .env_remove("TUIST_CARGO_CACHE_SHARE_OUT_DIR")
        .env_remove("TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT")
        .env_remove("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION")
        .env_remove("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL")
        .env_remove("TUIST_CARGO_CACHE_VERIFY")
        .env_remove("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE")
        // Native links are cached by default and several counts here include
        // one, so an inherited answer would decide them.
        .env_remove("TUIST_CARGO_CACHE_CACHE_LINKS")
        // An action may group every build in the surrounding job. Individual
        // tests opt into that explicitly rather than leaking into its group.
        .env_remove(tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV)
        // The C shims are on by default; a test that says nothing about them
        // must not inherit a different answer from the developer's shell. The
        // compiler variables matter just as much: this suite is itself run
        // through tuist_cargo_cache, so without this a fixture would inherit the outer
        // session's shims and every build here would stand aside.
        .env_remove("TUIST_CARGO_CACHE_CC")
        .env_remove("CC")
        .env_remove("CXX")
        .env_remove("HOST_CC")
        .env_remove("HOST_CXX")
        .env_remove("TARGET_CC")
        .env_remove("TARGET_CXX")
        .env_remove("TUIST_CARGO_CACHE_REAL_CC")
        .env_remove("TUIST_CARGO_CACHE_REAL_CXX")
        .env_remove("TUIST_CARGO_CACHE_SOCKET")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CLIPPY_CONF_DIR");
    for (name, value) in settings {
        command.env(name, value);
    }
    command
}

fn cargo_with_command(
    command: Command,
    project: &Path,
    store: &Path,
    report: &Path,
    arguments: &[&str],
    settings: &[(&str, &str)],
) -> (serde_json::Value, String) {
    let mut command = isolated_cargo_command(command, project, store, report, arguments, settings);
    // Tests that copy tuist_cargo_cache to a new path and run the copy can hit ETXTBSY: a
    // sibling test that forks while the copy is open for write hands its child
    // that descriptor until the child reaches its own exec.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let output = loop {
        match command.output() {
            Err(error)
                if error.kind() == std::io::ErrorKind::ExecutableFileBusy
                    && std::time::Instant::now() < deadline =>
            {
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
            other => break other.expect("tuist_cargo_cache should run"),
        }
    };
    assert!(
        output.status.success(),
        "build failed ({}): {}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );
    let stats = std::fs::read(report).expect("a statistics report should be written");
    (
        serde_json::from_slice(&stats).expect("the report should be JSON"),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

/// Run `tuist_cargo_cache` against `store` and return its stdout.
fn tuist_cargo_cache(store: &Path, arguments: &[&str]) -> String {
    let output = cargo_cache_command()
        .args(arguments)
        .env("TUIST_CARGO_CACHE_DIR", store)
        .output()
        .expect("tuist_cargo_cache should run");
    assert!(
        output.status.success(),
        "{arguments:?} failed ({}): {}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).into_owned()
}

/// The bytes `tuist_cargo_cache gc` weighs against its budget.
fn store_bytes(store: &Path) -> u64 {
    tree_bytes(&store.join("actions/cas")) + tree_bytes(&store.join("actions/action-results"))
}

/// Total size of every file under `directory`.
fn tree_bytes(directory: &Path) -> u64 {
    let mut total = 0;
    let mut pending = vec![directory.to_path_buf()];
    while let Some(next) = pending.pop() {
        let Ok(listing) = std::fs::read_dir(&next) else {
            continue;
        };
        for entry in listing.flatten() {
            let metadata = entry.metadata().expect("the entry should be readable");
            if metadata.is_dir() {
                pending.push(entry.path());
            } else if metadata.is_file() {
                total += metadata.len();
            }
        }
    }
    total
}

fn count(stats: &serde_json::Value, field: &str) -> u64 {
    stats[field]
        .as_u64()
        .unwrap_or_else(|| panic!("{field} should be a number"))
}

#[test]
fn clippy_workspace_compilations_restore_and_track_clippy_toml() {
    if !Command::new(cargo())
        .args(["clippy", "--version"])
        .status()
        .is_ok_and(|status| status.success())
    {
        return;
    }
    let store = tempfile::tempdir().unwrap();
    let appearance_store = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let changed = tempfile::tempdir().unwrap();
    let changed_flags = tempfile::tempdir().unwrap();
    let without_config = tempfile::tempdir().unwrap();
    let added_config = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    for project in [
        &first,
        &second,
        &changed,
        &changed_flags,
        &without_config,
        &added_config,
    ] {
        write_project(project.path());
    }
    for project in [&first, &second, &changed_flags] {
        std::fs::write(
            project.path().join("clippy.toml"),
            "too-many-arguments-threshold = 7\n",
        )
        .unwrap();
    }
    std::fs::write(
        changed.path().join("clippy.toml"),
        "too-many-arguments-threshold = 8\n",
    )
    .unwrap();
    std::fs::write(
        added_config.path().join("clippy.toml"),
        "too-many-arguments-threshold = 7\n",
    )
    .unwrap();

    let (cold, cold_stderr) = cargo_with(
        first.path(),
        store.path(),
        &reports.path().join("clippy-cold.json"),
        &["clippy", "--offline"],
        &[],
    );
    assert_eq!(count(&cold, "hits"), 0, "a cold clippy run cannot hit");
    assert!(
        cold["bypasses"].get("multiple-inputs").is_none(),
        "the real rustc path must not be parsed as a source: {cold}"
    );
    assert!(
        count(&cold, "stored_bytes") > 0,
        "the workspace compilation should be stored: {cold}\n{cold_stderr}"
    );

    let warm = cargo_with(
        second.path(),
        store.path(),
        &reports.path().join("clippy-warm.json"),
        &["clippy", "--offline"],
        &[],
    )
    .0;
    assert!(count(&warm, "hits") > 0, "clippy should restore: {warm}");

    let changed = cargo_with(
        changed.path(),
        store.path(),
        &reports.path().join("clippy-changed.json"),
        &["clippy", "--offline"],
        &[],
    )
    .0;
    assert!(
        count(&changed, "misses") > 0,
        "changed clippy.toml must miss: {changed}"
    );

    let changed_flags = cargo_with(
        changed_flags.path(),
        store.path(),
        &reports.path().join("clippy-changed-flags.json"),
        &["clippy", "--offline", "--", "-D", "warnings"],
        &[],
    )
    .0;
    assert!(
        count(&changed_flags, "misses") > 0,
        "changed CLIPPY_ARGS must miss: {changed_flags}"
    );

    let without_config = cargo_with(
        without_config.path(),
        appearance_store.path(),
        &reports.path().join("clippy-without-config.json"),
        &["clippy", "--offline"],
        &[],
    )
    .0;
    assert!(
        count(&without_config, "stored_bytes") > 0,
        "the no-config action should be stored: {without_config}"
    );
    let added_config = cargo_with(
        added_config.path(),
        appearance_store.path(),
        &reports.path().join("clippy-added-config.json"),
        &["clippy", "--offline"],
        &[],
    )
    .0;
    assert!(
        count(&added_config, "misses") > 0,
        "adding clippy.toml must miss: {added_config}"
    );
}

#[test]
fn rustdoc_pages_restore_and_rebuild_the_shared_index() {
    let store = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let changed = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_dependent_project(first.path());
    write_dependent_project(second.path());
    write_dependent_project(changed.path());

    let cold = document(
        first.path(),
        store.path(),
        &reports.path().join("cold-doc.json"),
    );
    assert!(
        count(&cold, "misses") >= 2,
        "both crates should render: {cold}"
    );
    let warm = document(
        second.path(),
        store.path(),
        &reports.path().join("warm-doc.json"),
    );

    assert!(count(&warm, "hits") >= 2, "rustdoc should restore: {warm}");
    assert!(second.path().join("target/doc/base/index.html").is_file());
    assert!(second.path().join("target/doc/above/index.html").is_file());
    let index = std::fs::read_to_string(second.path().join("target/doc/crates.js")).unwrap();
    assert!(
        index.contains("base") && index.contains("above"),
        "the finalized index should name both crates"
    );

    std::fs::write(
        changed.path().join("README.md"),
        "changed workspace documentation\n",
    )
    .unwrap();
    let changed_stats = document(
        changed.path(),
        store.path(),
        &reports.path().join("changed-doc.json"),
    );
    assert!(
        count(&changed_stats, "misses") >= 2,
        "a workspace-level doc input should invalidate the cached pages: {changed_stats}"
    );
    let changed_page =
        std::fs::read_to_string(changed.path().join("target/doc/base/index.html")).unwrap();
    assert!(changed_page.contains("changed workspace documentation"));
}

#[cfg(unix)]
#[test]
fn a_failed_mergeable_render_is_not_run_again_transparently() {
    use std::os::unix::fs::PermissionsExt as _;

    let project = tempfile::tempdir().unwrap();
    let store = tempfile::tempdir().unwrap();
    write_project(project.path());
    let wrapper = project.path().join("count-rustdoc");
    let count = project.path().join("rustdoc-count");
    std::fs::write(
        &wrapper,
        "#!/bin/sh\nif [ \"$1\" = \"-Vv\" ]; then exec \"$TEST_REAL_RUSTDOC\" \"$@\"; fi\nprintf x >> \"$TEST_RUSTDOC_COUNT\"\nprintf 'one rustdoc failure\\n' >&2\nexit 7\n",
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&wrapper).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&wrapper, permissions).unwrap();
    let rustdoc = which::which("rustdoc").unwrap();

    let output = cargo_cache_command()
        .current_dir(project.path())
        .args(["doc", "--offline", "--no-deps"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("RUSTDOC", &wrapper)
        .env("TEST_REAL_RUSTDOC", rustdoc)
        .env("TEST_RUSTDOC_COUNT", &count)
        .output()
        .unwrap();

    assert!(!output.status.success());
    assert_eq!(std::fs::read(&count).unwrap(), b"x");
}

/// Remove the outputs behind a target link so the next build must restore.
fn wipe_target(project: &Path) {
    let target = project.join("target");
    let outputs = std::fs::read_link(&target).unwrap_or(target);
    std::fs::remove_dir_all(outputs).unwrap();
}

fn corrupt_action_results(store: &Path) -> usize {
    let mut corrupted = 0;
    let mut pending = vec![store.join("actions/action-results")];
    while let Some(directory) = pending.pop() {
        let Ok(entries) = std::fs::read_dir(directory) else {
            continue;
        };
        for entry in entries.flatten() {
            if entry.file_type().is_ok_and(|kind| kind.is_dir()) {
                pending.push(entry.path());
            } else if std::fs::write(entry.path(), b"not json").is_ok() {
                corrupted += 1;
            }
        }
    }
    corrupted
}

#[test]
fn a_ci_export_group_collects_every_build_in_the_job() {
    let source_store = tempfile::tempdir().unwrap();
    let destination_store = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_named_project(first.path(), "first-fixture");
    write_named_project(second.path(), "second-fixture");
    let group = "github-run-42/test-linux";
    build_with(
        first.path(),
        source_store.path(),
        &reports.path().join("first.json"),
        &[
            (tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV, group),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ],
    );
    build_with(
        second.path(),
        source_store.path(),
        &reports.path().join("second.json"),
        &[
            (tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV, group),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ],
    );
    wipe_target(first.path());
    wipe_target(second.path());
    let warm_group = "github-run-43/test-linux";
    let first_warm = build_with(
        first.path(),
        source_store.path(),
        &reports.path().join("first-warm.json"),
        &[
            (
                tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV,
                warm_group,
            ),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ],
    )
    .0;
    edit_project(first.path(), 1);
    let first_changed = build_with(
        first.path(),
        source_store.path(),
        &reports.path().join("first-changed.json"),
        &[
            (
                tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV,
                warm_group,
            ),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ],
    )
    .0;
    let second_warm = build_with(
        second.path(),
        source_store.path(),
        &reports.path().join("second-warm.json"),
        &[
            (
                tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV,
                warm_group,
            ),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ],
    )
    .0;
    assert!(count(&first_warm, "hits") > 0);
    assert!(count(&first_changed, "misses") > 0);
    assert!(count(&second_warm, "hits") > 0);
    let archive = reports.path().join("job.tar");

    let export = cargo_cache_command()
        .current_dir(first.path())
        .args(["cache", "export", "--group", warm_group])
        .arg(&archive)
        .env("TUIST_CARGO_CACHE_DIR", source_store.path())
        .output()
        .unwrap();
    assert!(
        export.status.success(),
        "group export failed: {}",
        String::from_utf8_lossy(&export.stderr)
    );
    let import = cargo_cache_command()
        .args(["cache", "import"])
        .arg(&archive)
        .env("TUIST_CARGO_CACHE_DIR", destination_store.path())
        .output()
        .unwrap();
    assert!(
        import.status.success(),
        "group import failed: {}",
        String::from_utf8_lossy(&import.stderr)
    );
    let stats: serde_json::Value = serde_json::from_str(&tuist_cargo_cache(
        destination_store.path(),
        &["cache", "stats", "--json"],
    ))
    .unwrap();
    assert!(
        stats["action_results"].as_u64().unwrap() >= 3,
        "every grouped build should seed the destination store: {stats}; export: {}; import: {}",
        String::from_utf8_lossy(&export.stdout),
        String::from_utf8_lossy(&import.stdout),
    );
}

#[test]
fn a_cache_bundle_restores_cargo_workspace_state() {
    let source_store = tempfile::tempdir().unwrap();
    let destination_store = tempfile::tempdir().unwrap();
    let destination_targets = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());
    let group = "github-run-42/workspace-state";
    build_with(
        project.path(),
        source_store.path(),
        &reports.path().join("source.json"),
        &[
            (tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV, group),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ],
    );
    std::fs::write(project.path().join("target/scheduler-marker"), b"warm").unwrap();
    let archive = reports.path().join("workspace-state.tar");
    let export = cargo_cache_command()
        .current_dir(project.path())
        .args(["cache", "export", "--group", group])
        .arg(&archive)
        .env("TUIST_CARGO_CACHE_DIR", source_store.path())
        .output()
        .unwrap();
    assert!(
        export.status.success(),
        "workspace-state export failed: {}",
        String::from_utf8_lossy(&export.stderr)
    );
    wipe_target(project.path());

    let import = cargo_cache_command()
        .current_dir(project.path())
        .args(["cache", "import"])
        .arg(&archive)
        .env("TUIST_CARGO_CACHE_DIR", destination_store.path())
        .env("TUIST_CARGO_CACHE_TARGET_ROOT", destination_targets.path())
        .output()
        .unwrap();

    assert!(
        import.status.success(),
        "workspace-state import failed: {}",
        String::from_utf8_lossy(&import.stderr)
    );
    assert!(
        String::from_utf8_lossy(&import.stdout).contains("restored Cargo workspace state"),
        "import did not report a workspace restore: {}",
        String::from_utf8_lossy(&import.stdout)
    );
    assert_eq!(
        std::fs::read(project.path().join("target/scheduler-marker")).unwrap(),
        b"warm"
    );
    std::fs::write(project.path().join("target/scheduler-marker"), b"local").unwrap();
    let repeated_import = cargo_cache_command()
        .current_dir(project.path())
        .args(["cache", "import"])
        .arg(&archive)
        .env("TUIST_CARGO_CACHE_DIR", destination_store.path())
        .env("TUIST_CARGO_CACHE_TARGET_ROOT", destination_targets.path())
        .output()
        .unwrap();
    assert!(repeated_import.status.success());
    assert_eq!(
        std::fs::read(project.path().join("target/scheduler-marker")).unwrap(),
        b"local",
        "import must not replace an existing non-empty target"
    );
    let (_, cargo_stderr) = cargo_with(
        project.path(),
        destination_store.path(),
        &reports.path().join("restored.json"),
        &["build", "--offline", "--verbose"],
        &[
            (
                "TUIST_CARGO_CACHE_TARGET_ROOT",
                destination_targets.path().to_str().unwrap(),
            ),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ],
    );
    assert!(
        !cargo_stderr.contains("Compiling fixture"),
        "Cargo should accept the restored target as fresh: {}",
        cargo_stderr
    );

    let equivalent_project = tempfile::tempdir().unwrap();
    let equivalent_targets = tempfile::tempdir().unwrap();
    write_project(equivalent_project.path());
    let equivalent_import = cargo_cache_command()
        .current_dir(equivalent_project.path())
        .args(["cache", "import"])
        .arg(&archive)
        .env("TUIST_CARGO_CACHE_DIR", destination_store.path())
        .env("TUIST_CARGO_CACHE_TARGET_ROOT", equivalent_targets.path())
        .output()
        .unwrap();
    assert!(equivalent_import.status.success());
    assert_eq!(
        std::fs::read(equivalent_project.path().join("target/scheduler-marker")).unwrap(),
        b"warm",
        "a matching workspace signature should restore into another checkout"
    );
}

#[test]
fn incremental_is_opt_in_and_reaches_cargo() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    build(
        project.path(),
        store.path(),
        &reports.path().join("default.json"),
    );
    assert_eq!(
        incremental_sessions(project.path()),
        0,
        "the default build should still force CARGO_INCREMENTAL=0"
    );

    let (stats, _) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("incremental.json"),
        &[("TUIST_CARGO_CACHE_INCREMENTAL", "1")],
    );
    assert!(
        incremental_sessions(project.path()) > 0,
        "cargo should have compiled the member incrementally: {stats}"
    );
}

#[test]
fn workspace_policy_reaches_cargo() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());
    std::fs::write(
        project.path().join(".tuist_cargo_cache.toml"),
        "incremental = true\n",
    )
    .unwrap();

    let stats = build(
        project.path(),
        store.path(),
        &reports.path().join("workspace-policy.json"),
    );

    assert!(
        incremental_sessions(project.path()) > 0,
        "the checked-in workspace policy should reach cargo: {stats}"
    );
}

/// How many incremental sessions rustc left behind. Cargo creates the directory
/// either way, so its contents are the only evidence that anything used it.
fn incremental_sessions(project: &Path) -> usize {
    match std::fs::read_dir(project.join("target/debug/incremental")) {
        Ok(entries) => entries.count(),
        Err(_) => 0,
    }
}

/// Edit the fixture so it compiles to something new.
fn edit_project(project: &Path, revision: u32) {
    std::fs::write(
        project.join("src/lib.rs"),
        format!(
            "pub fn double(value: u32) -> u32 {{\n    value * 2 + {revision} - {revision}\n}}\n"
        ),
    )
    .unwrap();
}

/// Incremental state tuist_cargo_cache is keeping for churning units, as opposed to the
/// `incremental/` directory cargo drives itself.
///
/// Directories only: the churn records that decide when to create one live
/// beside them as files, and every compilation writes one of those whether or
/// not it ever goes hot.
fn learned_sessions(cache: &Path) -> usize {
    std::fs::read_dir(cache.join("incremental"))
        .into_iter()
        .flatten()
        .flatten()
        .filter(|checkout| checkout.file_name() != ".locks")
        .flat_map(|checkout| std::fs::read_dir(checkout.path()).into_iter().flatten())
        .flatten()
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_dir()))
        .count()
}

fn compiled_incrementally(stats: &serde_json::Value) -> u64 {
    // Its own field since report version 5: `compiler` groups compilations by
    // what their lookup did, and keeping private incremental state is not one
    // of those.
    stats["incremental_compilations"].as_u64().unwrap_or(0)
}

#[test]
fn eager_incremental_seeds_private_state_and_survives_a_fresh_target() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_dependent_project(project.path());
    let settings = [
        ("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1"),
        ("CARGO_INCREMENTAL", "0"),
    ];
    let seed = build_with(
        project.path(),
        store.path(),
        &reports.path().join("seed.json"),
        &settings,
    )
    .0;
    assert_eq!(compiled_incrementally(&seed), 2, "{seed}");
    assert_eq!(
        seed["stored_bytes"].as_u64(),
        Some(0),
        "private artifacts must not be published: {seed}"
    );
    let state = find_files(&store.path().join("incremental"), |path| {
        file_name_is(path, |name| name == "query-cache.bin")
    });
    assert_eq!(
        state.len(),
        2,
        "both workspace crates should seed rustc state: {state:?}"
    );
    wipe_target(project.path());
    assert!(
        state.iter().all(|path| path.is_file()),
        "Cargo target removal must preserve state"
    );
    std::fs::write(
        project.path().join("base/src/lib.rs"),
        "pub fn value() -> u32 { 21 }\n",
    )
    .unwrap();
    std::fs::write(
        project.path().join("above/src/main.rs"),
        "fn main() { assert_eq!(above::doubled(), 42); }\n",
    )
    .unwrap();
    let next = cargo_with(
        project.path(),
        store.path(),
        &reports.path().join("next.json"),
        &["run", "--offline", "-p", "above"],
        &settings,
    )
    .0;
    assert!(compiled_incrementally(&next) >= 2, "{next}");
    assert_eq!(next["stored_bytes"].as_u64(), Some(0), "{next}");
    wipe_target(project.path());
    let disabled = build_with(
        project.path(),
        store.path(),
        &reports.path().join("disabled.json"),
        &[("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "0")],
    )
    .0;
    assert_eq!(compiled_incrementally(&disabled), 0, "{disabled}");
    assert!(
        disabled["stored_bytes"].as_u64().unwrap() > 0,
        "disabling must restore shared publication: {disabled}"
    );
}

#[test]
fn eager_incremental_keeps_non_workspace_dependencies_shared() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let dependency = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let package = dependency
        .path()
        .join("registry/src/fixture/external-0.1.0");
    write_named_project(&package, "external");
    write_project(project.path());
    let manifest = project.path().join("Cargo.toml");
    let mut contents = std::fs::read_to_string(&manifest).unwrap();
    contents.push_str(&format!(
        "\n[dependencies]\nexternal = {{ path = {:?} }}\n",
        package.to_str().unwrap()
    ));
    std::fs::write(manifest, contents).unwrap();
    generate_lockfile(project.path());
    let settings = [
        ("GITHUB_ACTIONS", "true"),
        ("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "true"),
        ("TUIST_CARGO_CACHE_INCREMENTAL", "1"),
        ("CARGO_HOME", dependency.path().to_str().unwrap()),
    ];
    let seed = build_with(
        project.path(),
        store.path(),
        &reports.path().join("seed.json"),
        &settings,
    )
    .0;
    assert_eq!(compiled_incrementally(&seed), 1, "{seed}");
    assert!(seed["stored_bytes"].as_u64().unwrap() > 0, "{seed}");
    wipe_target(project.path());
    edit_project(project.path(), 1);
    let next = build_with(
        project.path(),
        store.path(),
        &reports.path().join("next.json"),
        &settings,
    )
    .0;
    assert_eq!(compiled_incrementally(&next), 1, "{next}");
    assert!(
        next["hits"].as_u64().unwrap_or(0) >= 1,
        "dependency should restore: {next}"
    );
}

#[test]
fn learned_private_dependents_reuse_state_after_the_target_is_removed() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_dependent_project(project.path());
    build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    for revision in 1..=2 {
        if revision == 2 {
            wipe_target(project.path());
        }
        std::fs::write(
            project.path().join("base/src/lib.rs"),
            format!("pub fn value() -> u32 {{ {revision} }}\n"),
        )
        .unwrap();
        let stats = build(
            project.path(),
            store.path(),
            &reports.path().join(format!("edit-{revision}.json")),
        );
        assert_eq!(
            compiled_incrementally(&stats),
            2,
            "revision {revision}: {stats}"
        );
        assert_eq!(stats["stored_bytes"].as_u64(), Some(0), "{stats}");
    }
}

#[test]
fn private_marker_failure_stops_the_build_before_compiling_unmarked_outputs() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());
    build_with(
        project.path(),
        store.path(),
        &reports.path().join("seed.json"),
        &[("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1")],
    );
    wipe_target(project.path());
    let markers = std::fs::read_dir(store.path().join("incremental"))
        .unwrap()
        .map(|entry| entry.unwrap().path().join("private"))
        .find(|path| path.is_dir())
        .unwrap();
    std::fs::remove_dir_all(&markers).unwrap();
    std::fs::write(&markers, "block marker directory creation").unwrap();
    let output = cargo_cache_command()
        .current_dir(project.path())
        .args(["build", "--offline"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .unwrap();
    assert!(
        !output.status.success(),
        "unmarked private compilation must fail: {output:?}"
    );
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("private artifacts could not be marked"),
        "{output:?}"
    );
    assert!(
        find_files(&project.path().join("target"), |path| path
            .extension()
            .is_some_and(|ext| ext == "rlib" || ext == "rmeta"))
        .is_empty()
    );
}

#[test]
fn verification_keeps_consumers_of_private_artifacts_out_of_the_shared_cache() {
    for verification in [
        "TUIST_CARGO_CACHE_VERIFY",
        "TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE",
    ] {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_dependent_project(project.path());
        let manifest = project.path().join("Cargo.toml");
        let contents = std::fs::read_to_string(&manifest).unwrap().replace(
            "members = [\"base\", \"above\"]",
            "members = [\"base\", \"above\", \"top\"]",
        );
        std::fs::write(manifest, contents).unwrap();
        std::fs::create_dir_all(project.path().join("top/src")).unwrap();
        std::fs::write(project.path().join("top/Cargo.toml"),
            "[package]\nname = \"top\"\nversion = \"0.1.0\"\nedition = \"2021\"\n[dependencies]\nabove = { path = \"../above\" }\n").unwrap();
        std::fs::write(
            project.path().join("top/src/lib.rs"),
            "pub fn value() -> u32 { above::doubled() }\n",
        )
        .unwrap();
        generate_lockfile(project.path());
        let seed = cargo_with(
            project.path(),
            store.path(),
            &reports.path().join("seed.json"),
            &["build", "--offline", "-p", "base"],
            &[("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1")],
        )
        .0;
        assert_eq!(compiled_incrementally(&seed), 1, "{seed}");
        assert_eq!(seed["stored_bytes"].as_u64(), Some(0), "{seed}");
        // Cargo retains the private base artifact. The selected consumers must
        // compile without incremental state, but must also remain private,
        // including the transitive consumer of the non-incremental middle unit.
        let checked = build_with(
            project.path(),
            store.path(),
            &reports.path().join("checked.json"),
            &[
                ("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1"),
                (
                    verification,
                    if verification == "TUIST_CARGO_CACHE_VERIFY" {
                        "1"
                    } else {
                        "100"
                    },
                ),
            ],
        )
        .0;
        assert_eq!(compiled_incrementally(&checked), 0, "{checked}");
        assert_eq!(
            checked["stored_bytes"].as_u64(),
            Some(0),
            "{verification}: {checked}"
        );
        assert_eq!(checked["hits"].as_u64(), Some(0), "{checked}");
    }
}

#[test]
fn nested_workspaces_keep_their_eager_policy_and_explicit_user_override() {
    for (outer_eager, user_override) in [
        (false, None),
        (true, None),
        (false, Some("0")),
        (true, Some("1")),
    ] {
        let store = tempfile::tempdir().unwrap();
        let outer = tempfile::tempdir().unwrap();
        let inner = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_named_project(outer.path(), "outer");
        write_named_project(inner.path(), "inner");
        std::fs::write(
            outer.path().join(".tuist_cargo_cache.toml"),
            format!("eager_incremental = {outer_eager}\n"),
        )
        .unwrap();
        std::fs::write(
            inner.path().join(".tuist_cargo_cache.toml"),
            format!("eager_incremental = {}\n", !outer_eager),
        )
        .unwrap();
        std::fs::write(outer.path().join("build.rs"), r#"
fn main() {
    let expected = std::env::var("TEST_EXPECTED_OVERRIDE").unwrap();
    assert_eq!(std::env::var("TUIST_CARGO_CACHE_EAGER_INCREMENTAL").ok(), if expected.is_empty() { None } else { Some(expected) });
    let output = std::process::Command::new(std::env::var_os("TEST_TUIST_CARGO_CACHE").unwrap())
        .current_dir(std::env::var_os("TEST_INNER").unwrap())
        .args(["build", "--offline"])
        .env("TUIST_CARGO_CACHE_STATS_REPORT", std::env::var_os("TEST_INNER_REPORT").unwrap())
        .output().unwrap();
    assert!(output.status.success(), "{output:?}");
}
"#).unwrap();
        let inner_report = reports.path().join("inner.json");
        let mut settings = vec![
            (
                "TEST_TUIST_CARGO_CACHE",
                env!("CARGO_BIN_EXE_tuist-cargo-cache-model"),
            ),
            ("TEST_INNER", inner.path().to_str().unwrap()),
            ("TEST_INNER_REPORT", inner_report.to_str().unwrap()),
            ("TEST_EXPECTED_OVERRIDE", user_override.unwrap_or("")),
        ];
        if let Some(value) = user_override {
            settings.push(("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", value));
        }
        build_with(
            outer.path(),
            store.path(),
            &reports.path().join("outer.json"),
            &settings,
        );
        let stats: serde_json::Value =
            serde_json::from_slice(&std::fs::read(inner_report).unwrap()).unwrap();
        let expected = user_override.map_or(!outer_eager, |value| value == "1");
        assert_eq!(
            compiled_incrementally(&stats),
            u64::from(expected),
            "outer={outer_eager}, override={user_override:?}: {stats}"
        );
    }
}

#[test]
fn eager_incremental_is_opt_in_and_yields_to_verification() {
    for settings in [
        vec![("CI", "1")],
        vec![],
        vec![
            ("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1"),
            ("TUIST_CARGO_CACHE_VERIFY", "1"),
        ],
        vec![
            ("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1"),
            ("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE", "100"),
        ],
        vec![
            ("CI", "1"),
            ("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1"),
            ("TUIST_CARGO_CACHE_VERIFY", "1"),
        ],
        vec![
            ("GITHUB_ACTIONS", "true"),
            ("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1"),
            ("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE", "100"),
        ],
    ] {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        let stats = build_with(
            project.path(),
            store.path(),
            &reports.path().join("build.json"),
            &settings,
        )
        .0;
        assert_eq!(compiled_incrementally(&stats), 0, "{settings:?}: {stats}");
    }
}

/// A workspace crate somebody is editing misses on every build no matter what
/// the cache does. On its first edit, it gets its own incremental
/// state -- which never reaches the store, because it describes one checkout's
/// edit history rather than its source.
#[test]
fn a_workspace_crate_is_incremental_on_its_first_edit_and_cargo_cache_clean_resets_it() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    let cold = build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    assert_eq!(
        compiled_incrementally(&cold),
        0,
        "a cold build should populate the shared cache: {cold}"
    );

    edit_project(project.path(), 1);
    let stats = build(
        project.path(),
        store.path(),
        &reports.path().join("edit-1.json"),
    );

    assert!(
        compiled_incrementally(&stats) > 0,
        "the edited crate should have compiled incrementally by now: {stats}"
    );
    assert!(
        learned_sessions(store.path()) > 0,
        "it should have left incremental state behind: {stats}"
    );
    assert_eq!(
        stats["stored_bytes"].as_u64(),
        Some(0),
        "an incremental artifact must never be published: {stats}"
    );

    let cleaned = cargo_cache_command()
        .current_dir(project.path())
        .arg("clean")
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("tuist_cargo_cache clean should run");
    assert!(
        cleaned.status.success(),
        "clean failed: {}",
        String::from_utf8_lossy(&cleaned.stderr)
    );

    edit_project(project.path(), 2);
    let after_clean = build(
        project.path(),
        store.path(),
        &reports.path().join("edit-after-clean.json"),
    );
    assert_eq!(
        compiled_incrementally(&after_clean),
        0,
        "tuist_cargo_cache clean should remove learned incremental state: {after_clean}"
    );
}

/// A native search directory the cache cannot describe, such as a system library
/// directory whose symlinks lead into other trees, makes a compilation
/// uncacheable. It says nothing about whether the crate's sources are being
/// edited, so the edit still has to switch the crate to private incremental state.
#[cfg(unix)]
fn assert_incremental_on_first_edit_despite_native_dir(prepare: impl FnOnce(&Path, &Path)) {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let native = tempfile::tempdir().unwrap();
    let elsewhere = tempfile::tempdir().unwrap();
    write_project(project.path());
    prepare(native.path(), elsewhere.path());
    std::fs::write(
        project.path().join("build.rs"),
        format!(
            "fn main() {{\n    println!(\"cargo:rerun-if-changed=build.rs\");\n    println!(\"cargo:rustc-link-search=native={}\");\n}}\n",
            native.path().display()
        ),
    )
    .unwrap();

    let cold = build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    assert_eq!(
        compiled_incrementally(&cold),
        0,
        "a first build has nothing to be incremental on: {cold}"
    );

    edit_project(project.path(), 1);
    let stats = build(
        project.path(),
        store.path(),
        &reports.path().join("edit-1.json"),
    );

    assert!(
        compiled_incrementally(&stats) > 0,
        "the edited crate should have compiled incrementally despite its search path: {stats}"
    );
    assert!(
        learned_sessions(store.path()) > 0,
        "it should have left incremental state behind: {stats}"
    );
    assert_eq!(
        stats["stored_bytes"].as_u64(),
        Some(0),
        "an incremental artifact must never be published: {stats}"
    );
}

#[cfg(unix)]
#[test]
fn a_crate_with_an_unshareable_native_search_path_is_incremental_on_its_first_edit() {
    assert_incremental_on_first_edit_despite_native_dir(|native, elsewhere| {
        std::fs::write(elsewhere.join("libextra.so.1"), b"not a library").unwrap();
        std::os::unix::fs::symlink(elsewhere.join("libextra.so.1"), native.join("libextra.so"))
            .unwrap();
    });
}

/// rustc never reads a link it is not asked to resolve, so a dangling one in the
/// search directory does not fail the build. It only keeps the directory from
/// being scanned.
#[cfg(unix)]
#[test]
fn a_dangling_link_in_a_native_search_path_does_not_stop_the_first_edit_going_incremental() {
    assert_incremental_on_first_edit_despite_native_dir(|native, elsewhere| {
        std::os::unix::fs::symlink(elsewhere.join("missing"), native.join("libgone.so")).unwrap();
    });
}

/// The same evidence that turns it on turns it off: once the content stops
/// moving, the unit compiles normally again and rejoins the shared cache.
#[test]
fn a_settled_crate_publishes_again() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    for revision in 1..=4 {
        edit_project(project.path(), revision);
        build(
            project.path(),
            store.path(),
            &reports.path().join(format!("edit-{revision}.json")),
        );
    }

    // Same content as the last build, so the key it recorded is the key this
    // compilation has: the churn is over.
    wipe_target(project.path());
    let settled = build(
        project.path(),
        store.path(),
        &reports.path().join("settled.json"),
    );
    assert_eq!(
        compiled_incrementally(&settled),
        0,
        "unchanged content should compile normally: {settled}"
    );
    assert!(
        settled["stored_bytes"].as_u64().unwrap_or(0) > 0,
        "and it should be published: {settled}"
    );

    wipe_target(project.path());
    let warm = build(
        project.path(),
        store.path(),
        &reports.path().join("warm.json"),
    );
    assert!(
        warm["hits"].as_u64().unwrap_or(0) > 0,
        "so a later build can restore it: {warm}"
    );
}

/// A compilation that failed left nothing behind to compare against, so the
/// retry that follows -- with nothing edited in between -- must not read as a
/// crate that had settled and drop it back to compiling from scratch.
#[test]
fn a_failed_build_does_not_cost_the_streak() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    for revision in 1..=3 {
        edit_project(project.path(), revision);
        build(
            project.path(),
            store.path(),
            &reports.path().join(format!("edit-{revision}.json")),
        );
    }

    // Break it, then retry the same broken source twice over.
    std::fs::write(project.path().join("src/lib.rs"), "fn broken( {\n").unwrap();
    for attempt in 0..2 {
        let failed = cargo_cache_command()
            .current_dir(project.path())
            .args(["build", "--offline"])
            .env("TUIST_CARGO_CACHE_DIR", store.path())
            .env_remove("CARGO_TARGET_DIR")
            .env_remove("TUIST_CARGO_CACHE_INCREMENTAL")
            .env_remove("CARGO_INCREMENTAL")
            .env_remove("CI")
            .env_remove("GITHUB_ACTIONS")
            .output()
            .expect("tuist_cargo_cache should run");
        assert!(!failed.status.success(), "attempt {attempt} should fail");
    }

    // One more real edit is all it should take to go hot.
    edit_project(project.path(), 4);
    let stats = build(
        project.path(),
        store.path(),
        &reports.path().join("recovered.json"),
    );

    assert!(
        compiled_incrementally(&stats) > 0,
        "the failures should not have reset what the edits established: {stats}"
    );
}

/// A fresh runner has no incremental state to reuse, so the trade is all cost.
#[test]
fn churn_earns_nothing_in_ci() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    let mut stats = build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    for revision in 1..=4 {
        edit_project(project.path(), revision);
        stats = build_with(
            project.path(),
            store.path(),
            &reports.path().join(format!("edit-{revision}.json")),
            &[("CI", "true")],
        )
        .0;
    }

    assert_eq!(
        compiled_incrementally(&stats),
        0,
        "CI should have compiled every edit normally: {stats}"
    );
}

/// A crate's action key hashes the artifacts it links against. Once the crate
/// below it has taken private incremental state, no other checkout can hold
/// that artifact, so publishing the crate above would pay for a full
/// compilation and store a result nothing can restore. It takes private state
/// too, and the whole cone publishes again once the edited crate settles.
#[test]
fn editing_one_crate_takes_its_dependents_private_too() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_dependent_project(project.path());

    let mut stats = build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    for revision in 1..=5 {
        std::fs::write(
            project.path().join("base/src/lib.rs"),
            format!("pub fn value() -> u32 {{ {revision} }}\n"),
        )
        .unwrap();
        stats = build(
            project.path(),
            store.path(),
            &reports.path().join(format!("edit-{revision}.json")),
        );
    }

    assert_eq!(
        compiled_incrementally(&stats),
        2,
        "the edited crate and the crate linking it should both compile incrementally: {stats}"
    );
    assert_eq!(
        stats["stored_bytes"].as_u64(),
        Some(0),
        "a result keyed on a private artifact cannot be restored anywhere, so nothing should publish: {stats}"
    );
    assert_eq!(
        stats["lookups"].as_u64(),
        Some(0),
        "neither crate can hit a shared action, so neither should look one up: {stats}"
    );

    // Unchanged sources after a wiped target are not churn, above or below:
    // the edited crate republishes, and the crate above it, now linking a
    // published artifact, publishes again too.
    let cleaned = cargo_cache_command()
        .current_dir(project.path())
        .arg("clean")
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("tuist_cargo_cache clean should run");
    assert!(
        cleaned.status.success(),
        "clean failed: {}",
        String::from_utf8_lossy(&cleaned.stderr)
    );
    let settled = build(
        project.path(),
        store.path(),
        &reports.path().join("settled.json"),
    );
    assert_eq!(
        compiled_incrementally(&settled),
        0,
        "settled sources should compile normally again: {settled}"
    );
    assert!(
        settled["stored_bytes"].as_u64().unwrap_or(0) > 0,
        "a settled cone should publish again: {settled}"
    );
}

#[test]
fn learned_incremental_can_be_turned_off() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    let mut stats = build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    for revision in 1..=4 {
        edit_project(project.path(), revision);
        stats = build_with(
            project.path(),
            store.path(),
            &reports.path().join(format!("edit-{revision}.json")),
            &[("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0")],
        )
        .0;
    }

    assert_eq!(
        compiled_incrementally(&stats),
        0,
        "the setting should have kept every edit normal: {stats}"
    );
}

#[test]
fn restores_a_wiped_target_directory_from_the_store() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    let cold = build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    assert!(
        cold["compiler"]["unconsulted"]["duration_ns"]
            .as_u64()
            .is_some_and(|duration| duration > 0),
        "the cold build should report time spent compiling: {cold}"
    );
    assert!(
        cold["slow_compilations"]
            .as_array()
            .is_some_and(|crates| !crates.is_empty()),
        "the cold build should identify its slowest uncached crates: {cold}"
    );
    assert_eq!(count(&cold, "hits"), 0, "a cold build cannot hit");
    assert!(
        count(&cold, "stored_bytes") > 0,
        "a cold build should publish its outputs: {cold}"
    );
    // A cold target directory leaves nothing to derive an action key from, so
    // these compilations run without the cache ever being consulted. Reported
    // apart from misses: counting them as zero of both says the cache was asked
    // and found nothing, which is not what happened.
    assert_eq!(
        count(&cold, "misses"),
        0,
        "a cold build looks nothing up, so it cannot miss: {cold}"
    );
    assert!(
        count(&cold, "unconsulted") > 0,
        "a cold build should report the compilations it had no key for: {cold}"
    );

    // Load-bearing, not cleanup: the wipe is what forces the warm build to
    // restore from the store. Left in place, cargo would find the cold build's
    // outputs and the test would pass without exercising the cache at all.
    wipe_target(project.path());

    let warm = build(
        project.path(),
        store.path(),
        &reports.path().join("warm.json"),
    );
    assert!(
        count(&warm, "hits") > 0,
        "the rebuilt target directory should be restored: {warm}"
    );
    // A hit that never lands on disk is still a broken restore, so check the
    // artifact itself rather than trusting the counter.
    assert!(
        project.path().join("target/debug/libfixture.rlib").exists(),
        "the restored artifact should be materialized: {warm}"
    );
    assert_eq!(
        count(&warm, "compiler_invocations_avoided"),
        count(&warm, "hits")
    );
    assert!(
        count(&warm, "estimated_compiler_duration_avoided_ns") > 0,
        "a warm build should report the compiler time recorded by its cold build: {warm}"
    );
}

#[test]
fn restores_predictions_across_equivalent_cargo_commands() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    wipe_target(project.path());

    let warm = cargo_with(
        project.path(),
        store.path(),
        &reports.path().join("warm.json"),
        &["build", "--offline", "--workspace"],
        &[],
    )
    .0;

    assert!(
        count(&warm, "hits") > 0,
        "adding a Cargo selector should not discard learned predictions: {warm}"
    );
    assert_eq!(
        count(&warm, "unconsulted"),
        0,
        "equivalent compilations should all have predictions: {warm}"
    );
}

#[test]
fn failed_prediction_lookups_are_timed_as_misses() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());
    build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );
    assert!(corrupt_action_results(store.path()) > 0);
    wipe_target(project.path());

    let rebuilt = build(
        project.path(),
        store.path(),
        &reports.path().join("rebuilt.json"),
    );

    assert!(count(&rebuilt, "lookups") > 0, "{rebuilt}");
    assert!(
        rebuilt["compiler"]["miss"]["invocations"]
            .as_u64()
            .is_some_and(|invocations| invocations > 0),
        "{rebuilt}"
    );
    assert_eq!(count(&rebuilt, "unconsulted"), 0, "{rebuilt}");
}

#[test]
fn a_second_checkout_starts_warm() {
    let store = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(first.path());
    write_project(second.path());

    build(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    let warm = build(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
    );

    assert!(
        count(&warm, "hits") > 0,
        "a checkout at another path should reuse the first build: {warm}"
    );

    edit_project(second.path(), 1);
    let edited = build(
        second.path(),
        store.path(),
        &reports.path().join("second-edit.json"),
    );
    assert!(
        compiled_incrementally(&edited) > 0,
        "a warm checkout should recognize its first edit immediately: {edited}"
    );
}

#[test]
fn a_release_marker_does_not_disable_the_cache() {
    let store = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(first.path());
    write_project(second.path());

    build_with(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
        &[("TUIST_CARGO_CACHE_RELEASE", "1")],
    );
    let (warm, _) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &[("TUIST_CARGO_CACHE_RELEASE", "1")],
    );

    assert!(
        count(&warm, "hits") > 0,
        "a release-marked build should still reuse cached output: {warm}"
    );
}

/// How a fixture's library uses its build script's output.
#[derive(Clone, Copy)]
enum Generated {
    /// A cfg only, so the compilation never reads `OUT_DIR`.
    Cfg,
    /// Includes the generated file. `OUT_DIR` becomes an input, but only rustc
    /// records the path, so `--remap-path-prefix` can take it back out.
    Include,
    /// Keeps `OUT_DIR` in a string constant. That lands in the artifact itself,
    /// where no remapping reaches it.
    Text,
    /// Includes generated code into which the build script wrote the
    /// checkout's own path. The generated sources differ per checkout, so
    /// nothing about them can be shared.
    Divergent,
    /// A crate that includes generated code, and a second crate depending on
    /// it. The first is keyed to its checkout; the second is what the remapping
    /// is for.
    Dependent,
}

/// Write a build-script fixture that leaves an observable execution count and
/// a nested output tree. The count is deliberately outside `OUT_DIR`, so a
/// restore cannot counterfeit an execution.
fn write_execution_cached_project(directory: &Path, declares_inputs: bool) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"execution-cache-fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(directory.join("input.txt"), "first\n").unwrap();
    let declaration = if declares_inputs {
        "println!(\"cargo:rerun-if-changed=input.txt\");\n    println!(\"cargo:rerun-if-env-changed=EXECUTION_CACHE_MODE\");"
    } else {
        "println!(\"cargo:rustc-cfg=generated\");"
    };
    std::fs::write(
        directory.join("build.rs"),
        format!(
            "use std::{{env, fs, path::PathBuf}};\n\
             fn main() {{\n\
                 let count = PathBuf::from(\"runs\");\n\
                 let runs = fs::read_to_string(&count).ok().and_then(|s| s.parse::<u32>().ok()).unwrap_or(0) + 1;\n\
                 fs::write(count, runs.to_string()).unwrap();\n\
                 let input = fs::read_to_string(\"input.txt\").unwrap();\n\
                 let out = PathBuf::from(env::var_os(\"OUT_DIR\").unwrap());\n\
                 fs::create_dir_all(out.join(\"nested\")).unwrap();\n\
                 fs::write(out.join(\"generated.rs\"), format!(\"pub const VALUE: &str = {{:?}};\\n\", input)).unwrap();\n\
                 fs::write(out.join(\"nested/header.h\"), input).unwrap();\n\
                 println!(\"cargo:rustc-env=MANIFEST_COPY={{}}\", env::var(\"CARGO_MANIFEST_DIR\").unwrap());\n\
                 {declaration}\n\
             }}\n"
        ),
    )
    .unwrap();
    std::fs::write(
        directory.join("src/lib.rs"),
        "include!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\n\
         pub const MANIFEST_COPY: &str = env!(\"MANIFEST_COPY\");\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// Write a portable binary with a build script whose execution is observable.
/// Unlike `write_execution_cached_project`, this fixture does not report an
/// absolute checkout path, so all three actions can restore in a fresh CI job.
fn write_exported_build_script_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"exported-build-script-fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(directory.join("input.txt"), "first\n").unwrap();
    std::fs::write(
        directory.join("build.rs"),
        "use std::fs;\n\
         fn main() {\n\
             let runs = fs::read_to_string(\"runs\").ok().and_then(|runs| runs.parse::<u32>().ok()).unwrap_or(0) + 1;\n\
             fs::write(\"runs\", runs.to_string()).unwrap();\n\
             println!(\"cargo:rerun-if-changed=input.txt\");\n\
             println!(\"cargo:rustc-cfg=from_build_script\");\n\
         }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("src/main.rs"),
        "fn main() { println!(\"{}\", cfg!(from_build_script)); }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// Write a build script with a Rust build-dependency. Cargo compares the
/// build-script executable's mtime with that dependency when checking whether
/// the compilation is fresh.
fn write_build_dependent_script_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::create_dir_all(directory.join("helper/src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"build-dependent-script\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[build-dependencies]\nhelper = { path = \"helper\" }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("helper/Cargo.toml"),
        "[package]\nname = \"helper\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("helper/src/lib.rs"),
        "pub fn emit() { println!(\"cargo:rerun-if-changed=build.rs\"); }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("build.rs"),
        "fn main() { helper::emit(); }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("src/lib.rs"),
        "pub fn value() -> u32 { 1 }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

#[test]
fn build_script_shim_does_not_redirty_its_compilation() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_build_dependent_script_project(project.path());

    build(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    let helper = find_files(&project.path().join("target/debug"), |path| {
        file_name_is(path, |name| {
            name.starts_with("libhelper-") && name.ends_with(".rlib")
        })
    })
    .into_iter()
    .next()
    .expect("the build dependency should have an rlib");
    // rustc links `build_script_build-<hash>` before Cargo 1.100 and an
    // unhashed `build_script_build` from 1.100.
    let build_script = find_files(&project.path().join("target/debug/build"), |path| {
        file_name_is(path, |name| {
            (name == format!("build_script_build{}", std::env::consts::EXE_SUFFIX)
                || name.starts_with("build_script_build-"))
                && !name.ends_with(".d")
                && !name.ends_with(".pdb")
                && !name.contains(".tuist_cargo_cache-real")
        })
    })
    .into_iter()
    .next()
    .expect("the compiled build script should exist");

    #[cfg(unix)]
    {
        assert!(
            build_script.metadata().unwrap().len() < 1024,
            "a build-script path should contain the compact launcher"
        );
        let pinned = project
            .path()
            .join("target/debug/.tuist_cargo_cache-build-script-shims");
        let identities = pinned
            .read_dir()
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(
            identities.len(),
            1,
            "one tuist_cargo_cache identity should serve the profile"
        );
        let binaries = identities[0]
            .path()
            .read_dir()
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(
            binaries.len(),
            1,
            "the identity should pin one tuist_cargo_cache binary"
        );
        assert_ne!(
            binaries[0].metadata().unwrap().permissions().mode() & 0o100,
            0,
            "the pinned tuist_cargo_cache binary should be executable"
        );
    }

    let build_script_mtime = build_script.metadata().unwrap().modified().unwrap();
    filetime::set_file_mtime(
        &helper,
        filetime::FileTime::from_system_time(
            build_script_mtime + std::time::Duration::from_secs(4),
        ),
    )
    .unwrap();
    assert!(
        helper.metadata().unwrap().modified().unwrap() > build_script_mtime,
        "the fixture dependency must be newer than the compiled build script"
    );
    let helper_mtime = helper.metadata().unwrap().modified().unwrap();
    while std::time::SystemTime::now() <= helper_mtime {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let repaired = build(
        project.path(),
        store.path(),
        &reports.path().join("repaired.json"),
    );
    assert!(
        count(&repaired, "hits") > 0,
        "the newer dependency should make Cargo invoke cached work: {repaired}"
    );

    let noop = build(
        project.path(),
        store.path(),
        &reports.path().join("noop.json"),
    );
    assert_eq!(
        count(&noop, "hits"),
        0,
        "Cargo should not invoke the compiler or build script again: {noop}"
    );
    assert_eq!(
        count(&noop, "misses"),
        0,
        "Cargo should consider every target fresh: {noop}"
    );
}

/// Write a fixture that relies on Cargo's implicit package-wide build-script
/// input. Its execution log lives outside the package so observing a run does
/// not itself invalidate that input.
fn write_default_input_project(directory: &Path, execution_log: &Path) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"default-input-fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(directory.join("input.txt"), "first\n").unwrap();
    let build_script =
        "use std::{env, fs, path::PathBuf};\n\
         fn main() {\n\
             let log = PathBuf::from($EXECUTION_LOG);\n\
             let mut runs = fs::read_to_string(&log).unwrap_or_default();\n\
             runs.push_str(\"run\\n\");\n\
             fs::write(log, runs).unwrap();\n\
             let input = fs::read_to_string(\"input.txt\").unwrap();\n\
             let out = PathBuf::from(env::var_os(\"OUT_DIR\").unwrap());\n\
             fs::write(out.join(\"generated.rs\"), format!(\"pub const VALUE: &str = {:?};\\n\", input)).unwrap();\n\
         }\n"
            .replace(
                "$EXECUTION_LOG",
                &format!("{:?}", execution_log.to_str().unwrap()),
            );
    std::fs::write(directory.join("build.rs"), build_script).unwrap();
    std::fs::write(
        directory.join("src/lib.rs"),
        "include!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

#[test]
fn build_script_execution_and_out_dir_restore_across_checkouts() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_execution_cached_project(first.path(), true);
    write_execution_cached_project(second.path(), true);

    let no_link_cache = [("TUIST_CARGO_CACHE_CACHE_LINKS", "0")];
    build_with(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
        &no_link_cache,
    );
    let (warm, stderr) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &no_link_cache,
    );

    assert_eq!(
        std::fs::read_to_string(first.path().join("runs")).unwrap(),
        "1"
    );
    assert!(
        !second.path().join("runs").exists(),
        "the second checkout ran its build script instead of restoring it: {warm}\n{stderr}"
    );
    let build = second.path().join("target/debug/build");
    let header = find_files(&build, |path| path.ends_with("out/nested/header.h"))
        .into_iter()
        .next()
        .expect("nested OUT_DIR output should be restored");
    assert_eq!(std::fs::read_to_string(header).unwrap(), "first\n");
    // Cargo records a run's stdout as `build/<pkg>-<hash>/output` before 1.100
    // and as `build/<pkg>/<hash>/run/stdout` from 1.100.
    let replayed = find_files(&build, |path| {
        path.ends_with("run/stdout")
            || (file_name_is(path, |name| name == "output")
                && path.ancestors().nth(2) == Some(build.as_path()))
    })
    .into_iter()
    .next()
    .map(|path| std::fs::read_to_string(path).unwrap())
    .expect("Cargo should retain the replayed build-script directives");
    assert!(
        replayed.contains(second.path().to_string_lossy().as_ref()),
        "replayed directives should name the restoring checkout: {replayed}"
    );
    assert!(
        !replayed.contains(first.path().to_string_lossy().as_ref()),
        "replayed directives retained the publishing checkout: {replayed}"
    );
    assert!(count(&warm, "hits") >= 1, "build script should hit: {warm}");
}

/// A script that writes into an input it declared saw a different tree than the
/// one its result is keyed to: the key is taken from the tree the run left. A
/// restore of that result would hand back output the script no longer produces
/// from that tree, so the run is not recorded and the next build runs again.
#[test]
fn a_build_script_that_writes_into_its_declared_inputs_is_not_recorded() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(project.path().join("src")).unwrap();
    std::fs::write(
        project.path().join("Cargo.toml"),
        "[package]\nname = \"input-writer-fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(project.path().join("src/lib.rs"), "").unwrap();
    std::fs::write(
        project.path().join("build.rs"),
        "use std::{env, fs, path::{Path, PathBuf}};\n\
         fn main() {\n\
             let seen = if Path::new(\"data\").exists() { \"present\" } else { \"absent\" };\n\
             fs::create_dir_all(\"data\").unwrap();\n\
             let out = PathBuf::from(env::var_os(\"OUT_DIR\").unwrap());\n\
             fs::write(out.join(\"seen\"), seen).unwrap();\n\
             println!(\"cargo:rerun-if-changed=data\");\n\
         }\n",
    )
    .unwrap();
    generate_lockfile(project.path());

    let seen = |project: &Path| {
        let found = find_files(&project.join("target/debug/build"), |path| {
            path.ends_with("out/seen")
        });
        std::fs::read_to_string(found.into_iter().next().expect("the script's output")).unwrap()
    };
    let no_link_cache = [("TUIST_CARGO_CACHE_CACHE_LINKS", "0")];
    build_with(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
        &no_link_cache,
    );
    assert_eq!(seen(project.path()), "absent");

    // The same tree, now holding what the first run created, built from an
    // empty target directory. Only a run can say what the script does here.
    std::fs::remove_dir_all(project.path().join("target")).unwrap();
    let (stats, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("second.json"),
        &no_link_cache,
    );
    assert_eq!(
        seen(project.path()),
        "present",
        "a result recorded from the run that created `data` was restored: {stats}\n{stderr}"
    );
}

/// Deleting a declared input is writing into it: the script ran while the file
/// existed, but the result would be keyed to the tree where it is gone.
#[test]
fn a_build_script_that_deletes_a_declared_input_is_not_recorded() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(project.path().join("src")).unwrap();
    std::fs::write(
        project.path().join("Cargo.toml"),
        "[package]\nname = \"input-deleter-fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(project.path().join("src/lib.rs"), "").unwrap();
    std::fs::write(project.path().join("flag"), "").unwrap();
    std::fs::write(
        project.path().join("build.rs"),
        "use std::{env, fs, path::{Path, PathBuf}};\n\
         fn main() {\n\
             let seen = if Path::new(\"flag\").exists() { \"present\" } else { \"absent\" };\n\
             let _ = fs::remove_file(\"flag\");\n\
             let out = PathBuf::from(env::var_os(\"OUT_DIR\").unwrap());\n\
             fs::write(out.join(\"seen\"), seen).unwrap();\n\
             println!(\"cargo:rerun-if-changed=flag\");\n\
         }\n",
    )
    .unwrap();
    generate_lockfile(project.path());

    let seen = |project: &Path| {
        let found = find_files(&project.join("target/debug/build"), |path| {
            path.ends_with("out/seen")
        });
        std::fs::read_to_string(found.into_iter().next().expect("the script's output")).unwrap()
    };
    let no_link_cache = [("TUIST_CARGO_CACHE_CACHE_LINKS", "0")];
    build_with(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
        &no_link_cache,
    );
    assert_eq!(seen(project.path()), "present");

    // `flag` is gone now. Only a run can say what the script does without it.
    std::fs::remove_dir_all(project.path().join("target")).unwrap();
    let (stats, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("second.json"),
        &no_link_cache,
    );
    assert_eq!(
        seen(project.path()),
        "absent",
        "a result recorded from the run that deleted `flag` was restored: {stats}\n{stderr}"
    );
}

/// A CI cache export must include a build script that this run restored. The
/// next job starts with an empty store and target directory, so it can only
/// restore the script when the previous job re-recorded its prediction.
#[test]
fn a_restored_build_script_stays_in_every_ci_cache_export() {
    let reports = tempfile::tempdir().unwrap();
    let mut previous_archive = None;

    for round in 1..=4 {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        write_exported_build_script_project(project.path());

        if let Some(archive) = previous_archive.as_ref() {
            let import = cargo_cache_command()
                // Import outside the checkout, as a CI cache restore does:
                // the following build must have an empty target directory.
                .current_dir(reports.path())
                .args(["cache", "import"])
                .arg(archive)
                .env("TUIST_CARGO_CACHE_DIR", store.path())
                .output()
                .unwrap();
            assert!(
                import.status.success(),
                "round {round} import failed: {}",
                String::from_utf8_lossy(&import.stderr)
            );
        }

        let group = format!("github-run-{round}/build");
        let settings = [
            (
                tuist_cargo_cache::session::CACHE_EXPORT_GROUP_ENV,
                group.as_str(),
            ),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
        ];
        let (stats, stderr) = build_with(
            project.path(),
            store.path(),
            &reports.path().join(format!("round-{round}.json")),
            &settings,
        );
        if round == 1 {
            assert_eq!(
                std::fs::read_to_string(project.path().join("runs")).unwrap(),
                "1"
            );
        } else {
            assert!(
                !project.path().join("runs").exists(),
                "round {round} ran the build script instead of restoring it: {stats}\n{stderr}"
            );
            assert_eq!(
                count(&stats, "misses"),
                0,
                "round {round} should restore every cached action: {stats}"
            );
            assert_eq!(
                count(&stats, "hits"),
                3,
                "round {round} should restore the build script and both Rust actions: {stats}"
            );
        }

        let archive = reports.path().join(format!("round-{round}.tar"));
        let export = cargo_cache_command()
            .current_dir(project.path())
            .args(["cache", "export", "--group", &group])
            .arg(&archive)
            .env("TUIST_CARGO_CACHE_DIR", store.path())
            .output()
            .unwrap();
        assert!(
            export.status.success(),
            "round {round} export failed: {}",
            String::from_utf8_lossy(&export.stderr)
        );
        assert!(
            String::from_utf8_lossy(&export.stdout).contains("exported 3 actions"),
            "round {round} export omitted a restored action: {}",
            String::from_utf8_lossy(&export.stdout)
        );
        previous_archive = Some(archive);
    }
}

/// Move the fixture's build script to `builder/main.rs`, as aws-lc-sys does.
/// Cargo then compiles it as `build_script_main` and runs `build-script-main`.
fn rename_build_script(directory: &Path) {
    std::fs::create_dir_all(directory.join("builder")).unwrap();
    std::fs::rename(
        directory.join("build.rs"),
        directory.join("builder/main.rs"),
    )
    .unwrap();
    let manifest = directory.join("Cargo.toml");
    let contents = std::fs::read_to_string(&manifest).unwrap();
    std::fs::write(
        manifest,
        contents.replace(
            "edition = \"2021\"\n",
            "edition = \"2021\"\nbuild = \"builder/main.rs\"\n",
        ),
    )
    .unwrap();
}

#[test]
fn a_build_script_with_a_custom_path_restores_across_checkouts() {
    for (label, environment) in [
        ("linked", &[][..]),
        (
            "execution-only",
            &[("TUIST_CARGO_CACHE_CACHE_LINKS", "0")][..],
        ),
    ] {
        let store = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        for checkout in [first.path(), second.path()] {
            write_execution_cached_project(checkout, true);
            rename_build_script(checkout);
        }

        build_with(
            first.path(),
            store.path(),
            &reports.path().join("first.json"),
            environment,
        );
        let (warm, stderr) = build_with(
            second.path(),
            store.path(),
            &reports.path().join("second.json"),
            environment,
        );

        assert_eq!(
            std::fs::read_to_string(first.path().join("runs")).unwrap(),
            "1",
            "{label}"
        );
        assert!(
            !second.path().join("runs").exists(),
            "{label}: the second checkout ran builder/main.rs instead of restoring it: {warm}\n{stderr}"
        );
    }
}

#[test]
fn a_binary_target_named_like_a_build_script_still_runs() {
    // Cargo compiles a `[[bin]]` named `build-script-build` as crate
    // `build_script_build`, the name it gives `build.rs`. Only a real build
    // script may be replaced by the execution-cache launcher.
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(project.path().join("src")).unwrap();
    std::fs::write(
        project.path().join("Cargo.toml"),
        "[package]\nname = \"named-bin\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[[bin]]\nname = \"build-script-build\"\npath = \"src/main.rs\"\n",
    )
    .unwrap();
    std::fs::write(
        project.path().join("src/main.rs"),
        "fn main() { println!(\"ordinary binary\"); }\n",
    )
    .unwrap();
    generate_lockfile(project.path());
    build(
        project.path(),
        store.path(),
        &reports.path().join("build.json"),
    );

    let output = Command::new(project.path().join(format!(
        "target/debug/build-script-build{}",
        std::env::consts::EXE_SUFFIX
    )))
    .env_remove("TUIST_CARGO_CACHE_SOCKET")
    .output()
    .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&output.stdout), "ordinary binary\n");
}

#[test]
fn a_library_sharing_the_build_script_prefix_keeps_its_compilation_cache() {
    // Without native-link caching a build script takes an execution-only
    // path that never restores or publishes the compilation. A library whose
    // crate name merely starts with `build_script_` must not be sent there,
    // including one named exactly like Cargo's default build script.
    for package in ["build-script-helper", "build-script-build"] {
        a_library_named_like_a_build_script_restores(package);
    }
}

fn a_library_named_like_a_build_script_restores(package: &str) {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    for checkout in [first.path(), second.path()] {
        std::fs::create_dir_all(checkout.join("src")).unwrap();
        std::fs::write(
            checkout.join("Cargo.toml"),
            format!("[package]\nname = \"{package}\"\nversion = \"0.1.0\"\nedition = \"2021\"\n"),
        )
        .unwrap();
        std::fs::write(checkout.join("src/lib.rs"), "pub fn helper() {}\n").unwrap();
        generate_lockfile(checkout);
    }

    let no_link_cache = [("TUIST_CARGO_CACHE_CACHE_LINKS", "0")];
    build_with(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
        &no_link_cache,
    );
    let (warm, stderr) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &no_link_cache,
    );

    assert_eq!(
        count(&warm, "hits"),
        1,
        "{package} should restore like any library: {warm}\n{stderr}"
    );
}

/// A proc macro can enumerate files without recording any of them in rustc's
/// dep-info. Cargo relies on the package's build script to invalidate that
/// compilation, even when its directives and generated output stay unchanged.
fn write_untracked_macro_project(directory: &Path) {
    for subdirectory in ["app/src", "embedder/src"] {
        std::fs::create_dir_all(directory.join(subdirectory)).unwrap();
    }
    std::fs::write(
        directory.join("Cargo.toml"),
        "[workspace]\nmembers = [\"app\", \"embedder\"]\nresolver = \"2\"\n",
    )
    .unwrap();
    std::fs::write(directory.join("app/Cargo.toml"),
        "[package]\nname = \"app\"\nversion = \"0.1.0\"\nedition = \"2021\"\n[dependencies]\nembedder = { path = \"../embedder\" }\n").unwrap();
    std::fs::write(directory.join("embedder/Cargo.toml"),
        "[package]\nname = \"embedder\"\nversion = \"0.1.0\"\nedition = \"2021\"\n[lib]\nproc-macro = true\n").unwrap();
    std::fs::write(
        directory.join("app/build.rs"),
        r#"
fn main() {
    println!("cargo::rerun-if-changed=../dist");
    println!("cargo:rerun-if-env-changed=TUIST_CARGO_CACHE_TEST_EMBEDDED_MODE");
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    std::fs::write(out.join("generated.rs"), "pub const GENERATED: u32 = 0;").unwrap();
}
"#,
    )
    .unwrap();
    std::fs::write(directory.join("embedder/src/lib.rs"), r#"
#[proc_macro]
pub fn embed(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    let folder = std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap()).join("../dist");
    let value = match std::fs::read_dir(folder) {
        Err(_) => "missing".to_string(),
        Ok(entries) => {
            let mut files = entries.map(|entry| {
                let entry = entry.unwrap();
                format!("{}:{}", entry.file_name().to_string_lossy(), std::fs::read_to_string(entry.path()).unwrap())
            }).collect::<Vec<_>>();
            files.sort();
            files.join(",")
        }
    };
    let value = format!("{}{value}", std::env::var("TUIST_CARGO_CACHE_TEST_EMBEDDED_MODE").unwrap_or_default());
    format!("pub const VALUE: &str = {value:?};").parse().unwrap()
}
"#).unwrap();
    std::fs::write(
        directory.join("app/src/lib.rs"),
        "embedder::embed!();\ninclude!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("app/src/main.rs"),
        "fn main() { println!(\"{}\", app::VALUE); }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// Watching the package root must retain successful rustc outputs even when
/// compilation writes into a default or custom target directory inside it.
#[test]
fn build_script_watching_compiler_outputs_keeps_successful_results() {
    for custom_target in [false, true] {
        let store = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        write_project(project.path());
        std::fs::write(
            project.path().join("build.rs"),
            "fn main() { println!(\"cargo::rerun-if-changed=.\"); }\n",
        )
        .unwrap();
        let target = project
            .path()
            .join(if custom_target { "artifacts" } else { "target" });
        let target_name = target.to_str().unwrap();
        for run in ["first", "second"] {
            if run == "second" {
                std::fs::write(project.path().join("src/lib.rs"), "pub fn changed() {}\n").unwrap();
            }
            let (stats, stderr) = cargo_with(
                project.path(),
                store.path(),
                &reports.path().join(format!("{run}.json")),
                &["build", "--offline"],
                &[
                    ("TUIST_CARGO_CACHE_INCREMENTAL", "0"),
                    ("CARGO_TARGET_DIR", target_name),
                ],
            );
            assert!(target.join("debug/libfixture.rlib").is_file());
            assert!(
                stats["bypasses"]["build-script-input-overlaps-outputs"]
                    .as_u64()
                    .unwrap_or(0)
                    > 0,
                "overlap should have a specific bypass reason: {stats}\n{stderr}"
            );
            assert!(
                stats["bypasses"].get("other").is_none(),
                "{stats}\n{stderr}"
            );
            assert!(
                !stderr.contains("tuist_cargo_cache[warning]: rustc cache bypassed"),
                "{stderr}"
            );
        }
    }
}

#[test]
fn build_script_declared_directory_invalidates_macro_compilations() {
    for (release, execution) in [(false, "1"), (true, "1"), (false, "0")] {
        let store = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        write_untracked_macro_project(project.path());
        let arguments = if release {
            vec!["build", "--offline", "--release", "-p", "app"]
        } else {
            vec!["build", "--offline", "-p", "app"]
        };
        let profile = if release { "release" } else { "debug" };
        let check = |expected: &str, mode: &str| {
            cargo_with(
                project.path(),
                store.path(),
                &reports.path().join("build.json"),
                &arguments,
                &[
                    ("TUIST_CARGO_CACHE_INCREMENTAL", "0"),
                    ("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", execution),
                    ("TUIST_CARGO_CACHE_TEST_EMBEDDED_MODE", mode),
                ],
            );
            let output = Command::new(project.path().join(format!(
                "target/{profile}/app{}",
                std::env::consts::EXE_SUFFIX
            )))
            .output()
            .unwrap();
            assert!(output.status.success());
            assert_eq!(
                String::from_utf8(output.stdout).unwrap().trim(),
                expected,
                "the {profile} compile should observe the declared directory"
            );
        };
        check("missing", "");
        let dist = project.path().join("dist");
        std::fs::create_dir(&dist).unwrap();
        check("", "");
        std::fs::write(dist.join("index.html"), "hi").unwrap();
        check("index.html:hi", "");
        std::fs::write(dist.join("index.html"), "updated").unwrap();
        check("index.html:updated", "");
        std::fs::write(dist.join("other.html"), "other").unwrap();
        check("index.html:updated,other.html:other", "");
        std::fs::remove_file(dist.join("index.html")).unwrap();
        check("other.html:other", "");
        check("modeother.html:other", "mode");
        // With identical inputs, the package still restores in a new checkout
        // through prediction, without a local dep-info file to consult.
        let checkout = tempfile::tempdir().unwrap();
        write_untracked_macro_project(checkout.path());
        std::fs::create_dir(checkout.path().join("dist")).unwrap();
        std::fs::write(checkout.path().join("dist/other.html"), "other").unwrap();
        let (warm, stderr) = cargo_with(
            checkout.path(),
            store.path(),
            &reports.path().join("warm.json"),
            &arguments,
            &[
                ("TUIST_CARGO_CACHE_INCREMENTAL", "0"),
                ("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", execution),
                ("TUIST_CARGO_CACHE_TEST_EMBEDDED_MODE", ""),
            ],
        );
        assert!(
            count(&warm, "hits") >= 4,
            "unchanged compilations should restore in a new checkout: {warm}\n{stderr}"
        );
        let output = Command::new(checkout.path().join(format!(
            "target/{profile}/app{}",
            std::env::consts::EXE_SUFFIX
        )))
        .output()
        .unwrap();
        assert!(output.status.success());
        assert_eq!(
            String::from_utf8(output.stdout).unwrap().trim(),
            "other.html:other"
        );
    }
}

#[test]
fn changed_declared_input_executes_build_script_again() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_execution_cached_project(project.path(), true);
    build(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    std::fs::write(project.path().join("input.txt"), "second\n").unwrap();
    build(
        project.path(),
        store.path(),
        &reports.path().join("second.json"),
    );
    assert_eq!(
        std::fs::read_to_string(project.path().join("runs")).unwrap(),
        "2"
    );
}

#[test]
fn changed_declared_environment_executes_build_script_again() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_execution_cached_project(project.path(), true);
    build_with(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
        &[("EXECUTION_CACHE_MODE", "first")],
    );
    build_with(
        project.path(),
        store.path(),
        &reports.path().join("second.json"),
        &[("EXECUTION_CACHE_MODE", "second")],
    );
    assert_eq!(
        std::fs::read_to_string(project.path().join("runs")).unwrap(),
        "2"
    );
}

#[test]
fn build_script_without_declared_inputs_uses_the_package_tree() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let log = tempfile::NamedTempFile::new().unwrap();
    write_default_input_project(first.path(), log.path());
    write_default_input_project(second.path(), log.path());
    build(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    let (warm, _) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &[],
    );
    assert_eq!(std::fs::read_to_string(log.path()).unwrap(), "run\n");
    assert!(count(&warm, "hits") >= 1, "build script should hit: {warm}");
}

#[test]
fn a_changed_implicit_package_input_executes_the_build_script_again() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let log = tempfile::NamedTempFile::new().unwrap();
    write_default_input_project(project.path(), log.path());
    build(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    std::fs::write(project.path().join("input.txt"), "second\n").unwrap();
    build(
        project.path(),
        store.path(),
        &reports.path().join("second.json"),
    );
    assert_eq!(std::fs::read_to_string(log.path()).unwrap(), "run\nrun\n");
}

/// A build script that looks up its cached run and misses runs again, and
/// that run is the lookup's miss. Before, it was recorded as neither, so the
/// summary's hits and misses fell short of its lookups.
#[test]
fn a_build_script_that_misses_counts_its_run_as_the_miss() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_execution_cached_project(project.path(), true);
    build(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    // A declared input changes, so the prediction still names this run but
    // its action no longer matches the one that was stored.
    std::fs::write(project.path().join("input.txt"), "second\n").unwrap();
    let rebuilt = build(
        project.path(),
        store.path(),
        &reports.path().join("second.json"),
    );

    assert_eq!(
        std::fs::read_to_string(project.path().join("runs")).unwrap(),
        "2",
        "the changed input should run the build script again"
    );
    assert!(
        count(&rebuilt, "misses") >= 1,
        "the run should be a miss: {rebuilt}"
    );
    assert_eq!(
        count(&rebuilt, "lookups"),
        count(&rebuilt, "hits") + count(&rebuilt, "misses"),
        "every lookup should end as a hit or a miss: {rebuilt}"
    );
}

#[test]
fn build_script_execution_cache_can_be_turned_off() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_execution_cached_project(first.path(), true);
    write_execution_cached_project(second.path(), true);
    build(
        first.path(),
        store.path(),
        &reports.path().join("enabled.json"),
    );
    let disabled = [("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0")];
    build_with(
        second.path(),
        store.path(),
        &reports.path().join("disabled.json"),
        &disabled,
    );
    assert_eq!(
        std::fs::read_to_string(second.path().join("runs")).unwrap(),
        "1",
        "the opt-out should execute the build script instead of restoring it"
    );
}

#[test]
fn installed_build_script_wrapper_is_transparent_outside_an_cargo_cache_session() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_execution_cached_project(project.path(), true);
    build(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    std::fs::write(project.path().join("input.txt"), "second\n").unwrap();

    let status = Command::new(cargo())
        .current_dir(project.path())
        .args(["build", "--offline"])
        .env_remove("TUIST_CARGO_CACHE_SOCKET")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_TARGET_DIR")
        .status()
        .unwrap();
    assert!(status.success());
    assert_eq!(
        std::fs::read_to_string(project.path().join("runs")).unwrap(),
        "2"
    );
}

/// Write a fixture whose build script generates code, used as `generated` says.
#[test]
fn a_second_build_of_an_out_dir_reader_compiles_nothing() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_generated_project(project.path(), Generated::Include);

    build(
        project.path(),
        store.path(),
        &reports.path().join("first.json"),
    );
    let (again, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("again.json"),
        &[],
    );

    // Cargo announces every unit it runs rustc for, including one tuist_cargo_cache never
    // looks up, so its own output is the complete answer.
    assert!(
        !stderr.contains("Compiling "),
        "Cargo should find the OUT_DIR reader fresh: {stderr}"
    );
    assert_eq!(
        count(&again, "hits") + count(&again, "misses") + count(&again, "unconsulted"),
        0,
        "{again}"
    );
}

fn write_generated_project(directory: &Path, generated: Generated) {
    if matches!(generated, Generated::Dependent) {
        write_dependent_generated_project(directory);
        return;
    }
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n         [lints.rust]\nunexpected_cfgs = { level = \"allow\" }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("build.rs"),
        "use std::{env, fs, path::PathBuf};\n         fn main() {\n         \u{20}   let out = PathBuf::from(env::var(\"OUT_DIR\").unwrap());\n         \u{20}   fs::write(out.join(\"generated.rs\"), \"pub const VALUE: u32 = 7;\\n\").unwrap();\n         \u{20}   println!(\"cargo:rustc-cfg=generated\");\n         }\n",
    )
    .unwrap();
    let lib = match generated {
        // Handled above: this shape is a workspace, not one package.
        Generated::Dependent => unreachable!("the dependent fixture writes its own tree"),
        Generated::Cfg => "#[cfg(generated)]\npub fn value() -> u32 { 7 }\n".to_string(),
        Generated::Include => {
            "include!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\npub fn value() -> u32 { VALUE }\n"
                .to_string()
        }
        Generated::Text => {
            "include!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\n\
             pub const WHERE: &str = env!(\"OUT_DIR\");\n\
             pub fn value() -> u32 { VALUE }\n"
                .to_string()
        }
        Generated::Divergent => {
            std::fs::write(
                directory.join("build.rs"),
                "use std::{env, fs, path::PathBuf};\n         fn main() {\n         \u{20}   let out = PathBuf::from(env::var(\"OUT_DIR\").unwrap());\n         \u{20}   fs::write(out.join(\"generated.rs\"), format!(\"pub const VALUE: u32 = 7;\\npub const HERE: &str = {:?};\\n\", env::var(\"CARGO_MANIFEST_DIR\").unwrap())).unwrap();\n         \u{20}   println!(\"cargo:rustc-cfg=generated\");\n         }\n",
            )
            .unwrap();
            "include!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\npub fn value() -> u32 { VALUE }\n"
                .to_string()
        }
    };
    std::fs::write(directory.join("src/lib.rs"), lib).unwrap();
    generate_lockfile(directory);
}

/// Two crates: one reading `OUT_DIR`, and one that only depends on it.
///
/// The build script is the same one the single-crate fixtures use, so the inner
/// crate is keyed to its checkout. The outer crate reads nothing remapped, and
/// shares only if the artifact it consumes is identical in both checkouts.
fn write_dependent_generated_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("inner/src")).unwrap();
    std::fs::create_dir_all(directory.join("outer/src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[workspace]\nmembers = [\"inner\", \"outer\"]\nresolver = \"2\"\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("inner/Cargo.toml"),
        "[package]\nname = \"inner\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[lints.rust]\nunexpected_cfgs = { level = \"allow\" }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("inner/build.rs"),
        "use std::{env, fs, path::PathBuf};\n         fn main() {\n         \u{20}   let out = PathBuf::from(env::var(\"OUT_DIR\").unwrap());\n         \u{20}   fs::write(out.join(\"generated.rs\"), \"pub const VALUE: u32 = 7;\\n\").unwrap();\n         }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("inner/src/lib.rs"),
        "include!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\npub fn value() -> u32 { VALUE }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("outer/Cargo.toml"),
        "[package]\nname = \"outer\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\ninner = { path = \"../inner\" }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("outer/src/lib.rs"),
        "pub fn value() -> u32 { inner::value() }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// Turning sharing off changes nothing for a compilation that only uses a
/// build-script cfg, and leaves one that consumes `OUT_DIR` with the value
/// Cargo gave it: keyed to its checkout.
#[test]
fn out_dir_remapping_can_be_turned_off() {
    let disabled = [("TUIST_CARGO_CACHE_SHARE_OUT_DIR", "0")];
    for (generated, expect_hits) in [(Generated::Cfg, true), (Generated::Include, false)] {
        assert_eq!(
            two_checkouts_share(generated, &disabled),
            expect_hits,
            "the opt-out changed the wrong shape"
        );
    }
}

/// A compilation that reads `OUT_DIR` shares between checkouts whose generated
/// sources are the same bytes, whether or not it keeps the path.
///
/// Both checkouts hand rustc the same stable path, so a crate that keeps the
/// value, or derives anything from it, embeds the same thing in both; no claim
/// that the artifact ignores the path is needed, or made.
#[test]
fn a_compilation_that_reads_out_dir_shares_between_checkouts_with_the_same_generated_sources() {
    for generated in [Generated::Include, Generated::Text] {
        assert!(
            two_checkouts_share(generated, &[]),
            "a compilation reading identical generated sources was not shared"
        );
    }
}

/// Generated sources that differ between checkouts are different inputs, and
/// the compilation that reads them is keyed to its own.
#[test]
fn a_compilation_reading_divergent_generated_sources_is_not_shared() {
    assert!(
        !two_checkouts_share(Generated::Divergent, &[]),
        "generated sources carrying the checkout path were shared"
    );
}

/// A workspace member that reads `OUT_DIR` is restored rather than rebuilt,
/// so the crate above it consumes the same artifact in both checkouts and
/// shares too. The pair is checked by crate: the fixture also compiles a build
/// script, which shares either way and would hide a dependent still rebuilding
/// behind the session total.
#[test]
fn a_workspace_member_reading_out_dir_shares_with_its_dependents() {
    let (store, _) = two_checkouts(Generated::Dependent, &[]);
    let outcomes = second_build_outcomes(store.path());
    assert_eq!(
        outcomes.get("inner").map(String::as_str),
        Some("hit"),
        "the crate that read OUT_DIR recompiled: {outcomes:?}"
    );
    assert_eq!(
        outcomes.get("outer").map(String::as_str),
        Some("hit"),
        "its dependent recompiled: {outcomes:?}"
    );
}

/// Cargo's freshness check sees the stable tree as ordinary input files, so a
/// checkout that restored a compilation reading it is fresh on the next build:
/// nothing reaches the shim at all.
#[test]
fn a_restored_out_dir_reader_stays_fresh_for_cargo() {
    let store = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_generated_project(first.path(), Generated::Text);
    write_generated_project(second.path(), Generated::Text);
    let settings = [
        ("TUIST_CARGO_CACHE_CACHE_LINKS", "0"),
        ("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0"),
    ];
    build_with(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
        &settings,
    );
    let (warm, _) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &settings,
    );
    assert!(
        count(&warm, "hits") > 0,
        "the second checkout should restore: {warm}"
    );

    let (again, stderr) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("again.json"),
        &settings,
    );

    assert_eq!(
        count(&again, "lookups"),
        0,
        "cargo should have found everything fresh: {again}\n{stderr}"
    );
    assert!(
        !stderr.contains("Compiling"),
        "cargo should have compiled nothing: {stderr}"
    );
}

/// Mapping the workspace root still stops a checkout path recorded by rustc
/// itself from reaching the artifact, which is what makes the rebuilt member
/// match; with the generated sources stable as well, both crates share.
#[test]
fn mapping_the_workspace_root_keeps_the_dependents_of_an_out_dir_reader_sharing() {
    let mapped = [("TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT", "1")];
    let (store, _) = two_checkouts(Generated::Dependent, &mapped);
    let outcomes = second_build_outcomes(store.path());
    assert_eq!(
        outcomes.get("outer").map(String::as_str),
        Some("hit"),
        "the dependent recompiled: {outcomes:?}"
    );
    assert_eq!(
        outcomes.get("inner").map(String::as_str),
        Some("hit"),
        "the crate that read OUT_DIR recompiled: {outcomes:?}"
    );
}

/// What the second checkout's build recorded for each crate it compiled.
///
/// A stream is named for the millisecond its build started, so sorting the
/// names orders the two builds the way `events::session_ids` does. Modification
/// times would not: a filesystem that records them coarsely can give both
/// streams the same one, and the later build would be chosen by directory
/// order.
fn second_build_outcomes(store: &Path) -> std::collections::BTreeMap<String, String> {
    let directory = store.join("actions/sessions/v1");
    let mut streams: Vec<std::path::PathBuf> = std::fs::read_dir(&directory)
        .expect("a session directory should exist")
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "jsonl")
        })
        .collect();
    streams.sort();
    assert_eq!(
        streams.len(),
        2,
        "two builds should record one stream each, found {streams:?}"
    );
    std::fs::read_to_string(streams.pop().unwrap())
        .unwrap()
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .filter(|event| event["type"] == "action")
        .filter_map(|event| {
            Some((
                event["crate_name"].as_str()?.to_string(),
                event["outcome"]["kind"].as_str()?.to_string(),
            ))
        })
        .collect()
}

/// Build the same fixture in two checkouts, reporting whether the second one
/// reused anything from the first.
/// Whether the *crate* shares, which is what every caller here is asking.
///
/// Native links are left out rather than counted: a build script's own binary
/// reads no `OUT_DIR` -- the value is handed to it when it runs, long after it
/// compiles -- so it shares between these checkouts whatever the crate does,
/// and counting it would answer a question nobody asked.
fn two_checkouts_share(generated: Generated, settings: &[(&str, &str)]) -> bool {
    let (_store, stats) = two_checkouts(generated, settings);
    count(&stats, "hits") > 0
}

/// Build the same fixture in two checkouts of it, handing back the store so a
/// caller can read what the second build recorded rather than only its totals.
fn two_checkouts(
    generated: Generated,
    settings: &[(&str, &str)],
) -> (tempfile::TempDir, serde_json::Value) {
    let store = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_generated_project(first.path(), generated);
    write_generated_project(second.path(), generated);

    let settings: Vec<(&str, &str)> = [
        ("TUIST_CARGO_CACHE_CACHE_LINKS", "0"),
        ("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0"),
    ]
    .into_iter()
    .chain(settings.iter().copied())
    .collect();
    build_with(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
        &settings,
    );
    let (stats, _) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &settings,
    );
    (store, stats)
}

#[test]
fn an_empty_store_reports_nothing() {
    let store = tempfile::tempdir().unwrap();
    let output = cargo_cache_command()
        .args(["cache", "stats"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .output()
        .expect("tuist_cargo_cache should run");

    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("objects: 0"), "unexpected output: {stdout}");
}

#[test]
fn forwards_non_build_cargo_subcommands() {
    let root = tempfile::tempdir().unwrap();
    let store = tempfile::tempdir().unwrap();

    let output = cargo_cache_command()
        .current_dir(root.path())
        .args(["new", "--vcs", "none", "new-project"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("tuist_cargo_cache new should run");
    assert!(
        output.status.success(),
        "tuist_cargo_cache new failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(root.path().join("new-project/Cargo.toml").is_file());

    let initialized = root.path().join("initialized-project");
    std::fs::create_dir(&initialized).unwrap();
    let output = cargo_cache_command()
        .current_dir(&initialized)
        .args(["init", "--vcs", "none"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("tuist_cargo_cache init should run");
    assert!(
        output.status.success(),
        "tuist_cargo_cache init failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(initialized.join("Cargo.toml").is_file());
}

#[test]
fn a_build_records_the_checkout_it_ran_in() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    build(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
    );

    // The record is what later tells the collector this checkout exists, so a
    // build that leaves none has silently opted out of being protected.
    let records = store.path().join("actions/checkouts/v1");
    assert!(
        tree_bytes(&records) > 0,
        "the build should record its checkout under {}",
        records.display()
    );
}

#[test]
fn a_failed_build_records_the_compilations_it_completed() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_partially_failing_project(project.path());

    let output = cargo_cache_command()
        .current_dir(project.path())
        .args(["build", "--workspace", "--offline"])
        .env("TUIST_CARGO_CACHE_DIR", store.path())
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env_remove("CARGO_TARGET_DIR")
        .env_remove("CARGO_INCREMENTAL")
        // A test run that is itself under tuist_cargo_cache would otherwise hand its
        // wrapper down, and the build under test would defer to it and
        // record nothing.
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .output()
        .expect("tuist_cargo_cache should run");

    assert!(!output.status.success(), "the bad member should fail");
    assert!(
        tree_bytes(&store.path().join("actions/task-manifests/v1")) > 0,
        "the successful dependency should still be recorded as reachable"
    );
}

#[test]
fn a_build_sweeps_the_store_to_its_budget() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    let (_, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
        // A one-byte budget swept every build: nothing this build stored can
        // stay, so the sweep is unambiguous.
        &[
            ("TUIST_CARGO_CACHE_GC_AUTO", "1"),
            ("TUIST_CARGO_CACHE_GC_MAX_SIZE", "1"),
            ("TUIST_CARGO_CACHE_GC_INTERVAL", "0"),
        ],
    );

    // The sweep runs after the build has exited, in a process of its own, so
    // the build that scheduled it has nothing to say about it yet.
    assert!(
        !stderr.contains("tuist_cargo_cache[gc]:"),
        "the build should not wait for the sweep: {stderr}"
    );
    wait_for_sweep_report(store.path());
    let stats = tuist_cargo_cache(store.path(), &["cache", "stats"]);
    assert!(
        stats.contains("objects: 0"),
        "the store should be swept empty: {stats}"
    );

    // Collection is off for the build that reports, so what it says can only
    // be the sweep that already happened.
    let (_, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("warm.json"),
        &[("TUIST_CARGO_CACHE_GC_AUTO", "0")],
    );

    assert!(
        stderr.contains("tuist_cargo_cache[gc]: evicted"),
        "the next build should say what the sweep evicted: {stderr}"
    );
    assert!(
        !store
            .path()
            .join("actions/gc/v1/last-sweep-report")
            .exists(),
        "the report should be said once"
    );
}

#[test]
fn a_cargo_hardlink_build_runs_the_automatic_collector() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let install = tempfile::tempdir().unwrap();
    write_project(project.path());

    // Copy first so the real hardlink works even when the test binary and
    // temporary storage live on different filesystems. A symlink does not
    // reproduce this: current_exe() can resolve it back to the tuist_cargo_cache basename.
    let executable = install
        .path()
        .join(format!("tuist_cargo_cache{}", std::env::consts::EXE_SUFFIX));
    let shim = install
        .path()
        .join(format!("cargo{}", std::env::consts::EXE_SUFFIX));
    std::fs::copy(env!("CARGO_BIN_EXE_tuist-cargo-cache-model"), &executable).unwrap();
    std::fs::hard_link(&executable, &shim).unwrap();
    let (stats, stderr) = cargo_with_command(
        isolated_command(&shim),
        project.path(),
        store.path(),
        &install.path().join("build.json"),
        &["build", "--offline"],
        &[
            ("TUIST_CARGO_CACHE_GC_AUTO", "1"),
            ("TUIST_CARGO_CACHE_GC_MAX_SIZE", "1"),
            ("TUIST_CARGO_CACHE_GC_INTERVAL", "0"),
            ("TUIST_CARGO_CACHE_LOG", "tuist_cargo_cache::cli::gc=debug"),
        ],
    );
    assert!(
        count(&stats, "stored_bytes") > 0,
        "the shim must cache the build: {stats}"
    );
    assert!(
        !stderr.contains("the automatic sweep runs in the foreground"),
        "the build must launch the detached collector: {stderr}"
    );
    wait_for_sweep_report(store.path());
    let stats = tuist_cargo_cache(store.path(), &["cache", "stats"]);
    assert!(
        stats.contains("objects: 0"),
        "the collector must evict the stored objects: {stats}"
    );
    let log = std::fs::read_to_string(store.path().join("actions/gc/v1/sweep.log")).unwrap();
    // Foreground fallback can also evict objects and leave a report, but its
    // diagnostics go to the build's stderr, not the detached collector's log.
    assert!(
        log.contains("the automatic sweep freed"),
        "the detached collector must complete a sweep: {log}"
    );
    assert!(
        !log.contains("no such command"),
        "the collector must not run Cargo: {log}"
    );
}

#[cfg(unix)]
#[test]
fn a_low_disk_floor_starts_collection_before_the_build_ends() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_dependent_project(project.path());

    // Hold the first real compilation until the test has observed that Cargo
    // is alive, then keep the dependent compiler alive until the detached
    // collector claims its stamp.
    let wrapper = project.path().join("delayed-rustc");
    let compiled = project.path().join("compiler-finished");
    let release = project.path().join("release-compiler");
    let stamp = store.path().join("actions/gc/v1/last-sweep");
    std::fs::write(
        &wrapper,
        "#!/bin/sh\n\"$TEST_REAL_RUSTC\" \"$@\"\nstatus=$?\ncase \" $* \" in\n  *\" --crate-name base \"*)\n    if [ \"$status\" -eq 0 ]; then\n      : > \"$TEST_COMPILER_FINISHED\"\n      while [ ! -e \"$TEST_RELEASE_COMPILER\" ]; do sleep 0.02; done\n    fi\n    ;;\n  *\" --crate-name above \"*)\n    if [ \"$status\" -eq 0 ]; then\n      attempts=0\n      while [ ! -e \"$TEST_SWEEP_STAMP\" ] && [ \"$attempts\" -lt 1500 ]; do\n        sleep 0.02\n        attempts=$((attempts + 1))\n      done\n    fi\n    ;;\nesac\nexit \"$status\"\n",
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&wrapper).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&wrapper, permissions).unwrap();

    let report = reports.path().join("build.json");
    let real_rustc = which::which("rustc").unwrap();
    let mut command = isolated_cargo_command(
        cargo_cache_command(),
        project.path(),
        store.path(),
        &report,
        &["check", "--offline"],
        &[
            ("TUIST_CARGO_CACHE_GC_AUTO", "1"),
            ("TUIST_CARGO_CACHE_GC_MIN_FREE_SIZE", "1PiB"),
            ("TUIST_CARGO_CACHE_GC_MAX_SIZE", "1"),
            ("TUIST_CARGO_CACHE_GC_INTERVAL", "1h"),
            ("RUSTC", wrapper.to_str().unwrap()),
            ("TEST_REAL_RUSTC", real_rustc.to_str().unwrap()),
            ("TEST_COMPILER_FINISHED", compiled.to_str().unwrap()),
            ("TEST_RELEASE_COMPILER", release.to_str().unwrap()),
            ("TEST_SWEEP_STAMP", stamp.to_str().unwrap()),
        ],
    );
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = BuildChildGuard::new(command.spawn().expect("tuist_cargo_cache should run"));

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while !compiled.exists() && std::time::Instant::now() < deadline {
        assert!(
            child.try_wait().unwrap().is_none(),
            "the build exited before the compiler could be released"
        );
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert!(
        compiled.exists(),
        "the compiler did not reach the test barrier"
    );

    std::fs::write(&release, b"").unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while !stamp.exists() && std::time::Instant::now() < deadline {
        assert!(
            child.try_wait().unwrap().is_none(),
            "the build ended before the low-disk sweep was claimed"
        );
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert!(
        stamp.exists(),
        "the low-disk collector was not claimed while the build was running"
    );

    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "the build failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

/// Wait for the collector a build started to leave its report.
///
/// The collector is detached from the build, so a test that wants to observe
/// what it did has to wait for it. Only a sweep that removed something leaves
/// a report; tests that call this made sure theirs does.
fn wait_for_sweep_report(store: &Path) {
    let report = store.join("actions/gc/v1/last-sweep-report");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(60);
    while !report.exists() {
        assert!(
            std::time::Instant::now() < deadline,
            "the background sweep should finish; its log says: {}",
            std::fs::read_to_string(store.join("actions/gc/v1/sweep.log")).unwrap_or_default()
        );
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
}

#[test]
fn automatic_sweeps_can_be_turned_off() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());

    let (_, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
        &[
            ("TUIST_CARGO_CACHE_GC_MAX_SIZE", "1"),
            ("TUIST_CARGO_CACHE_GC_INTERVAL", "0"),
            ("TUIST_CARGO_CACHE_GC_AUTO", "0"),
        ],
    );

    assert!(
        !stderr.contains("tuist_cargo_cache[gc]:"),
        "no sweep should run: {stderr}"
    );
    assert!(
        !store.path().join("actions/gc/v1/sweep.log").exists(),
        "no collector should have been started"
    );
    let stats = tuist_cargo_cache(store.path(), &["cache", "stats"]);
    assert!(
        !stats.contains("objects: 0"),
        "the store should be left alone: {stats}"
    );
}

/// Two checkouts, one deleted, a budget that fits only one of them.
///
/// Plain recency would keep the deleted checkout's newer artifacts and evict
/// the surviving one's, so the survivor coming back warm is the whole claim.
#[test]
fn deleting_a_checkout_releases_what_only_it_used() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let surviving = tempfile::tempdir().unwrap();
    let deleted = tempfile::tempdir().unwrap();
    write_named_project(surviving.path(), "surviving");
    write_named_project(deleted.path(), "deleted");

    build(
        surviving.path(),
        store.path(),
        &reports.path().join("surviving.json"),
    );
    // Budget the store as it stood with one checkout in it, plus slack. The
    // slack matters: an action result is only dropped once its objects are
    // gone, which happens after eviction has already decided how deep to go, so
    // a budget set to the exact byte forces eviction one object further than
    // the arithmetic suggests. At a real budget that rounding is noise; at this
    // scale it is the whole margin.
    let budget = store_bytes(store.path()) + 4096;
    build(
        deleted.path(),
        store.path(),
        &reports.path().join("deleted.json"),
    );
    std::fs::remove_dir_all(deleted.path()).unwrap();

    tuist_cargo_cache(store.path(), &["gc", "--max-size", &budget.to_string()]);

    // Load-bearing, not cleanup: the wipe is what forces the next build to go
    // to the store, which is the only way to see what survived the sweep.
    wipe_target(surviving.path());
    let warm = build(
        surviving.path(),
        store.path(),
        &reports.path().join("warm.json"),
    );

    assert!(
        count(&warm, "hits") > 0,
        "the surviving checkout should still be warm: {warm}"
    );
}

/// The per-compilation stream `tuist_cargo_cache tui` reads.
mod session_events {
    use super::*;
    use std::path::PathBuf;

    /// Where session streams live, beside the rest of the store's bookkeeping.
    fn sessions_dir(store: &Path) -> PathBuf {
        store.join("actions/sessions/v1")
    }

    /// The events of the one session `store` recorded, in order.
    fn stream(store: &Path) -> Vec<serde_json::Value> {
        let directory = sessions_dir(store);
        let mut streams: Vec<PathBuf> = std::fs::read_dir(&directory)
            .expect("a session directory should exist")
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "jsonl")
            })
            .collect();
        assert_eq!(
            streams.len(),
            1,
            "one build should record exactly one stream, found {streams:?}"
        );
        let contents = std::fs::read_to_string(streams.pop().unwrap()).unwrap();
        contents
            .lines()
            .map(|line| serde_json::from_str(line).expect("every line should be JSON"))
            .collect()
    }

    fn outcomes(events: &[serde_json::Value], kind: &str) -> usize {
        events
            .iter()
            .filter(|event| event["type"] == "action" && event["outcome"]["kind"] == kind)
            .count()
    }

    #[test]
    fn a_build_records_its_compilations_between_a_start_and_its_totals() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());

        let cold = build(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
        );

        let events = stream(store.path());
        assert_eq!(events.first().unwrap()["type"], "session_started");
        assert_eq!(
            events.first().unwrap()["command"],
            serde_json::json!(["build", "--offline"])
        );
        let last = events.last().unwrap();
        assert_eq!(last["type"], "session_finished");
        // The stream's own totals are the summary's totals, so a reader of a
        // finished session never has to re-derive them from the rows.
        assert_eq!(last["stats"]["unconsulted"], cold["unconsulted"]);
        assert_eq!(last["stats"]["hits"], cold["hits"]);
        // A cold build compiles without a key to look up, and every one of
        // those compilations should appear as a row.
        assert_eq!(
            outcomes(&events, "unconsulted") as u64,
            count(&cold, "unconsulted"),
            "every unconsulted compilation should have a row: {events:?}"
        );
    }

    #[test]
    fn a_warm_build_records_a_row_per_hit_naming_its_crate() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());

        build(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
        );
        // Load-bearing, not cleanup: without the wipe cargo finds the cold
        // build's outputs and the warm build has nothing to restore.
        wipe_target(project.path());
        let warm = build(
            project.path(),
            store.path(),
            &reports.path().join("warm.json"),
        );

        // Two builds, two streams; this reads the newest.
        let directory = sessions_dir(store.path());
        let mut streams: Vec<PathBuf> = std::fs::read_dir(&directory)
            .unwrap()
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "jsonl")
            })
            .collect();
        streams.sort();
        let contents = std::fs::read_to_string(streams.last().unwrap()).unwrap();
        let events: Vec<serde_json::Value> = contents
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();

        let hits = count(&warm, "hits");
        assert!(hits > 0, "the warm build should hit: {warm}");
        assert_eq!(
            outcomes(&events, "hit") as u64,
            hits,
            "every hit should have a row: {events:?}"
        );
        // The crate name is what the protocol bump was for: a row that cannot
        // say which crate it restored is not worth showing.
        assert!(
            events.iter().any(|event| {
                event["outcome"]["kind"] == "hit" && event["crate_name"] == "fixture"
            }),
            "a hit row should name the crate it restored: {events:?}"
        );
    }

    #[test]
    fn recording_can_be_turned_off() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());

        build_with(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
            &[("TUIST_CARGO_CACHE_EVENTS", "0")],
        );

        assert!(
            !sessions_dir(store.path()).exists(),
            "a build that records nothing should leave no session directory"
        );
    }
}

/// Managed target directories rest on a symlink standing in for `target`, and
/// Windows only lets a privileged or developer-mode process create one, so tuist_cargo_cache
/// leaves the target directory where cargo put it there. These cover the
/// platforms where the feature is available.
#[cfg(unix)]
mod target_views {
    use super::*;

    fn managed(project: &Path) -> std::path::PathBuf {
        std::fs::read_link(project.join("target")).expect("target should be a link")
    }

    #[test]
    fn a_managed_target_directory_keeps_the_workspace_clean() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());

        build(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
        );

        let directory = managed(project.path());
        assert!(
            directory.starts_with(store.path().join("targets")),
            "outputs should land under the managed root, not the workspace: {}",
            directory.display()
        );
        // The link is the point: a relocation that breaks the paths people type
        // would not be worth the disk it reclaims.
        assert!(
            project.path().join("target/debug/libfixture.rlib").exists(),
            "the workspace should still reach its own build outputs"
        );
    }

    #[test]
    fn cargo_reports_workspace_paths_for_managed_artifacts() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        write_project(project.path());

        let output = cargo_cache_command()
            .current_dir(project.path())
            .args(["build", "--offline", "--message-format=json"])
            .env("TUIST_CARGO_CACHE_DIR", store.path())
            .env_remove("CARGO_TARGET_DIR")
            .output()
            .expect("tuist_cargo_cache should run");
        assert!(
            output.status.success(),
            "build failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let artifact = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
            .find(|message| message["reason"] == "compiler-artifact")
            .expect("Cargo should report the built artifact");
        // Cargo canonicalizes `/var` to `/private/var` on macOS. Anchor the
        // expected public path to that same workspace spelling without
        // canonicalizing `target` itself through the managed symlink.
        let target = std::fs::canonicalize(project.path())
            .unwrap()
            .join("target");
        for filename in artifact["filenames"].as_array().unwrap() {
            let filename = Path::new(filename.as_str().unwrap());
            assert!(
                filename.starts_with(&target),
                "debugger-facing artifact path escaped the workspace: {}",
                filename.display()
            );
        }
    }

    #[test]
    fn check_and_clippy_get_their_own_directory_inside_the_managed_target() {
        // Clippy is an external subcommand, so it takes a different route to
        // the lane than the built-in `check` does.
        for command in ["check", "clippy"] {
            if command == "clippy" && !clippy_available() {
                continue;
            }
            let store = tempfile::tempdir().unwrap();
            let project = tempfile::tempdir().unwrap();
            let reports = tempfile::tempdir().unwrap();
            write_project(project.path());
            let settings = [("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")];

            cargo_with(
                project.path(),
                store.path(),
                &reports.path().join("check.json"),
                &[command, "--offline"],
                &settings,
            );

            let directory = managed(project.path());
            assert!(
                directory.join("check/debug/.cargo-lock").is_file(),
                "`{command}` should write to the lane inside the managed target"
            );
            assert!(
                !directory.join("debug").exists(),
                "`{command}` should leave the build's profile directory alone"
            );

            build_with(
                project.path(),
                store.path(),
                &reports.path().join("build.json"),
                &settings,
            );
            assert!(
                project.path().join("target/debug/libfixture.rlib").exists(),
                "a build should still write where builds have always written"
            );
        }
    }

    fn clippy_available() -> bool {
        Command::new(cargo())
            .args(["clippy", "--version"])
            .status()
            .is_ok_and(|status| status.success())
    }

    fn lane_check(
        project: &Path,
        store: &Path,
        report: &Path,
        settings: &[(&str, &str)],
        stderr: Stdio,
    ) -> std::process::Child {
        isolated_cargo_command(
            cargo_cache_command(),
            project,
            store,
            report,
            &["check", "--offline"],
            settings,
        )
        .stdout(Stdio::null())
        .stderr(stderr)
        .spawn()
        .expect("tuist_cargo_cache should run")
    }

    /// Wait for `predicate` to hold of `path`'s contents, up to `wait`.
    fn file_eventually(
        path: &Path,
        wait: std::time::Duration,
        predicate: impl Fn(&str) -> bool,
    ) -> bool {
        let deadline = std::time::Instant::now() + wait;
        while std::time::Instant::now() < deadline {
            if std::fs::read_to_string(path).is_ok_and(|text| predicate(&text)) {
                return true;
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        false
    }

    /// Whether `child` finished within `wait`, killing it if it did not.
    fn finishes_within(child: &mut std::process::Child, wait: std::time::Duration) -> bool {
        let deadline = std::time::Instant::now() + wait;
        while std::time::Instant::now() < deadline {
            if child.try_wait().unwrap().is_some() {
                return true;
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        child.kill().unwrap();
        child.wait().unwrap();
        false
    }

    #[test]
    fn a_check_does_not_wait_for_a_build_holding_the_target_lock() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        build_with(
            project.path(),
            store.path(),
            &reports.path().join("build.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        // What a build in progress holds for as long as it compiles.
        let lock = std::fs::File::open(project.path().join("target/debug/.cargo-lock"))
            .expect("a build should leave Cargo's lock file behind");
        lock.lock().unwrap();

        // The control: with lanes off, Cargo reports that it is waiting on the
        // build's lock. Observing that, rather than a slow start, is what makes
        // the run below a test of the lane.
        let log = reports.path().join("queued.log");
        let mut queued = lane_check(
            project.path(),
            store.path(),
            &reports.path().join("queued.json"),
            &[
                ("TUIST_CARGO_CACHE_TARGET_VIEWS", "1"),
                ("TUIST_CARGO_CACHE_TARGET_LANES", "0"),
            ],
            Stdio::from(std::fs::File::create(&log).unwrap()),
        );
        let blocked = file_eventually(&log, std::time::Duration::from_secs(60), |text| {
            text.lines().any(|line| {
                line.contains("waiting for file lock on") && !line.contains("package cache")
            })
        });
        queued.kill().unwrap();
        queued.wait().unwrap();
        assert!(
            blocked,
            "without a lane the check should wait for the build's lock: {}",
            std::fs::read_to_string(&log).unwrap_or_default()
        );

        let mut check = lane_check(
            project.path(),
            store.path(),
            &reports.path().join("check.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
            Stdio::null(),
        );
        assert!(
            finishes_within(&mut check, std::time::Duration::from_secs(60)),
            "a check in its own lane should not wait for the build"
        );
        assert!(check.wait().unwrap().success());
    }

    #[test]
    fn an_alias_for_check_gets_the_lane_too() {
        // `c` is Cargo's own shorthand; `chk` is one this project defines.
        for alias in ["c", "chk"] {
            let store = tempfile::tempdir().unwrap();
            let project = tempfile::tempdir().unwrap();
            let reports = tempfile::tempdir().unwrap();
            write_project(project.path());
            std::fs::create_dir_all(project.path().join(".cargo")).unwrap();
            std::fs::write(
                project.path().join(".cargo/config.toml"),
                "[alias]\nchk = \"check\"\n",
            )
            .unwrap();

            cargo_with(
                project.path(),
                store.path(),
                &reports.path().join("alias.json"),
                &[alias, "--offline"],
                &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
            );

            let directory = managed(project.path());
            assert!(
                directory.join("check/debug/.cargo-lock").is_file(),
                "`{alias}` should write to the lane"
            );
            assert!(!directory.join("debug").exists(), "`{alias}`");
        }
    }

    #[test]
    fn an_alias_that_names_a_target_directory_keeps_it() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        std::fs::create_dir_all(project.path().join(".cargo")).unwrap();
        std::fs::write(
            project.path().join(".cargo/config.toml"),
            "[alias]\nchk-elsewhere = \"check --target-dir elsewhere\"\n",
        )
        .unwrap();

        cargo_with(
            project.path(),
            store.path(),
            &reports.path().join("alias.json"),
            &["chk-elsewhere", "--offline"],
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );

        // Where the alias sent it, not a lane laid over the top of it.
        assert!(project.path().join("elsewhere/debug").is_dir());
        if let Ok(managed) = std::fs::read_link(project.path().join("target")) {
            assert!(!managed.join("check").exists());
        }
    }

    #[test]
    fn a_build_directory_in_the_environment_keeps_a_check_in_the_shared_target() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());

        // The target's own path, so nothing about the probe looks unusual.
        let output = isolated_cargo_command(
            cargo_cache_command(),
            project.path(),
            store.path(),
            &reports.path().join("check.json"),
            &["check", "--offline"],
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        )
        .env("CARGO_BUILD_BUILD_DIR", "target")
        .output()
        .expect("tuist_cargo_cache should run");

        assert!(
            output.status.success(),
            "check failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let directory = managed(project.path());
        assert!(!directory.join("check").exists());
        assert!(directory.join("debug").is_dir());
    }

    #[test]
    fn a_configured_build_directory_keeps_a_check_in_the_shared_target() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        std::fs::create_dir_all(project.path().join(".cargo")).unwrap();
        // The same path as the target: a lane would move the target but leave
        // the lock, and the check would still queue behind a build.
        std::fs::write(
            project.path().join(".cargo/config.toml"),
            "[build]\nbuild-dir = \"target\"\n",
        )
        .unwrap();

        cargo_with(
            project.path(),
            store.path(),
            &reports.path().join("check.json"),
            &["check", "--offline"],
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );

        let directory = managed(project.path());
        assert!(!directory.join("check").exists());
        assert!(directory.join("debug").is_dir());
    }

    #[test]
    fn cargo_cache_clean_removes_the_managed_view_and_link() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        build(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
        );
        let managed = managed(project.path());

        let output = cargo_cache_command()
            .current_dir(project.path().join("src"))
            .arg("clean")
            .env("TUIST_CARGO_CACHE_DIR", store.path())
            .env_remove("CARGO_TARGET_DIR")
            .output()
            .expect("tuist_cargo_cache clean should run");

        assert!(
            output.status.success(),
            "clean failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!managed.exists());
        assert!(std::fs::symlink_metadata(project.path().join("target")).is_err());
    }

    #[test]
    fn a_managed_target_directory_still_hits_the_cache() {
        let store = tempfile::tempdir().unwrap();
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(first.path());
        write_project(second.path());

        build(
            first.path(),
            store.path(),
            &reports.path().join("first.json"),
        );
        let (warm, _) = build_with(
            second.path(),
            store.path(),
            &reports.path().join("second.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );

        // The shim maps the target directory out of its keys before anything
        // else, so moving it must not cost a single hit.
        assert!(
            count(&warm, "hits") > 0,
            "a relocated target directory should still reuse the first build: {warm}"
        );
    }

    #[test]
    fn deleting_a_checkout_frees_its_managed_target_directory() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());

        build_with(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        let directory = managed(project.path());
        assert!(tree_bytes(&directory) > 0);

        // Outputs used to live inside the checkout and die with it. Now that
        // they outlive it, collecting them is tuist_cargo_cache's job.
        std::fs::remove_dir_all(project.path()).unwrap();
        let output = tuist_cargo_cache(store.path(), &["gc", "--max-size", "20GiB"]);

        assert!(
            !directory.exists(),
            "the target directory of a checkout that is gone should be freed"
        );
        assert!(
            output.contains("removed 1 target directories"),
            "gc should say what it freed: {output}"
        );
    }

    /// What a fixture program prints once it is running, and then waits for
    /// its standard input to close before it exits.
    ///
    /// The line is the test's sign that Cargo has finished and the program is
    /// what is running; closing standard input is how the test lets it go. No
    /// clock is involved, so the window in which `tuist_cargo_cache gc` runs is exactly the
    /// time the program is running, however slow the machine.
    const WAIT_FOR_STDIN: &str = r#"{
    use std::io::{Read, Write};
    let mut out = std::io::stdout();
    out.write_all(b"ready\n").unwrap();
    out.flush().unwrap();
    let mut rest = String::new();
    std::io::stdin().read_to_string(&mut rest).unwrap();
}"#;

    /// Run `tuist_cargo_cache gc` with a maximum age every managed target directory in
    /// `store` has passed, once its record has been aged.
    fn gc_expired_targets(store: &Path) -> (String, String) {
        let output = cargo_cache_command()
            .arg("gc")
            .env("TUIST_CARGO_CACHE_DIR", store)
            .env("TUIST_CARGO_CACHE_TARGET_MAX_AGE", "1s")
            .output()
            .expect("tuist_cargo_cache gc should run");
        let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
        assert!(
            output.status.success(),
            "gc failed ({}):\nstdout: {stdout}\nstderr: {stderr}",
            output.status
        );
        (stdout, stderr)
    }

    /// Start `arguments` under tuist_cargo_cache in `project`, whose program prints
    /// `ready` and then waits on standard input, and check that `tuist_cargo_cache gc`
    /// keeps the managed target directory while the program runs and
    /// removes it once the command has exited.
    ///
    /// Once Cargo has finished compiling, the target directory is still in
    /// use: `cargo run` executes the program from it, and `cargo test`
    /// executes the test binaries from it. Removing it underneath them takes
    /// away files they may still open, such as a test's fixtures or a
    /// program's own dynamic libraries.
    fn assert_gc_waits_for(project: &Path, arguments: &[&str]) {
        let store = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        // A file rather than a pipe, so that nothing has to drain it while the
        // test waits on standard output, and so a failure can quote it.
        let stderr_path = reports.path().join("stderr");
        let mut child = isolated_cargo_command(
            cargo_cache_command(),
            project,
            store.path(),
            &reports.path().join("run.json"),
            arguments,
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        )
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(std::fs::File::create(&stderr_path).unwrap())
        .spawn()
        .expect("tuist_cargo_cache should start");
        let child_stderr = || std::fs::read_to_string(&stderr_path).unwrap_or_default();

        let mut stdout = std::io::BufReader::new(child.stdout.take().unwrap());
        let mut seen = String::new();
        loop {
            let mut line = String::new();
            let read = std::io::BufRead::read_line(&mut stdout, &mut line).unwrap();
            assert!(
                read > 0,
                "the program should say it is running before stdout closes ({:?}):\nstdout: {seen}\nstderr: {}",
                child.wait(),
                child_stderr()
            );
            seen.push_str(&line);
            // libtest prints its own lines around a test, and when it runs
            // tests one at a time it opens the test's line before the test
            // runs, so only the end of the line is the program's.
            if line.trim_end().ends_with("ready") {
                break;
            }
        }

        let view = managed(project);
        assert!(
            view.starts_with(store.path().join("targets/v1")),
            "the target directory should be managed: {}",
            view.display()
        );
        // Make the view old enough to expire, so the only thing standing
        // between it and collection is the command still using it.
        let record = view.with_extension("json");
        let mut fields: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&record).expect("the view should have a record"))
                .unwrap();
        fields["updated_secs"] = 1.into();
        std::fs::write(&record, serde_json::to_vec(&fields).unwrap()).unwrap();

        let (gc_stdout, gc_stderr) = gc_expired_targets(store.path());
        assert!(
            view.is_dir() && record.is_file(),
            "gc should keep a target directory a running command uses:\ngc stdout: {gc_stdout}\ngc stderr: {gc_stderr}\ncargo_cache stderr: {}",
            child_stderr()
        );
        assert!(
            gc_stdout
                .lines()
                .any(|line| line == "kept 1 target directories in use by running commands"),
            "gc should say why it kept the target directory:\ngc stdout: {gc_stdout}\ngc stderr: {gc_stderr}"
        );

        drop(child.stdin.take());
        let mut rest = String::new();
        std::io::Read::read_to_string(&mut stdout, &mut rest).unwrap();
        let status = child.wait().unwrap();
        assert!(
            status.success(),
            "the command should succeed ({status}):\nstdout: {seen}{rest}\nstderr: {}",
            child_stderr()
        );

        let (gc_stdout, gc_stderr) = gc_expired_targets(store.path());
        assert!(
            !view.exists(),
            "gc should remove the expired target directory once the command has exited:\ngc stdout: {gc_stdout}\ngc stderr: {gc_stderr}"
        );
        assert!(
            gc_stdout.contains("removed 1 target directories"),
            "gc should say what it removed:\ngc stdout: {gc_stdout}\ngc stderr: {gc_stderr}"
        );
    }

    #[test]
    fn gc_leaves_a_target_directory_alone_while_cargo_run_is_running() {
        let project = tempfile::tempdir().unwrap();
        write_project(project.path());
        std::fs::write(
            project.path().join("src/main.rs"),
            format!("fn main() {WAIT_FOR_STDIN}\n"),
        )
        .unwrap();

        // tuist_cargo_cache runs the program itself once Cargo has exited, so Cargo's own
        // lock on the target directory is gone by the time the program runs.
        assert_gc_waits_for(project.path(), &["run", "--offline"]);
    }

    #[test]
    fn gc_leaves_a_target_directory_alone_while_cargo_test_is_running() {
        let project = tempfile::tempdir().unwrap();
        write_project(project.path());
        // Written through the raw handle, which libtest does not capture, so
        // the line reaches the test even though the test passes.
        std::fs::write(
            project.path().join("src/lib.rs"),
            format!(
                "pub fn double(value: u32) -> u32 {{\n    value * 2\n}}\n\n#[test]\nfn waits_for_its_caller() {WAIT_FOR_STDIN}\n"
            ),
        )
        .unwrap();

        assert_gc_waits_for(project.path(), &["test", "--offline"]);
    }

    #[test]
    fn gc_removes_units_no_build_has_used_from_a_live_target_directory() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        build_with(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        let directory = managed(project.path());
        // Collection only judges units where reads move access times, and
        // skips them everywhere else, which a CI volume may be.
        if !access_times_tracked(directory.parent().unwrap()) {
            return;
        }

        // As if the last build to use these units ran two months ago, which
        // is what the fingerprint access times say once a lockfile or
        // toolchain change moves every build on to other units.
        age_tree(&directory.join("debug"));
        let output = tuist_cargo_cache(store.path(), &["gc", "--max-size", "20GiB"]);

        assert!(
            output.contains("unused build units from live target directories"),
            "gc should remove and report the unused units: {output}"
        );
        assert!(
            find_files(&directory.join("debug"), |path| {
                file_name_is(path, |name| {
                    name.starts_with("libfixture-") && name.ends_with(".rlib")
                })
            })
            .is_empty(),
            "the unit's outputs should be gone"
        );
        assert!(directory.is_dir(), "the live target directory stays");

        let (rebuilt, _) = build_with(
            project.path(),
            store.path(),
            &reports.path().join("rebuilt.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        assert!(
            count(&rebuilt, "hits") > 0,
            "the next build should restore the removed unit: {rebuilt}"
        );
    }

    #[test]
    fn gc_keeps_units_a_fresh_build_still_uses() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        build_with(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        let directory = managed(project.path());
        age_tree(&directory.join("debug"));

        // Nothing to compile, so nothing is written; Cargo still reads every
        // unit's fingerprint, and that read is what marks the unit as used.
        build_with(
            project.path(),
            store.path(),
            &reports.path().join("fresh.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        let output = tuist_cargo_cache(store.path(), &["gc", "--max-size", "20GiB"]);

        assert!(
            !output.contains("unused build units"),
            "a unit the last build used should stay: {output}"
        );
        assert!(
            !find_files(&directory.join("debug"), |path| {
                file_name_is(path, |name| {
                    name.starts_with("libfixture-") && name.ends_with(".rlib")
                })
            })
            .is_empty(),
            "the unit's outputs should remain"
        );
    }

    /// Whether reading a file in `directory` moves its access time, checked
    /// the way unit collection checks before it removes anything.
    fn access_times_tracked(directory: &Path) -> bool {
        let probe = directory.join(".access-time-probe");
        std::fs::write(&probe, b"access time probe").unwrap();
        let past = std::time::SystemTime::now() - std::time::Duration::from_secs(2 * 24 * 60 * 60);
        let time = filetime::FileTime::from_system_time(past);
        filetime::set_file_times(&probe, time, time).unwrap();
        std::fs::read(&probe).unwrap();
        let accessed = std::fs::metadata(&probe).unwrap().accessed().unwrap();
        std::fs::remove_file(&probe).unwrap();
        accessed > past + std::time::Duration::from_secs(24 * 60 * 60)
    }

    /// Date everything below `directory` two months back, as if no build had
    /// read or written it since.
    fn age_tree(directory: &Path) {
        let past = filetime::FileTime::from_system_time(
            std::time::SystemTime::now() - std::time::Duration::from_secs(60 * 24 * 60 * 60),
        );
        let mut pending = vec![directory.to_path_buf()];
        while let Some(next) = pending.pop() {
            for entry in std::fs::read_dir(&next).unwrap().flatten() {
                if entry.file_type().unwrap().is_dir() {
                    pending.push(entry.path());
                }
                filetime::set_file_times(entry.path(), past, past).unwrap();
            }
        }
    }

    /// A checkout depending on `seeded-dep` from a local Git repository,
    /// which Cargo treats like any other non-path package.
    #[cfg(unix)]
    fn write_git_dependent_project(directory: &Path, repository: &Path) {
        std::fs::create_dir_all(directory.join("src")).unwrap();
        std::fs::write(
            directory.join("Cargo.toml"),
            format!(
                "[package]\nname = \"app\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\nseeded-dep = {{ git = \"file://{}\" }}\n",
                repository.display()
            ),
        )
        .unwrap();
        std::fs::write(
            directory.join("src/lib.rs"),
            "pub fn flavor() -> &'static str {\n    seeded_dep::FLAVOR\n}\n",
        )
        .unwrap();
    }

    /// A Git repository holding a library whose build script writes the
    /// source the library includes.
    #[cfg(unix)]
    fn write_seeded_dependency(repository: &Path) {
        std::fs::create_dir_all(repository.join("src")).unwrap();
        std::fs::write(
            repository.join("Cargo.toml"),
            "[package]\nname = \"seeded-dep\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
        )
        .unwrap();
        std::fs::write(
            repository.join("build.rs"),
            r#"fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=SEEDED_FLAVOR");
    let flavor = std::env::var("SEEDED_FLAVOR").unwrap_or_else(|_| "plain".into());
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    std::fs::write(out.join("flavor.rs"), format!("pub const FLAVOR: &str = {flavor:?};\n")).unwrap();
}
"#,
        )
        .unwrap();
        std::fs::write(
            repository.join("src/lib.rs"),
            "include!(concat!(env!(\"OUT_DIR\"), \"/flavor.rs\"));\n",
        )
        .unwrap();
        for arguments in [
            &["init", "-q"][..],
            &["add", "."],
            &[
                "-c",
                "user.name=tuist_cargo_cache",
                "-c",
                "user.email=tuist_cargo_cache@example.com",
                "commit",
                "-q",
                "-m",
                "seeded",
            ],
        ] {
            let status = Command::new("git")
                .current_dir(repository)
                .args(arguments)
                .status()
                .expect("git should run");
            assert!(status.success(), "git {arguments:?} failed");
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_new_checkout_starts_with_another_checkouts_registry_units() {
        let store = tempfile::tempdir().unwrap();
        let cargo_home = tempfile::tempdir().unwrap();
        let repository = tempfile::tempdir().unwrap();
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let third = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_seeded_dependency(repository.path());
        for checkout in [first.path(), second.path(), third.path()] {
            write_git_dependent_project(checkout, repository.path());
        }
        let home = cargo_home.path().to_str().unwrap();
        // Fetch once into a private Cargo home, so the offline builds below
        // resolve the same Git checkout.
        let status = Command::new(cargo())
            .current_dir(first.path())
            .args(["generate-lockfile"])
            .env("CARGO_HOME", home)
            .status()
            .expect("cargo should run");
        assert!(status.success(), "the fixture should resolve");
        for checkout in [second.path(), third.path()] {
            std::fs::copy(first.path().join("Cargo.lock"), checkout.join("Cargo.lock")).unwrap();
        }
        let settings = [
            ("TUIST_CARGO_CACHE_TARGET_VIEWS", "1"),
            ("CARGO_HOME", home),
        ];

        build_with(
            first.path(),
            store.path(),
            &reports.path().join("first.json"),
            &settings,
        );
        let cargo_1_100 = managed(first.path())
            .join("debug/build/seeded-dep")
            .read_dir()
            .into_iter()
            .flatten()
            .flatten()
            .any(|unit| unit.path().join("fingerprint").is_dir());
        let (seeded, stderr) = build_with(
            second.path(),
            store.path(),
            &reports.path().join("second.json"),
            &settings,
        );
        let (unseeded, _) = build_with(
            third.path(),
            store.path(),
            &reports.path().join("third.json"),
            &[
                ("TUIST_CARGO_CACHE_TARGET_VIEWS", "1"),
                ("CARGO_HOME", home),
                ("TUIST_CARGO_CACHE_TARGET_SEED", "0"),
            ],
        );
        let compilations =
            |stats: &serde_json::Value| count(stats, "hits") + count(stats, "misses");
        if !cargo_1_100 {
            assert!(
                !stderr.contains("registry build units"),
                "units are only copied from Cargo 1.100's layout: {stderr}"
            );
            return;
        }
        assert!(
            stderr.contains("copied 3 registry build units from"),
            "the new checkout should say what it copied: {stderr}"
        );
        assert!(
            compilations(&seeded) < compilations(&unseeded),
            "Cargo should skip the copied units: {seeded} against {unseeded}"
        );

        // A copied build script that has to run again execs the pinned tuist_cargo_cache,
        // and rewrites only this checkout's fingerprints and output.
        let fingerprints = |checkout: &Path| {
            find_files(&managed(checkout).join("debug/build/seeded-dep"), |path| {
                path.parent().and_then(Path::file_name) == Some("fingerprint".as_ref())
            })
            .into_iter()
            .map(|path| std::fs::read(path).unwrap())
            .collect::<Vec<_>>()
        };
        let donor_fingerprints = fingerprints(first.path());
        build_with(
            second.path(),
            store.path(),
            &reports.path().join("rerun.json"),
            &[
                ("TUIST_CARGO_CACHE_TARGET_VIEWS", "1"),
                ("CARGO_HOME", home),
                ("SEEDED_FLAVOR", "spicy"),
            ],
        );
        let flavors = |checkout: &Path| {
            find_files(&managed(checkout).join("debug/build/seeded-dep"), |path| {
                file_name_is(path, |name| name == "flavor.rs")
            })
            .into_iter()
            .map(|path| std::fs::read_to_string(path).unwrap())
            .collect::<Vec<_>>()
        };
        assert!(
            flavors(second.path())
                .iter()
                .any(|flavor| flavor.contains("spicy")),
            "the rerun build script should have written this checkout's output"
        );
        assert!(
            flavors(first.path())
                .iter()
                .all(|flavor| flavor.contains("plain")),
            "the other checkout's build-script output should be untouched"
        );
        assert_eq!(
            fingerprints(first.path()),
            donor_fingerprints,
            "the other checkout's fingerprints should be untouched"
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_new_checkouts_first_check_starts_with_another_checkouts_check_units() {
        let store = tempfile::tempdir().unwrap();
        let cargo_home = tempfile::tempdir().unwrap();
        let repository = tempfile::tempdir().unwrap();
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_seeded_dependency(repository.path());
        for checkout in [first.path(), second.path()] {
            write_git_dependent_project(checkout, repository.path());
        }
        let home = cargo_home.path().to_str().unwrap();
        let status = Command::new(cargo())
            .current_dir(first.path())
            .args(["generate-lockfile"])
            .env("CARGO_HOME", home)
            .status()
            .expect("cargo should run");
        assert!(status.success(), "the fixture should resolve");
        std::fs::copy(
            first.path().join("Cargo.lock"),
            second.path().join("Cargo.lock"),
        )
        .unwrap();
        let settings = [
            ("TUIST_CARGO_CACHE_TARGET_VIEWS", "1"),
            ("CARGO_HOME", home),
        ];
        let check = ["check", "--offline"];

        cargo_with(
            first.path(),
            store.path(),
            &reports.path().join("first.json"),
            &check,
            &settings,
        );
        let units = |checkout: &Path| {
            managed(checkout)
                .join("check/debug/build/seeded-dep")
                .read_dir()
                .into_iter()
                .flatten()
                .flatten()
                .filter(|unit| unit.path().join("fingerprint").is_dir())
                .count()
        };
        if units(first.path()) == 0 {
            eprintln!("skipped: Cargo before 1.100 keeps no unit directories to copy");
            return;
        }
        let (seeded, stderr) = cargo_with(
            second.path(),
            store.path(),
            &reports.path().join("second.json"),
            &check,
            &settings,
        );
        assert!(
            stderr.contains("registry build units from"),
            "the new checkout's check should say what it copied: {stderr}"
        );
        assert_eq!(units(second.path()), units(first.path()));
        assert!(
            !managed(second.path()).join("debug").exists(),
            "a check should seed only its own lane"
        );
        assert_eq!(
            count(&seeded, "hits") + count(&seeded, "misses"),
            1,
            "only the workspace crate should be checked: {seeded}"
        );

        // The editor's checks keep a directory of their own the same way.
        let editor = ["check", "--offline", "--target-dir", "target/rust-analyzer"];
        cargo_with(
            first.path(),
            store.path(),
            &reports.path().join("first-editor.json"),
            &editor,
            &settings,
        );
        let (seeded, stderr) = cargo_with(
            second.path(),
            store.path(),
            &reports.path().join("second-editor.json"),
            &editor,
            &settings,
        );
        assert!(
            stderr.contains("registry build units from"),
            "the new checkout's editor check should say what it copied: {stderr}"
        );
        assert_eq!(
            count(&seeded, "hits") + count(&seeded, "misses"),
            1,
            "only the workspace crate should be checked: {seeded}"
        );
        assert!(
            !managed(second.path())
                .join("rust-analyzer/rust-analyzer")
                .exists(),
            "the editor's units belong in its own directory, not one below it"
        );
    }

    #[test]
    fn a_store_sweep_failure_still_frees_managed_target_directories() {
        let store = tempfile::tempdir().unwrap();
        let gone = tempfile::tempdir().unwrap();
        let current = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_named_project(gone.path(), "gone");
        write_named_project(current.path(), "current");

        build_with(
            gone.path(),
            store.path(),
            &reports.path().join("gone.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        let directory = managed(gone.path());
        assert!(
            std::fs::read_dir(store.path().join("incremental"))
                .unwrap()
                .next()
                .is_some(),
            "the build should record learned incremental state"
        );
        std::fs::remove_dir_all(gone.path()).unwrap();

        // Make the due store sweep fail after it writes its throttle stamp.
        // Target collection is independent and must not be skipped with it.
        let cas = store.path().join("actions/cas/v1");
        std::fs::remove_dir_all(&cas).unwrap();
        std::fs::write(&cas, b"not a directory").unwrap();
        build_with(
            current.path(),
            store.path(),
            &reports.path().join("current.json"),
            &[
                ("TUIST_CARGO_CACHE_TARGET_VIEWS", "1"),
                ("TUIST_CARGO_CACHE_GC_AUTO", "1"),
                ("TUIST_CARGO_CACHE_GC_INTERVAL", "0"),
            ],
        );

        // Target collection removes the gone checkout's directory, and that
        // is what the sweep reports even though the store half failed.
        wait_for_sweep_report(store.path());
        let log = std::fs::read_to_string(store.path().join("actions/gc/v1/sweep.log")).unwrap();
        assert!(log.contains("the store was not swept"), "{log}");
        assert!(
            !directory.exists(),
            "target collection should still run when store collection fails"
        );
        let report =
            std::fs::read_to_string(store.path().join("actions/gc/v1/last-sweep-report")).unwrap();
        assert!(
            report.contains("removed 1 target directories"),
            "the next build should hear about the target: {report}"
        );
    }

    #[test]
    fn explicit_gc_still_frees_targets_when_store_collection_fails() {
        let store = tempfile::tempdir().unwrap();
        let gone = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(gone.path());

        build_with(
            gone.path(),
            store.path(),
            &reports.path().join("gone.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")],
        );
        let directory = managed(gone.path());
        std::fs::remove_dir_all(gone.path()).unwrap();
        let cas = store.path().join("actions/cas/v1");
        std::fs::remove_dir_all(&cas).unwrap();
        std::fs::write(&cas, b"not a directory").unwrap();

        let output = cargo_cache_command()
            .args(["gc", "--max-size", "20GiB"])
            .env("TUIST_CARGO_CACHE_DIR", store.path())
            .output()
            .expect("tuist_cargo_cache should run");

        assert!(
            !output.status.success(),
            "the broken store should be reported"
        );
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(
            stdout.contains("removed 1 target directories"),
            "successful target collection should still be reported"
        );
        assert!(
            stdout.contains("removed 1 learned incremental directories"),
            "successful incremental collection should still be reported: {stdout}"
        );
        assert!(
            !directory.exists(),
            "explicit gc should collect targets independently of the store"
        );
    }

    #[test]
    fn a_noninteractive_build_adopts_a_real_target_directory() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        build_with(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "0")],
        );
        assert!(project.path().join("target").is_dir());

        // Captured stdio makes this non-interactive, as an agent's build is.
        let (_, stderr) = build_with(
            project.path(),
            store.path(),
            &reports.path().join("warm.json"),
            &[("CI", "0"), ("GITHUB_ACTIONS", "0")],
        );

        let link = std::fs::read_link(project.path().join("target"))
            .expect("the existing target directory should be adopted");
        assert!(
            link.starts_with(store.path()),
            "{} is not under the managed root",
            link.display()
        );
        assert!(stderr.contains("moved the existing target/ directory"));
        assert!(!stderr.contains("Compiling"), "adoption kept the outputs");
        assert!(project.path().join("target/debug/libfixture.rlib").exists());
    }

    #[test]
    fn a_ci_build_leaves_a_real_target_directory_in_place() {
        let store = tempfile::tempdir().unwrap();
        let project = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_project(project.path());
        build_with(
            project.path(),
            store.path(),
            &reports.path().join("cold.json"),
            &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "0")],
        );

        // A CI cache step saves target/ itself and would save only a link.
        build_with(
            project.path(),
            store.path(),
            &reports.path().join("warm.json"),
            &[("CI", "true")],
        );

        assert!(
            std::fs::read_link(project.path().join("target")).is_err(),
            "CI outputs stay where the cache step expects them"
        );
        assert!(project.path().join("target/debug/libfixture.rlib").exists());
    }
}

/// Build `project` into an explicit target directory, so two builds of the
/// same checkout differ only in where their outputs land.
fn build_into_target(
    project: &Path,
    store: &Path,
    target: &Path,
    settings: &[(&str, &str)],
) -> String {
    let mut command = cargo_cache_command();
    command
        .current_dir(project)
        .args(["build", "--offline"])
        .env("TUIST_CARGO_CACHE_DIR", store)
        .env("CARGO_TARGET_DIR", target)
        .env_remove("TUIST_CARGO_CACHE_INCREMENTAL")
        .env_remove("CARGO_INCREMENTAL")
        .env_remove("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL")
        .env_remove("TUIST_CARGO_CACHE_VERIFY")
        .env_remove("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE")
        .env_remove("CI")
        .env_remove("GITHUB_ACTIONS")
        .env_remove("TUIST_CARGO_CACHE_SHARE_OUT_DIR")
        .env_remove("TUIST_CARGO_CACHE_SOCKET")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER");
    for (name, value) in settings {
        command.env(name, value);
    }
    let output = command.output().expect("tuist_cargo_cache should run");
    assert!(
        output.status.success(),
        "build failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stderr).into_owned()
}

/// Read the dep-info rustc wrote for the fixture's library.
fn dep_info_contents(target: &Path) -> String {
    let path = find_files(&target.join("debug"), |path| {
        file_name_is(path, |name| {
            name.starts_with("fixture-") && name.ends_with(".d")
        })
    })
    .into_iter()
    .next()
    .expect("the library's dep-info should exist");
    std::fs::read_to_string(path).expect("dep-info should be readable")
}

/// A restored compilation must describe the checkout it was restored into.
///
/// Dep-info rules are keyed by absolute output paths, so a result stored
/// verbatim hands the next target directory rules naming the one that
/// published them. Cargo reads that file, and `TUIST_CARGO_CACHE_VERIFY=1` compares it, so
/// the stale spelling is both a wrong artifact and a permanent divergence.
#[test]
fn a_restored_dep_info_names_the_target_directory_it_was_restored_into() {
    let store = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_project(project.path());

    build_into_target(project.path(), store.path(), first.path(), &[]);
    build_into_target(project.path(), store.path(), second.path(), &[]);

    let restored = dep_info_contents(second.path());
    let foreign = first.path().to_string_lossy().into_owned();
    assert!(
        !restored.contains(&foreign),
        "restored dep-info still names the publishing target directory:\n{restored}"
    );
    assert!(
        restored.contains(&*second.path().to_string_lossy()),
        "restored dep-info should name this target directory:\n{restored}"
    );
}

/// The same compilation restored into a different target directory is what a
/// fresh compilation there would have produced.
///
/// Unix only, and the reason is worth stating. On Windows the compiled
/// artifact itself is not byte-identical between two target directories: with
/// everything else held constant -- one checkout, one set of sources,
/// incremental off -- the rlib still differs, because the debug information
/// records where the compilation wrote its objects. Nothing this fix does can
/// change that, and rewriting inside a compiled artifact would be corruption
/// rather than translation, so verification there reports a difference that is
/// real.
#[cfg(unix)]
#[test]
fn verification_is_clean_across_target_directories() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_project(project.path());

    build_into_target(project.path(), store.path(), first.path(), &[]);
    let report = reports.path().join("verify.json");
    let stderr = build_into_target(
        project.path(),
        store.path(),
        second.path(),
        &[
            ("TUIST_CARGO_CACHE_VERIFY", "1"),
            ("TUIST_CARGO_CACHE_STATS_REPORT", report.to_str().unwrap()),
        ],
    );
    let reported = stderr
        .lines()
        .filter(|line| line.contains("diverged"))
        .collect::<Vec<_>>()
        .join("\n");

    let stats: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&report).expect("a report should be written"))
            .expect("the report should be JSON");
    assert!(
        count(&stats, "verifications") > 0,
        "the run should have verified something: {stats}"
    );
    assert_eq!(
        count(&stats, "divergences"),
        0,
        "a restore into another target directory diverged: {reported}"
    );
}

/// Runtime-only writes in an implicit package input withhold publication but
/// must still audit a predicted result in full and sampled verification runs.
#[cfg(unix)]
#[test]
fn verification_audits_results_when_implicit_build_script_inputs_change() {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_project(project.path());
    std::fs::write(project.path().join("build.rs"), "fn main() {}\n").unwrap();
    let runtime = project.path().join("runtime.txt");
    std::fs::write(&runtime, "original\n").unwrap();
    let wrapper = reports.path().join("mutating-rustc");
    std::fs::write(
        &wrapper,
        r#"#!/bin/sh
"$TEST_REAL_RUSTC" "$@"
status=$?
case " $* " in
  *" --crate-name fixture "*)
    if [ "$status" -eq 0 ] && [ "$TEST_MUTATE_DURING_COMPILE" = 1 ]; then
      printf 'changed\n' > "$TEST_RUNTIME_PATH"
    fi
    ;;
esac
exit "$status"
"#,
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&wrapper).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&wrapper, permissions).unwrap();
    let rustc = which::which("rustc").unwrap();
    let settings = [
        ("TUIST_CARGO_CACHE_INCREMENTAL", "0"),
        ("TUIST_CARGO_CACHE_CACHE_LINKS", "0"),
        ("RUSTC", wrapper.to_str().unwrap()),
        ("TEST_REAL_RUSTC", rustc.to_str().unwrap()),
        ("TEST_RUNTIME_PATH", runtime.to_str().unwrap()),
    ];
    cargo_with(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
        &["check", "--offline"],
        &settings,
    );
    for mode in [
        "TUIST_CARGO_CACHE_VERIFY",
        "TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE",
    ] {
        std::fs::remove_dir_all(project.path().join("target")).unwrap();
        std::fs::write(&runtime, "original\n").unwrap();
        let mut settings = settings.to_vec();
        settings.extend([
            (
                mode,
                if mode == "TUIST_CARGO_CACHE_VERIFY" {
                    "1"
                } else {
                    "100"
                },
            ),
            ("TEST_MUTATE_DURING_COMPILE", "1"),
        ]);
        let (stats, stderr) = cargo_with(
            project.path(),
            store.path(),
            &reports.path().join("verify.json"),
            &["check", "--offline"],
            &settings,
        );
        assert!(
            stderr.contains("implicit build-script inputs changed"),
            "{stderr}"
        );
        assert_eq!(
            count(&stats, "verifications"),
            1,
            "{mode}: {stats}\n{stderr}"
        );
        assert_eq!(count(&stats, "divergences"), 0, "{mode}: {stats}\n{stderr}");
        assert_eq!(
            count(&stats["compiler"]["verification"], "invocations"),
            1,
            "the verification compile must be recorded exactly once: {stats}"
        );
    }
}

/// Write a fixture whose build script compiles C through `$CC`.
///
/// Deliberately hand-rolled rather than using the `cc` crate: this suite
/// resolves offline and takes no dependencies, and what is under test is the
/// shim the build script inherits, not the crate that would call it.
#[cfg(unix)]
fn write_c_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::create_dir_all(directory.join("include")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("include/hello.h"),
        "int hello_value(void);\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("src/hello.c"),
        "#include \"hello.h\"\nint hello_value(void) { return 7; }\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("build.rs"),
        r#"use std::{env, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    // The `cc` crate reads HOST_CC before CC when host and target agree, and
    // that is the variable tuist_cargo_cache sets; mirroring its precedence is what makes
    // this fixture exercise the same path a real build script takes.
    let compiler = env::var("HOST_CC")
        .or_else(|_| env::var("CC"))
        .unwrap_or_else(|_| "cc".into());
    let status = Command::new(&compiler)
        .arg("-O2")
        .arg("-Iinclude")
        .arg("-c")
        .arg("-o")
        .arg(out.join("hello.o"))
        .arg("src/hello.c")
        .status()
        .expect("the C compiler should run");
    assert!(status.success(), "the fixture's C should compile");
    // The tests disable build-script execution caching so the second checkout
    // reaches the compiler shim whose behavior is under test.
    println!("cargo:rustc-cfg=c_compiled");
}
"#,
    )
    .unwrap();
    std::fs::write(
        directory.join("src/lib.rs"),
        "pub fn value() -> u32 { 7 }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// Whether a C compiler is available to compile the fixture at all.
#[cfg(unix)]
fn has_c_compiler() -> bool {
    // Deliberately a real compilation rather than `cc -v`, which is what the
    // adapter's own identity probe runs. Sharing that signal would mean a
    // regression in the probe skipped these tests instead of failing them --
    // the feature would go dead and the suite would stay green.
    let Ok(directory) = tempfile::tempdir() else {
        return false;
    };
    let source = directory.path().join("probe.c");
    if std::fs::write(&source, "int probe(void) { return 0; }\n").is_err() {
        return false;
    }
    Command::new("cc")
        .arg("-c")
        .arg("-o")
        .arg(directory.path().join("probe.o"))
        .arg(&source)
        .output()
        .is_ok_and(|output| output.status.success())
}

/// Build the fixture in two fresh checkouts sharing one store, and report how
/// much the second one reused.
///
/// The hit count is the measure: a C compilation that crosses checkouts is one
/// more cached action than the same build without it. Compiler statistics are
/// keyed by outcome rather than by what was compiled, so they cannot tell the
/// C compile apart from the Rust one.
#[cfg(unix)]
fn warm_checkout_hits(settings: &[(&str, &str)]) -> u64 {
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_c_project(first.path());
    write_c_project(second.path());

    let settings: Vec<(&str, &str)> = [("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0")]
        .into_iter()
        .chain(settings.iter().copied())
        .collect();
    build_with(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
        &settings,
    );
    let (warm, _) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &settings,
    );
    count(&warm, "hits")
}

/// A build script's C compilation is cached, and a second checkout restores it
/// rather than compiling again.
#[cfg(unix)]
#[test]
fn a_build_script_c_compilation_crosses_checkouts() {
    if !has_c_compiler() {
        return;
    }
    let cached = warm_checkout_hits(&[]);
    let uncached = warm_checkout_hits(&[("TUIST_CARGO_CACHE_CC", "0")]);
    assert_eq!(
        cached,
        uncached + 1,
        "the C compilation should be exactly one more restored action"
    );
}

/// Write a fixture whose build script generates a header into `OUT_DIR` and
/// compiles several objects into that same directory.
///
/// This is the shape that a manifest counting every filename gets wrong: the
/// objects land beside the generated header, so what the key recorded depended
/// on how many sibling compilations had finished.
#[cfg(unix)]
fn write_generated_header_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    for name in ["a", "b", "c"] {
        std::fs::write(
            directory.join(format!("src/{name}.c")),
            format!("#include \"config.h\"\nint {name}(void) {{ return CONFIG_V; }}\n"),
        )
        .unwrap();
    }
    std::fs::write(
        directory.join("build.rs"),
        r##"use std::{env, fs, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    fs::write(out.join("config.h"), "#define CONFIG_V 7
").unwrap();
    let compiler = env::var("HOST_CC")
        .or_else(|_| env::var("CC"))
        .unwrap_or_else(|_| "cc".into());
    for name in ["a", "b", "c"] {
        let status = Command::new(&compiler)
            .arg(format!("-I{}", out.display()))
            .arg("-c")
            .arg("-o")
            .arg(out.join(format!("{name}.o")))
            .arg(format!("src/{name}.c"))
            .status()
            .expect("the C compiler should run");
        assert!(status.success());
    }
}
"##,
    )
    .unwrap();
    std::fs::write(
        directory.join("src/lib.rs"),
        "pub fn value() -> u32 { 7 }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// A header generated into `OUT_DIR` is cached like any other, even though the
/// build writes its objects into that same directory.
#[cfg(unix)]
#[test]
fn objects_landing_beside_a_generated_header_still_cross_checkouts() {
    if !has_c_compiler() {
        return;
    }
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_generated_header_project(first.path());
    write_generated_header_project(second.path());

    build_with(
        first.path(),
        store.path(),
        &reports.path().join("cold.json"),
        &[("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0")],
    );
    let (warm, _) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("warm.json"),
        &[("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0")],
    );
    assert_eq!(
        count(&warm, "hits"),
        5,
        "all three C compilations, the Rust one, and the build script should be restored: {warm}"
    );
}

/// A cached C warning names the checkout it is replayed in, not the one that
/// published it.
///
/// A compiler diagnostic names the file it is about, and a generated source
/// lives at an absolute path that differs per checkout, so replaying the stored
/// bytes verbatim would point the reader at somebody else's tree.
#[cfg(unix)]
#[test]
fn a_restored_c_diagnostic_names_the_checkout_it_is_replayed_in() {
    if !has_c_compiler() {
        return;
    }
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_warning_project(first.path());
    write_warning_project(second.path());

    build_with(
        first.path(),
        store.path(),
        &reports.path().join("cold.json"),
        &[],
    );
    let (warm, stderr) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("warm.json"),
        &[],
    );
    assert!(
        count(&warm, "hits") > 0,
        "the second checkout should have restored the compilation: {warm}"
    );
    let diagnostic = stderr
        .lines()
        .find(|line| line.contains("CCWARN>>>"))
        .unwrap_or_default();
    assert!(
        !diagnostic.contains(&first.path().display().to_string()),
        "a replayed warning must not name the checkout that published it: {diagnostic}"
    );
}

/// A fixture whose build script compiles a generated source that warns, so the
/// diagnostic carries an absolute path.
#[cfg(unix)]
fn write_warning_project(directory: &Path) {
    std::fs::create_dir_all(directory.join("src")).unwrap();
    std::fs::write(
        directory.join("Cargo.toml"),
        "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(
        directory.join("build.rs"),
        r##"use std::{env, fs, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    let source = out.join("gen.c");
    fs::write(&source, "int value(void) { int unused = 1; return 7; }
").unwrap();
    let compiler = env::var("HOST_CC")
        .or_else(|_| env::var("CC"))
        .unwrap_or_else(|_| "cc".into());
    let output = Command::new(&compiler)
        .arg("-Wall")
        .arg("-c")
        .arg("-o")
        .arg(out.join("gen.o"))
        .arg(&source)
        .output()
        .expect("the C compiler should run");
    for line in String::from_utf8_lossy(&output.stderr).lines() {
        println!("cargo:warning=CCWARN>>>{line}");
    }
    assert!(output.status.success());
}
"##,
    )
    .unwrap();
    std::fs::write(
        directory.join("src/lib.rs"),
        "pub fn value() -> u32 { 7 }\n",
    )
    .unwrap();
    generate_lockfile(directory);
}

/// A prediction that no longer describes the tree must not strand the
/// compilation.
///
/// This adapter has no second way to build a key, so a stale prediction that
/// aborted the cache path would fail identically on every later build. The
/// recovery is what the test pins: compile, republish, and hit next time.
#[cfg(unix)]
#[test]
fn a_stale_prediction_recovers_instead_of_stranding_the_compilation() {
    if !has_c_compiler() {
        return;
    }
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let project = tempfile::tempdir().unwrap();
    write_c_project(project.path());

    // Record a prediction that names the header.
    build_with(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
        &[],
    );

    // Delete the header and stop including it. The command line is untouched,
    // so the invocation still resolves to the same prediction -- one that now
    // names a file that is gone.
    std::fs::remove_file(project.path().join("include/hello.h")).unwrap();
    std::fs::write(
        project.path().join("src/hello.c"),
        "int hello_value(void) { return 7; }\n",
    )
    .unwrap();

    let (recovered, _) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("recover.json"),
        &[],
    );
    assert_eq!(
        recovered["bypasses"].get("cc-input-read"),
        None,
        "a stale prediction is not a bypass: {recovered}"
    );

    // A second checkout of the same modified sources shares the store but none
    // of the outputs, so what it restores is what the recovery republished.
    let second = tempfile::tempdir().unwrap();
    write_c_project(second.path());
    std::fs::remove_file(second.path().join("include/hello.h")).unwrap();
    std::fs::write(
        second.path().join("src/hello.c"),
        "int hello_value(void) { return 7; }\n",
    )
    .unwrap();
    let (warm, _) = build_with(
        second.path(),
        store.path(),
        &reports.path().join("warm.json"),
        &[],
    );
    assert_eq!(
        count(&warm, "hits"),
        3,
        "the Rust, the C, and the build script's own compilation should be restored: {warm}"
    );
}

/// A build that chose its own compiler keeps it.
///
/// `CC` is commonly exported machine-wide, so the shim standing aside is the
/// difference between redirecting a build the user configured and leaving it
/// alone.
#[cfg(unix)]
#[test]
fn an_existing_cc_setting_is_left_alone() {
    if !has_c_compiler() {
        return;
    }
    let chosen = which::which("cc").expect("cc should resolve");
    let preset = warm_checkout_hits(&[("HOST_CC", chosen.to_str().unwrap())]);
    let uncached = warm_checkout_hits(&[("TUIST_CARGO_CACHE_CC", "0")]);
    assert_eq!(
        preset, uncached,
        "tuist_cargo_cache should not have intercepted a compiler the build chose"
    );
}

/// The object a cache hit restores is the object the compiler produced.
#[cfg(unix)]
#[test]
fn a_restored_object_is_byte_identical_to_a_compiled_one() {
    if !has_c_compiler() {
        return;
    }
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    write_c_project(first.path());
    write_c_project(second.path());

    build_with(
        first.path(),
        store.path(),
        &reports.path().join("first.json"),
        &[],
    );
    build_with(
        second.path(),
        store.path(),
        &reports.path().join("second.json"),
        &[],
    );

    let compiled = find_object(first.path()).expect("the first checkout should have an object");
    let restored = find_object(second.path()).expect("the second checkout should have an object");
    assert_eq!(
        std::fs::read(&compiled).unwrap(),
        std::fs::read(&restored).unwrap(),
        "a restored object must match the one that was compiled"
    );
}

/// Find the fixture's object file beneath a checkout's target directory.
#[cfg(unix)]
fn find_object(project: &Path) -> Option<std::path::PathBuf> {
    let target = project.join("target");
    let root = std::fs::read_link(&target).unwrap_or(target);
    let mut pending = vec![root];
    while let Some(directory) = pending.pop() {
        for entry in std::fs::read_dir(&directory).ok()? {
            let entry = entry.ok()?;
            let path = entry.path();
            if path.is_dir() {
                pending.push(path);
            } else if path.file_name().is_some_and(|name| name == "hello.o") {
                return Some(path);
            }
        }
    }
    None
}

#[test]
fn wrapper_phase_reports_and_trace_cover_real_cold_and_warm_builds() {
    let project = tempfile::tempdir().unwrap();
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());
    let settings = [
        ("TUIST_CARGO_CACHE_TARGET_VIEWS", "0"),
        ("TUIST_CARGO_CACHE_INCREMENTAL", "0"),
    ];
    let (cold, stderr) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
        &settings,
    );
    assert!(
        cold["wrapper_phases_ns"]["compiler"]
            .as_u64()
            .is_some_and(|n| n > 0),
        "cold report: {cold}\n{stderr}"
    );
    assert!(cold["wrapper_phases_ns"]["store"].as_u64().unwrap() > 0);
    std::fs::remove_dir_all(project.path().join("target")).unwrap();
    let (warm, _) = build_with(
        project.path(),
        store.path(),
        &reports.path().join("warm.json"),
        &settings,
    );
    assert!(count(&warm, "hits") > 0);
    for name in ["startup", "key", "lookup", "restore", "unattributed"] {
        assert!(
            warm["wrapper_phases_ns"][name].as_u64().unwrap() > 0,
            "{name}: {warm}"
        );
    }
    // Follow the same discovery a user does: session streams live under the
    // store, and cache trace reads their published JSONL contract.
    let store_path = store.path().join("actions/sessions/v1");
    let mut exported = 0;
    for entry in std::fs::read_dir(&store_path).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_none_or(|ext| ext != "jsonl") {
            continue;
        }
        let output = cargo_cache_command()
            .args(["cache", "trace"])
            .arg(&path)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let trace: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert!(!trace["traceEvents"].as_array().unwrap().is_empty());
        for line in std::fs::read_to_string(path).unwrap().lines() {
            let event: serde_json::Value = serde_json::from_str(line).unwrap();
            if event["type"] != "wrapper_timing" {
                continue;
            }
            let timing = &event["timing"];
            let total: u64 = timing["phases_ns"]
                .as_object()
                .unwrap()
                .values()
                .map(|v| v.as_u64().unwrap())
                .sum();
            assert_eq!(total, timing["duration_ns"].as_u64().unwrap());
        }
        exported += 1;
    }
    assert!(exported >= 2);
}

#[test]
fn sampled_verification_reaches_wrappers_and_full_verification_overrides_it() {
    let project = tempfile::tempdir().unwrap();
    let store = tempfile::tempdir().unwrap();
    let reports = tempfile::tempdir().unwrap();
    write_project(project.path());
    let settings = [
        ("TUIST_CARGO_CACHE_TARGET_VIEWS", "0"),
        ("TUIST_CARGO_CACHE_INCREMENTAL", "0"),
    ];
    build_with(
        project.path(),
        store.path(),
        &reports.path().join("cold.json"),
        &settings,
    );
    for (rate, full, should_verify) in [("100", "0", true), ("0", "0", false), ("0", "1", true)] {
        std::fs::remove_dir_all(project.path().join("target")).unwrap();
        let mut settings = settings.to_vec();
        settings.extend([
            ("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE", rate),
            ("TUIST_CARGO_CACHE_VERIFY", full),
        ]);
        let (stats, stderr) = build_with(
            project.path(),
            store.path(),
            &reports.path().join("warm.json"),
            &settings,
        );
        if should_verify {
            assert!(count(&stats, "verifications") > 0, "{stats}\n{stderr}");
            assert_eq!(count(&stats, "divergences"), 0, "{stats}\n{stderr}");
        } else {
            assert!(count(&stats, "hits") > 0, "{stats}\n{stderr}");
            assert_eq!(count(&stats, "verifications"), 0);
        }
    }
}

#[test]
fn routine_shim_logs_obey_session_filters_without_fingerprint_pollution() {
    for (filter, visible) in [
        ("info", false),
        ("off,tuist_cargo_cache::session=debug", true),
        ("debug,tuist_cargo_cache::session=off", false),
        (
            "off,tuist_cargo_cache::session=debug/never-match-this-message",
            false,
        ),
    ] {
        let project = tempfile::tempdir().unwrap();
        let store = tempfile::tempdir().unwrap();
        write_project(project.path());
        let report = project.path().join("report.json");
        // rustc queries made by Cargo take the routine bypass path.
        let (_, stderr) = build_with(
            project.path(),
            store.path(),
            &report,
            &[("TUIST_CARGO_CACHE_LOG", filter)],
        );
        let lines: Vec<_> = stderr
            .lines()
            .filter(|line| line.contains("rustc cache bypassed:"))
            .collect();
        assert_eq!(!lines.is_empty(), visible, "filter {filter}: {stderr}");
        for line in lines {
            assert!(line.contains("DEBUG"), "wrong severity: {line}");
        }
        let mut pending = vec![project.path().join("target")];
        while let Some(path) = pending.pop() {
            if path.is_dir() {
                pending.extend(
                    std::fs::read_dir(path)
                        .unwrap()
                        .map(|entry| entry.unwrap().path()),
                );
            } else if path
                .file_name()
                .is_some_and(|name| name.to_string_lossy().starts_with("output-"))
            {
                let bytes = std::fs::read(&path).unwrap();
                assert!(
                    !String::from_utf8_lossy(&bytes).contains("cache bypassed:"),
                    "polluted fingerprint: {}",
                    path.display()
                );
            }
        }
        let (_, fresh_stderr) = build_with(
            project.path(),
            store.path(),
            &report,
            &[("TUIST_CARGO_CACHE_LOG", "off")],
        );
        assert!(
            !fresh_stderr.contains("cache bypassed:"),
            "replayed diagnostic: {fresh_stderr}"
        );
    }
}

#[cfg(unix)]
#[test]
fn routine_shim_logs_stay_off_compiler_stderr_when_delivery_fails() {
    let directory = tempfile::tempdir().unwrap();
    let shim = tuist_cargo_cache::session::install_shim(
        Path::new(env!("CARGO_BIN_EXE_tuist-cargo-cache-model")),
        directory.path(),
        tuist_cargo_cache::session::ShimLink::Tracking,
    )
    .unwrap();
    // A query bypasses compilation before running this stand-in compiler.
    let compiler = directory.path().join("compiler");
    std::fs::write(
        &compiler,
        "#!/bin/sh\nprintf 'compiler stdout\\n'\nprintf 'compiler stderr\\n' >&2\n",
    )
    .unwrap();
    std::fs::set_permissions(&compiler, std::fs::Permissions::from_mode(0o755)).unwrap();
    let output = isolated_command(shim)
        .arg(compiler)
        .arg("--version")
        .env(
            "TUIST_CARGO_CACHE_SOCKET",
            directory.path().join("missing-agent.sock"),
        )
        .env("TUIST_CARGO_CACHE_LOG", "debug")
        .env_remove("TUIST_CARGO_CACHE_PREVIOUS_RUSTC_WRAPPER")
        .env_remove("TUIST_CARGO_CACHE_PREVIOUS_RUSTC_WORKSPACE_WRAPPER")
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    assert_eq!(output.stdout, b"compiler stdout\n");
    assert_eq!(output.stderr, b"compiler stderr\n");
}

/// Publication can refuse a successful compile. The reason must remain
/// available in release builds without contaminating the compiler's stderr.
#[cfg(unix)]
#[test]
fn cc_publication_failures_are_visible_without_counting_a_second_outcome() {
    if !has_c_compiler() {
        return;
    }
    for (filter, visible) in [("off", false), ("debug", true)] {
        let project = tempfile::tempdir().unwrap();
        let store = tempfile::tempdir().unwrap();
        let reports = tempfile::tempdir().unwrap();
        write_c_project(project.path());
        std::fs::write(
            project.path().join("src/hello.c"),
            "const char *build_date(void) { return __DATE__; }\n",
        )
        .unwrap();
        let script = project.path().join("build.rs");
        let source = std::fs::read_to_string(&script).unwrap()
            .replace(".status()", ".output()")
            .replace("status.success()", "status.status.success()")
            .replace("// The tests disable", "assert!(status.stderr.is_empty(), \"compiler stderr was polluted: {:?}\", status.stderr);\n    // The tests disable");
        std::fs::write(script, source).unwrap();
        let log = reports.path().join("bypass.log");
        let (stats, stderr) = build_with(
            project.path(),
            store.path(),
            &reports.path().join("stats.json"),
            &[
                ("TUIST_CARGO_CACHE_LOG", filter),
                ("TUIST_CARGO_CACHE_BYPASS_LOG", log.to_str().unwrap()),
            ],
        );
        let diagnostics: Vec<_> = stderr
            .lines()
            .filter(|line| line.contains("cc result was not published for cc:hello.c"))
            .collect();
        assert_eq!(!diagnostics.is_empty(), visible, "{stderr}");
        assert!(
            diagnostics.iter().all(|line| line.contains("DEBUG")),
            "{stderr}"
        );
        let log = std::fs::read_to_string(log).unwrap();
        assert!(log.contains("input expands a timestamp macro:"), "{log}");
        assert!(log.contains("unit=cc:hello.c"), "{log}");
        assert!(
            stats["bypasses"]
                .get("cc-embedded-timestamp-macro")
                .is_none(),
            "publication must not double-count the compilation: {stats}"
        );
        assert!(
            stats["wrapper_phases_ns"]["include_scan"]
                .as_u64()
                .unwrap_or(0)
                > 0,
            "{stats}"
        );
    }
}

#[cfg(unix)]
#[test]
fn private_shims_keep_native_builds_cached_across_checkouts() {
    if !has_c_compiler() {
        return;
    }
    let cached = private_shims_warm_hits(&[]);
    let uncached = private_shims_warm_hits(&[("TUIST_CARGO_CACHE_CC", "0")]);
    assert_eq!(
        cached,
        uncached + 1,
        "private shims should restore exactly one additional C compilation"
    );
}

#[cfg(unix)]
fn private_shims_warm_hits(settings: &[(&str, &str)]) -> u64 {
    let directory = tempfile::tempdir().unwrap();
    let cache = directory.path().join("cache");
    let mut warm_hits = 0;
    for name in ["first", "second"] {
        let project = directory.path().join(name);
        write_c_project(&project);
        let shims = directory.path().join(format!("{name} shims"));
        let report = directory.path().join(format!("{name}.json"));
        let settings: Vec<(&str, &str)> = [
            ("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0"),
            ("TUIST_CARGO_CACHE_SHIMS_DIR", shims.to_str().unwrap()),
        ]
        .into_iter()
        .chain(settings.iter().copied())
        .collect();
        let (stats, _) = build_with(&project, &cache, &report, &settings);
        if name == "second" {
            warm_hits = count(&stats, "hits");
        }
        if !settings.contains(&("TUIST_CARGO_CACHE_CC", "0")) {
            let cc = native_shim(&shims, tuist_cargo_cache::session::CC_SHIM_STEM);
            assert!(
                cc.is_file(),
                "the configured persistent compiler should exist"
            );
            let probe = isolated_command(&cc).arg("--version").output().unwrap();
            assert!(
                probe.status.success(),
                "the compiler path must outlive its session: {}",
                String::from_utf8_lossy(&probe.stderr)
            );
        }
        // The same directory works on a later invocation with retained outputs.
        build_with(&project, &cache, &report, &settings);
    }
    assert!(
        !cache.join("shims").exists(),
        "the shared default must remain untouched"
    );
    warm_hits
}

/// The one native shim named `stem` a single tuist_cargo_cache binary installed under
/// `shims`.
#[cfg(unix)]
fn native_shim(shims: &Path, stem: &str) -> PathBuf {
    let binaries: Vec<_> = std::fs::read_dir(shims.join("native"))
        .expect("sessions should install native shims per binary")
        .map(|entry| entry.unwrap().path())
        .collect();
    assert_eq!(binaries.len(), 1, "one binary built here: {binaries:?}");
    binaries[0].join(stem)
}

/// Two tuist_cargo_cache installations sharing one cache, as concurrent CI jobs on a
/// self-hosted runner do, each with its own tool directory.
///
/// The C shim handed to build scripts used to be one machine-wide symlink,
/// repointed at whichever binary started a session last. A job whose binary
/// was then cleaned up left every other job's `HOST_CC` dangling, and their
/// next C compile failed with `ToolNotFound`.
#[cfg(unix)]
#[test]
fn another_installation_leaving_does_not_strand_the_c_shim() {
    if !has_c_compiler() {
        return;
    }
    let directory = tempfile::tempdir().unwrap();
    let cache = directory.path().join("cache");
    let mut recorded = Vec::new();
    for name in ["staying", "leaving"] {
        let install = directory.path().join(format!("{name} install"));
        std::fs::create_dir(&install).unwrap();
        let executable = install.join("tuist_cargo_cache");
        std::fs::copy(env!("CARGO_BIN_EXE_tuist-cargo-cache-model"), &executable).unwrap();
        let project = directory.path().join(name);
        std::fs::create_dir_all(project.join("src")).unwrap();
        std::fs::write(
            project.join("Cargo.toml"),
            "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
        )
        .unwrap();
        std::fs::write(project.join("src/lib.rs"), "").unwrap();
        std::fs::write(
            project.join("build.rs"),
            r#"fn main() {
    let compiler = std::env::var("HOST_CC").unwrap_or_default();
    std::fs::write(std::env::var("HOST_CC_RECORD").unwrap(), compiler).unwrap();
}
"#,
        )
        .unwrap();
        generate_lockfile(&project);
        let record = directory.path().join(format!("{name}.host-cc"));
        cargo_with_command(
            isolated_command(&executable),
            &project,
            &cache,
            &directory.path().join(format!("{name}.json")),
            &["build", "--offline"],
            &[
                ("TUIST_CARGO_CACHE_GC_AUTO", "0"),
                ("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0"),
                ("HOST_CC_RECORD", record.to_str().unwrap()),
            ],
        );
        let host_cc = PathBuf::from(std::fs::read_to_string(&record).unwrap());
        assert!(
            host_cc.starts_with(cache.join("shims")),
            "{name} should build through a C shim: {}",
            host_cc.display()
        );
        recorded.push(host_cc);
    }
    assert_ne!(recorded[0], recorded[1], "each installation owns its shim");
    std::fs::remove_dir_all(directory.path().join("leaving install")).unwrap();

    // The staying job's build is still running with the path it was handed.
    let probe = isolated_command(&recorded[0])
        .arg("--version")
        .output()
        .unwrap();
    assert!(
        probe.status.success(),
        "the shim a running build was handed must survive another install leaving: {}",
        String::from_utf8_lossy(&probe.stderr)
    );
}

#[cfg(unix)]
#[test]
fn private_shims_support_nested_exec_and_survive_the_command() {
    if !has_c_compiler() {
        return;
    }
    let directory = tempfile::tempdir().unwrap();
    let cache = directory.path().join("cache");
    let shims = directory.path().join("private shims");
    std::fs::write(
        directory.path().join("input.c"),
        "int value(void) { return 7; }\n",
    )
    .unwrap();
    let output = cargo_cache_command()
        .current_dir(directory.path())
        .env("TUIST_CARGO_CACHE_DIR", &cache)
        .env("TUIST_CARGO_CACHE_SHIMS_DIR", &shims)
        .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
        .env("TEST_TUIST_CARGO_CACHE_BINARY", env!("CARGO_BIN_EXE_tuist-cargo-cache-model"))
        .args([
            "exec",
            "sh",
            "-c",
            "command -v cc; \"$TEST_TUIST_CARGO_CACHE_BINARY\" exec sh -c 'cc -c input.c -o result.o'",
        ])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        shims.join("cc").to_str().unwrap()
    );
    assert!(directory.path().join("result.o").is_file());
    assert!(!cache.join("shims").exists());
    let probe = isolated_command(shims.join("cc"))
        .arg("--version")
        .output()
        .unwrap();
    assert!(probe.status.success());
}

#[test]
fn cargo_cache_clean_under_reports_when_a_deleted_root_has_no_records() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("cache");
    let root = directory.path().join("deleted").join("session");
    assert!(!root.exists());

    let output = cargo_cache_command()
        .args(["clean", "--under"])
        .arg(&root)
        .env("TUIST_CARGO_CACHE_DIR", &store)
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("tuist_cargo_cache clean --under should run");

    assert!(
        output.status.success(),
        "clean failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        format!("nothing found under {}", root.display())
    );
}

#[cfg(unix)]
#[test]
fn cargo_cache_clean_under_does_not_invoke_cargo_for_a_missing_root() {
    use std::os::unix::fs::PermissionsExt as _;

    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("cache");
    let root = directory.path().join("deleted/session");
    let cargo = directory.path().join("cargo-that-must-not-run");
    let invoked = directory.path().join("cargo-was-invoked");
    std::fs::write(
        &cargo,
        "#!/bin/sh\nprintf called > \"$TUIST_CARGO_CACHE_TEST_CARGO_INVOKED\"\nexit 1\n",
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&cargo).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&cargo, permissions).unwrap();

    let output = cargo_cache_command()
        .args(["clean", "--under"])
        .arg(&root)
        .env("CARGO", &cargo)
        .env("TUIST_CARGO_CACHE_TEST_CARGO_INVOKED", &invoked)
        .env("TUIST_CARGO_CACHE_DIR", &store)
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("tuist_cargo_cache clean --under should run");

    assert!(
        output.status.success(),
        "clean failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(!invoked.exists(), "clean --under must not run Cargo");
}

#[test]
fn cargo_cache_clean_under_rejects_relative_and_root_paths_and_conflicting_workspace() {
    let directory = tempfile::tempdir().unwrap();
    let store = directory.path().join("cache");
    for arguments in [
        vec!["clean", "--under", "relative/root"],
        vec!["clean", "--under", "/"],
        vec!["clean", "workspace", "--under", "/tmp/session"],
    ] {
        let output = cargo_cache_command()
            .current_dir(directory.path())
            .args(arguments)
            .env("TUIST_CARGO_CACHE_DIR", &store)
            .env_remove("CARGO_TARGET_DIR")
            .output()
            .expect("tuist_cargo_cache clean should run");
        assert!(
            !output.status.success(),
            "arguments unexpectedly succeeded: {}",
            String::from_utf8_lossy(&output.stdout)
        );
    }
}
