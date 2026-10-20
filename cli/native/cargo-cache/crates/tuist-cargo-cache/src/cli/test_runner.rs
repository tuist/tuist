//! Test binaries under the machine-wide permit pool.
//!
//! The pool paces compilers, but `cargo test` spends much of its time running
//! test binaries, and libtest sizes itself to the whole machine. Three
//! worktrees testing at once are three suites each starting a thread per CPU.
//! With `scheduler.tests`, tuist_cargo_cache installs itself as Cargo's target runner for
//! the command; each test binary then waits for permits like a compiler does,
//! and chains to whatever runner was configured before.
//!
//! Work a test starts is charged to the test's own permits: its children see
//! scheduling turned off. Otherwise a test that builds something -- trybuild,
//! compile-fail suites, tuist_cargo_cache's own integration tests -- would hold permits
//! while its compilers waited for more, and two of them could hold the whole
//! pool between them and wait on each other forever.
use eyre::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const SHIM: &str = "tuist_cargo_cache-test-runner";
/// Shortest run whose CPU use is worth measuring. Below this, start-up
/// dominates the average, so a complete run is remembered as one core.
const MIN_CPU_SAMPLE: std::time::Duration = std::time::Duration::from_secs(1);
/// The [`Overlay`] the shim reads back.
const RUNNERS: &str = "TUIST_CARGO_CACHE_TEST_RUNNERS";

/// What the shim needs from the command that installed it.
#[derive(Debug, Default, Serialize, Deserialize)]
struct Overlay {
    /// The runner each target had before this one, by target triple.
    runners: BTreeMap<String, Option<Runner>>,
    /// The caller's value of each runner key this overlay replaced, handed
    /// back to the test so a Cargo command it runs finds its own runners
    /// rather than a shim its `PATH` may no longer reach.
    restore: BTreeMap<String, Option<String>>,
    /// The repository the tests belong to, as [`repository_identity`] names
    /// it, so unrelated projects keep separate history.
    #[serde(default)]
    project: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
struct Runner {
    path: PathBuf,
    args: Vec<OsString>,
}

pub(super) struct TestRunner {
    /// Runner environment keys, each paired with the triple it names.
    keys: Vec<(String, String)>,
    runners: BTreeMap<String, Option<Runner>>,
    project: Option<String>,
    shim: PathBuf,
}

impl TestRunner {
    /// Wrap this command's test binaries, when it is a `cargo test` and
    /// scheduling them is on. `None` leaves Cargo's runners alone.
    pub(super) fn prepare(
        config: &crate::config::Config,
        arguments: &[String],
        workspace_root: &Path,
        directory: &Path,
    ) -> Result<Option<Self>> {
        if !config.scheduler.enabled || !config.scheduler.tests || !wraps(arguments) {
            return Ok(None);
        }
        // Resolution is best-effort, like the pool itself: a configuration
        // tuist_cargo_cache cannot read runs the tests unscheduled rather than failing.
        let resolved = (|| -> Result<_> {
            let cargo = super::launch::load_cargo_config()?;
            let inherited = inherited_overlay().runners;
            let mut keys = Vec::new();
            let mut runners = BTreeMap::new();
            for target in super::launch::requested_targets(&cargo, arguments)? {
                let triple = target.triple().to_owned();
                let runner = cargo.runner(&target)?.map(|runner| Runner {
                    path: runner.path,
                    args: runner.args,
                });
                // A nested tuist_cargo_cache sees the outer one's shim as the configured
                // runner. Chaining to it would loop; chain to what it wraps.
                // Only when there is an outer overlay for this target, though:
                // otherwise the runner merely shares the shim's name.
                let runner = match (runner, inherited.get(&triple)) {
                    (Some(runner), Some(wrapped)) if is_shim(&runner.path) => wrapped.clone(),
                    (runner, _) => runner,
                };
                keys.push((super::launch::runner_key(&target), triple.clone()));
                runners.insert(triple, runner);
            }
            Ok((keys, runners))
        })();
        let (keys, runners) = match resolved {
            Ok(resolved) => resolved,
            Err(error) => {
                log::debug!("running tests without machine-wide permits: {error:#}");
                return Ok(None);
            }
        };
        let shim = crate::session::install_shim_named(
            &std::env::current_exe()?,
            directory,
            SHIM,
            crate::session::ShimLink::Tracking,
        )?;
        Ok(Some(Self {
            keys,
            runners,
            project: repository_identity(workspace_root),
            shim,
        }))
    }

