//! Cache Cargo build-script execution after the script has declared its inputs.

use crate::ar::ArDeterminism;
use crate::materialize::{
    apply_file_mode, denormalize_output_text, file_mode, find_blobs, normalize_output_text,
    read_canonical_blob, read_verified_blob, record_action_hit, replay_bytes, staging_directory,
    validate_file_mode,
};
use crate::session;
use eyre::{Context as _, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::time::{Instant, SystemTime};
use tuist_cargo_cache_core::{
    ActionPrediction, AgentRequest, AgentResponse, CacheDigest, CacheDirectory, CacheDirectoryNode,
    CacheFileNode, CacheSymlinkNode, FileDigestCache, FileDigestResolution, FileDigestScope,
    FileIdentity, NoFileDigestCache, RecordedFileDigest, RemoteActionResult, RestoreStats,
    canonical_json, digest_file, digest_file_validated,
};
use tuist_cargo_cache_rustc::PathMapping;

const ADAPTER: &str = "build-script";

#[derive(Debug, Serialize)]
struct Invocation<'a> {
    binary_action: &'a CacheDigest,
    kind: &'static str,
    version: u8,
}

#[derive(Debug, Serialize)]
struct Action<'a> {
    /// The `ZERO_AR_DATE` the script will read, so a change of archive policy
    /// is a different entry instead of a stale restore. See [`crate::ar`].
    archive_timestamps: Option<&'a str>,
    binary_action: &'a CacheDigest,
    cargo_environment: &'a BTreeMap<String, Option<String>>,
    environment: &'a BTreeMap<String, Option<String>>,
    inputs: &'a BTreeMap<String, InputState>,
    kind: &'static str,
    out_dir: Option<&'a str>,
    version: u8,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum InputState {
    Missing,
    File {
        digest: CacheDigest,
    },
    Directory {
        digest: CacheDigest,
    },
    Symlink {
        target: String,
        referent: Box<InputState>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Prediction {
    #[serde(default)]
    default_package: bool,
    environment: Vec<String>,
    inputs: Vec<String>,
    portable_out_dir: bool,
    version: u8,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Metadata {
    kind: String,
    stderr: CacheDigest,
    stdout: CacheDigest,
    version: u8,
}

struct Restored {
    stats: RestoreStats,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

/// Preserve the real program beside Cargo's expected path and replace it with tuist_cargo_cache.
pub(crate) fn install(executable: &Path, binary_action: &CacheDigest) -> Result<()> {
    // Cargo decides whether a build-script compilation is fresh partly by
    // comparing this path's mtime with its dependencies. The path becomes a
    // shim below, but it still has to look as new as the binary it represents:
    // copying the tuist_cargo_cache executable can otherwise give it tuist_cargo_cache's older mtime and
    // make Cargo compile the build script again on every invocation.
    let modified = std::fs::metadata(executable)?
        .modified()
        .wrap_err("failed to inspect the build-script modification time")?;
    let real = session::build_script_real_path(executable);
    let temporary = real.with_extension("tuist_cargo_cache-real-new");
    let _ = std::fs::remove_file(&temporary);
    std::fs::copy(executable, &temporary).wrap_err("failed to preserve the build script")?;
    // `copy` carries the source's mode, and a build script restored by hard
    // link is the store's read-only object, so this copy of it cannot be
    // opened for writing. The timestamp is set through a read-only handle,
    // which an owner may do and which works whichever way the restore landed.
    crate::materialize::set_modified(&temporary, modified)?;
    let _ = std::fs::remove_file(&real);
    std::fs::rename(&temporary, &real)?;
    std::fs::write(
        build_script_action_path(&real),
        canonical_json(binary_action)?,
    )?;

    // Unix needs only a tiny launcher at each Cargo-owned path. Pin one tuist_cargo_cache
    // binary beside the profile and let every launcher exec it while carrying
    // its own path out of band. Besides saving local disk, keeping the launchers
    // distinct preserves the mtimes Cargo uses for freshness. Windows keeps the
    // self-contained executable because Cargo needs a PE binary there.
    let tuist_cargo_cache =
        std::env::current_exe().wrap_err("failed to locate the tuist_cargo_cache shim")?;
    let _ = std::fs::remove_file(executable);
    let installed = install_launcher(&tuist_cargo_cache, executable).and_then(|_| {
        std::fs::OpenOptions::new()
            .write(true)
            .open(executable)?
            .set_times(std::fs::FileTimes::new().set_modified(modified))
    });
    if let Err(error) = installed {
        let _ = std::fs::rename(&real, executable);
        return Err(error).wrap_err("failed to install the build-script shim");
    }
    Ok(())
}

#[cfg(unix)]
fn install_launcher(tuist_cargo_cache: &Path, executable: &Path) -> std::io::Result<()> {
    let depth = profile_depth(executable);
    let profile = executable
        .ancestors()
        .nth(depth)
        .ok_or_else(|| std::io::Error::other("build-script path has no Cargo profile directory"))?;
    let metadata = std::fs::metadata(tuist_cargo_cache)?;
    let modified = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok());
    let absolute = std::path::absolute(tuist_cargo_cache)?;
    let mut identity = absolute.as_os_str().as_encoded_bytes().to_vec();
    identity.push(0);
    identity.extend_from_slice(&metadata.len().to_le_bytes());
    identity.extend_from_slice(&modified.map_or(0, |time| time.as_nanos()).to_le_bytes());
    let identity = CacheDigest::blake3(&identity);
    // Put the pinned binary under the profile, which every build script of
    // that profile shares, so the launcher stays portable when a target
    // directory moves between checkouts or CI runners.
    let relative = PathBuf::from(".tuist_cargo_cache-build-script-shims")
        .join(&identity.hash)
        .join("tuist_cargo_cache");
    let pinned = profile.join(&relative);
    install_pinned_binary(tuist_cargo_cache, &pinned)?;

    let launcher = format!(
        "#!/bin/sh\n{}=\"$0\" exec \"$(dirname \"$0\")/{}{}\" \"$@\"\n",
        session::BUILD_SCRIPT_SHIM_PATH_ENV,
        "../".repeat(depth - 1),
        relative.to_string_lossy(),
    );
    std::fs::write(executable, launcher)?;
    std::fs::set_permissions(executable, std::fs::Permissions::from_mode(0o755))
}

/// How many levels a build-script executable sits below its Cargo profile
/// directory: `<profile>/build/<unit>/<name>` before Cargo 1.100, and
/// `<profile>/build/<package>/<hash>/out/<name>` from it. An old-layout unit
/// directory is `<package>-<hash>`, so it is never named `out`.
#[cfg(unix)]
fn profile_depth(executable: &Path) -> usize {
    if executable.parent().and_then(Path::file_name) == Some("out".as_ref()) {
        5
    } else {
        3
    }
}

#[cfg(unix)]
fn install_pinned_binary(tuist_cargo_cache: &Path, destination: &Path) -> std::io::Result<()> {
    let parent = destination
        .parent()
        .ok_or_else(|| std::io::Error::other("pinned shim has no parent directory"))?;
    std::fs::create_dir_all(parent)?;

    // macOS can SIGKILL an exec through a hard link created moments earlier.
    // A copied inode published by rename does not hit that kernel race. Races
    // between installers are harmless because this identity names identical
    // tuist_cargo_cache bytes, and rename keeps the destination complete at every instant.
    #[cfg(target_os = "macos")]
    {
        if destination.exists() {
            return Ok(());
        }
        let temporary = tempfile::NamedTempFile::new_in(parent)?;
        std::fs::copy(tuist_cargo_cache, temporary.path())?;
        let mut permissions = std::fs::metadata(temporary.path())?.permissions();
        permissions.set_mode(permissions.mode() | 0o100);
        std::fs::set_permissions(temporary.path(), permissions)?;
        let (file, temporary) = temporary.into_parts();
        drop(file);
        temporary
            .persist(destination)
            .map_err(|error| error.error)?;
        Ok(())
    }

    #[cfg(not(target_os = "macos"))]
    {
        match std::fs::hard_link(tuist_cargo_cache, destination) {
            Ok(()) => return Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => return Ok(()),
            Err(_) => {}
        }

        let temporary = tempfile::NamedTempFile::new_in(parent)?;
        std::fs::copy(tuist_cargo_cache, temporary.path())?;
        let mut permissions = std::fs::metadata(temporary.path())?.permissions();
        permissions.set_mode(permissions.mode() | 0o100);
        std::fs::set_permissions(temporary.path(), permissions)?;
        let (file, temporary) = temporary.into_parts();
        drop(file);
        match std::fs::hard_link(&temporary, destination) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(error) => return Err(error),
        }
        Ok(())
    }
}

#[cfg(not(unix))]
fn install_launcher(tuist_cargo_cache: &Path, executable: &Path) -> std::io::Result<()> {
    std::fs::copy(tuist_cargo_cache, executable).map(|_| ())
}

/// Apply tuist_cargo_cache's archive-timestamp policy to a build script's environment.
///
/// Set on every host rather than only on macOS: the variable is read by Apple's
/// archive tools wherever they run, which includes cctools cross-compiling to
/// an Apple target from Linux, and is inert for toolchains that do not know it.
/// See [`crate::ar`] for why the timestamp matters to the cache.
fn apply_ar_determinism(command: &mut Command) {
    let inherited = std::env::var_os(crate::ar::ZERO_AR_DATE).is_some();
    if crate::ar::normalizes(ar_mode(), ar_profile().as_deref(), inherited) {
        command.env(crate::ar::ZERO_AR_DATE, "1");
    }
}

fn ar_mode() -> ArDeterminism {
    std::env::var(session::AR_DETERMINISM_ENV).map_or_else(
        |_| ArDeterminism::default(),
        |value| ArDeterminism::parse(&value),
    )
}

fn ar_profile() -> Option<String> {
    std::env::var(crate::ar::PROFILE).ok()
}

/// The `ZERO_AR_DATE` this build script will see, for its cache key.
fn archive_timestamp_key() -> Option<String> {
    // `var_os`, matching `apply_ar_determinism`: the two have to agree about
    // whether a value was inherited, including one that is not UTF-8.
    let inherited = std::env::var_os(crate::ar::ZERO_AR_DATE);
    crate::ar::effective_zero_ar_date(ar_mode(), ar_profile().as_deref(), inherited.as_deref())
}

/// Time this build-script run as its own unit, until the returned guard drops.
///
/// Held by the shim around both the cached run and the uncached fallback, so
/// a run that falls back is timed through the script it runs.
pub(crate) fn start_timing() -> Option<crate::phase_timing::Invocation> {
    let invoked = session::build_script_invocation_path()?;
    let timing = crate::phase_timing::start("build-script", Some(stats_label()));
    let out_dir = std::env::var_os("OUT_DIR").map(std::path::PathBuf::from);
    let (unit_id, dependencies) =
        crate::unit_graph::build_script_run_unit(out_dir.as_deref(), &invoked);
    crate::phase_timing::identify(unit_id, dependencies);
    Some(timing)
}

/// Run the preserved program without consulting the cache.
pub(crate) fn run_real() -> ExitCode {
    let Some(invoked) = session::build_script_invocation_path() else {
        return ExitCode::FAILURE;
    };
    let Some(real) = session::find_build_script_real_path(&invoked) else {
        eprintln!("tuist_cargo_cache[error]: the preserved build script is missing");
        return ExitCode::FAILURE;
    };
    let mut command = Command::new(real);
    command.args(std::env::args_os().skip(1));
    command.env_remove(session::BUILD_SCRIPT_SHIM_PATH_ENV);
    apply_ar_determinism(&mut command);
    match command.status() {
        Ok(status) => crate::materialize::exit_code(status),
        Err(error) => {
            eprintln!("tuist_cargo_cache[error]: failed to execute the build script: {error}");
            ExitCode::FAILURE
        }
    }
}

pub(crate) fn run() -> Result<ExitCode> {
    let invoked = session::build_script_invocation_path()
        .ok_or_else(|| eyre::eyre!("build-script shim has no argv0"))?;
    let real = session::find_build_script_real_path(&invoked)
        .ok_or_else(|| eyre::eyre!("preserved build script is missing"))?;
    let action_path = build_script_action_path(&real);
    let action_bytes = std::fs::read(&action_path)?;
    let binary_action: CacheDigest = serde_json::from_slice(&action_bytes)?;
    if binary_action.validate().is_err() || canonical_json(&binary_action)? != action_bytes {
        bail!("build-script binary action is not canonical");
    }
    let invocation_bytes = canonical_json(&Invocation {
        binary_action: &binary_action,
        kind: ADAPTER,
        version: 1,
    })?;
    let invocation = CacheDigest::blake3(&invocation_bytes);

    // Whether the run below follows a lookup. The agent counted that lookup,
    // so the run is its miss; without one the run was never consulted.
    let mut looked_up = false;
    if let Some(prediction) = find_prediction(&invocation)? {
        let (action_bytes, action) = build_action(&binary_action, &prediction)?;
        looked_up = true;
        // A result that fails to restore is a miss like any other: running the
        // script republishes it, where bypassing would leave it broken.
        match restore(&action, &action_bytes) {
            Ok(Some(restored)) => {
                tuist_cargo_cache_core::record_public_build_script(&action, &stats_label(), "hit");
                record_action_hit(&action, restored.stats, &stats_label());
                replay_bytes(&restored.stdout, &restored.stderr)?;
                // A grouped export follows this run's receipt rather than the
                // cumulative manifest. Keep a restored script in that receipt
                // so the next CI job can look it up too. Recording is only
                // bookkeeping after its output reached Cargo: a failure must
                // not run an already-restored script a second time.
                if let Err(error) = record_prediction(invocation, action, &prediction) {
                    session::report_shim_warning(&format!(
                        "restored build-script prediction was not recorded: {error:#}"
                    ));
                }
                return Ok(ExitCode::SUCCESS);
            }
            Ok(None) => {}
            Err(error) => session::report_shim_warning(&format!(
                "build-script result was not restored: {error:#}"
            )),
        }
    }
    if !looked_up {
        session::record_unconsulted();
    }

    let mut command = Command::new(&real);
    command.args(std::env::args_os().skip(1));
    command.env_remove(session::BUILD_SCRIPT_SHIM_PATH_ENV);
    apply_ar_determinism(&mut command);
    let started = Instant::now();
    let started_at = run_start_stamp();
    let output = command
        .output()
        .wrap_err("failed to execute the build script")?;
    session::record_compiler_invocation(
        if looked_up { "miss" } else { "unconsulted" },
        Some(&stats_label()),
        crate::util::duration_ns(started.elapsed()),
    );
    replay_bytes(&output.stdout, &output.stderr)?;
    if !output.status.success() {
        return Ok(crate::materialize::exit_code(output.status));
    }

    let caching = (|| -> Result<()> {
        let Some(prediction) = parse_prediction(&output.stdout)? else {
            record_bypass("build-script-always-rerun");
            return Ok(());
        };
        if declared_inputs_changed_since(&prediction, started_at)? {
            // The result is keyed to the inputs as the run left them, but the
            // script read them as they were before. Cargo runs it again, and
            // that run starts from the tree this one left.
            record_bypass("build-script-wrote-its-inputs");
            return Ok(());
        }
        let (action_bytes, action) = build_action(&binary_action, &prediction)?;
        publish(&action, &action_bytes, &output.stdout, &output.stderr)?;
        tuist_cargo_cache_core::record_public_build_script(
            &action,
            &stats_label(),
            if looked_up { "miss" } else { "unconsulted" },
        );
        record_prediction(invocation, action, &prediction)
    })();
    if let Err(error) = caching {
        // The script has already run and its streams have already reached
        // Cargo. Cache bookkeeping may fail, but retrying the program would
        // duplicate arbitrary side effects and every emitted directive.
        session::report_shim_warning(&format!("build-script result was not stored: {error:#}"));
    }
    Ok(ExitCode::SUCCESS)
}

fn record_bypass(kind: &str) {
    let _ = session::request_agent(&[AgentRequest::RecordBypass { kind: kind.into() }]);
}

/// The package Cargo is running this build script for, when it says.
fn cargo_package_name() -> Option<String> {
    std::env::var("CARGO_PKG_NAME")
        .ok()
        .filter(|name| !name.is_empty() && name.len() <= 200 && !name.chars().any(char::is_control))
}

/// The label a run is recorded under, as its timing names it: every package's
/// build script is the crate `build_script_build`, so that alone would merge
/// them all in the slow-compilation report. The crate name is kept when Cargo
/// did not provide a package.
fn stats_label() -> String {
    cargo_package_name().map_or_else(
        || "build_script_build".into(),
        |package| format!("{package} build script"),
    )
}

fn build_script_action_path(real: &Path) -> PathBuf {
    let mut path = real.as_os_str().to_os_string();
    path.push(".action");
    PathBuf::from(path)
}

fn find_prediction(invocation: &CacheDigest) -> Result<Option<Prediction>> {
    let task = std::env::var(session::BUILD_ENV).wrap_err("build session has no task identity")?;
    let responses = session::request_agent(&[AgentRequest::FindActionPrediction {
        task,
        invocation: invocation.clone(),
    }])?;
    match responses.into_iter().next() {
        Some(AgentResponse::ActionPrediction {
            prediction: Some(found),
        }) if found.adapter == ADAPTER && found.invocation == *invocation => {
            Ok(Some(decode_prediction(&found.payload)?))
        }
        Some(AgentResponse::ActionPrediction { prediction: None }) => Ok(None),
        Some(AgentResponse::Error { message }) => bail!(message),
        _ => bail!("cache agent returned an unexpected build-script prediction response"),
    }
}

fn decode_prediction(payload: &str) -> Result<Prediction> {
    let value: serde_json::Value = serde_json::from_str(payload)?;
    if canonical_json(&value)? != payload.as_bytes() {
        bail!("cached build-script prediction is unsupported");
    }
    let has_default_package = value
        .as_object()
        .is_some_and(|value| value.contains_key("default_package"));
    let prediction: Prediction = serde_json::from_value(value)?;
    let supported_version = match prediction.version {
        // Version 1 predates Cargo-default package inputs. Every prediction it
        // stored came from explicit rerun directives, so false is exact.
        1 => !has_default_package && !prediction.default_package,
        2 => has_default_package,
        _ => false,
    };
    if !supported_version
        || (prediction.default_package
            && (prediction.inputs != ["${build_script_manifest_dir}"]
                || !prediction.environment.is_empty()))
    {
        bail!("cached build-script prediction is unsupported");
    }
    Ok(prediction)
}

fn record_prediction(
    invocation: CacheDigest,
    action: CacheDigest,
    prediction: &Prediction,
) -> Result<()> {
    let task = std::env::var(session::BUILD_ENV)?;
    let payload = prediction_payload(prediction)?;
    let responses = session::request_agent(&[AgentRequest::RecordActionPrediction {
        task,
        prediction: ActionPrediction {
            invocation,
            action,
            adapter: ADAPTER.into(),
            payload,
        },
    }])?;
    match responses.into_iter().next() {
        Some(AgentResponse::ActionPredictionRecorded) => Ok(()),
        Some(AgentResponse::Error { message }) => bail!(message),
        _ => bail!("cache agent did not record the build-script prediction"),
    }
}

/// Serialize a prediction in the schema version that produced it.
///
/// A restored v1 prediction has no `default_package` field. Re-recording it
/// with the current Rust type would add that false field, turning it into an
/// invalid hybrid which the v1 decoder deliberately rejects on the next run.
fn prediction_payload(prediction: &Prediction) -> Result<String> {
    let mut payload = serde_json::to_value(prediction)?;
    if prediction.version == 1 {
        let object = payload
            .as_object_mut()
            .ok_or_else(|| eyre::eyre!("build-script prediction did not serialize to an object"))?;
        object.remove("default_package");
    }
    Ok(String::from_utf8(canonical_json(&payload)?)?)
}

/// Whether a directive hands the linker a path in the target directory that
/// is not inside `OUT_DIR`. Only `OUT_DIR` is restored on a hit, so a link path
/// elsewhere (rusty_v8 downloads its archive to `gn_out/obj`) would be replayed
/// pointing at nothing, and the script has to run again in every checkout.
/// `OUT_DIR` normalizes to its own placeholder, so any `${target` left in the
/// value is a path outside it, as is a `..` that climbs out of `OUT_DIR`.
fn links_outside_out_dir(directive: &str, mappings: &[PathMapping]) -> bool {
    let Some((name, value)) = directive.split_once('=') else {
        return false;
    };
    let links = name.starts_with("rustc-link-search")
        || name.starts_with("rustc-link-arg")
        || name.starts_with("rustc-cdylib-link-arg")
        || name == "rustc-flags";
    if !links {
        return false;
    }
    let value = normalize_environment_value(value, mappings);
    // Normalization is textual, so `${build_script_out_dir}/../native` still
    // reads as inside `OUT_DIR` while naming a sibling. Resolve parent
    // components lexically: a path rooted in `OUT_DIR` that stays below it is
    // restored, and any other `..` may leave the restored tree.
    //
    // A relative path is resolved by the linker from the build script's working
    // directory, which can place it in the target directory too.
    let bases = relative_bases();
    // The word after `-l` or `-framework` names a library, not a path.
    let mut names_library = false;
    let relative_in_target = {
        value.split(' ').any(|word| {
            let skip = std::mem::replace(
                &mut names_library,
                matches!(word, "-l" | "-framework" | "-weak_framework"),
            );
            !skip
                && word
                    .split(['=', ','])
                    .any(|token| relative_token_is_in_target(token, &bases, mappings))
        })
    };
    relative_in_target
        || value.contains("${target")
        || value.split([' ', '=', ',']).any(|token| {
            let rooted = token
                .strip_prefix("${build_script_out_dir")
                .and_then(|rest| rest.split_once('}'))
                .map(|(_, rest)| rest);
            let mut depth = 0_usize;
            for part in rooted.unwrap_or(token).split(['/', '\\']) {
                match part {
                    ".." if rooted.is_some() && depth > 0 => depth -= 1,
                    ".." => return true,
                    "" | "." => {}
                    _ => depth += 1,
                }
            }
            false
        })
}

/// The directories a relative link path may be resolved from: the build
/// script's working directory, and the workspace root that rustc runs in.
fn relative_bases() -> Vec<PathBuf> {
    let mut bases = Vec::new();
    bases.extend(std::env::current_dir().ok());
    bases.extend(std::env::var_os(session::WORKSPACE_ROOT_ENV).map(PathBuf::from));
    bases
}

/// Whether a relative path argument lands in the target directory from any of
/// `bases` once its `.` and `..` components are resolved.
fn relative_token_is_in_target(token: &str, bases: &[PathBuf], mappings: &[PathMapping]) -> bool {
    // An attached `-L<path>` carries its path after the flag.
    let token = token.strip_prefix("-L").unwrap_or(token);
    let path = Path::new(token);
    if token.is_empty() || token.starts_with(['-', '$']) || !path.is_relative() {
        return false;
    }
    bases.iter().any(|base| {
        let mut resolved = PathBuf::new();
        for component in base.join(path).components() {
            match component {
                std::path::Component::ParentDir => {
                    resolved.pop();
                }
                std::path::Component::CurDir => {}
                other => resolved.push(other),
            }
        }
        normalize_environment_value(&resolved.to_string_lossy(), mappings).contains("${target")
    })
}

/// Whether recorded output carries such a directive. Predictions stored before
/// this check existed can still resolve to one.
fn output_links_outside_out_dir(stdout: &[u8]) -> bool {
    let Ok(text) = std::str::from_utf8(stdout) else {
        return false;
    };
    output_links_outside_out_dir_with(text, &build_script_mappings())
}

fn output_links_outside_out_dir_with(text: &str, mappings: &[PathMapping]) -> bool {
    text.lines().any(|line| {
        line.strip_prefix("cargo::")
            .or_else(|| line.strip_prefix("cargo:"))
            .is_some_and(|directive| links_outside_out_dir(directive, mappings))
    })
}

fn parse_prediction(stdout: &[u8]) -> Result<Option<Prediction>> {
    let text = std::str::from_utf8(stdout).wrap_err("build-script stdout is not UTF-8")?;
    let mappings = build_script_mappings();
    parse_prediction_with_mappings(text, &mappings)
}

fn parse_prediction_with_mappings(
    text: &str,
    mappings: &[PathMapping],
) -> Result<Option<Prediction>> {
    let mut inputs = BTreeSet::new();
    let mut environment = BTreeSet::new();
    for line in text.lines() {
        let directive = line
            .strip_prefix("cargo::")
            .or_else(|| line.strip_prefix("cargo:"));
        let Some(directive) = directive else { continue };
        if let Some(path) = directive.strip_prefix("rerun-if-changed=") {
            // Cargo treats the empty path as an always-rerun declaration. No
            // finite action key can preserve that contract.
            if path.is_empty() {
                return Ok(None);
            }
            let path = normalize_environment_value(path, mappings);
            // A generated file cannot also be an input to the execution that
            // generated it. Build scripts use this shape to make Cargo run
            // them every time (shadow-rs does so in release builds), and
            // publishing it under a key derived after execution makes two
            // different results contend for one local action. Preserve the
            // script's always-rerun contract instead of trying to cache it.
            if path.starts_with("${build_script_out_dir}")
                || path.starts_with("${build_script_out_dir:")
            {
                return Ok(None);
            }
            inputs.insert(path);
        } else if let Some(name) = directive.strip_prefix("rerun-if-env-changed=")
            && !name.is_empty()
        {
            environment.insert(name.to_string());
        } else if links_outside_out_dir(directive, mappings) {
            return Ok(None);
        }
    }
    let default_package = inputs.is_empty() && environment.is_empty();
    if default_package {
        // With no rerun directives Cargo treats the complete package source as
        // the build script's input. Keep that implicit declaration explicit in
        // the prediction so equivalent package trees can share the execution.
        inputs.insert("${build_script_manifest_dir}".into());
    }
    Ok(Some(Prediction {
        default_package,
        inputs: inputs.into_iter().collect(),
        environment: environment.into_iter().collect(),
        portable_out_dir: out_dir_is_portable()?,
        version: 2,
    }))
}

fn build_action(
    binary_action: &CacheDigest,
    prediction: &Prediction,
) -> Result<(Vec<u8>, CacheDigest)> {
    let working_dir = std::env::current_dir()?;
    let mappings = build_script_mappings();
    let mut inputs = BTreeMap::new();
    for declared in &prediction.inputs {
        let resolved_name =
            String::from_utf8(denormalize_output_text(declared.as_bytes(), &mappings))
                .expect("denormalizing UTF-8 paths preserves UTF-8");
        let path = Path::new(&resolved_name);
        let resolved = if path.is_absolute() {
            path.to_path_buf()
        } else {
            working_dir.join(path)
        };
        let state = if prediction.default_package {
            package_input_state(&resolved, &mappings)?
        } else {
            input_state(&resolved, &mappings)?
        };
        inputs.insert(declared.clone(), state);
    }
    let environment = prediction
        .environment
        .iter()
        .map(|name| {
            let value = std::env::var_os(name)
                .map(|value| {
                    value
                        .into_string()
                        .map_err(|_| eyre::eyre!("environment input is not UTF-8: {name}"))
                })
                .transpose()?
                .map(|value| normalize_environment_value(&value, &mappings));
            Ok((name.clone(), value))
        })
        .collect::<Result<BTreeMap<_, _>>>()?;
    let cargo_environment = cargo_environment(&mappings);
    let out_dir = (!prediction.portable_out_dir)
        .then(|| std::env::var("OUT_DIR"))
        .transpose()?;
    let archive_timestamps = archive_timestamp_key();
    let bytes = canonical_json(&Action {
        archive_timestamps: archive_timestamps.as_deref(),
        binary_action,
        cargo_environment: &cargo_environment,
        environment: &environment,
        inputs: &inputs,
        kind: ADAPTER,
        out_dir: out_dir.as_deref(),
        // Bumped with `archive_timestamps`, then again when a script that
        // wrote into its declared inputs stopped being recorded: an entry
        // stored before either cannot say which policy produced it, so it is
        // not reused.
        version: 4,
    })?;
    let digest = CacheDigest::blake3(&bytes);
    Ok((bytes, digest))
}

/// Cargo's build-script declarations also invalidate the package's rustc
/// compilations. Proc macros may read these paths without putting them in
/// dep-info, so the declarations must be hashed before any compilation lookup.
/// Read Cargo's recorded stdout, even when execution caching is disabled or
/// Cargo ran the build script outside tuist_cargo_cache.
pub(crate) struct CompilationInputs {
    pub(crate) input: tuist_cargo_cache_rustc::ActionInput,
    manifest_dir: PathBuf,
    mappings: Vec<PathMapping>,
    implicit_package: bool,
    compiler_directories: Vec<PathBuf>,
}

impl CompilationInputs {
    /// Read only this package's declarations, ignoring an inherited OUT_DIR
    /// when a nested Cargo invocation compiles a package without a build script.
    pub(crate) fn for_package(out_dir: &Path, manifest_dir: &Path) -> Result<Option<Self>> {
        // Nested Cargo commands can inherit their caller's OUT_DIR. Cargo
        // replaces it for a package with a build script, but leaves it alone
        // for packages without one; those must not read the caller's inputs.
        let manifest: toml::Value =
            toml::from_str(&std::fs::read_to_string(manifest_dir.join("Cargo.toml"))?)?;
        let has_script = match manifest
            .get("package")
            .and_then(|package| package.get("build"))
        {
            Some(toml::Value::Boolean(enabled)) => *enabled,
            Some(toml::Value::String(_)) => true,
            None => manifest_dir.join("build.rs").is_file(),
            Some(_) => bail!("unsupported Cargo build-script declaration"),
        };
        if has_script {
            Self::read(out_dir, manifest_dir).map(Some)
        } else {
            Ok(None)
        }
    }

    /// Capture Cargo's declarations using the session's shared content ledger.
    pub(crate) fn read(out_dir: &Path, manifest_dir: &Path) -> Result<Self> {
        Self::read_with_cache(out_dir, manifest_dir, session::file_digest_cache())
    }

    /// Capture a compilation key with an explicit ledger, including all file
    /// contents, directory membership, symlink targets, and declared variables.
    fn read_with_cache(
        out_dir: &Path,
        manifest_dir: &Path,
        digests: &dyn FileDigestCache,
    ) -> Result<Self> {
        let unit = out_dir
            .parent()
            .ok_or_else(|| eyre::eyre!("OUT_DIR has no parent"))?;
        // Cargo 1.100 moved the recorded output from `output` to `run/stdout`.
        let output = if unit.join("run").is_dir() {
            unit.join("run/stdout")
        } else {
            unit.join("output")
        };
        let mappings = build_script_mappings_with_env(|name| match name {
            "OUT_DIR" => Some(out_dir.to_path_buf()),
            "CARGO_MANIFEST_DIR" => Some(manifest_dir.to_path_buf()),
            _ => std::env::var_os(name).map(PathBuf::from),
        });
        let mut inputs = Self {
            input: tuist_cargo_cache_rustc::ActionInput {
                path: output,
                digest: CacheDigest::blake3(&[]),
            },
            manifest_dir: manifest_dir.to_path_buf(),
            mappings,
            implicit_package: false,
            compiler_directories: [
                std::env::var_os(session::TARGET_DIR_ENV).map(PathBuf::from),
                // Also covers Cargo's separate build directory, and callers
                // without tuist_cargo_cache's target-directory environment.
                out_dir.ancestors().nth(3).map(Path::to_path_buf),
            ]
            .into_iter()
            .flatten()
            .map(std::fs::canonicalize)
            .collect::<std::io::Result<_>>()?,
        };
        (inputs.input.digest, inputs.implicit_package) = inputs.digest(digests)?;
        Ok(inputs)
    }

    /// Rebuild the declaration signature, rejecting explicit watches that
    /// include compiler outputs rather than silently excluding watched files.
    fn digest(&self, digests: &dyn FileDigestCache) -> Result<(CacheDigest, bool)> {
        let stdout = std::fs::read_to_string(&self.input.path)
            .wrap_err("failed to read Cargo's build-script declarations")?;
        let mut inputs = BTreeMap::new();
        let mut environment = BTreeMap::new();
        for line in stdout.lines() {
            let Some(directive) = line
                .strip_prefix("cargo::")
                .or_else(|| line.strip_prefix("cargo:"))
            else {
                continue;
            };
            if let Some(path) = directive.strip_prefix("rerun-if-changed=") {
                // An empty declaration asks Cargo to rerun every time. There
                // is no finite compilation key that preserves that contract.
                if path.is_empty() {
                    bail!("build script declares an always-changing input");
                }
                inputs.insert(
                    normalize_environment_value(path, &self.mappings),
                    InputTree::read(
                        &self.manifest_dir.join(path),
                        &self.mappings,
                        &[],
                        &self.compiler_directories,
                        0,
                    )?,
                );
            } else if let Some(name) = directive.strip_prefix("rerun-if-env-changed=")
                && !name.is_empty()
            {
                let value = std::env::var_os(name)
                    .map(|value| {
                        value
                            .into_string()
                            .map_err(|_| eyre::eyre!("environment input is not UTF-8: {name}"))
                    })
                    .transpose()?;
                environment.insert(name, value);
            }
        }
        let implicit_package = inputs.is_empty() && environment.is_empty();
        if implicit_package {
            inputs.insert(
                "${build_script_manifest_dir}".into(),
                InputTree::read(
                    &self.manifest_dir,
                    &self.mappings,
                    &default_package_exclusions(&self.manifest_dir)?,
                    &[],
                    0,
                )?,
            );
        }
        let mut paths = BTreeSet::new();
        for tree in inputs.values() {
            tree.files(&mut paths);
        }
        let files = compilation_file_digests(paths, digests)?;
        let inputs = inputs
            .into_iter()
            .map(|(path, tree)| Ok((path, tree.state(&mut |path| Ok(files[path].clone()))?)))
            .collect::<Result<BTreeMap<_, _>>>()?;
        Ok((
            CacheDigest::blake3(&canonical_json(&(inputs, environment))?),
            implicit_package,
        ))
    }

    /// Check the current bytes independently of any cached discovery digests.
    pub(crate) fn verify(&self) -> Result<()> {
        // Verify from disk even when the session ledger answered discovery.
        if self.digest(&NoFileDigestCache)?.0 != self.input.digest {
            if self.implicit_package {
                // The implicit tree can contain runtime state (including a
                // cache configured inside the package). Such a mutation
                // prevents publication, but does not invalidate rustc's local
                // result. Its actual dep-info inputs are checked separately.
                bail!("implicit build-script inputs changed during compilation");
            }
            return Err(
                tuist_cargo_cache_rustc::BypassReason::BuildScriptInputsChanged(
                    self.input.path.clone(),
                )
                .into(),
            );
        }
        Ok(())
    }
}

/// Keep directory membership and symlink targets in the key while resolving
/// regular-file contents in one ledger request for the entire declared tree.
enum InputTree {
    Missing,
    File(PathBuf),
    Directory(BTreeMap<String, Self>),
    Symlink { target: String, referent: Box<Self> },
}

impl InputTree {
    /// Capture an input's shape, following symlinks and preserving missing paths.
    fn read(
        path: &Path,
        mappings: &[PathMapping],
        excluded: &[PathBuf],
        compiler_directories: &[PathBuf],
        symlink_depth: usize,
    ) -> Result<Self> {
        Self::read_at(
            path,
            mappings,
            excluded,
            compiler_directories,
            symlink_depth,
            true,
        )
    }

    /// Check output overlap at each declared root and symlink referent; ordinary
    /// descendants stay within the parent already checked.
    fn read_at(
        path: &Path,
        mappings: &[PathMapping],
        excluded: &[PathBuf],
        compiler_directories: &[PathBuf],
        symlink_depth: usize,
        check_overlap: bool,
    ) -> Result<Self> {
        let metadata = match std::fs::symlink_metadata(path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Self::Missing),
            Err(error) => return Err(error.into()),
        };
        if metadata.file_type().is_symlink() {
            if symlink_depth >= 64 {
                bail!("declared build-script input contains a symlink cycle");
            }
            let target = std::fs::read_link(path)?;
            let resolved = path.parent().unwrap_or_else(|| Path::new("")).join(&target);
            return Ok(Self::Symlink {
                target: normalize_environment_value(&target.to_string_lossy(), mappings),
                referent: Box::new(Self::read(
                    &resolved,
                    mappings,
                    excluded,
                    compiler_directories,
                    symlink_depth + 1,
                )?),
            });
        }
        if check_overlap && !compiler_directories.is_empty() {
            let resolved = std::fs::canonicalize(path)?;
            if compiler_directories.iter().any(|directory| {
                resolved.starts_with(directory)
                    || (metadata.is_dir() && directory.starts_with(&resolved))
            }) {
                // Explicit watches must retain their complete meaning. Do not
                // omit target files a macro might read; run rustc uncached
                // instead of treating its own output writes as source edits.
                return Err(
                    tuist_cargo_cache_rustc::BypassReason::BuildScriptInputOverlapsOutputs(
                        path.to_path_buf(),
                    )
                    .into(),
                );
            }
        }
        if metadata.is_file() {
            return Ok(Self::File(path.to_path_buf()));
        }
        if metadata.is_dir() {
            let children = std::fs::read_dir(path)?
                .map(|entry| {
                    let entry = entry?;
                    if excluded.iter().any(|excluded| entry.path() == *excluded) {
                        return Ok(None);
                    }
                    Ok(Some((
                        entry.file_name().to_string_lossy().into_owned(),
                        // A child's ordinary path cannot reach outside its
                        // checked parent. Symlink referents are checked anew.
                        Self::read_at(
                            &entry.path(),
                            mappings,
                            excluded,
                            compiler_directories,
                            symlink_depth,
                            false,
                        )?,
                    )))
                })
                .collect::<Result<Vec<_>>>()?
                .into_iter()
                .flatten()
                .collect();
            return Ok(Self::Directory(children));
        }
        bail!(
            "declared build-script input is not a file or directory: {}",
            path.display()
        )
    }

    /// Collect regular files across declarations for one batched ledger lookup.
    fn files(&self, paths: &mut BTreeSet<PathBuf>) {
        match self {
            Self::Missing => {}
            Self::File(path) => {
                paths.insert(path.clone());
            }
            Self::Directory(children) => {
                for child in children.values() {
                    child.files(paths);
                }
            }
            Self::Symlink { referent, .. } => referent.files(paths),
        }
    }

    /// Hash the captured tree using the caller's strategy for regular files.
    fn state(
        self,
        digest_file: &mut impl FnMut(&Path) -> Result<CacheDigest>,
    ) -> Result<InputState> {
        Ok(match self {
            Self::Missing => InputState::Missing,
            Self::File(path) => InputState::File {
                digest: digest_file(&path)?,
            },
            Self::Directory(children) => InputState::Directory {
                digest: CacheDigest::blake3(&canonical_json(
                    &children
                        .into_iter()
                        .map(|(name, tree)| Ok((name, tree.state(digest_file)?)))
                        .collect::<Result<BTreeMap<_, _>>>()?,
                )?),
            },
            Self::Symlink { target, referent } => InputState::Symlink {
                target,
                referent: Box::new(referent.state(digest_file)?),
            },
        })
    }
}

/// Reuse only digests whose file identities still match; validate and publish
/// misses under the same content scope used by rustc's dep-info inputs.
fn compilation_file_digests(
    paths: BTreeSet<PathBuf>,
    digests: &dyn FileDigestCache,
) -> Result<BTreeMap<PathBuf, CacheDigest>> {
    let identified = paths
        .into_iter()
        .map(|path| {
            let identity = FileIdentity::for_digest_cache(&path, &std::fs::metadata(&path)?)?;
            Ok((path, identity))
        })
        .collect::<Result<Vec<_>>>()?;
    let queries = identified
        .iter()
        .filter_map(|(_, identity)| identity.clone())
        .collect::<Vec<_>>();
    let mut resolved = digests
        .resolve(FileDigestScope::Content, &queries)
        .into_iter();
    let mut files = BTreeMap::new();
    let mut fresh = Vec::new();
    for (path, identity) in identified {
        let cached = identity
            .as_ref()
            .and_then(|identity| match resolved.next() {
                Some(FileDigestResolution::Digest(digest))
                    if identity.len == digest.size
                        && identity.still_describes().unwrap_or(false) =>
                {
                    Some(digest)
                }
                _ => None,
            });
        let digest = if let Some(digest) = cached {
            digest
        } else if let Some(observed) = digest_file_validated(FileDigestScope::Content, &path)? {
            let digest = observed
                .resolution
                .into_digest()
                .ok_or_else(|| eyre::eyre!("content digest resolution returned no digest"))?;
            if let Some(file) = observed.cache_identity
                && file.len == digest.size
            {
                fresh.push(RecordedFileDigest {
                    file,
                    digest: digest.clone(),
                });
            }
            digest
        } else {
            digest_file(FileDigestScope::Content, &path)?
                .into_digest()
                .ok_or_else(|| eyre::eyre!("content digest resolution returned no digest"))?
        };
        files.insert(path, digest);
    }
    digests.record(FileDigestScope::Content, fresh);
    Ok(files)
}

/// Hash all files in an explicit build-script execution input without exclusions.
fn input_state(path: &Path, mappings: &[PathMapping]) -> Result<InputState> {
    input_state_at(path, mappings, &[], 0)
}

/// Hash Cargo's implicit package input while omitting package build directories.
fn package_input_state(path: &Path, mappings: &[PathMapping]) -> Result<InputState> {
    let excluded = default_package_exclusions(path)?;
    input_state_at(path, mappings, &excluded, 0)
}

/// What Cargo's package-wide default input leaves out of `package`.
fn default_package_exclusions(package: &Path) -> Result<Vec<PathBuf>> {
    let mut excluded = vec![package.join(".git"), package.join("target")];
    if let Some(target) = std::env::var_os(session::TARGET_DIR_ENV) {
        let target = std::path::absolute(target)?;
        if target.starts_with(package) {
            excluded.push(target);
        }
    }
    Ok(excluded)
}

/// Preserve the execution adapter's direct content reads using the same tree
/// representation as compilation-input discovery.
fn input_state_at(
    path: &Path,
    mappings: &[PathMapping],
    excluded: &[PathBuf],
    symlink_depth: usize,
) -> Result<InputState> {
    InputTree::read(path, mappings, excluded, &[], symlink_depth)?
        .state(&mut |path| CacheDigest::blake3_file(path))
}

/// The moment a run starts, as the file system's own clock reports it.
///
/// File times come from a clock that can lag the one `SystemTime` reads by a
/// tick or more, so comparing the two misjudges a write made in the first
/// moments of a run or an input edited just before it. A file created now
/// carries the time any write from here on will carry or exceed. The earlier of
/// that and the process clock is used, so a file system whose clock runs ahead
/// of this machine's (a network mount, say) cannot push the start past a write.
/// Falls back to the process clock when no file can be made.
fn run_start_stamp() -> SystemTime {
    let now = SystemTime::now();
    let stamp = std::env::var_os("OUT_DIR").and_then(|out_dir| {
        let path = Path::new(&out_dir).join(format!(
            ".tuist_cargo_cache-run-start-{}",
            std::process::id()
        ));
        std::fs::write(&path, b"").ok()?;
        let modified = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
        let _ = std::fs::remove_file(&path);
        modified
    });
    stamp.map_or(now, |stamp| stamp.min(now))
}

/// Whether anything a prediction declares as an input was modified at or after
/// `started`.
fn declared_inputs_changed_since(prediction: &Prediction, started: SystemTime) -> Result<bool> {
    let since = started;
    let mappings = build_script_mappings();
    let working_dir = std::env::current_dir()?;
    for declared in &prediction.inputs {
        let resolved_name =
            String::from_utf8(denormalize_output_text(declared.as_bytes(), &mappings))
                .expect("denormalizing UTF-8 paths preserves UTF-8");
        let path = working_dir.join(resolved_name);
        let excluded = if prediction.default_package {
            default_package_exclusions(&path)?
        } else {
            Vec::new()
        };
        if modified_since(&path, &excluded, since, 0)? {
            return Ok(true);
        }
    }
    Ok(false)
}

fn modified_since(
    path: &Path,
    excluded: &[PathBuf],
    since: SystemTime,
    symlink_depth: usize,
) -> Result<bool> {
    let metadata = match std::fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            // A missing input may have been there when the script started.
            // Removing it changed its parent directory.
            // Look at the nearest directory that still exists, following a
            // link: unlinking through one changes the directory it points to.
            // A link that was replaced during the run shows in its own time.
            for ancestor in path.ancestors().skip(1) {
                match std::fs::symlink_metadata(ancestor) {
                    Ok(own) => {
                        // A link whose target is gone cannot say what happened
                        // to it, so count it as a change.
                        let Ok(target) = std::fs::metadata(ancestor) else {
                            return Ok(true);
                        };
                        return Ok(own.modified()? >= since || target.modified()? >= since);
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error.into()),
                }
            }
            return Ok(false);
        }
        Err(error) => return Err(error.into()),
    };
    if metadata.modified()? >= since {
        return Ok(true);
    }
    if metadata.file_type().is_symlink() {
        if symlink_depth >= 64 {
            return Ok(false);
        }
        let target = std::fs::read_link(path)?;
        let resolved = path.parent().unwrap_or_else(|| Path::new("")).join(target);
        return modified_since(&resolved, excluded, since, symlink_depth + 1);
    }
    if metadata.is_dir() {
        for entry in std::fs::read_dir(path)? {
            let entry = entry?;
            if !excluded.iter().any(|excluded| entry.path() == *excluded)
                && modified_since(&entry.path(), excluded, since, symlink_depth)?
            {
                return Ok(true);
            }
        }
    }
    Ok(false)
}

