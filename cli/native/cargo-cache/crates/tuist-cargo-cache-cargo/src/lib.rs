//! Cargo invocation resolution shared by tuist_cargo_cache and embedded cache clients.
//!
//! This crate is intentionally unstable while the first embedders converge.
//! Breaking changes are made in a new pre-1.0 minor release.
#![deny(missing_docs)]

use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::SystemTime;
use tuist_cargo_cache_core::{CacheDigest, canonical_json};

const CARGO_TARGET_DIR_ENV: &str = "CARGO_TARGET_DIR";
const PROBE_GLOBAL_FLAGS: [&str; 3] = ["-C", "--config", "-Z"];
const PROBE_MANIFEST_TOGGLES: [&str; 3] = ["--offline", "--frozen", "--locked"];

/// Cargo-resolved roots and the stable prediction-manifest identity for one invocation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CargoInvocation {
    /// Cargo's resolved workspace root.
    pub workspace_root: PathBuf,
    /// Cargo's resolved output directory.
    pub target_dir: PathBuf,
    /// Cargo's intermediate build directory, when reported by this Cargo version.
    pub build_dir: Option<PathBuf>,
    /// Whether a flag, environment value, or Cargo configuration explicitly selected the target.
    pub target_dir_requested: bool,
    /// Cross-checkout identity used to select the action-prediction manifest.
    pub build_identity: String,
}

/// Resolve one Cargo invocation exactly enough for a cache session.
pub fn resolve(
    cargo: &OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<OsString>,
) -> CargoInvocation {
    resolve_in(
        cache_root().as_deref(),
        cargo,
        arguments,
        working_dir,
        target_dir_env,
    )
}

fn resolve_in(
    cache: Option<&Path>,
    cargo: &OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<OsString>,
) -> CargoInvocation {
    let cargo_args = cargo_arguments(arguments);
    let reported = recalled_cargo_roots(
        cache,
        effective_cargo_home().as_deref(),
        cargo,
        cargo_args,
        working_dir,
        target_dir_env.as_deref(),
    );
    resolve_with_reported(arguments, working_dir, target_dir_env, reported)
}

/// Resolve one Cargo invocation only when Cargo successfully reports its roots.
///
/// Persistent Cargo shims use this form to distinguish a usable build from an
/// invocation they should pass through, while retaining the successful
/// metadata result for the session instead of probing twice.
pub fn resolve_reported(
    cargo: &OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<OsString>,
) -> Option<CargoInvocation> {
    resolve_reported_in(
        cache_root().as_deref(),
        cargo,
        arguments,
        working_dir,
        target_dir_env,
    )
}

fn resolve_reported_in(
    cache: Option<&Path>,
    cargo: &OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<OsString>,
) -> Option<CargoInvocation> {
    resolve_reported_from_home(
        cache,
        effective_cargo_home().as_deref(),
        cargo,
        arguments,
        working_dir,
        target_dir_env,
    )
}

/// The directory Cargo reads its home configuration from: `CARGO_HOME`, or
/// `.cargo` under the home directory when it is unset.
fn effective_cargo_home() -> Option<PathBuf> {
    std::env::var_os("CARGO_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| dirs::home_dir().map(|home| home.join(".cargo")))
}

fn resolve_reported_from_home(
    cache: Option<&Path>,
    cargo_home: Option<&Path>,
    cargo: &OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<OsString>,
) -> Option<CargoInvocation> {
    let reported = recalled_cargo_roots(
        cache,
        cargo_home,
        cargo,
        cargo_arguments(arguments),
        working_dir,
        target_dir_env.as_deref(),
    )?;
    Some(resolve_with_reported(
        arguments,
        working_dir,
        target_dir_env,
        Some(reported),
    ))
}

fn resolve_with_reported(
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<OsString>,
    reported: Option<(PathBuf, PathBuf, Option<PathBuf>)>,
) -> CargoInvocation {
    let cargo_args = cargo_arguments(arguments);
    let install_source = path_install_dir(cargo_args, working_dir);
    let invocation_dir = if install_source.is_some() {
        directory_option_dir(cargo_args, working_dir)
    } else {
        invocation_dir(cargo_args, working_dir)
    };
    let workspace_root = reported
        .as_ref()
        .map(|roots| roots.0.clone())
        .unwrap_or_else(|| workspace_root(&invocation_dir));
    let flagged = target_dir_argument(cargo_args);
    let target_dir_requested = flagged.is_some()
        || target_dir_env
            .as_ref()
            .is_some_and(|value| !value.is_empty())
        || cargo_config_may_set_target_dir(
            cargo_args,
            install_source.as_deref().unwrap_or(&invocation_dir),
        );
    let build_dir = reported.as_ref().and_then(|roots| roots.2.clone());
    let target_dir = flagged
        .map(|value| absolute(&invocation_dir, value))
        .or_else(|| reported.map(|roots| roots.1))
        .or_else(|| {
            target_dir_env
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
                .map(|value| absolute(&invocation_dir, &value.to_string_lossy()))
        })
        .unwrap_or_else(|| workspace_root.join("target"));
    let build_identity = build_identity(&workspace_root, arguments);
    CargoInvocation {
        workspace_root,
        target_dir,
        target_dir_requested,
        build_dir,
        build_identity,
    }
}

#[derive(Serialize)]
struct ActionIdentity<'a> {
    version: u8,
    workspace: &'a str,
    os: &'static str,
    arch: &'static str,
}

/// Derive the prediction-manifest identity used by tuist_cargo_cache for a Cargo command.
///
/// The command is accepted for API compatibility but deliberately does not
/// enter the identity. rustc invocation digests distinguish profiles,
/// features, targets, and compiler toolchains; keeping the surrounding Cargo
/// command here would prevent equivalent dependency compilations from sharing
/// predictions across `build`, `test`, and Clippy.
pub fn build_identity(workspace_root: &Path, _command: &[String]) -> String {
    identity_for_workspace(&workspace_marker(workspace_root))
}

/// The identities recorded for earlier states of this workspace's
/// `Cargo.lock`, newest first.
///
/// The identity is the lockfile's digest, so a dependency bump starts a
/// manifest with nothing in it although most of the graph is unchanged and
/// its results are already cached. Version control remembers what the lockfile
/// was before: the committed copy first, for an edit that has not been
/// committed yet, then the copy in `HEAD`'s first parent, which on a pull
/// request's merge commit is the base branch, then the copy each commit that
/// touched the file replaced. A shallow clone offers what it can reach, which
/// on a `fetch-depth: 1` checkout is nothing beyond `HEAD` itself. A checkout
/// that is not under Git, or a lockfile it does not track, yields nothing.
/// Every prediction a manifest holds is rehashed before it is trusted, so an
/// inherited one can only fail to match, never restore the wrong result.
pub fn previous_build_identities(workspace_root: &Path) -> Vec<String> {
    let Ok(lock) = std::fs::read(workspace_root.join("Cargo.lock")) else {
        return Vec::new();
    };
    // History belongs to the tracked file. A lockfile Cargo generated after a
    // tracked one was deleted has none, whatever the deleted one's was.
    if git_output(
        workspace_root,
        &["ls-files", "--error-unmatch", "--", "Cargo.lock"],
    )
    .is_none()
    {
        return Vec::new();
    }
    let limit = PREVIOUS_LOCKFILE_STATES.to_string();
    let Some(revisions) = git_output(
        workspace_root,
        &["rev-list", "-n", &limit, "HEAD", "--", "Cargo.lock"],
    ) else {
        return Vec::new();
    };
    // A commit's own copy of the lockfile is what its successor replaced, so
    // the parent of each commit that touched the file is one state further
    // back; a root commit has no parent and is skipped.
    let revisions = String::from_utf8_lossy(&revisions);
    let candidates = ["HEAD", "HEAD^"].into_iter().map(str::to_string).chain(
        revisions
            .lines()
            .map(|revision| format!("{}^", revision.trim())),
    );
    let mut seen = BTreeSet::from([CacheDigest::blake3(&lock).hash]);
    let mut identities = Vec::new();
    for revision in candidates {
        let Some(lock) = git_output(
            workspace_root,
            &["show", &format!("{revision}:./Cargo.lock")],
        ) else {
            continue;
        };
        let marker = CacheDigest::blake3(&lock).hash;
        if seen.insert(marker.clone()) {
            identities.push(identity_for_workspace(&marker));
        }
        if identities.len() == PREVIOUS_LOCKFILE_STATES {
            break;
        }
    }
    identities
}