    pub(super) fn environment(&self, environment: &mut BTreeMap<String, String>) -> Result<()> {
        // Cargo splits a runner from the environment on whitespace, so the
        // shim is named through PATH, as `cargo run`'s launch shim is, and
        // the triple rides along as its first argument.
        let path = environment
            .get("PATH")
            .map(OsString::from)
            .or_else(|| std::env::var_os("PATH"))
            .unwrap_or_default();
        let path = std::env::join_paths(
            std::iter::once(self.shim.parent().unwrap().to_path_buf())
                .chain(std::env::split_paths(&path)),
        )?;
        environment.insert("PATH".into(), path.to_string_lossy().into_owned());
        let mut restore = BTreeMap::new();
        for (key, triple) in &self.keys {
            restore.insert(key.clone(), std::env::var(key).ok());
            environment.insert(key.clone(), format!("{SHIM} {triple}"));
        }
        let overlay = Overlay {
            runners: self.runners.clone(),
            restore,
            project: self.project.clone(),
        };
        environment.insert(RUNNERS.into(), serde_json::to_string(&overlay)?);
        Ok(())
    }
}

/// Whether a Cargo command line runs test binaries tuist_cargo_cache can wrap.
///
/// Configuration overrides on the command line are out of reach for the same
/// reason as in `cargo run`'s launch: cargo-config2 cannot resolve them, and
/// an unknown runner must never be replaced. A directory change is one too:
/// Cargo reads configuration from the new directory, cargo-config2 from this
/// one.
fn wraps(arguments: &[String]) -> bool {
    let args: Vec<_> = arguments
        .iter()
        .take_while(|arg| arg.as_str() != "--")
        .collect();
    matches!(
        super::launch::cargo_subcommand(arguments),
        Some("test" | "t")
    ) && !args.iter().any(|arg| {
        arg.starts_with('+')
            || arg.starts_with("-C")
            || matches!(
                arg.as_str(),
                "--config" | "--directory" | "--help" | "-h" | "--no-run"
            )
            || arg.starts_with("--config=")
            || arg.starts_with("--directory=")
    })
}

fn is_shim(path: &Path) -> bool {
    path.file_stem() == Some(OsStr::new(SHIM))
}

fn inherited_overlay() -> Overlay {
    std::env::var(RUNNERS)
        .ok()
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_default()
}

/// Run one test binary once the pool has room for it.
pub fn dispatch() -> Option<ExitCode> {
    let mut arguments = std::env::args_os();
    if arguments.next().is_none_or(|arg| !is_shim(Path::new(&arg))) {
        return None;
    }
    let result = (|| -> Result<ExitCode> {
        let triple = arguments
            .next()
            .ok_or_else(|| eyre::eyre!("missing target triple"))?;
        let executable = arguments
            .next()
            .ok_or_else(|| eyre::eyre!("Cargo supplied no test binary"))?;
        let rest: Vec<OsString> = arguments.collect();
        let mut overlay = inherited_overlay();
        let runner = overlay.runners.remove(&*triple.to_string_lossy()).flatten();
        let mut command = match &runner {
            Some(runner) => {
                let mut command = Command::new(&runner.path);
                command.args(&runner.args).arg(&executable);
                command
            }
            None => Command::new(&executable),
        };
        command
            .args(&rest)
            // Explicitly off for shims the test's own builds run, and for any
            // tuist_cargo_cache command it starts: that work is charged to this permit.
            .env(crate::scheduler::SCHED_DIR_ENV, "")
            .env("TUIST_CARGO_CACHE_SCHEDULER", "0")
            .env("TUIST_CARGO_CACHE_CONTROL_CHILD", "1")
            .env_remove(RUNNERS);
        for (key, value) in &overlay.restore {
            match value {
                Some(value) => command.env(key, value),
                None => command.env_remove(key),
            };
        }
        // Cargo names its test binaries with a metadata hash. Rustdoc runs
        // each doctest through the same runner, from a temporary binary with
        // no hash, and those run unscheduled: a permit per doctest would
        // serialize a crate's doc examples behind half the pool apiece.
        let demand = test_binary_name(Path::new(&executable)).map(|name| {
            crate::scheduler::Demand::test(
                &ledger_name(
                    overlay.project.as_deref(),
                    std::env::var("CARGO_PKG_NAME").ok().as_deref(),
                    &name,
                ),
                test_threads(&rest, std::env::var("RUST_TEST_THREADS").ok().as_deref()),
            )
        });
        // Listing a suite starts no tests and costs nothing worth waiting for.
        let permit = demand
            .as_ref()
            .filter(|_| !lists_tests(&rest))
            .and_then(|demand| {
                crate::scheduler::pool()?
                    .admit(demand)
                    .map(|permit| (demand, permit))
            });
        let started = std::time::Instant::now();
        let status = command
            .status()
            .wrap_err_with(|| format!("failed to run {}", Path::new(&executable).display()))?;
        let wall = started.elapsed();
        if let Some((demand, permit)) = permit {
            crate::scheduler::record_compiler_memory(demand, &status);
            // A run that exited on its own, failing tests included, ran the
            // whole suite; one a signal stopped, or one narrowed to some of
            // its tests, says little about what the suite costs.
            if status.code().is_some() && !narrows_suite(&rest) {
                // A suite this quick cannot keep cores busy long enough to
                // matter, but unrecorded it would ask for half the pool on
                // every run. Weigh it one core; a longer run raises that.
                // Where CPU time cannot be measured nothing could raise it,
                // so nothing is recorded.
                let cores = crate::scheduler::child_cpu_time().map(|cpu| {
                    if wall < MIN_CPU_SAMPLE {
                        1
                    } else {
                        crate::scheduler::average_cores(cpu, wall)
                    }
                });
                if let Some(cores) = cores {
                    crate::scheduler::record_test_cpu(demand, cores);
                }
            }
            drop(permit);
        }
        Ok(super::cargo::exit_code(status))
    })();
    Some(result.unwrap_or_else(|error| {
        eprintln!("tuist_cargo_cache[error]: failed to run test binary: {error:#}");
        ExitCode::FAILURE
    }))
}

/// A Cargo test binary's name without the metadata hash Cargo appends to it,
/// so its memory history survives the hash changing. `None` for anything
/// without that hash, which is not a binary Cargo built.
fn test_binary_name(executable: &Path) -> Option<String> {
    let stem = executable.file_stem()?.to_str()?;
    let (name, hash) = stem.rsplit_once('-')?;
    (!name.is_empty() && hash.len() == 16 && hash.bytes().all(|byte| byte.is_ascii_hexdigit()))
        .then(|| name.to_owned())
}

/// What a test binary's history is remembered under.
///
/// The ledger is shared by every project on the machine, and both package and
/// test names repeat across projects -- `server`, `tests/integration.rs` -- so
/// the repository and the package Cargo is testing are part of the name.
/// Neither a package name nor a binary name can hold a `/`.
fn ledger_name(project: Option<&str>, package: Option<&str>, binary: &str) -> String {
    [project, package, Some(binary)]
        .into_iter()
        .flatten()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("/")
}

/// A short name for the Git repository `workspace_root` is in, the same for
/// each of its worktrees and different for any other repository.
///
/// Not the checkout path, which would keep a project's worktrees from sharing
/// what one of them measured: a linked worktree's `.git` file points into the
/// main repository, whose directory every worktree shares. Read from the files
/// rather than asked of `git`, which is not guaranteed to be installed.
/// `None` outside Git, where history falls back to package and binary names.
fn repository_identity(workspace_root: &Path) -> Option<String> {
    use sha2::Digest as _;
    let checkout = workspace_root
        .ancestors()
        .find(|directory| directory.join(".git").exists())?;
    let dot_git = checkout.join(".git");
    let common = if dot_git.is_dir() {
        dot_git
    } else {
        let pointer = std::fs::read_to_string(&dot_git).ok()?;
        let git_dir = checkout.join(pointer.strip_prefix("gitdir:")?.trim());
        match std::fs::read_to_string(git_dir.join("commondir")) {
            Ok(common) => git_dir.join(common.trim()),
            // A submodule's directory is its own repository.
            Err(_) => git_dir,
        }
    };
    let common = common.canonicalize().ok()?;
    let digest = sha2::Sha256::digest(common.as_os_str().as_encoded_bytes());
    Some(hex::encode(&digest[..6]))
}

/// The thread count libtest will use, when the command or environment says.
fn test_threads(arguments: &[OsString], environment: Option<&str>) -> Option<u64> {
    let mut arguments = arguments.iter().filter_map(|arg| arg.to_str());
    let mut stated = None;
    while let Some(argument) = arguments.next() {
        if argument == "--" {
            break;
        }
        if argument == "--test-threads" {
            stated = arguments.next().and_then(|value| value.parse().ok());
        } else if let Some(value) = argument.strip_prefix("--test-threads=") {
            stated = value.parse().ok();
        }
    }
    stated.or_else(|| environment?.parse().ok())
}

/// Whether the harness arguments run only part of the suite: a name filter,
/// `--skip`, or `--ignored`.
fn narrows_suite(arguments: &[OsString]) -> bool {
    let mut arguments = arguments.iter().map(|arg| arg.to_string_lossy());
    while let Some(argument) = arguments.next() {
        match argument.as_ref() {
            "--" => return arguments.next().is_some(),
            "--skip" | "--ignored" => return true,
            argument if argument.starts_with("--skip=") => return true,
            // libtest's options that take a separate value.
            "--test-threads" | "--format" | "--logfile" | "--color" | "--shuffle-seed" | "-Z" => {
                arguments.next();
            }
            argument if !argument.starts_with('-') => return true,
            _ => {}
        }
    }
    false
}

fn lists_tests(arguments: &[OsString]) -> bool {
    arguments
        .iter()
        .take_while(|arg| arg.as_os_str() != "--")
        .any(|arg| arg == "--list")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    fn os(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    #[test]
    fn only_plain_test_commands_are_wrapped() {
        assert!(wraps(&strings(&["test"])));
        assert!(wraps(&strings(&["t", "--workspace"])));
        assert!(wraps(&strings(&["--color", "always", "test"])));
        assert!(wraps(&strings(&["test", "--", "--config"])));
        assert!(!wraps(&strings(&["build"])));
        assert!(!wraps(&strings(&["run", "--", "test"])));
        assert!(!wraps(&strings(&["test", "--no-run"])));
        assert!(!wraps(&strings(&["+nightly", "test"])));
        assert!(!wraps(&strings(&["test", "--config", "a.toml"])));
        assert!(!wraps(&strings(&["test", "--config=a.toml"])));
        assert!(!wraps(&strings(&["-C", "other", "test"])));
        assert!(!wraps(&strings(&["-Cother", "test"])));
        assert!(!wraps(&strings(&["--directory", "other", "test"])));
        assert!(!wraps(&strings(&["--directory=other", "test"])));
    }

    #[test]
    fn only_hashed_cargo_binaries_are_test_binaries() {
        assert_eq!(
            test_binary_name(Path::new(
                "target/debug/deps/tuist_cargo_cache-0123456789abcdef"
            ))
            .as_deref(),
            Some("tuist_cargo_cache")
        );
        assert_eq!(
            test_binary_name(Path::new("deps/cache_tests-fedcba9876543210.exe")).as_deref(),
            Some("cache_tests")
        );
        assert_eq!(test_binary_name(Path::new("deps/my-tool")), None);
        assert_eq!(test_binary_name(Path::new("deps/-0123456789abcdef")), None);
        // Rustdoc's doctest binaries.
        assert_eq!(
            test_binary_name(Path::new("/tmp/rustdoctestAbC/rust_out")),
            None
        );
    }

    #[test]
    fn history_is_kept_per_repository_and_package() {
        assert_eq!(
            ledger_name(Some("ab12"), Some("parser"), "it"),
            "ab12/parser/it"
        );
        assert_ne!(
            ledger_name(Some("ab12"), Some("server"), "it"),
            ledger_name(Some("cd34"), Some("server"), "it")
        );
        assert_eq!(ledger_name(None, Some("parser"), "it"), "parser/it");
        assert_eq!(ledger_name(None, None, "it"), "it");
        assert_eq!(ledger_name(Some(""), Some(""), "it"), "it");
    }

    #[test]
    fn worktrees_share_a_repository_identity_and_other_repositories_do_not() {
        let root = tempfile::tempdir().unwrap();
        let main = root.path().join("main");
        std::fs::create_dir_all(main.join(".git/worktrees/feature")).unwrap();
        std::fs::create_dir_all(main.join("crates/app")).unwrap();
        std::fs::write(main.join(".git/worktrees/feature/commondir"), "../..\n").unwrap();
        // Linked worktrees, pointing into the main repository relatively
        // from one checkout and absolutely from another.
        let feature = root.path().join("feature");
        std::fs::create_dir_all(&feature).unwrap();
        std::fs::write(
            feature.join(".git"),
            "gitdir: ../main/.git/worktrees/feature\n",
        )
        .unwrap();
        let other_feature = root.path().join("other-feature");
        std::fs::create_dir_all(&other_feature).unwrap();
        std::fs::write(
            other_feature.join(".git"),
            format!(
                "gitdir: {}\n",
                main.join(".git/worktrees/feature").display()
            ),
        )
        .unwrap();
        let unrelated = root.path().join("unrelated");
        std::fs::create_dir_all(unrelated.join(".git")).unwrap();

        let identity = repository_identity(&main).expect("a repository has an identity");
        assert_eq!(identity.len(), 12);
        assert_eq!(
            repository_identity(&main.join("crates/app")),
            Some(identity.clone())
        );
        assert_eq!(repository_identity(&feature), Some(identity.clone()));
        assert_eq!(repository_identity(&other_feature), Some(identity.clone()));
        assert_ne!(repository_identity(&unrelated), Some(identity));
    }

    #[test]
    fn thread_counts_come_from_arguments_before_the_environment() {
        assert_eq!(test_threads(&os(&[]), None), None);
        assert_eq!(test_threads(&os(&[]), Some("3")), Some(3));
        assert_eq!(
            test_threads(&os(&["--test-threads", "2"]), Some("3")),
            Some(2)
        );
        assert_eq!(test_threads(&os(&["--test-threads=5"]), None), Some(5));
        assert_eq!(test_threads(&os(&["--", "--test-threads=5"]), None), None);
        assert_eq!(test_threads(&os(&[]), Some("many")), None);
    }

    #[test]
    fn narrowed_runs_are_recognised() {
        assert!(!narrows_suite(&os(&[])));
        assert!(!narrows_suite(&os(&["--test-threads", "4", "--nocapture"])));
        assert!(!narrows_suite(&os(&[
            "--format",
            "json",
            "--include-ignored"
        ])));
        assert!(narrows_suite(&os(&["parser"])));
        assert!(narrows_suite(&os(&["--exact", "parser::tokens"])));
        assert!(narrows_suite(&os(&["--skip", "slow"])));
        assert!(narrows_suite(&os(&["--skip=slow"])));
        assert!(narrows_suite(&os(&["--ignored"])));
        assert!(narrows_suite(&os(&["--", "parser"])));
    }

    #[test]
    fn listing_is_recognised() {
        assert!(lists_tests(&os(&["--list", "--format", "terse"])));
        assert!(!lists_tests(&os(&["--exact", "list"])));
    }

    #[test]
    fn nested_shims_are_recognised_by_name() {
        assert!(is_shim(Path::new(
            "/tmp/tuist_cargo_cache-session-x/tuist_cargo_cache-test-runner"
        )));
        assert!(is_shim(Path::new("tuist_cargo_cache-test-runner.exe")));
        assert!(!is_shim(Path::new("/usr/bin/qemu-aarch64")));
    }
}