fn out_dir_is_portable() -> Result<bool> {
    let Some(out_dir) = std::env::var_os("OUT_DIR") else {
        return Ok(false);
    };
    let needles = [
        "OUT_DIR",
        "CARGO_MANIFEST_DIR",
        session::WORKSPACE_ROOT_ENV,
        session::TARGET_DIR_ENV,
        "CARGO_HOME",
    ]
    .into_iter()
    .filter_map(std::env::var_os)
    .map(|value| value.to_string_lossy().into_owned())
    .filter(|value| !value.is_empty())
    .collect::<BTreeSet<_>>();
    let root = PathBuf::from(&out_dir);
    if !root.is_dir() {
        return Ok(true);
    }
    let mut pending = vec![root.clone()];
    while let Some(directory) = pending.pop() {
        for entry in std::fs::read_dir(directory)? {
            let entry = entry?;
            let kind = entry.file_type()?;
            if kind.is_dir() {
                pending.push(entry.path());
            } else if kind.is_symlink() {
                let target = std::fs::read_link(entry.path())?;
                if needles
                    .iter()
                    .any(|needle| target.to_string_lossy().contains(needle))
                {
                    return Ok(false);
                }
            }
        }
    }
    for path in walk_files(&root)? {
        let contents = std::fs::read(path)?;
        if needles
            .iter()
            .any(|needle| memchr::memmem::find(&contents, needle.as_bytes()).is_some())
        {
            return Ok(false);
        }
    }
    Ok(true)
}