/// How many earlier lockfile states are offered as prediction sources.
///
/// Each one costs a manifest lookup when it is consulted, which only happens
/// once nothing was recorded under the current identity, and a run of
/// dependency bumps rarely goes deeper than this before a build of the trunk
/// records the newest state.
const PREVIOUS_LOCKFILE_STATES: usize = 8;

/// Git's standard output for a command run in `workspace_root`, or nothing
/// when Git is absent or the command fails.
fn git_output(workspace_root: &Path, arguments: &[&str]) -> Option<Vec<u8>> {
    let output = Command::new("git")
        .arg("-C")
        .arg(workspace_root)
        .args(arguments)
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    output.status.success().then_some(output.stdout)
}

/// The manifest identity for one workspace marker on this platform.
fn identity_for_workspace(workspace: &str) -> String {
    let bytes = canonical_json(&ActionIdentity {
        version: 3,
        workspace,
        os: std::env::consts::OS,
        arch: std::env::consts::ARCH,
    })
    .expect("Cargo build identity must serialize");
    CacheDigest::blake3(&bytes).hash
}

fn workspace_marker(workspace_root: &Path) -> String {
    std::fs::read(workspace_root.join("Cargo.lock")).map_or_else(
        |_| {
            workspace_root
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned()
        },
        |lock| CacheDigest::blake3(&lock).hash,
    )
}

/// Resolve the shared tuist_cargo_cache cache root from the environment, machine config, or platform default.
pub fn cache_root() -> Option<PathBuf> {
    if let Some(root) = std::env::var_os("TUIST_CARGO_CACHE_DIR").filter(|value| !value.is_empty())
    {
        return Some(PathBuf::from(root));
    }
    if let Some(config) = dirs::config_dir().map(|root| root.join("tuist_cargo_cache/config.toml"))
        && let Ok(contents) = std::fs::read_to_string(config)
        && let Ok(document) = toml::from_str::<toml::Value>(&contents)
        && let Some(root) = document.get("cache_dir").and_then(toml::Value::as_str)
    {
        return Some(PathBuf::from(root));
    }
    dirs::cache_dir().map(|root| root.join("tuist_cargo_cache"))
}

fn cargo_arguments(arguments: &[String]) -> &[String] {
    &arguments[..arguments
        .iter()
        .position(|argument| argument == "--")
        .unwrap_or(arguments.len())]
}

fn absolute(working_dir: &Path, value: &str) -> PathBuf {
    let path = PathBuf::from(value);
    if path.is_absolute() {
        path
    } else {
        working_dir.join(path)
    }
}

fn forwarded_flags(arguments: &[String], flags: &[&str]) -> Vec<String> {
    let mut forwarded = Vec::new();
    let mut remaining = arguments.iter();
    while let Some(argument) = remaining.next() {
        if let Some((flag, value)) = argument
            .split_once('=')
            .filter(|(flag, _)| flags.contains(flag))
        {
            forwarded.extend([flag.to_string(), value.to_string()]);
        } else if flags.contains(&argument.as_str()) {
            if let Some(value) = remaining.next() {
                forwarded.extend([argument.clone(), value.clone()]);
            }
        } else if flags
            .iter()
            .any(|flag| flag.len() == 2 && argument.len() > 2 && argument.starts_with(flag))
        {
            forwarded.push(argument.clone());
        }
    }
    forwarded
}

fn invocation_dir(arguments: &[String], working_dir: &Path) -> PathBuf {
    flag_value(arguments, "-C")
        .map(|value| absolute(working_dir, value))
        .unwrap_or_else(|| working_dir.to_path_buf())
}

// Path installs change the probe's cwd, and manifest discovery starts from
// wherever Cargo was pointed, so resolve every directory-option spelling.
fn directory_option_dir(arguments: &[String], working_dir: &Path) -> PathBuf {
    flag_value(arguments, "-C")
        .or_else(|| flag_value(arguments, "--directory"))
        .or_else(|| {
            arguments
                .iter()
                .find_map(|arg| arg.strip_prefix("-C").filter(|value| !value.is_empty()))
        })
        .map(|value| absolute(working_dir, value))
        .unwrap_or_else(|| working_dir.to_path_buf())
}

/// Whether Cargo has a manifest to work from here.
///
/// Without one there is no package to compile, no target directory to place,
/// and nothing for a probe to report, so a metadata failure means only that
/// Cargo was run outside a project. Cargo's own diagnostic is then the useful
/// one, and the caller can hand the invocation straight to it.
pub fn manifest_in_scope(arguments: &[String], working_dir: &Path) -> bool {
    let arguments = cargo_arguments(arguments);
    let invocation = directory_option_dir(arguments, working_dir);
    // `install --path` compiles the manifest in the directory it names, which
    // it has even where the invocation directory has none, and does not walk
    // up to a surrounding workspace for it. Only a real install gives `--path`
    // that meaning: other subcommands use the same flag for their own
    // purposes, such as the local template `cargo generate --path` reads.
    // Callers expand aliases first, so an aliased install arrives spelled out.
    if let Some(source) = path_install_dir(arguments, working_dir) {
        return source.join("Cargo.toml").is_file();
    }
    match flag_value(arguments, "--manifest-path") {
        Some(manifest) => absolute(&invocation, manifest).is_file(),
        None => invocation
            .ancestors()
            .any(|directory| directory.join("Cargo.toml").is_file()),
    }
}

// Only a real install subcommand gives --path this meaning; option values
// and arguments after -- must not make an unrelated command look like one.
fn path_install_dir(arguments: &[String], working_dir: &Path) -> Option<PathBuf> {
    let arguments = cargo_arguments(arguments);
    let mut remaining = arguments.iter();
    while let Some(argument) = remaining.next() {
        match argument.as_str() {
            "--color" | "--config" | "-Z" | "-C" | "--directory" => {
                remaining.next()?;
            }
            value if !value.starts_with('-') && !value.starts_with('+') => {
                return (value == "install")
                    .then(|| {
                        flag_value(arguments, "--path").map(|path| {
                            absolute(&directory_option_dir(arguments, working_dir), path)
                        })
                    })
                    .flatten();
            }
            _ => {}
        }
    }
    None
}