fn walk_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut pending = vec![root.to_path_buf()];
    let mut files = Vec::new();
    while let Some(directory) = pending.pop() {
        for entry in std::fs::read_dir(directory)? {
            let entry = entry?;
            let kind = entry.file_type()?;
            if kind.is_dir() {
                pending.push(entry.path());
            } else if kind.is_file() {
                files.push(entry.path());
            }
        }
    }
    Ok(files)
}

fn publish(action: &CacheDigest, action_bytes: &[u8], stdout: &[u8], stderr: &[u8]) -> Result<()> {
    let out_dir = PathBuf::from(
        std::env::var_os("OUT_DIR").ok_or_else(|| eyre::eyre!("build script has no OUT_DIR"))?,
    );
    let staging = staging_directory()?;
    let mut blobs = Vec::new();
    let root = store_directory(&out_dir, staging.path(), &mut blobs)?;
    let mappings = build_script_mappings();
    let stdout = stage_bytes(
        staging.path(),
        "stdout",
        &normalize_output_text(stdout, &mappings),
    )?;
    let stderr = stage_bytes(
        staging.path(),
        "stderr",
        &normalize_output_text(stderr, &mappings),
    )?;
    let action_blob = stage_bytes(staging.path(), "action", action_bytes)?;
    let metadata = canonical_json(&Metadata {
        kind: ADAPTER.into(),
        version: 1,
        stdout: stdout.0.clone(),
        stderr: stderr.0.clone(),
    })?;
    let metadata = stage_bytes(staging.path(), "metadata", &metadata)?;
    blobs.extend([stdout, stderr, action_blob, metadata.clone()]);
    let mut requests = Vec::new();
    let mut seen = BTreeSet::new();
    for (digest, source) in blobs {
        if seen.insert(digest.clone()) {
            requests.push(AgentRequest::StoreBlob { digest, source });
        }
    }
    requests.push(AgentRequest::StoreActionResult {
        result: RemoteActionResult {
            action: action.clone(),
            metadata: Some(metadata.0),
            output_root: Some(root),
            version: 1,
        },
    });
    for response in session::request_agent(&requests)? {
        match response {
            AgentResponse::Stored { .. } | AgentResponse::ActionStored { .. } => {}
            AgentResponse::Error { message } => bail!(message),
            _ => bail!("cache agent returned an unexpected build-script store response"),
        }
    }
    Ok(())
}