// Inline includes use cwd, unlike includes inside a config file. Rewrite the
// override itself: appending another include would concatenate array entries.
fn rebase_cli_include(value: &str, caller: &Path) -> String {
    fn rebase(value: &mut toml::Value, caller: &Path) {
        match value {
            toml::Value::String(path) => {
                *path = absolute(caller, path).to_string_lossy().into_owned();
            }
            toml::Value::Array(entries) => {
                for entry in entries {
                    rebase(entry, caller);
                }
            }
            toml::Value::Table(entry) => {
                if let Some(toml::Value::String(path)) = entry.get_mut("path") {
                    *path = absolute(caller, path).to_string_lossy().into_owned();
                }
            }
            _ => {}
        }
    }
    if let Ok(mut config) = toml::from_str::<toml::Value>(value)
        && config.as_table().is_some_and(|table| table.len() == 1)
        && let Some(include) = config.get_mut("include")
    {
        rebase(include, caller);
        return format!("include = {include}");
    }
    value.to_owned()
}

/// The roots a `cargo metadata` probe reports, remembered under `cache`.
///
/// The probe is a Cargo process per build, and it costs more than the shim
/// work around a hot compile once the rest has been trimmed. Its answer is a
/// function of things this crate can watch: the Cargo binary, the manifests
/// and configuration files Cargo reads on the way from the invocation
/// directory to the root, and the environment that selects a target
/// directory. A record stands while every one of those is as the probing
/// run saw it, including the ones that were absent; anything else, or no
/// cache to remember in, runs the probe.
fn recalled_cargo_roots(
    cache: Option<&Path>,
    cargo_home: Option<&Path>,
    cargo: &OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<&OsStr>,
) -> Option<(PathBuf, PathBuf, Option<PathBuf>)> {
    if let Some(source) = path_install_dir(arguments, working_dir) {
        // `install --path` reads configuration from the source directory,
        // whereas metadata normally reads it from the caller's directory.
        // Probe there, retaining caller-relative CLI paths and target overrides.
        let caller = directory_option_dir(arguments, working_dir);
        let mut probe_args = Vec::new();
        if let Some(target) =
            std::env::var_os("CARGO_BUILD_TARGET_DIR").filter(|value| !value.is_empty())
        {
            // This environment setting outranks files but is itself overridden
            // by --config; insert it before the caller's explicit overrides.
            probe_args.extend([
                "--config".into(),
                format!(
                    "build.target-dir = {}",
                    toml::Value::String(
                        absolute(&caller, &target.to_string_lossy())
                            .to_string_lossy()
                            .into_owned()
                    )
                ),
            ]);
        }
        for value in config_arguments(arguments) {
            let value = if value.contains('=') {
                rebase_cli_include(value, &caller)
            } else {
                absolute(&caller, value).to_string_lossy().into_owned()
            };
            probe_args.extend(["--config".into(), value.clone()]);
            // Inline target paths also stay relative to the caller. Preserve
            // any other settings in this override and the order of overrides.
            if let Ok(config) = toml::from_str::<toml::Value>(&value)
                && let Some(target) = config
                    .get("build")
                    .and_then(|build| build.get("target-dir"))
                    .and_then(toml::Value::as_str)
            {
                probe_args.extend([
                    "--config".into(),
                    format!(
                        "build.target-dir = {}",
                        toml::Value::String(
                            absolute(&caller, target).to_string_lossy().into_owned()
                        )
                    ),
                ]);
            }
        }
        probe_args.extend(forwarded_flags(arguments, &["-Z"]));
        probe_args.push("build".into());
        probe_args.extend(
            arguments
                .iter()
                .filter(|arg| PROBE_MANIFEST_TOGGLES.contains(&arg.as_str()))
                .cloned(),
        );
        let target = target_dir_env
            .filter(|value| !value.is_empty())
            .map(|value| absolute(&caller, &value.to_string_lossy()).into_os_string());
        return recalled_cargo_roots(
            cache,
            cargo_home,
            cargo,
            &probe_args,
            &source,
            target.as_deref(),
        );
    }
    let probe = cache.and_then(|cache| {
        ProbeRecord::describe(
            cache,
            cargo_home,
            cargo,
            arguments,
            working_dir,
            target_dir_env,
        )
    });
    if let Some(recalled) = probe.as_ref().and_then(ProbeRecord::recall) {
        return Some(recalled);
    }
    let roots = cargo_roots(cargo, arguments, working_dir, target_dir_env)?;
    if let Some(probe) = probe {
        probe.remember(&roots);
    }
    Some(roots)
}

const PROBE_RECORD_VERSION: u8 = 2;

/// Everything a probe's answer was a function of, and the answer.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct ProbeRecord {
    version: u8,
    key: ProbeKey,
    /// The files Cargo consulted, present or absent, as they were when the
    /// probe ran. The root manifest joins them once the probe has named it.
    pins: Vec<Pin>,
    #[serde(skip)]
    path: PathBuf,
    workspace_root: PathBuf,
    target_dir: PathBuf,
    build_dir: Option<PathBuf>,
}

/// The inputs that select a record: an identical key with intact pins is
/// the same question, so it gets the same answer.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct ProbeKey {
    cargo: PathBuf,
    arguments: Vec<String>,
    working_dir: PathBuf,
    target_dir_env: Option<String>,
    build_target_dir_env: Option<String>,
    build_dir_env: Option<String>,
    target_dir_argument: Option<String>,
    cargo_home: Option<String>,
}

/// A file as the probe found it: absent, or present with a length and
/// modification time. Length alone would miss an edit that kept the size.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct Pin {
    path: PathBuf,
    state: Option<(u64, u64, u32)>,
}

impl Pin {
    /// Describe `path`, or nothing when the filesystem cannot say enough
    /// about it to notice a change.
    fn describe(path: PathBuf) -> Option<Self> {
        let state = match std::fs::metadata(&path) {
            Ok(metadata) => {
                let modified = metadata
                    .modified()
                    .ok()?
                    .duration_since(SystemTime::UNIX_EPOCH)
                    .ok()?;
                Some((metadata.len(), modified.as_secs(), modified.subsec_nanos()))
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(_) => return None,
        };
        Some(Self { path, state })
    }

    fn holds(&self) -> bool {
        Pin::describe(self.path.clone()).as_ref() == Some(self)
    }
}

impl ProbeRecord {
    /// Describe the probe about to run, or nothing when some input cannot be
    /// pinned, in which case the probe runs and is not remembered.
    fn describe(
        cache: &Path,
        cargo_home: Option<&Path>,
        cargo: &OsStr,
        arguments: &[String],
        working_dir: &Path,
        target_dir_env: Option<&OsStr>,
    ) -> Option<Self> {
        let cargo = resolve_program(cargo)?;
        let env =
            |name: &str| std::env::var_os(name).map(|value| value.to_string_lossy().into_owned());
        let key = ProbeKey {
            cargo: cargo.clone(),
            arguments: probe_arguments(arguments),
            working_dir: working_dir.to_path_buf(),
            target_dir_env: target_dir_env.map(|value| value.to_string_lossy().into_owned()),
            build_target_dir_env: env("CARGO_BUILD_TARGET_DIR"),
            build_dir_env: env("CARGO_BUILD_BUILD_DIR"),
            target_dir_argument: target_dir_argument(arguments).map(str::to_owned),
            // The directory itself rather than the variable: with the
            // variable unset it follows the home directory, and a record
            // made under one home must not answer under another.
            cargo_home: cargo_home.map(|home| home.to_string_lossy().into_owned()),
        };
        let invocation_dir = invocation_dir(arguments, working_dir);
        // Cargo finds the manifest nearest the invocation directory, or the
        // one named outright, and walks up from there for the workspace. Its
        // configuration it reads from every `.cargo` above the invocation
        // directory itself, wherever the manifest is, and from home last.
        let manifest_start = flag_value(arguments, "--manifest-path")
            .map(|manifest| absolute(&invocation_dir, manifest))
            .and_then(|manifest| manifest.parent().map(Path::to_path_buf))
            .unwrap_or_else(|| invocation_dir.clone());
        let mut watched = vec![cargo];
        watched.extend(
            manifest_start
                .ancestors()
                .map(|directory| directory.join("Cargo.toml")),
        );
        for directory in invocation_dir.ancestors() {
            let dot_cargo = directory.join(".cargo");
            watched.push(dot_cargo.join("config.toml"));
            watched.push(dot_cargo.join("config"));
        }
        if let Some(home) = cargo_home {
            watched.push(home.join("config.toml"));
            watched.push(home.join("config"));
        }
        watched.extend(
            config_arguments(arguments)
                .map(|value| absolute(&invocation_dir, value))
                .filter(|path| path.is_file()),
        );
        // A configuration file may `include` others this list does not
        // name, and a command-line `include=` does the same. Their target
        // directory cannot be pinned, so it is not remembered. A `--config`
        // naming a file is on the list above and read like the rest.
        if config_arguments(arguments).any(|value| {
            value
                .split_once('=')
                .is_some_and(|(key, _)| key.trim() == "include")
        }) || watched
            .iter()
            .skip(1)
            .filter(|path| path.file_name().is_some_and(|name| name != "Cargo.toml"))
            .any(|path| config_includes_files(path))
        {
            return None;
        }
        let pins = watched
            .into_iter()
            .map(Pin::describe)
            .collect::<Option<Vec<_>>>()?;
        let selector = canonical_json(&key).ok()?;
        let path = cache
            .join("cargo-roots")
            .join("v1")
            .join(format!("{}.json", CacheDigest::blake3(&selector).hash));
        Some(Self {
            version: PROBE_RECORD_VERSION,
            key,
            pins,
            path,
            workspace_root: PathBuf::new(),
            target_dir: PathBuf::new(),
            build_dir: None,
        })
    }

    /// The answer an earlier probe left for this key, if its pins all hold.
    fn recall(&self) -> Option<(PathBuf, PathBuf, Option<PathBuf>)> {
        let bytes = std::fs::read(&self.path).ok()?;
        let recorded: ProbeRecord = serde_json::from_slice(&bytes).ok()?;
        if recorded.version != PROBE_RECORD_VERSION
            || recorded.key != self.key
            || !recorded.pins.iter().all(Pin::holds)
        {
            return None;
        }
        Some((
            recorded.workspace_root,
            recorded.target_dir,
            recorded.build_dir,
        ))
    }

    /// Leave the answer behind for the next invocation. Best-effort: a
    /// record that cannot be written costs the next build a probe.
    fn remember(mut self, roots: &(PathBuf, PathBuf, Option<PathBuf>)) {
        let root_manifest = roots.0.join("Cargo.toml");
        if !self.pins.iter().any(|pin| pin.path == root_manifest) {
            let Some(pin) = Pin::describe(root_manifest) else {
                return;
            };
            self.pins.push(pin);
        }
        self.workspace_root = roots.0.clone();
        self.target_dir = roots.1.clone();
        self.build_dir = roots.2.clone();
        let Ok(bytes) = serde_json::to_vec(&self) else {
            return;
        };
        let Some(directory) = self.path.parent() else {
            return;
        };
        if std::fs::create_dir_all(directory).is_err() {
            return;
        }
        let staged = directory.join(format!(
            ".{}.{}",
            self.path.file_name().unwrap_or_default().to_string_lossy(),
            std::process::id()
        ));
        if std::fs::write(&staged, bytes).is_ok() && std::fs::rename(&staged, &self.path).is_err() {
            let _ = std::fs::remove_file(&staged);
        }
    }
}

/// Whether a Cargo configuration file names others through `include`.
///
/// A file that cannot be read or parsed is treated as though it did: the
/// question is whether the probe can be pinned, and a file this cannot see
/// into is one it cannot pin.
fn config_includes_files(path: &Path) -> bool {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return false,
        Err(_) => return true,
    };
    toml::from_str::<toml::Value>(&contents).is_ok_and(|config| config.get("include").is_some())
        || toml::from_str::<toml::Value>(&contents).is_err()
}

/// The probe command's arguments, in the order it runs them: Cargo's global
/// flags, then `metadata`, then the options that pick the manifest.
fn probe_arguments(arguments: &[String]) -> Vec<String> {
    let mut probe = forwarded_flags(arguments, &PROBE_GLOBAL_FLAGS);
    probe.extend(
        ["metadata", "--no-deps", "--format-version", "1"]
            .iter()
            .map(|argument| (*argument).to_string()),
    );
    if let Some(manifest) = flag_value(arguments, "--manifest-path") {
        probe.push("--manifest-path".into());
        probe.push(manifest.into());
    }
    probe.extend(
        arguments
            .iter()
            .filter(|argument| PROBE_MANIFEST_TOGGLES.contains(&argument.as_str()))
            .cloned(),
    );
    probe
}

/// Where `program` is, the way `Command::new` would find it.
fn resolve_program(program: &OsStr) -> Option<PathBuf> {
    let candidate = Path::new(program);
    if candidate.components().count() > 1 {
        return candidate.is_file().then(|| candidate.to_path_buf());
    }
    let names = if cfg!(windows) {
        vec![candidate.as_os_str().to_os_string(), {
            let mut exe = candidate.as_os_str().to_os_string();
            exe.push(".exe");
            exe
        }]
    } else {
        vec![candidate.as_os_str().to_os_string()]
    };
    std::env::split_paths(&std::env::var_os("PATH")?)
        .flat_map(|directory| names.iter().map(move |name| directory.join(name)))
        .find(|path| path.is_file())
}

fn cargo_roots(
    cargo: &OsStr,
    arguments: &[String],
    working_dir: &Path,
    target_dir_env: Option<&OsStr>,
) -> Option<(PathBuf, PathBuf, Option<PathBuf>)> {
    let mut command = Command::new(cargo);
    match target_dir_argument(arguments)
        .map(OsStr::new)
        .or(target_dir_env)
    {
        Some(value) => command.env(CARGO_TARGET_DIR_ENV, value),
        None => command.env_remove(CARGO_TARGET_DIR_ENV),
    };
    command
        .current_dir(working_dir)
        .args(probe_arguments(arguments));
    let output = command.output().ok()?;
    if !output.status.success() {
        return None;
    }
    let metadata: serde_json::Value = serde_json::from_slice(&output.stdout).ok()?;
    Some((
        PathBuf::from(metadata.get("workspace_root")?.as_str()?),
        PathBuf::from(metadata.get("target_directory")?.as_str()?),
        metadata
            .get("build_directory")
            .and_then(|value| value.as_str())
            .map(PathBuf::from),
    ))
}

fn target_dir_argument(arguments: &[String]) -> Option<&str> {
    flag_value(arguments, "--target-dir")
}