fn stage_bytes(directory: &Path, name: &str, bytes: &[u8]) -> Result<(CacheDigest, PathBuf)> {
    let path = directory.join(name);
    std::fs::write(&path, bytes)?;
    Ok((CacheDigest::blake3(bytes), path))
}

fn store_directory(
    directory: &Path,
    staging: &Path,
    blobs: &mut Vec<(CacheDigest, PathBuf)>,
) -> Result<CacheDigest> {
    let mut directories = Vec::new();
    let mut files = Vec::new();
    let mut symlinks = Vec::new();
    let mut entries = std::fs::read_dir(directory)?.collect::<std::io::Result<Vec<_>>>()?;
    entries.sort_by_key(std::fs::DirEntry::file_name);
    for entry in entries {
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| eyre::eyre!("OUT_DIR entry name is not UTF-8"))?;
        let path = entry.path();
        let metadata = std::fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            let target = std::fs::read_link(path)?;
            if target.is_absolute()
                || target
                    .components()
                    .any(|component| matches!(component, std::path::Component::ParentDir))
            {
                bail!("OUT_DIR contains a symlink that may escape it");
            }
            symlinks.push(CacheSymlinkNode {
                name,
                mode: 0,
                target: target.to_string_lossy().into_owned(),
            });
        } else if metadata.is_dir() {
            directories.push(CacheDirectoryNode {
                name,
                mode: file_mode(&metadata),
                digest: store_directory(&path, staging, blobs)?,
            });
        } else if metadata.is_file() {
            let digest = CacheDigest::blake3_file(&path)?;
            blobs.push((digest.clone(), path));
            files.push(CacheFileNode {
                name,
                mode: file_mode(&metadata),
                executable: is_executable(&metadata),
                digest,
            });
        } else {
            bail!("OUT_DIR contains an unsupported entry");
        }
    }
    let bytes = canonical_json(&CacheDirectory {
        directories,
        files,
        symlinks,
        version: 1,
    })?;
    let name = format!("directory-{}", blobs.len());
    let staged = stage_bytes(staging, &name, &bytes)?;
    blobs.push(staged.clone());
    Ok(staged.0)
}

#[cfg(unix)]
fn is_executable(metadata: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt as _;
    metadata.permissions().mode() & 0o111 != 0
}
#[cfg(not(unix))]
fn is_executable(_: &std::fs::Metadata) -> bool {
    false
}

fn restore(action: &CacheDigest, action_bytes: &[u8]) -> Result<Option<Restored>> {
    let responses = session::request_agent(&[AgentRequest::FindActionResult {
        action: action.clone(),
    }])?;
    let result = match responses.into_iter().next() {
        Some(AgentResponse::ActionResult {
            result: Some(result),
        }) => result,
        Some(AgentResponse::ActionResult { result: None }) => return Ok(None),
        Some(AgentResponse::Error { message }) => bail!(message),
        _ => bail!("cache agent returned an unexpected build-script lookup response"),
    };
    if result.version != 1 || result.action != *action {
        bail!("cached build-script result has an invalid identity");
    }
    let metadata_digest = result
        .metadata
        .ok_or_else(|| eyre::eyre!("cached build-script result has no metadata"))?;
    let root = result
        .output_root
        .ok_or_else(|| eyre::eyre!("cached build-script result has no output tree"))?;
    let roots = find_blobs(&[action.clone(), metadata_digest.clone()])?;
    if read_verified_blob(&roots[0], action, "build-script action")? != action_bytes {
        bail!("cached build-script action descriptor differs");
    }
    let metadata: Metadata =
        read_canonical_blob(&roots[1], &metadata_digest, "build-script metadata")?;
    if metadata.version != 1 || metadata.kind != ADAPTER {
        bail!("cached build-script metadata is unsupported");
    }
    let streams = find_blobs(&[metadata.stdout.clone(), metadata.stderr.clone()])?;
    let stdout = read_verified_blob(&streams[0], &metadata.stdout, "build-script stdout")?;
    let stderr = read_verified_blob(&streams[1], &metadata.stderr, "build-script stderr")?;
    let out_dir = PathBuf::from(
        std::env::var_os("OUT_DIR").ok_or_else(|| eyre::eyre!("build script has no OUT_DIR"))?,
    );
    let mappings = build_script_mappings();
    let stdout = denormalize_output_text(&stdout, &mappings);
    // A result stored before such scripts were excluded names a link target
    // that is gone. Decline before installing its tree, so the rerun starts
    // from the OUT_DIR Cargo left rather than from stale cached files.
    if output_links_outside_out_dir(&stdout) {
        return Ok(None);
    }
    let stderr = denormalize_output_text(&stderr, &mappings);
    let parent = out_dir
        .parent()
        .ok_or_else(|| eyre::eyre!("OUT_DIR has no parent"))?;
    std::fs::create_dir_all(parent)?;
    let staged = tempfile::tempdir_in(parent)?;
    let started = Instant::now();
    let (files, bytes) = restore_directory(&root, staged.path())?;
    if out_dir.exists() {
        std::fs::remove_dir_all(&out_dir)?;
    }
    std::fs::rename(staged.path(), &out_dir)?;
    let _ = staged.keep();
    Ok(Some(Restored {
        stats: RestoreStats {
            duration_ns: started.elapsed().as_nanos().try_into().unwrap_or(u64::MAX),
            output_files: files,
            output_bytes: bytes,
            copied_output_files: files,
            copied_output_bytes: bytes,
            ..RestoreStats::default()
        },
        stdout,
        stderr,
    }))
}