fn cargo_config_may_set_target_dir(arguments: &[String], invocation_dir: &Path) -> bool {
    if std::env::var_os("CARGO_BUILD_TARGET_DIR").is_some_and(|value| !value.is_empty()) {
        return true;
    }
    if config_arguments(arguments).any(|value| {
        value
            .split_once('=')
            .is_none_or(|(key, _)| matches!(key.trim(), "build.target-dir" | "include"))
    }) {
        return true;
    }
    let project = invocation_dir.ancestors().flat_map(|directory| {
        let cargo = directory.join(".cargo");
        [cargo.join("config.toml"), cargo.join("config")]
    });
    let home = std::env::var_os("CARGO_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs::home_dir().map(|root| root.join(".cargo")))
        .into_iter()
        .flat_map(|cargo| [cargo.join("config.toml"), cargo.join("config")]);
    project.chain(home).any(|path| config_may_set_target(&path))
}

fn config_arguments(arguments: &[String]) -> impl Iterator<Item = &str> {
    let mut values = Vec::new();
    let mut remaining = arguments.iter();
    while let Some(argument) = remaining.next() {
        if let Some(value) = argument.strip_prefix("--config=") {
            values.push(value);
        } else if argument == "--config"
            && let Some(value) = remaining.next()
        {
            values.push(value);
        }
    }
    values.into_iter()
}

fn config_may_set_target(path: &Path) -> bool {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return false,
        Err(_) => return true,
    };
    let Ok(config) = toml::from_str::<toml::Value>(&contents) else {
        return true;
    };
    config
        .get("build")
        .and_then(|build| build.get("target-dir"))
        .is_some()
        || config.get("include").is_some()
}

fn flag_value<'a>(arguments: &'a [String], flag: &str) -> Option<&'a str> {
    let joined = format!("{flag}=");
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        if let Some(value) = argument.strip_prefix(&joined) {
            return Some(value);
        }
        if argument == flag {
            return arguments.next().map(String::as_str);
        }
    }
    None
}