/// Roots whose machine-specific spellings may appear in build-script state.
fn build_script_mappings() -> Vec<PathMapping> {
    build_script_mappings_with_env(|name| std::env::var_os(name).map(PathBuf::from))
}

/// Construct build-script mappings from an injectable environment lookup.
fn build_script_mappings_with_env(
    environment: impl Fn(&str) -> Option<PathBuf>,
) -> Vec<PathMapping> {
    let mut mappings = Vec::new();
    for (name, placeholder) in [
        ("OUT_DIR", "build_script_out_dir"),
        ("CARGO_MANIFEST_DIR", "build_script_manifest_dir"),
        (session::WORKSPACE_ROOT_ENV, "workspace"),
        (session::TARGET_DIR_ENV, "target"),
    ] {
        if let Some(root) = environment(name) {
            mappings.push(PathMapping::new(root, placeholder));
        }
    }
    let cargo_home = environment("CARGO_HOME").or_else(|| {
        ["HOME", "USERPROFILE"]
            .into_iter()
            .find_map(|name| environment(name).map(|home| home.join(".cargo")))
    });
    if let Some(cargo_home) = cargo_home {
        mappings.push(PathMapping::new(
            cargo_home.join("registry"),
            "cargo_registry",
        ));
        mappings.push(PathMapping::new(cargo_home, "cargo_home"));
    }
    mappings
}

fn normalize_environment_value(value: &str, mappings: &[PathMapping]) -> String {
    String::from_utf8(normalize_output_text(value.as_bytes(), mappings))
        .expect("normalizing UTF-8 paths preserves UTF-8")
}

/// Cargo-provided values that are implicit inputs to the build-script unit.
/// Cargo reruns the script when these change even though scripts do not emit
/// `rerun-if-env-changed` for them, so the execution key must do the same.
fn cargo_environment(mappings: &[PathMapping]) -> BTreeMap<String, Option<String>> {
    const FIXED: &[&str] = &[
        "CARGO_ENCODED_RUSTFLAGS",
        "CARGO_MANIFEST_DIR",
        "CARGO_MANIFEST_LINKS",
        "CARGO_MANIFEST_PATH",
        "DEBUG",
        "HOST",
        "NUM_JOBS",
        "OPT_LEVEL",
        "PROFILE",
        "TARGET",
    ];
    let mut names = FIXED
        .iter()
        .map(|name| (*name).to_owned())
        .collect::<BTreeSet<_>>();
    names.extend(std::env::vars().filter_map(|(name, _)| {
        ["CARGO_CFG_", "CARGO_FEATURE_", "CARGO_PKG_", "DEP_"]
            .iter()
            .any(|prefix| name.starts_with(prefix))
            .then_some(name)
    }));
    names
        .into_iter()
        .map(|name| {
            let value = std::env::var(&name)
                .ok()
                .map(|value| normalize_environment_value(&value, mappings));
            (name, value)
        })
        .collect()
}

fn restore_directory(digest: &CacheDigest, destination: &Path) -> Result<(u64, u64)> {
    let path = find_blobs(std::slice::from_ref(digest))?.remove(0);
    let directory: CacheDirectory =
        read_canonical_blob(&path, digest, "build-script output directory")?;
    if directory.version != 1 {
        bail!("cached build-script output directory is unsupported");
    }
    std::fs::create_dir_all(destination)?;
    let mut count = 0_u64;
    let mut bytes = 0_u64;
    for node in directory.files {
        validate_name(&node.name)?;
        validate_file_mode(&node, node.executable)?;
        let source = find_blobs(std::slice::from_ref(&node.digest))?.remove(0);
        let target = destination.join(&node.name);
        if std::fs::copy(&source, &target)? != node.digest.size {
            bail!("restored build-script output has the wrong size");
        }
        apply_file_mode(&target, node.mode, node.executable)?;
        count = count.saturating_add(1);
        bytes = bytes.saturating_add(node.digest.size);
    }
    for node in directory.directories {
        validate_name(&node.name)?;
        let (child_count, child_bytes) =
            restore_directory(&node.digest, &destination.join(node.name))?;
        count = count.saturating_add(child_count);
        bytes = bytes.saturating_add(child_bytes);
    }
    for node in directory.symlinks {
        validate_name(&node.name)?;
        let target = Path::new(&node.target);
        if target.is_absolute()
            || target
                .components()
                .any(|component| matches!(component, std::path::Component::ParentDir))
        {
            bail!("cached build-script output has an unsafe symlink");
        }
        restore_symlink(&node.target, &destination.join(node.name))?;
    }
    Ok((count, bytes))
}