fn workspace_root(start: &Path) -> PathBuf {
    start
        .ancestors()
        .find(|directory| directory.join("Cargo.toml").is_file())
        .unwrap_or(start)
        .to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cargo_fixture() -> tempfile::TempDir {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join("Cargo.toml"),
            "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
        )
        .unwrap();
        std::fs::create_dir_all(directory.path().join("src")).unwrap();
        std::fs::write(directory.path().join("src/lib.rs"), "").unwrap();
        directory
    }

    fn fixture_root(path: &Path) -> PathBuf {
        // Cargo omits Windows verbatim prefixes; Unix may have aliases (/var).
        if cfg!(windows) {
            path.to_path_buf()
        } else {
            path.canonicalize().unwrap()
        }
    }

    #[test]
    fn a_manifest_is_in_scope_only_where_cargo_would_read_one() {
        let outside = tempfile::tempdir().unwrap();
        let outside = outside.path();
        let arguments = |value: &str| {
            value
                .split_whitespace()
                .map(str::to_owned)
                .collect::<Vec<_>>()
        };
        assert!(!manifest_in_scope(&arguments("binstall"), outside));
        assert!(!manifest_in_scope(&arguments("build"), outside));

        let project = cargo_fixture();
        let project = project.path();
        let nested = project.join("src");
        assert!(manifest_in_scope(&arguments("binstall"), project));
        // Cargo walks up for the nearest manifest, so a subdirectory of a
        // package is inside it.
        assert!(manifest_in_scope(&arguments("binstall"), &nested));

        // A directory option moves the search, either way.
        assert!(manifest_in_scope(
            &[
                "-C".into(),
                project.to_string_lossy().into_owned(),
                "binstall".into()
            ],
            outside
        ));
        assert!(!manifest_in_scope(
            &[
                "--directory".into(),
                outside.to_string_lossy().into_owned(),
                "binstall".into()
            ],
            project
        ));

        // `--manifest-path` names the manifest outright rather than starting
        // a search, so a missing one is out of scope even inside a package.
        assert!(manifest_in_scope(
            &[
                "binstall".into(),
                "--manifest-path".into(),
                "Cargo.toml".into()
            ],
            project
        ));
        assert!(!manifest_in_scope(
            &["binstall".into(), "--manifest-path=src/Cargo.toml".into()],
            project
        ));

        // `install --path` names a manifest the invocation directory does not
        // have. Callers expand aliases before asking, so only a real install
        // gives `--path` that meaning here; other subcommands spend the same
        // flag on their own arguments and must not be read as path installs.
        assert!(manifest_in_scope(
            &[
                "install".into(),
                "--path".into(),
                project.to_string_lossy().into_owned()
            ],
            outside
        ));
        assert!(!manifest_in_scope(
            &[
                "generate".into(),
                "--path".into(),
                project.to_string_lossy().into_owned()
            ],
            outside
        ));
        assert!(!manifest_in_scope(
            &[
                "install".into(),
                "--path".into(),
                outside.join("absent").to_string_lossy().into_owned()
            ],
            outside
        ));
        // Arguments after `--` belong to the built program, not to Cargo.
        assert!(!manifest_in_scope(
            &[
                "run".into(),
                "--".into(),
                "--path".into(),
                project.to_string_lossy().into_owned()
            ],
            outside
        ));
    }

    #[test]
    fn lockfile_makes_identity_independent_of_checkout_path() {
        let left = tempfile::tempdir().unwrap();
        let right = tempfile::tempdir().unwrap();
        std::fs::write(left.path().join("Cargo.lock"), "same").unwrap();
        std::fs::write(right.path().join("Cargo.lock"), "same").unwrap();
        let command = vec!["build".to_string(), "--workspace".to_string()];
        assert_eq!(
            build_identity(left.path(), &command),
            build_identity(right.path(), &command)
        );
    }

    #[test]
    fn cargo_commands_and_toolchain_selectors_share_predictions() {
        let project = tempfile::tempdir().unwrap();
        std::fs::write(project.path().join("Cargo.lock"), "same").unwrap();

        let build = vec!["build".to_string()];
        let test = vec!["test".to_string(), "--workspace".to_string()];
        let msrv = vec!["+1.91".to_string(), "check".to_string()];

        assert_eq!(
            build_identity(project.path(), &build),
            build_identity(project.path(), &test),
        );
        assert_eq!(
            build_identity(project.path(), &build),
            build_identity(project.path(), &msrv),
        );
    }

    #[test]
    fn rustc_flags_after_separator_are_not_cargo_globals() {
        let args = vec![
            "rustc".into(),
            "--".into(),
            "-C".into(),
            "opt-level=3".into(),
        ];
        assert_eq!(
            invocation_dir(cargo_arguments(&args), Path::new("/work")),
            PathBuf::from("/work")
        );
    }

    #[test]
    fn target_directory_flags_and_environment_are_recorded_as_explicit() {
        let directory = cargo_fixture();
        let root = directory.path();
        let cargo = OsStr::new("cargo-that-does-not-exist");
        let plain = ["build".to_string()];

        let default = resolve(cargo, &plain, root, None);
        assert_eq!(default.target_dir, root.join("target"));
        assert!(!default.target_dir_requested);

        for arguments in [
            vec!["build".into(), "--target-dir=target".into()],
            vec!["build".into(), "--target-dir".into(), "target".into()],
        ] {
            let resolved = resolve(cargo, &arguments, root, None);
            assert_eq!(resolved.target_dir, root.join("target"));
            assert!(resolved.target_dir_requested);
        }

        let from_environment = resolve(cargo, &plain, root, Some("elsewhere".into()));
        assert_eq!(from_environment.target_dir, root.join("elsewhere"));
        assert!(from_environment.target_dir_requested);

        let empty_environment = resolve(cargo, &plain, root, Some("".into()));
        assert!(!empty_environment.target_dir_requested);

        let dangling = ["build".into(), "--target-dir".into()];
        assert!(!resolve(cargo, &dangling, root, None).target_dir_requested);
    }

    #[test]
    fn project_config_that_names_the_default_target_is_still_explicit() {
        let directory = cargo_fixture();
        let root = directory.path();
        std::fs::create_dir_all(root.join(".cargo")).unwrap();
        std::fs::write(
            root.join(".cargo/config.toml"),
            "[build]\ntarget-dir = \"target\"\n",
        )
        .unwrap();

        let resolved = resolve(
            OsStr::new("cargo-that-does-not-exist"),
            &["build".into()],
            root,
            None,
        );

        assert_eq!(resolved.target_dir, root.join("target"));
        assert!(resolved.target_dir_requested);
    }

    #[test]
    fn command_line_config_include_may_set_the_target_directory() {
        let directory = cargo_fixture();
        let arguments = [
            "build".into(),
            "--config".into(),
            "include='target-config.toml'".into(),
        ];

        let resolved = resolve(
            OsStr::new("cargo-that-does-not-exist"),
            &arguments,
            directory.path(),
            None,
        );

        assert!(resolved.target_dir_requested);
    }

    #[test]
    fn command_line_target_config_reaches_the_cargo_probe() {
        let directory = cargo_fixture();
        let root = directory.path();
        let configured = root.join("configured-target");
        let arguments = [
            "build".into(),
            "--offline".into(),
            "--manifest-path".into(),
            root.join("Cargo.toml").display().to_string(),
            "--config".into(),
            format!("build.target-dir='{}'", configured.display()),
        ];

        let resolved =
            resolve_reported_in(None, OsStr::new("cargo"), &arguments, root, None).unwrap();

        assert_eq!(resolved.target_dir, configured);
        assert!(resolved.target_dir_requested);
    }

    #[test]
    fn path_install_probes_source_config_and_preserves_caller_relative_targets() {
        let source = cargo_fixture();
        let caller = cargo_fixture();
        let source_root = fixture_root(source.path());
        let caller_root = fixture_root(caller.path());
        for (root, target) in [
            (source_root.as_path(), "source-target"),
            (caller_root.as_path(), "caller-target"),
        ] {
            std::fs::create_dir_all(root.join(".cargo")).unwrap();
            std::fs::write(
                root.join(".cargo/config.toml"),
                format!("[build]\ntarget-dir = '{target}'\n"),
            )
            .unwrap();
        }
        let arguments = vec![
            "install".into(),
            format!("--path={}", source_root.as_path().display()),
            "--offline".into(),
        ];
        let cache = tempfile::tempdir().unwrap();
        let resolve = |args: &[String], target| {
            resolve_reported_in(
                Some(cache.path()),
                OsStr::new("cargo"),
                args,
                caller_root.as_path(),
                target,
            )
            .unwrap()
        };
        let roots = resolve(&arguments, None);
        assert_eq!(roots.workspace_root, source_root.as_path());
        assert_eq!(
            roots.target_dir,
            source_root.as_path().join("source-target")
        );
        assert!(roots.target_dir_requested);

        let mut flagged = arguments.clone();
        flagged.extend(["--target-dir".into(), "flag-target".into()]);
        assert_eq!(
            resolve(&flagged, None).target_dir,
            caller_root.as_path().join("flag-target")
        );
        assert_eq!(
            resolve(&arguments, Some("env-target".into())).target_dir,
            caller_root.as_path().join("env-target")
        );
        let mut configured = arguments.clone();
        configured.extend(["--config".into(), "build.target-dir='cli-target'".into()]);
        assert_eq!(
            resolve(&configured, None).target_dir,
            caller_root.as_path().join("cli-target")
        );

        // A warm metadata cache must watch the installed source's config.
        std::fs::write(
            source_root.as_path().join(".cargo/config.toml"),
            "[build]\ntarget-dir = 'changed-source-target'\n",
        )
        .unwrap();
        assert_eq!(
            resolve(&arguments, None).target_dir,
            source_root.as_path().join("changed-source-target")
        );
    }

    #[test]
    fn path_install_directory_flags_rebase_the_source_and_target() {
        let source = cargo_fixture();
        let source_root = fixture_root(source.path());
        let caller = source_root.parent().unwrap();
        let directory = source_root.file_name().unwrap().to_str().unwrap();
        for flags in [
            vec!["--directory".into(), directory.into()],
            vec![format!("--directory={directory}")],
            vec!["-C".into(), directory.into()],
            vec![format!("-C{directory}")],
        ] {
            let mut arguments = flags;
            arguments.extend(
                [
                    "install",
                    "--path",
                    ".",
                    "--target-dir",
                    "shared",
                    "--offline",
                ]
                .map(str::to_owned),
            );
            let roots =
                resolve_reported_in(None, OsStr::new("cargo"), &arguments, caller, None).unwrap();
            assert_eq!(roots.workspace_root, source_root);
            assert_eq!(roots.target_dir, source_root.join("shared"));
            assert!(roots.target_dir_requested);
        }
    }

    #[test]
    fn path_install_cli_includes_keep_caller_paths_and_override_order() {
        let source = cargo_fixture();
        let caller = cargo_fixture();
        let source_root = fixture_root(source.path());
        let caller_root = fixture_root(caller.path());
        for (root, target) in [
            (&caller_root, "caller-target"),
            (&source_root, "wrong-target"),
        ] {
            std::fs::create_dir_all(root.join(".config")).unwrap();
            std::fs::write(
                root.join(".config/extra.toml"),
                format!("[build]\ntarget-dir = '{target}'\n"),
            )
            .unwrap();
        }
        let resolve = |overrides: &[&str]| {
            let mut args = vec![
                "install".into(),
                "--path".into(),
                source_root.display().to_string(),
                "--offline".into(),
            ];
            for value in overrides {
                args.extend(["--config".into(), (*value).into()]);
            }
            resolve_reported_in(None, OsStr::new("cargo"), &args, &caller_root, None)
        };
        for include in [
            "include=['.config/extra.toml']",
            "include=[{path='.config/extra.toml'}, {path='.config/missing.toml', optional=true}]",
        ] {
            assert_eq!(
                resolve(&[include]).unwrap().target_dir,
                caller_root.join("caller-target")
            );
            assert_eq!(
                resolve(&[include, "build.target-dir='override'"])
                    .unwrap()
                    .target_dir,
                caller_root.join("override")
            );
        }
        let absolute_include = format!(
            "include=[{}]",
            toml::Value::String(caller_root.join(".config/extra.toml").display().to_string())
        );
        assert_eq!(
            resolve(&[&absolute_include]).unwrap().target_dir,
            caller_root.join("caller-target")
        );
        assert!(resolve(&["include=['.config/missing.toml']"]).is_none());

        // Keep unsupported Cargo values invalid instead of repairing them.
        assert!(resolve(&["include=42"]).is_none());
    }

    /// A stand-in Cargo that answers `metadata` and logs every call.
    #[cfg(unix)]
    fn logging_cargo(directory: &Path, project: &Path, log: &Path) -> PathBuf {
        use std::os::unix::fs::PermissionsExt as _;
        let script = directory.join("cargo");
        std::fs::write(
            &script,
            format!(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> {log}\ncase \" $* \" in *' metadata '*) printf '{{\"workspace_root\":\"{root}\",\"target_directory\":\"{root}/target\",\"packages\":[]}}';; esac\n",
                log = log.display(),
                root = project.display(),
            ),
        )
        .unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        script
    }

    /// A stand-in Cargo whose reported directories follow what it is given,
    /// so a record recalled for the wrong inputs is visibly wrong rather than
    /// accidentally right.
    #[cfg(unix)]
    fn build_dir_cargo(directory: &Path, project: &Path, log: &Path) -> PathBuf {
        use std::os::unix::fs::PermissionsExt as _;
        let script = directory.join("cargo");
        std::fs::write(
            &script,
            format!(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> {log}\ncase \" $* \" in *' metadata '*) target=\"${{CARGO_TARGET_DIR:-{root}/target}}\"; build=\"${{CARGO_BUILD_BUILD_DIR:-$target/build-dir}}\"; printf '{{\"workspace_root\":\"{root}\",\"target_directory\":\"%s\",\"build_directory\":\"%s\",\"packages\":[]}}' \"$target\" \"$build\";; esac\n",
                log = log.display(),
                root = project.display(),
            ),
        )
        .unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        script
    }

    #[cfg(unix)]
    fn probes(log: &Path) -> usize {
        std::fs::read_to_string(log)
            .unwrap_or_default()
            .lines()
            .filter(|line| line.contains("metadata"))
            .count()
    }

    #[test]
    fn reported_intermediates_survive_resolution_and_cached_records() {
        let directory = cargo_fixture();
        let root = directory.path();
        let cache = tempfile::tempdir().unwrap();
        let arguments = ["build".to_owned()];
        let roots = (
            root.to_path_buf(),
            root.join("target"),
            Some(root.join("intermediates")),
        );
        let resolved = resolve_with_reported(&arguments, root, None, Some(roots.clone()));
        assert_eq!(resolved.build_dir, roots.2);
        let describe = || {
            ProbeRecord::describe(
                cache.path(),
                None,
                OsStr::new("cargo"),
                &arguments,
                root,
                None,
            )
            .unwrap()
        };
        describe().remember(&roots);
        assert_eq!(describe().recall(), Some(roots.clone()));
        let old_cargo =
            resolve_with_reported(&arguments, root, None, Some((roots.0, roots.1, None)));
        assert_eq!(old_cargo.build_dir, None);
    }

    /// The environment variable that names the child run of the test below.
    #[cfg(unix)]
    const BUILD_DIR_PROBE_CHILD: &str = "TUIST_CARGO_CACHE_CARGO_BUILD_DIR_PROBE_CHILD";

    /// Take a reported build directory through the whole probe path: Cargo
    /// reports it, resolution carries it, and the record answers for it. The
    /// sibling test above hands the roots in by hand, so it cannot tell
    /// whether `cargo metadata` output is read at all, nor whether the
    /// inputs that select a build directory select a record. Here the
    /// stand-in Cargo derives what it reports from `CARGO_BUILD_BUILD_DIR`
    /// and `CARGO_TARGET_DIR`, so a record recalled for the wrong inputs
    /// reports the wrong directory instead of the right one by chance. The
    /// body runs in a child copy of the test binary because it sets process
    /// environment, which is not safe beside tests reading it in parallel.
    #[test]
    #[cfg(unix)]
    fn a_probed_build_directory_is_parsed_recalled_and_rekeyed() {
        if std::env::var_os(BUILD_DIR_PROBE_CHILD).is_none() {
            let status = Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "--nocapture",
                    "--test-threads=1",
                    "tests::a_probed_build_directory_is_parsed_recalled_and_rekeyed",
                ])
                .env(BUILD_DIR_PROBE_CHILD, "1")
                .env_remove("CARGO_BUILD_BUILD_DIR")
                .env_remove("CARGO_TARGET_DIR")
                .env_remove("CARGO_BUILD_TARGET_DIR")
                .status()
                .unwrap();
            assert!(status.success(), "the child run of this test failed");
            return;
        }

        let directory = cargo_fixture();
        let root = directory.path();
        let cache = tempfile::tempdir().unwrap();
        let log = root.join("cargo.log");
        let cargo = build_dir_cargo(root, root, &log);
        let home = root.join("cargo-home");
        let resolve = |arguments: &[String]| {
            resolve_reported_from_home(
                Some(cache.path()),
                Some(&home),
                cargo.as_os_str(),
                arguments,
                root,
                None,
            )
            .unwrap()
        };
        let build = ["build".to_string()];

        // What Cargo reported is what resolution carries.
        let first = resolve(&build);
        assert_eq!(first.build_dir, Some(root.join("target/build-dir")));
        assert_eq!(probes(&log), 1);

        // The same question again is answered from the record, not Cargo.
        assert_eq!(resolve(&build).build_dir, first.build_dir);
        assert_eq!(probes(&log), 1);

        // The environment that selects a build directory is part of the key.
        let elsewhere = root.join("elsewhere");
        // SAFETY: this child process runs this test and no other.
        unsafe { std::env::set_var("CARGO_BUILD_BUILD_DIR", &elsewhere) };
        assert_eq!(resolve(&build).build_dir, Some(elsewhere));
        assert_eq!(probes(&log), 2);
        // SAFETY: as above.
        unsafe { std::env::remove_var("CARGO_BUILD_BUILD_DIR") };
        assert_eq!(resolve(&build).build_dir, first.build_dir);
        assert_eq!(probes(&log), 2);

        // So is a target directory named on the command line, which the
        // probe never sees among its own arguments.
        let other_target = root.join("other-target");
        let targeted = [
            "build".to_string(),
            "--target-dir".to_string(),
            other_target.display().to_string(),
        ];
        let with_target = resolve(&targeted);
        assert_eq!(with_target.build_dir, Some(other_target.join("build-dir")));
        assert_eq!(probes(&log), 3);
        assert_eq!(resolve(&targeted).build_dir, with_target.build_dir);
        assert_eq!(resolve(&build).build_dir, first.build_dir);
        assert_eq!(probes(&log), 3);
    }

    #[test]
    #[cfg(unix)]
    fn a_probe_is_remembered_while_what_cargo_read_stands() {
        let directory = cargo_fixture();
        let root = directory.path();
        let cache = tempfile::tempdir().unwrap();
        let log = root.join("cargo.log");
        let cargo = logging_cargo(root, root, &log);
        let arguments = ["build".to_string(), "--locked".to_string()];
        let home = root.join("cargo-home");
        let resolve = |target_dir_env: Option<&str>| {
            resolve_reported_from_home(
                Some(cache.path()),
                Some(&home),
                cargo.as_os_str(),
                &arguments,
                root,
                target_dir_env.map(OsString::from),
            )
            .unwrap()
        };

        let first = resolve(None);
        assert_eq!(first.workspace_root, root);
        assert_eq!(probes(&log), 1);
        // The same question again is answered from the record.
        assert_eq!(resolve(None), first);
        assert_eq!(probes(&log), 1);

        // An edit to a manifest Cargo read runs the probe again.
        std::fs::write(
            root.join("Cargo.toml"),
            "[package]\nname = \"fixture\"\nversion = \"0.2.0\"\nedition = \"2021\"\n",
        )
        .unwrap();
        assert_eq!(resolve(None), first);
        assert_eq!(probes(&log), 2);
        assert_eq!(resolve(None), first);
        assert_eq!(probes(&log), 2);

        // So does a configuration file appearing where Cargo would look.
        std::fs::create_dir_all(root.join(".cargo")).unwrap();
        std::fs::write(root.join(".cargo/config.toml"), "[build]\njobs = 2\n").unwrap();
        assert_eq!(resolve(None), first);
        assert_eq!(probes(&log), 3);

        // The environment that selects a target directory is part of the key.
        assert!(resolve(Some("elsewhere")).target_dir_requested);
        assert_eq!(probes(&log), 4);
        assert_eq!(resolve(None), first);
        assert_eq!(probes(&log), 4);

        // So is the Cargo home, which follows HOME when CARGO_HOME is unset,
        // and whose configuration is watched like the project's.
        let other_home = root.join("other-home");
        let from_other_home = resolve_reported_from_home(
            Some(cache.path()),
            Some(&other_home),
            cargo.as_os_str(),
            &arguments,
            root,
            None,
        )
        .unwrap();
        assert_eq!(from_other_home.workspace_root, first.workspace_root);
        assert_eq!(probes(&log), 5);
        std::fs::create_dir_all(&other_home).unwrap();
        std::fs::write(other_home.join("config.toml"), "[build]\njobs = 4\n").unwrap();
        resolve_reported_from_home(
            Some(cache.path()),
            Some(&other_home),
            cargo.as_os_str(),
            &arguments,
            root,
            None,
        )
        .unwrap();
        assert_eq!(probes(&log), 6);
        assert_eq!(resolve(None), first);
        assert_eq!(probes(&log), 6);

        // A configuration that includes files this cannot see is never
        // remembered: every build probes.
        std::fs::write(
            root.join(".cargo/config.toml"),
            "include = \"other.toml\"\n",
        )
        .unwrap();
        assert_eq!(resolve(None).workspace_root, first.workspace_root);
        assert_eq!(resolve(None).workspace_root, first.workspace_root);
        assert_eq!(probes(&log), 8);
    }

    #[test]
    #[cfg(unix)]
    fn a_config_file_named_on_the_command_line_is_pinned() {
        let directory = cargo_fixture();
        let root = directory.path();
        let cache = tempfile::tempdir().unwrap();
        let log = root.join("cargo.log");
        let cargo = logging_cargo(root, root, &log);
        let extra = root.join("extra.toml");
        std::fs::write(&extra, "[build]\njobs = 2\n").unwrap();
        let arguments = [
            "build".to_string(),
            "--config".to_string(),
            extra.display().to_string(),
        ];
        let resolve = || {
            resolve_reported_in(
                Some(cache.path()),
                cargo.as_os_str(),
                &arguments,
                root,
                None,
            )
            .unwrap()
        };

        let first = resolve();
        assert_eq!(resolve(), first);
        assert_eq!(probes(&log), 1);
        // The file is watched like any other configuration.
        std::fs::write(&extra, "[build]\njobs = 3\n").unwrap();
        assert_eq!(resolve(), first);
        assert_eq!(probes(&log), 2);
        // Until it includes something that cannot be.
        std::fs::write(&extra, "include = \"more.toml\"\n").unwrap();
        resolve();
        resolve();
        assert_eq!(probes(&log), 4);
    }

    #[test]
    #[cfg(unix)]
    fn a_failed_probe_is_not_remembered() {
        use std::os::unix::fs::PermissionsExt as _;
        let directory = cargo_fixture();
        let root = directory.path();
        let cache = tempfile::tempdir().unwrap();
        let script = root.join("cargo");
        std::fs::write(&script, "#!/bin/sh\nexit 1\n").unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        let arguments = ["build".to_string()];

        assert!(
            resolve_reported_in(
                Some(cache.path()),
                script.as_os_str(),
                &arguments,
                root,
                None
            )
            .is_none()
        );
        assert!(!cache.path().join("cargo-roots").exists());
    }

    #[test]
    fn reported_resolution_requires_a_successful_metadata_probe() {
        let directory = cargo_fixture();
        assert!(
            resolve_reported(
                OsStr::new("cargo-that-does-not-exist"),
                &["build".into()],
                directory.path(),
                None,
            )
            .is_none()
        );
    }

    fn git(directory: &Path, arguments: &[&str]) {
        let status = Command::new("git")
            .arg("-C")
            .arg(directory)
            .args(["-c", "commit.gpgsign=false", "-c", "user.name=t"])
            .args(["-c", "user.email=t@example.com"])
            .args(arguments)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .unwrap();
        assert!(status.success(), "git {arguments:?} failed");
    }

    #[test]
    fn earlier_lockfile_states_are_offered_newest_first() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let command = Vec::new();
        git(root, &["init", "-q"]);
        let mut committed = Vec::new();
        for state in ["one", "two", "three"] {
            std::fs::write(root.join("Cargo.lock"), state).unwrap();
            committed.push(build_identity(root, &command));
            git(root, &["add", "Cargo.lock"]);
            git(root, &["commit", "-q", "-m", state]);
        }
        committed.reverse();

        // An uncommitted edit: the committed copy is the nearest earlier state.
        std::fs::write(root.join("Cargo.lock"), "four").unwrap();
        assert!(!committed.contains(&build_identity(root, &command)));
        assert_eq!(previous_build_identities(root), committed);

        // Once committed, the working copy matches HEAD and is not offered as
        // its own fallback.
        git(root, &["commit", "-q", "-am", "four"]);
        assert_eq!(previous_build_identities(root), committed);
    }

    #[test]
    fn a_shallow_clone_offers_the_states_it_can_reach() {
        let origin = tempfile::tempdir().unwrap();
        let root = origin.path();
        let command = Vec::new();
        git(root, &["init", "-q"]);
        let mut committed = Vec::new();
        for state in ["one", "two", "three", "four"] {
            std::fs::write(root.join("Cargo.lock"), state).unwrap();
            committed.push(build_identity(root, &command));
            git(root, &["add", "Cargo.lock"]);
            git(root, &["commit", "-q", "-m", state]);
        }
        let clones = tempfile::tempdir().unwrap();
        let shallow = clones.path().join("shallow");
        git(
            clones.path(),
            &[
                "clone",
                "-q",
                "--depth",
                "2",
                &format!("file://{}", root.display()),
                shallow.to_str().unwrap(),
            ],
        );
        // HEAD holds "four"; its parent "three" was fetched and "two" was not.
        assert_eq!(
            previous_build_identities(&shallow),
            vec![committed[2].clone()]
        );
    }

    #[test]
    fn an_untracked_lockfile_has_no_history_to_borrow_from() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        git(root, &["init", "-q"]);
        std::fs::write(root.join("Cargo.lock"), "tracked").unwrap();
        git(root, &["add", "Cargo.lock"]);
        git(root, &["commit", "-q", "-m", "tracked"]);
        git(root, &["rm", "-q", "Cargo.lock"]);
        git(root, &["commit", "-q", "-m", "removed"]);
        // Cargo generated a replacement nobody tracks.
        std::fs::write(root.join("Cargo.lock"), "generated").unwrap();
        assert!(previous_build_identities(root).is_empty());
    }

    #[test]
    fn a_workspace_outside_version_control_has_no_earlier_states() {
        let directory = cargo_fixture();
        std::fs::write(directory.path().join("Cargo.lock"), "one").unwrap();
        assert!(previous_build_identities(directory.path()).is_empty());
    }
}