fn validate_name(name: &str) -> Result<()> {
    if name.is_empty() || name == "." || name == ".." || Path::new(name).components().count() != 1 {
        bail!("cached build-script output has an unsafe name");
    }
    Ok(())
}

#[cfg(unix)]
fn restore_symlink(target: &str, link: &Path) -> Result<()> {
    std::os::unix::fs::symlink(target, link)?;
    Ok(())
}
#[cfg(not(unix))]
fn restore_symlink(_: &str, _: &Path) -> Result<()> {
    bail!("cached OUT_DIR symlinks are unsupported on this platform")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, SystemTime};

    #[cfg(unix)]
    #[test]
    fn build_script_shims_pin_one_binary_per_profile_in_either_layout() {
        for unit in [
            "build/fixture-0123456789abcdef/build-script-build",
            "build/fixture/0123456789abcdef/out/build_script_build",
        ] {
            let directory = tempfile::tempdir().unwrap();
            let profile = directory.path().join("target/debug");
            let executable = profile.join(unit);
            std::fs::create_dir_all(executable.parent().unwrap()).unwrap();
            std::fs::write(&executable, b"compiled build script").unwrap();

            install(&executable, &CacheDigest::blake3(b"action")).unwrap();

            assert!(
                profile
                    .join(".tuist_cargo_cache-build-script-shims")
                    .is_dir(),
                "{unit} should pin tuist_cargo_cache beside its profile"
            );
            let launcher = std::fs::read_to_string(&executable).unwrap();
            let pinned = launcher
                .split("exec \"$(dirname \"$0\")/")
                .nth(1)
                .and_then(|rest| rest.split('"').next())
                .unwrap();
            assert!(
                executable.parent().unwrap().join(pinned).is_file(),
                "{unit} launcher should reach the pinned binary"
            );
        }
    }

    #[test]
    fn build_script_shim_keeps_the_compiled_binary_mtime() {
        let directory = tempfile::tempdir().unwrap();
        let executable = directory
            .path()
            .join("target/debug/build/fixture/build-script-build");
        std::fs::create_dir_all(executable.parent().unwrap()).unwrap();
        std::fs::write(&executable, b"compiled build script").unwrap();
        let modified = SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000);
        filetime::set_file_mtime(&executable, filetime::FileTime::from_system_time(modified))
            .unwrap();

        install(&executable, &CacheDigest::blake3(b"action")).unwrap();

        assert_eq!(
            std::fs::metadata(&executable).unwrap().modified().unwrap(),
            modified
        );
        assert_eq!(
            std::fs::metadata(session::build_script_real_path(&executable))
                .unwrap()
                .modified()
                .unwrap(),
            modified
        );
    }

    #[test]
    fn directives_are_deduplicated_and_both_cargo_spellings_are_accepted() {
        let parsed = parse_prediction(b"cargo:rerun-if-changed=src/a.h\ncargo::rerun-if-changed=src/a.h\ncargo:rerun-if-env-changed=MODE\n").unwrap().unwrap();
        assert!(!parsed.default_package);
        assert_eq!(parsed.inputs, ["src/a.h"]);
        assert_eq!(parsed.environment, ["MODE"]);
        let encoded = String::from_utf8(canonical_json(&parsed).unwrap()).unwrap();
        assert_eq!(decode_prediction(&encoded).unwrap(), parsed);
    }

    #[test]
    fn packages_without_build_scripts_ignore_an_inherited_out_dir() {
        let package = tempfile::tempdir().unwrap();
        let manifest = package.path().join("Cargo.toml");
        let out_dir = package.path().join("foreign/out");
        for declaration in ["", "build = false\n"] {
            std::fs::write(
                &manifest,
                format!("[package]\nname = \"fixture\"\n{declaration}"),
            )
            .unwrap();
            assert!(
                CompilationInputs::for_package(&out_dir, package.path())
                    .unwrap()
                    .is_none()
            );
        }
        std::fs::write(
            &manifest,
            "[package]\nname = \"fixture\"\nbuild = \"builder/main.rs\"\n",
        )
        .unwrap();
        assert!(CompilationInputs::for_package(&out_dir, package.path()).is_err());
    }

    #[test]
    fn compilation_inputs_read_both_cargo_layouts_and_verify_directory_changes() {
        for output_name in ["output", "run/stdout"] {
            let package = tempfile::tempdir().unwrap();
            let out_dir = package.path().join("target/debug/build/fixture/out");
            let output = out_dir.parent().unwrap().join(output_name);
            std::fs::create_dir_all(&out_dir).unwrap();
            std::fs::create_dir_all(output.parent().unwrap()).unwrap();
            std::fs::write(&output, "cargo::rerun-if-changed=data\n").unwrap();
            let snapshot = || CompilationInputs::read(&out_dir, package.path()).unwrap();
            let missing = snapshot();
            missing.verify().unwrap();
            std::fs::create_dir(package.path().join("data")).unwrap();
            let error = missing.verify().unwrap_err();
            assert_eq!(
                error.downcast_ref::<tuist_cargo_cache_rustc::BypassReason>(),
                Some(
                    &tuist_cargo_cache_rustc::BypassReason::BuildScriptInputsChanged(
                        output.clone()
                    )
                )
            );
            assert_eq!(
                error.to_string(),
                format!(
                    "build-script inputs changed during compilation (declarations: {})",
                    output.display()
                )
            );
            let empty = snapshot();
            assert_ne!(missing.input.digest, empty.input.digest);
            std::fs::write(package.path().join("data/new.txt"), "new").unwrap();
            let populated = snapshot();
            assert_ne!(empty.input.digest, populated.input.digest);
            std::fs::write(
                &output,
                "cargo:rerun-if-changed=data\ncargo::rerun-if-changed=data\n",
            )
            .unwrap();
            assert_eq!(populated.input.digest, snapshot().input.digest);
            std::fs::write(&output, "cargo::rerun-if-changed=\n").unwrap();
            assert!(CompilationInputs::read(&out_dir, package.path()).is_err());
            std::fs::remove_file(output).unwrap();
            assert!(CompilationInputs::read(&out_dir, package.path()).is_err());
        }
    }

    #[test]
    fn compilation_inputs_bypass_watches_that_overlap_compiler_outputs() {
        let package = tempfile::tempdir().unwrap();
        let out_dir = package.path().join("artifacts/debug/build/fixture/out");
        std::fs::create_dir_all(&out_dir).unwrap();
        let output = out_dir.parent().unwrap().join("output");
        for watch in [
            ".",
            "artifacts",
            "artifacts/debug",
            "artifacts/../artifacts",
            "artifacts/debug/build/fixture/out",
        ] {
            std::fs::write(&output, format!("cargo::rerun-if-changed={watch}\n")).unwrap();
            let error = CompilationInputs::read(&out_dir, package.path())
                .err()
                .unwrap();
            assert!(
                error.to_string().contains("overlaps compiler outputs"),
                "{error:#}"
            );
        }
        #[cfg(unix)]
        {
            let data = package.path().join("data");
            std::fs::create_dir(&data).unwrap();
            std::os::unix::fs::symlink("../artifacts/debug", data.join("outputs")).unwrap();
            std::fs::write(&output, "cargo::rerun-if-changed=data\n").unwrap();
            assert!(CompilationInputs::read(&out_dir, package.path()).is_err());
        }
    }

    #[test]
    fn compilation_inputs_batch_shared_digests_and_verify_without_the_ledger() {
        use std::sync::Mutex;

        #[derive(Default)]
        struct Ledger {
            entries: Mutex<BTreeMap<FileIdentity, CacheDigest>>,
            requests: Mutex<Vec<usize>>,
            misses: Mutex<usize>,
        }
        impl FileDigestCache for Ledger {
            fn find(
                &self,
                scope: FileDigestScope,
                files: &[FileIdentity],
            ) -> Vec<Option<CacheDigest>> {
                assert_eq!(scope, FileDigestScope::Content);
                self.requests.lock().unwrap().push(files.len());
                let entries = self.entries.lock().unwrap();
                files
                    .iter()
                    .map(|file| {
                        let digest = entries.get(file).cloned();
                        if digest.is_none() {
                            *self.misses.lock().unwrap() += 1;
                        }
                        digest
                    })
                    .collect()
            }

            fn record(&self, scope: FileDigestScope, entries: Vec<RecordedFileDigest>) {
                assert_eq!(scope, FileDigestScope::Content);
                self.entries
                    .lock()
                    .unwrap()
                    .extend(entries.into_iter().map(|entry| (entry.file, entry.digest)));
            }
        }

        let package = tempfile::tempdir().unwrap();
        let out_dir = package.path().join("target/debug/build/fixture/out");
        std::fs::create_dir_all(&out_dir).unwrap();
        std::fs::write(
            out_dir.parent().unwrap().join("output"),
            "cargo::rerun-if-changed=data\n",
        )
        .unwrap();
        let data = package.path().join("data");
        std::fs::create_dir(&data).unwrap();
        std::fs::write(data.join("a.txt"), "first").unwrap();
        std::fs::write(data.join("b.txt"), "second").unwrap();
        // Digests of files written this moment are withheld from reuse.
        std::thread::sleep(std::time::Duration::from_millis(50));
        let ledger = Ledger::default();
        let first = CompilationInputs::read_with_cache(&out_dir, package.path(), &ledger).unwrap();
        let second = CompilationInputs::read_with_cache(&out_dir, package.path(), &ledger).unwrap();
        assert_eq!(first.input.digest, second.input.digest);
        assert_eq!(*ledger.requests.lock().unwrap(), [2, 2]);
        assert_eq!(
            *ledger.misses.lock().unwrap(),
            2,
            "unchanged targets reuse both content digests"
        );
        first.verify().unwrap();
        assert_eq!(
            *ledger.requests.lock().unwrap(),
            [2, 2],
            "verification must not consult the ledger"
        );
        std::fs::write(data.join("a.txt"), "other").unwrap();
        assert!(first.verify().is_err());
        let changed =
            CompilationInputs::read_with_cache(&out_dir, package.path(), &ledger).unwrap();
        assert_ne!(first.input.digest, changed.input.digest);
        assert_eq!(
            *ledger.misses.lock().unwrap(),
            3,
            "only the edited file needs a new digest"
        );
    }

    #[test]
    fn compilation_inputs_use_the_default_package_tree_without_target_outputs() {
        let package = tempfile::tempdir().unwrap();
        let out_dir = package.path().join("target/debug/build/fixture/out");
        std::fs::create_dir_all(&out_dir).unwrap();
        std::fs::write(out_dir.parent().unwrap().join("output"), "").unwrap();
        let before = CompilationInputs::read(&out_dir, package.path()).unwrap();
        std::fs::write(out_dir.join("generated.rs"), "generated").unwrap();
        before.verify().unwrap();
        std::fs::write(package.path().join("new.txt"), "source").unwrap();
        assert!(before.verify().is_err());
    }

    #[test]
    fn no_declared_inputs_use_cargos_package_default() {
        let parsed = parse_prediction(b"cargo:rustc-cfg=hello\n")
            .unwrap()
            .unwrap();
        assert!(parsed.default_package);
        assert_eq!(parsed.inputs, ["${build_script_manifest_dir}"]);
    }

    #[test]
    fn build_script_mappings_use_the_default_cargo_home() {
        let directory = tempfile::tempdir().unwrap();
        let home = directory.path().join("home");
        let mappings = build_script_mappings_with_env(|name| match name {
            "HOME" => Some(home.clone()),
            _ => None,
        });
        let registry_input = home
            .join(".cargo")
            .join("registry")
            .join("src")
            .join("index")
            .join("widget-1.0.0")
            .join("src")
            .join("lib.rs");
        let registry_key = PathBuf::from("${cargo_registry}")
            .join("src")
            .join("index")
            .join("widget-1.0.0")
            .join("src")
            .join("lib.rs");

        assert_eq!(
            normalize_environment_value(&registry_input.to_string_lossy(), &mappings),
            registry_key.to_string_lossy()
        );
        let cargo_bin = home.join(".cargo").join("bin");
        assert_eq!(
            normalize_environment_value(&cargo_bin.to_string_lossy(), &mappings),
            PathBuf::from("${cargo_home}").join("bin").to_string_lossy()
        );
    }

    #[test]
    fn version_one_predictions_remain_usable() {
        let payload =
            r#"{"environment":["MODE"],"inputs":["input.h"],"portable_out_dir":true,"version":1}"#;
        let parsed = decode_prediction(payload).unwrap();
        assert!(!parsed.default_package);
        assert_eq!(parsed.inputs, ["input.h"]);
        assert_eq!(parsed.environment, ["MODE"]);
        assert_eq!(
            prediction_payload(&parsed).unwrap(),
            payload,
            "a restored v1 prediction must remain decodable after it is recorded again"
        );
        assert!(
            decode_prediction(
                r#"{"environment":[],"inputs":["input.h"],"portable_out_dir":true,"version":2}"#
            )
            .is_err(),
            "version 2 must carry its default-package mode"
        );
    }

    #[test]
    fn cargos_package_default_excludes_generated_and_vcs_trees() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(directory.path().join("input"), "same").unwrap();
        std::fs::create_dir(directory.path().join("target")).unwrap();
        std::fs::create_dir(directory.path().join(".git")).unwrap();
        std::fs::write(directory.path().join("target/output"), "first").unwrap();
        std::fs::write(directory.path().join(".git/HEAD"), "first").unwrap();
        let first = package_input_state(directory.path(), &[]).unwrap();
        std::fs::write(directory.path().join("target/output"), "second").unwrap();
        std::fs::write(directory.path().join(".git/HEAD"), "second").unwrap();
        let second = package_input_state(directory.path(), &[]).unwrap();
        assert_eq!(first, second);
        std::fs::write(directory.path().join("input"), "changed").unwrap();
        let changed = package_input_state(directory.path(), &[]).unwrap();
        assert_ne!(second, changed);
    }

    #[test]
    fn an_empty_changed_path_bypasses_even_beside_other_inputs() {
        assert!(
            parse_prediction(
                b"cargo:rerun-if-changed=input.h\ncargo:rerun-if-changed=\ncargo:rerun-if-env-changed=MODE\n"
            )
            .unwrap()
            .is_none()
        );
    }

    #[test]
    fn an_out_dir_changed_path_bypasses_execution_caching() {
        let directory = tempfile::tempdir().unwrap();
        let out_dir = directory.path().join("target/build/package/out");
        let directive = format!("cargo:rerun-if-changed={}/shadow.rs\n", out_dir.display());
        let mappings = [PathMapping::new(&out_dir, "build_script_out_dir")];

        assert!(
            parse_prediction_with_mappings(&directive, &mappings)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn a_link_search_path_outside_out_dir_bypasses_execution_caching() {
        let directory = tempfile::tempdir().unwrap();
        let target = directory.path().join("target");
        let out_dir = target.join("debug/build/v8-abc/out");
        let mappings = [
            PathMapping::new(&out_dir, "build_script_out_dir"),
            PathMapping::new(&target, "target"),
        ];

        let outside = format!(
            "cargo:rustc-link-search={}/debug/gn_out/obj\n",
            target.display()
        );
        assert!(
            parse_prediction_with_mappings(&outside, &mappings)
                .unwrap()
                .is_none()
        );
        let outside_kind = format!(
            "cargo:rustc-link-search=native={}/debug/gn_out/obj\n",
            target.display()
        );
        assert!(
            parse_prediction_with_mappings(&outside_kind, &mappings)
                .unwrap()
                .is_none()
        );
        let lib = format!("{}/debug/gn_out/obj/lib.a", target.display());
        for directive in [
            format!("rustc-link-arg={lib}"),
            format!("rustc-link-arg-bins={lib}"),
            format!("rustc-link-arg-bin=tool={lib}"),
            format!("rustc-cdylib-link-arg={lib}"),
            format!("rustc-flags=-L {}/debug/gn_out/obj", target.display()),
            format!("rustc-link-arg={}/a.o {lib}", out_dir.display()),
        ] {
            let line = format!("cargo:{directive}\n");
            assert!(
                parse_prediction_with_mappings(&line, &mappings)
                    .unwrap()
                    .is_none(),
                "{directive} must bypass caching"
            );
        }
        let escaping = format!(
            "cargo:rustc-link-search=native={}/../native\n",
            out_dir.display()
        );
        assert!(
            parse_prediction_with_mappings(&escaping, &mappings)
                .unwrap()
                .is_none()
        );
        assert!(output_links_outside_out_dir_with(&escaping, &mappings));
        let working_dir = std::env::current_dir().unwrap();
        let relative_mappings = [
            PathMapping::new(working_dir.join("target"), "target"),
            PathMapping::new(
                working_dir.join("target/debug/build/v8-abc/out"),
                "build_script_out_dir",
            ),
        ];
        let relative = "cargo:rustc-link-search=native=target/debug/gn_out/obj\n";
        assert!(
            parse_prediction_with_mappings(relative, &relative_mappings)
                .unwrap()
                .is_none()
        );
        assert!(output_links_outside_out_dir_with(
            relative,
            &relative_mappings
        ));
        let attached = "cargo:rustc-flags=-Ltarget/debug/gn_out/obj\n";
        assert!(
            parse_prediction_with_mappings(attached, &relative_mappings)
                .unwrap()
                .is_none()
        );
        let library = "cargo:rustc-flags=-l target\n";
        assert!(
            parse_prediction_with_mappings(library, &relative_mappings)
                .unwrap()
                .is_some()
        );
        let nested = format!("cargo:rustc-link-search={}/sub/../lib\n", out_dir.display());
        assert!(
            parse_prediction_with_mappings(&nested, &mappings)
                .unwrap()
                .is_some()
        );
        let inside = format!("cargo:rustc-link-search={}/lib\n", out_dir.display());
        assert!(
            parse_prediction_with_mappings(&inside, &mappings)
                .unwrap()
                .is_some()
        );
    }

    #[test]
    fn an_input_modified_after_the_run_started_is_noticed_in_a_tree() {
        let directory = tempfile::tempdir().unwrap();
        let old = SystemTime::now() - Duration::from_secs(60);
        std::fs::create_dir(directory.path().join("sub")).unwrap();
        let file = directory.path().join("sub/input");
        std::fs::write(&file, "x").unwrap();
        for path in [&file, &directory.path().join("sub"), directory.path()] {
            filetime::set_file_mtime(path, filetime::FileTime::from_system_time(old)).unwrap();
        }
        let since = SystemTime::now() - Duration::from_secs(30);
        assert!(!modified_since(directory.path(), &[], since, 0).unwrap());
        filetime::set_file_mtime(&file, filetime::FileTime::now()).unwrap();
        assert!(modified_since(directory.path(), &[], since, 0).unwrap());
        assert!(
            !modified_since(directory.path(), &[directory.path().join("sub")], since, 0).unwrap()
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_input_includes_its_referent_contents() {
        use std::os::unix::fs::symlink;

        let directory = tempfile::tempdir().unwrap();
        let referent = directory.path().join("referent");
        let link = directory.path().join("input");
        std::fs::write(&referent, "first").unwrap();
        symlink("referent", &link).unwrap();
        let first = input_state(&link, &[]).unwrap();
        std::fs::write(referent, "second").unwrap();
        let second = input_state(&link, &[]).unwrap();
        assert_ne!(first, second);
    }

    #[cfg(unix)]
    #[test]
    fn a_missing_input_under_a_dangling_link_counts_as_changed() {
        let directory = tempfile::tempdir().unwrap();
        let link = directory.path().join("link");
        std::os::unix::fs::symlink(directory.path().join("gone"), &link).unwrap();
        let missing = link.join("flag");

        // Nothing says what became of the link's target, and that is no error.
        let since = SystemTime::now() + Duration::from_secs(3600);
        assert!(modified_since(&missing, &[], since, 0).unwrap());
    }
}
