//! Actionable explanations for conservative cache bypasses.

use crate::config::{CliSettings, Config};
use crate::events::{ActionOutcome, SessionEvent};
use eyre::{Context, Result};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::process::ExitCode;
use tuist_cargo_cache_core::ActionDiagnostic;

/// Run Cargo with a private bypass trace and explain its contents afterwards.
pub fn run(config: &Config, arguments: &[String]) -> Result<ExitCode> {
    let directory = tempfile::Builder::new()
        .prefix("tuist_cargo_cache-explain-")
        .tempdir()?;
    let log = directory.path().join("bypasses.tsv");
    let status = crate::cli::cargo_with_bypass_log(config, arguments, Some(&log))?;
    finish(&log, status)
}

pub(crate) fn run_with_settings(
    config: &Config,
    settings: &CliSettings,
    arguments: &[String],
) -> Result<ExitCode> {
    let directory = tempfile::Builder::new()
        .prefix("tuist_cargo_cache-explain-")
        .tempdir()?;
    let log = directory.path().join("bypasses.tsv");
    let status =
        crate::cli::cargo_with_settings_and_bypass_log(config, settings, arguments, Some(&log))?;
    finish(&log, status)
}

/// Replay the newest recorded build for this workspace and explain its misses
/// against the most recent earlier recording of each compilation unit.
pub(crate) fn last(config: &Config) -> Result<ExitCode> {
    let (target, baselines) = last_recorded(config)?;
    display_last(&target, &baselines);
    Ok(ExitCode::SUCCESS)
}

/// The newest recorded build for this workspace, and what earlier builds of the
/// same project recorded for comparison.
pub(crate) fn last_recorded(config: &Config) -> Result<(RecordedSession, Baselines)> {
    let workspace = crate::util::workspace_root(&std::env::current_dir()?);
    let mut sessions = recorded_sessions(&config.store_dir())?;
    let Some(target_index) = sessions
        .iter()
        .rposition(|session| session.workspace == workspace)
    else {
        eyre::bail!(
            "no recorded build was found for {}; run a build with session events enabled first",
            workspace.display()
        );
    };

    // Only earlier builds can explain this one.
    sessions.truncate(target_index + 1);
    let target = sessions.pop().expect("the target session was just found");
    let baselines = Baselines::collect(&sessions, &target);
    Ok((target, baselines))
}

pub(crate) struct RecordedSession {
    pub(crate) workspace: std::path::PathBuf,
    /// What that build called the project, when it recorded one.
    pub(crate) identity: Option<String>,
    pub(crate) command: Vec<String>,
    pub(crate) events: Vec<SessionEvent>,
}

type RecordedKeys = BTreeMap<(String, String), ActionDiagnostic>;

/// What an earlier build recorded for the same compilation unit.
///
/// Misses worth explaining are usually cross-checkout ones: the build that
/// published the key ran in another worktree, and in a cold store its
/// compilations are recorded as unconsulted rather than as hits. Restricting
/// the comparison to hits from this workspace left exactly that case with
/// nothing to compare against, which is the case `tuist_cargo_cache` exists to make rare.
///
/// This workspace still wins when it has its own recording of the unit: the
/// nearest neighbour is the better explanation when a local edit is what
/// changed the key.
///
/// Another workspace counts only when it built the same project. A unit is
/// identified by its crate name and a digest of its normalized source path and
/// unit arguments, which every package's `build_script_build` at
/// `${workspace}/build.rs` answers to -- so without this, an unrelated
/// repository could be offered as the explanation for a miss. Recordings from
/// before the identity was written carry none, and a missing identity is not a
/// match.
#[derive(Default)]
pub(crate) struct Baselines {
    here: RecordedKeys,
    elsewhere: RecordedKeys,
    /// Whether a session this drew on stopped recording before it finished.
    pub(crate) truncated: bool,
}

impl Baselines {
    pub(crate) fn collect(sessions: &[RecordedSession], target: &RecordedSession) -> Self {
        let mut baselines = Self::default();
        let mut truncated = false;
        for session in sessions {
            let recorded = if session.workspace == target.workspace {
                &mut baselines.here
            } else if session.identity.is_some() && session.identity == target.identity {
                &mut baselines.elsewhere
            } else {
                continue;
            };
            truncated |= is_truncated(session);
            for event in &session.events {
                if let SessionEvent::Action {
                    outcome,
                    crate_name: Some(crate_name),
                    diagnostic: Some(diagnostic),
                    ..
                } = event
                    && matches!(
                        outcome,
                        ActionOutcome::Hit | ActionOutcome::Miss | ActionOutcome::Unconsulted
                    )
                    && let Some(unit) = compilation_unit(diagnostic)
                {
                    recorded.insert((crate_name.clone(), unit), diagnostic.clone());
                }
            }
        }
        baselines.truncated = truncated;
        baselines
    }

    fn get(&self, key: &(String, String)) -> Option<&ActionDiagnostic> {
        self.here.get(key).or_else(|| self.elsewhere.get(key))
    }

    /// Whether the baseline for this unit comes from another checkout rather
    /// than from this workspace.
    fn is_other_checkout(&self, key: &(String, String)) -> bool {
        !self.here.contains_key(key) && self.elsewhere.contains_key(key)
    }
}

fn recorded_sessions(store: &Path) -> Result<Vec<RecordedSession>> {
    let mut sessions = Vec::new();
    for id in crate::events::session_ids(store) {
        let path = crate::events::session_paths(store, &id).events;
        let contents = match std::fs::read_to_string(&path) {
            Ok(contents) => contents,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => {
                return Err(error).wrap_err_with(|| format!("failed to read {}", path.display()));
            }
        };
        let events = crate::events::parse_events(&contents);
        let Some((recorded_workspace, command, identity)) =
            events.iter().find_map(|event| match event {
                SessionEvent::SessionStarted {
                    workspace_root,
                    command,
                    identity,
                    ..
                } => Some((workspace_root, command, identity)),
                _ => None,
            })
        else {
            continue;
        };
        sessions.push(RecordedSession {
            workspace: recorded_workspace.clone(),
            identity: identity.clone(),
            command: command.clone(),
            events,
        });
    }
    Ok(sessions)
}

/// Whether this session stopped recording rows before the build ended.
pub(crate) fn is_truncated(session: &RecordedSession) -> bool {
    session
        .events
        .iter()
        .any(|event| matches!(event, SessionEvent::Truncated { .. }))
}

fn display_last(session: &RecordedSession, baselines: &Baselines) {
    let command = if session.command.is_empty() {
        "cargo".to_string()
    } else {
        format!("cargo {}", session.command.join(" "))
    };
    let mut counts: BTreeMap<&str, u64> = BTreeMap::new();
    for event in &session.events {
        if let SessionEvent::Action { outcome, .. } = event {
            *counts.entry(outcome.label()).or_default() += 1;
        }
    }
    let summary = counts
        .iter()
        .map(|(outcome, count)| format!("{count} {outcome}"))
        .collect::<Vec<_>>()
        .join(", ");
    crate::session::note(&format!(
        "cache explanation: last recorded build\n  command: {command}\n  results: {summary}"
    ));
    // A large workspace reaches the per-session cap partway through a build,
    // and the counts above then describe the rows that fit rather than the
    // build. Saying so is the difference between a partial answer and a wrong
    // one: the totals in the build's own summary remain complete.
    if is_truncated(session) {
        crate::session::note(
            "\nthis build's recorded history stopped early: it reached the per-session size limit, so the results above and the misses below cover only the part that was recorded",
        );
        crate::session::note(
            "  raise TUIST_CARGO_CACHE_EVENTS_MAX_SIZE and build again to record all of it",
        );
    }

    let misses = session.events.iter().filter_map(|event| match event {
        SessionEvent::Action {
            outcome: ActionOutcome::Miss,
            crate_name,
            diagnostic,
            ..
        } => Some((
            crate_name.as_deref().unwrap_or("<unknown crate>"),
            diagnostic.as_ref(),
        )),
        _ => None,
    });
    let mut found = false;
    for (crate_name, diagnostic) in misses {
        if !found {
            crate::session::note("\nmissed crates");
            found = true;
        }
        crate::session::note(&format!("\n{crate_name}"));
        if diagnostic.is_some_and(|value| value.components.contains_key("path-specific C object")) {
            crate::session::note(
                "  this C object embeds absolute paths and is cached only for the same paths; a new checkout cannot reuse another checkout's entry",
            );
            crate::session::note(
                "  `tuist_cargo_cache settings set cc_store_path_specific false` (or TUIST_CARGO_CACHE_CC_STORE_PATH_SPECIFIC=0) skips storing these objects in disposable worktrees; existing entries remain readable",
            );
            continue;
        }
        let previous = previous_recording(baselines, crate_name, diagnostic);
        match (previous, diagnostic) {
            (Some(previous), Some(current)) => {
                display_diff(previous, current);
                if compilation_unit(current).is_some_and(|unit| {
                    baselines.is_other_checkout(&(crate_name.to_string(), unit))
                }) {
                    for line in checkout_hint(previous, current) {
                        crate::session::note(&line);
                    }
                }
            }
            (None, _) => crate::session::note(if baselines.truncated {
                "  no earlier build recorded key details for this crate; an earlier build stopped recording at the per-session size limit, so its details may be among the rows that were dropped"
            } else {
                "  no earlier build recorded key details for this crate; the cache may be cold, this action may use another adapter, or its history may have expired"
            }),
            (Some(_), None) => crate::session::note(
                "  key details were not recorded for this action; run another rustc compilation before comparing inputs",
            ),
        }
    }
    if !found {
        crate::session::note("\nno cache misses were recorded");
    }
}

fn compilation_unit(diagnostic: &ActionDiagnostic) -> Option<String> {
    diagnostic
        .components
        .get("compilation unit")
        .map(tuist_cargo_cache_core::CacheDigest::key)
}

pub(crate) fn previous_recording<'a>(
    baselines: &'a Baselines,
    crate_name: &str,
    diagnostic: Option<&ActionDiagnostic>,
) -> Option<&'a ActionDiagnostic> {
    let unit = diagnostic.and_then(compilation_unit)?;
    baselines.get(&(crate_name.to_string(), unit))
}

fn display_diff(previous: &ActionDiagnostic, current: &ActionDiagnostic) {
    for line in diff_lines(previous, current) {
        crate::session::note(&line);
    }
}

/// What changed between two recordings of one compilation, as a reader sees it.
///
/// Key details and inputs get a heading each, and only when something under it
/// changed. They were printed under one "inputs changed" heading, which named
/// the wrong thing for a miss caused by an argument or an environment value --
/// the two shapes this command exists to tell apart.
fn diff_lines(previous: &ActionDiagnostic, current: &ActionDiagnostic) -> Vec<String> {
    if previous.action == current.action {
        return vec![
            "  the action key did not change; its cached result was unavailable, evicted, or absent from the configured remote".into(),
        ];
    }
    let components = changed_keys(&previous.components, &current.components);
    let inputs = changed_keys(&previous.inputs, &current.inputs);
    let mut lines = Vec::new();
    // A compilation whose own key material is identical did not change; one of
    // the artifacts it consumes did, and the crate that produced that artifact
    // is where the miss actually starts. Saying so keeps a reader from hunting
    // through the arguments of a crate that is only collateral.
    let dependencies = dependencies_behind(&inputs);
    if components.is_empty() && !dependencies.is_empty() {
        let (subject, verb, next) = if dependencies.len() == 1 {
            ("the artifact of", "differs", "that crate")
        } else {
            ("the artifacts of", "differ", "those crates")
        };
        lines.push(format!(
            "  nothing in this compilation changed; it missed because {subject} {} {verb}, so explain {next} first",
            join_names(&dependencies),
        ));
    }
    if !components.is_empty() {
        lines.push("  key details changed since the last recording:".into());
        lines.extend(components.into_iter().map(|name| format!("    - {name}")));
    }
    if !inputs.is_empty() {
        lines.push("  inputs changed since the last recording:".into());
        lines.extend(inputs.into_iter().map(|path| match dependency_name(&path) {
            Some(name) => format!("    - input {path} (artifact of {name})"),
            None => format!("    - input {path}"),
        }));
    }
    // Two keys that differ with nothing recorded to show for it: the details
    // behind them were dropped or written by another version. Saying nothing at
    // all would read as though the miss had been explained.
    if lines.is_empty() {
        lines.push(
            "  the action key changed, but the recorded details do not say which part did".into(),
        );
    }
    lines
}

/// What to set when a miss is compared with another checkout's build and the
/// difference is one a setting can remove.
///
/// The comparison alone names what changed; this says which setting or
/// environment variable acts on it. It stays quiet when nothing recorded points
/// at a checkout path, since a flag or a variable that truly differs needs no
/// tuist_cargo_cache setting.
fn checkout_hint(previous: &ActionDiagnostic, current: &ActionDiagnostic) -> Vec<String> {
    let components = changed_keys(&previous.components, &current.components);
    let inputs = changed_keys(&previous.inputs, &current.inputs);
    let mut lines = Vec::new();
    let mut changed_env: Vec<&str> = Vec::new();
    let mut remap_differs = false;
    for name in &components {
        if let Some(variable) = name.strip_prefix("environment ") {
            changed_env.push(variable);
        } else if name.starts_with("argument --remap-path-prefix") {
            remap_differs = true;
        }
    }
    if changed_env.contains(&"OUT_DIR") {
        lines.push(
            "  hint: OUT_DIR differs between the checkouts; `TUIST_CARGO_CACHE_SHARE_OUT_DIR=1` (the default) gives rustc a shared build-script output directory, so check that neither checkout sets it to 0 in `.tuist_cargo_cache.toml` or the environment".into(),
        );
    }
    if changed_env.contains(&"CARGO_MANIFEST_DIR") {
        lines.push(
            "  hint: this crate reads CARGO_MANIFEST_DIR, so it is keyed to its checkout and recompiles in each one; `TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT=1` (or `share_workspace_root = true`) still lets the crates that depend on it share".into(),
        );
    }
    if remap_differs {
        lines.push(
            "  hint: --remap-path-prefix differs; if it comes from workspace-root sharing rather than a flag you pass, set `TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT` the same way in both checkouts".into(),
        );
    }
    let others: Vec<&str> = changed_env
        .into_iter()
        .filter(|name| !["OUT_DIR", "CARGO_MANIFEST_DIR"].contains(name))
        .collect();
    if !others.is_empty() {
        lines.push(format!(
            "  hint: {} differ{} between the checkouts; if a value holds a checkout path, set it the same in both or unset it",
            others.join(", "),
            if others.len() == 1 { "s" } else { "" },
        ));
    }
    if lines.is_empty() && components.is_empty() && !dependencies_behind(&inputs).is_empty() {
        lines.push(
            "  hint: if that crate is a workspace member whose source did not change, it may record its checkout path; `TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT=1` (or `share_workspace_root = true`) can make both checkouts produce the same bytes. If its source did change, inspect that crate's inputs instead".into(),
        );
    }
    lines
}

/// Render names as a reader would say them out loud.
pub(crate) fn join_names(names: &[String]) -> String {
    match names {
        [] => String::new(),
        [only] => only.clone(),
        [head @ .., last] => format!("{} and {last}", head.join(", ")),
    }
}

/// The crates whose artifacts account for every changed input, if they do.
pub(crate) fn dependencies_behind(inputs: &[String]) -> Vec<String> {
    let names: Vec<_> = inputs
        .iter()
        .filter_map(|path| dependency_name(path))
        .collect();
    if names.len() == inputs.len() {
        let mut names: Vec<_> = names
            .into_iter()
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        names.sort();
        names
    } else {
        Vec::new()
    }
}

/// The crate behind a compiler artifact path, as Cargo spells one.
///
/// Cargo names these `lib<crate>-<metadata>.rmeta` (and `.rlib`, and the
/// platform's dynamic library extension), which is enough to recover the crate
/// without consulting the dependency graph. Anything else is a source file, and
/// is left to speak for itself.
pub(crate) fn dependency_name(path: &str) -> Option<String> {
    let file = path.rsplit(['/', '\\']).next()?;
    let (stem, extension) = file.rsplit_once('.')?;
    if !matches!(extension, "rmeta" | "rlib" | "so" | "dylib" | "dll") {
        return None;
    }
    // Exactly one prefix: Cargo writes `libc` as `liblibc-<hash>.rlib`, and
    // stripping repeatedly would send a reader off to explain a crate called
    // `c`. Windows dynamic libraries carry no prefix at all.
    let stem = stem.strip_prefix("lib").unwrap_or(stem);
    let (name, metadata) = stem.rsplit_once('-')?;
    (!name.is_empty()
        && !metadata.is_empty()
        && metadata.bytes().all(|byte| byte.is_ascii_hexdigit()))
    .then(|| name.to_string())
}

pub(crate) fn changed_keys(
    previous: &BTreeMap<String, tuist_cargo_cache_core::CacheDigest>,
    current: &BTreeMap<String, tuist_cargo_cache_core::CacheDigest>,
) -> Vec<String> {
    previous
        .keys()
        .chain(current.keys())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .filter(|key| previous.get(*key) != current.get(*key))
        .cloned()
        .collect()
}

fn finish(log: &Path, status: ExitCode) -> Result<ExitCode> {
    let records = read_records(log)?;
    display(&records);
    Ok(status)
}

#[derive(Debug, Default, PartialEq, Eq)]
struct Records {
    bypasses: BTreeMap<String, BypassGroup>,
    observations: BTreeMap<String, String>,
}

#[derive(Debug, Default, PartialEq, Eq)]
struct BypassGroup {
    records: BTreeMap<(String, Option<String>), u64>,
}

impl Records {
    fn add(&mut self, kind: &str, detail: &str, remediation: Option<&str>) {
        let group = self.bypasses.entry(kind.to_string()).or_default();
        *group
            .records
            .entry((detail.to_string(), remediation.map(str::to_string)))
            .or_default() += 1;
    }

    fn total(&self) -> u64 {
        self.bypasses
            .values()
            .flat_map(|group| group.records.values())
            .copied()
            .sum()
    }
}

fn read_records(path: &Path) -> Result<Records> {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Records::default()),
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to read {}", path.display()));
        }
    };
    parse_records(&contents)
}

fn parse_records(contents: &str) -> Result<Records> {
    let mut records = Records::default();
    for (index, line) in contents.lines().enumerate() {
        let mut fields = line.splitn(3, '\t');
        let kind = fields.next().unwrap_or_default();
        let detail = fields
            .next()
            .ok_or_else(|| eyre::eyre!("invalid bypass record on line {}", index + 1))?;
        if kind == "@observation" {
            let observation = fields.next().ok_or_else(|| {
                eyre::eyre!("invalid cacheability observation on line {}", index + 1)
            })?;
            records
                .observations
                .insert(detail.to_string(), observation.to_string());
            continue;
        }
        if kind.is_empty() || detail.is_empty() {
            eyre::bail!("invalid bypass record on line {}", index + 1);
        }
        records.add(kind, detail, fields.next());
    }
    Ok(records)
}

fn display(records: &Records) {
    if records.bypasses.is_empty() {
        crate::session::note("\ncache explanation: no compilations bypassed the cache");
    } else {
        crate::session::note(&format!(
            "\ncache explanation: {} compilations bypassed the cache",
            records.total()
        ));
        for (kind, group) in &records.bypasses {
            let count: u64 = group.records.values().sum();
            crate::session::note(&format!("\n{kind} ({count})"));
            let mut sections: BTreeMap<Option<&str>, Vec<(&str, u64)>> = BTreeMap::new();
            for ((detail, remediation), occurrences) in &group.records {
                sections
                    .entry(remediation.as_deref())
                    .or_default()
                    .push((detail, *occurrences));
            }
            for (remediation, details) in sections {
                crate::session::note(remediation.unwrap_or_else(|| guidance(kind)));
                for (detail, occurrences) in details {
                    let suffix = if occurrences > 1 {
                        format!(" ({occurrences} times)")
                    } else {
                        String::new()
                    };
                    crate::session::note(&format!("  - {detail}{suffix}"));
                }
            }
        }
    }
    for observation in records.observations.values() {
        crate::session::note(&format!("\ncacheability warning\n{observation}"));
    }
}

pub(crate) fn guidance(kind: &str) -> &'static str {
    match kind {
        "compiler-query" => {
            "Expected: Cargo asks rustc for toolchain information; there is no compilation to cache."
        }
        "standard-input" => {
            "Expected for Cargo probes: source supplied on standard input cannot be rediscovered later."
        }
        "incremental" => {
            "Cargo compiled this incrementally, which tuist_cargo_cache cannot cache. `tuist_cargo_cache settings set incremental false` (or `TUIST_CARGO_CACHE_INCREMENTAL=0`) makes it cacheable again; tuist_cargo_cache already gives a crate you are editing its own incremental state without giving up the rest of the cache."
        }
        "response-file" => {
            "The invocation uses an `@response-file`; tuist_cargo_cache does not model response-file contents yet."
        }
        "unsupported-crate-type" => {
            "This linked artifact type is outside tuist_cargo_cache's current cacheability tier. Compilations that link nothing -- what `cargo check` and clippy run -- are cached whatever their crate type, and native test binaries and executables are cached where the linker can be identified. Dynamic libraries and proc macros still link normally."
        }
        "ambiguous-output-name" => {
            "This output is named like a library but is a program, so tuist_cargo_cache cannot tell which permissions to restore it with."
        }
        "unportable-native-link" => {
            "This link would embed a path, a timestamp, or a file tuist_cargo_cache does not store, so another checkout could not use its result."
        }
        "unsupported-search-path" => {
            "A native search path kind is not a precise compiler input, so tuist_cargo_cache cannot safely reuse this action."
        }
        "native-library" => {
            "This linked program or proc macro hands a native library to its linker, whose search tuist_cargo_cache does not model. A library compile that names one is cached: a bundled `-l static` archive it resolves is hashed into the key, and dylib, framework, link-arg, plain, and unbundled static flags are keyed as text."
        }
        "missing-native-library" => {
            "A `-l static` library was not found in any `-L` search directory, so there is no archive for tuist_cargo_cache to hash. Check the build script's `cargo:rustc-link-search` directive."
        }
        "custom-target-native-library" => {
            "A custom target specification chooses its own static-library file names, so tuist_cargo_cache cannot tell which archive a `-l static` flag makes rustc read."
        }
        "unknown-flag" | "unknown-codegen-option" => {
            "The toolchain passed an option this tuist_cargo_cache adapter does not model. Check for a newer tuist_cargo_cache release before reporting it."
        }
        "unmapped-absolute-path" => {
            "The invocation references an absolute path outside the workspace, target, Cargo, toolchain, and home mappings. Move it under a mapped root or keep this action uncached."
        }
        "no-dep-info" | "malformed-dep-info" => {
            "tuist_cargo_cache needs valid rustc dep-info to discover every input. Inspect the detail below for the rejected output."
        }
        "input-read" | "input-changed" | "input-modified-during-compilation" => {
            "An input was unavailable or changed while rustc ran. Stabilize generated inputs before retrying."
        }
        "cc-not-a-compile" | "cc-non-object-output" | "cc-compiler-query" => {
            "Expected: a build script asked the C compiler to link, preprocess, or describe itself, which is not a cacheable compilation."
        }
        "cc-unknown-flag" | "cc-tool-passthrough" => {
            "A build script passed a C compiler option this tuist_cargo_cache adapter does not model. Check for a newer tuist_cargo_cache release before reporting it."
        }
        "cc-unsupported-language" => {
            "tuist_cargo_cache caches C and C++ compilations; assembly, Objective-C, and precompiled headers still compile normally."
        }
        "cc-embedded-timestamp-macro" => {
            "A source or header expands `__DATE__`, `__TIME__`, or `__TIMESTAMP__`, so its object is not a function of its inputs and cannot be reused."
        }
        "cc-unsupported-environment" => {
            "An include-path or sub-tool environment variable changes the compilation in a way the argv model cannot see. Unset it to make these compilations cacheable."
        }
        "cc-search-path-modified-during-compilation" => {
            "An include directory gained or lost a header while the compiler was running, so what it read cannot be established. Avoid writing headers into a search directory during a build."
        }
        "cc-local-cpu-target" => {
            "A build script compiles for the machine's own processor (`-march=native` or similar), so the object it produces is not a function of anything the cache key names. Name the architecture explicitly to make these compilations cacheable."
        }
        "cc-unsupported-compiler-driver" => {
            "tuist_cargo_cache models gcc-style and clang-style drivers. Other compilers, including MSVC, compile normally without caching."
        }
        "cc-unmapped-absolute-path" => {
            "A build script's compilation reads a path outside the mapped and system roots, so tuist_cargo_cache cannot key it portably."
        }
        "other" => {
            "The cache adapter failed outside a recognized conservative bypass. The detail below should be included in a bug report."
        }
        _ => {
            "This action cannot be represented safely by the current cache model. The exact reason is shown below."
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn groups_repeated_details_by_stable_kind() {
        let records = parse_records(
            "unsupported-crate-type\trustc crate type is not cacheable yet: bin\n\
             unsupported-crate-type\trustc crate type is not cacheable yet: bin\n\
             compiler-query\trustc invocation is a compiler query, not a compilation\n",
        )
        .unwrap();

        assert_eq!(records.total(), 3);
        assert_eq!(
            records.bypasses["unsupported-crate-type"]
                .records
                .values()
                .sum::<u64>(),
            2
        );
        assert!(
            guidance("incremental").contains("tuist_cargo_cache settings set incremental false")
        );
        assert!(guidance("incremental").contains("TUIST_CARGO_CACHE_INCREMENTAL=0"));
    }

    /// A kind with nothing specific to say falls back to a sentence that
    /// amounts to "look at the reason below", which is what `tuist_cargo_cache explain`
    /// exists to save someone from. Every kind the adapter can report should
    /// therefore say something of its own.
    #[test]
    fn every_reported_kind_says_something_of_its_own() {
        let generic = guidance("a kind nobody wrote guidance for");
        for kind in [
            "compiler-query",
            "standard-input",
            "incremental",
            "response-file",
            "unsupported-crate-type",
            "unsupported-search-path",
            "native-library",
            "missing-native-library",
            "custom-target-native-library",
            "unportable-native-link",
            "ambiguous-output-name",
            "unknown-flag",
            "unknown-codegen-option",
            "unmapped-absolute-path",
        ] {
            assert_ne!(guidance(kind), generic, "{kind} has no guidance of its own");
        }
    }

    #[test]
    fn rejects_partial_records_instead_of_guessing() {
        let error = parse_records("missing a tab\n").unwrap_err();
        assert!(error.to_string().contains("line 1"));
    }

    #[test]
    fn reads_remediations_and_non_bypass_observations() {
        let records = parse_records(
            "unportable-native-link\tnative link is not reproducible: split-debuginfo=packed\tRemove the reported option.\n\
             @observation\tcc-compiler-override\tCC is already set, so C compiles are invisible.\n",
        )
        .unwrap();

        assert_eq!(records.total(), 1);
        assert!(
            records.bypasses["unportable-native-link"]
                .records
                .keys()
                .any(|(_, remediation)| remediation.as_deref()
                    == Some("Remove the reported option."))
        );
        assert!(records.observations["cc-compiler-override"].contains("invisible"));
    }

    #[test]
    fn one_kind_keeps_distinct_remediations_with_their_details() {
        let records = parse_records(
            "unportable-native-link\tnative link: split-debuginfo=packed\tRemove the option.\n\
             unportable-native-link\tthe linker could not be identified\tConfigure the linker.\n",
        )
        .unwrap();

        let group = &records.bypasses["unportable-native-link"];
        assert_eq!(group.records.len(), 2);
        assert!(group.records.contains_key(&(
            "native link: split-debuginfo=packed".into(),
            Some("Remove the option.".into())
        )));
        assert!(group.records.contains_key(&(
            "the linker could not be identified".into(),
            Some("Configure the linker.".into())
        )));
    }

    #[test]
    fn key_diff_names_changed_added_and_removed_inputs() {
        let digest = |text: &[u8]| tuist_cargo_cache_core::CacheDigest::blake3(text);
        let previous = BTreeMap::from([
            ("same".into(), digest(b"same")),
            ("changed".into(), digest(b"old")),
            ("removed".into(), digest(b"removed")),
        ]);
        let current = BTreeMap::from([
            ("same".into(), digest(b"same")),
            ("changed".into(), digest(b"new")),
            ("added".into(), digest(b"added")),
        ]);

        assert_eq!(
            changed_keys(&previous, &current),
            ["added", "changed", "removed"]
        );
    }

    #[test]
    fn a_dependency_artifact_names_the_crate_that_produced_it() {
        assert_eq!(
            dependency_name("${target}/debug/deps/libmanifest_dir-0b9adf9c9981063a.rmeta"),
            Some("manifest_dir".into())
        );
        assert_eq!(
            dependency_name("${target}/debug/deps/serde_derive-4c0f.so"),
            Some("serde_derive".into())
        );
        // Cargo spells crate `libc` as `liblibc-<hash>.rlib`. Stripping the
        // prefix more than once would name a crate that does not exist.
        assert_eq!(
            dependency_name("${target}/debug/deps/liblibc-9f2a.rlib"),
            Some("libc".into())
        );
        assert_eq!(
            dependency_name("${target}/debug/deps/liblibloading-9f2a.rmeta"),
            Some("libloading".into())
        );
        // Source files are not artifacts, and neither is a name with nothing
        // that looks like Cargo's metadata hash on the end.
        assert_eq!(dependency_name("${workspace}/src/lib.rs"), None);
        assert_eq!(dependency_name("${workspace}/data-file.rmeta"), None);
    }

    #[test]
    fn changed_inputs_are_only_blamed_on_dependencies_when_all_of_them_are() {
        let artifacts = [
            "${target}/debug/deps/libone-00ff.rmeta".to_string(),
            "${target}/debug/deps/libtwo-a1b2.rlib".to_string(),
        ];
        assert_eq!(dependencies_behind(&artifacts), ["one", "two"]);

        let mixed = [
            "${target}/debug/deps/libone-00ff.rmeta".to_string(),
            "${workspace}/src/lib.rs".to_string(),
        ];
        assert!(dependencies_behind(&mixed).is_empty());
    }

    fn diagnostic(
        action: &[u8],
        components: &[(&str, &[u8])],
        inputs: &[(&str, &[u8])],
    ) -> ActionDiagnostic {
        ActionDiagnostic {
            action: tuist_cargo_cache_core::CacheDigest::blake3(action),
            components: components
                .iter()
                .map(|(name, value)| {
                    (
                        (*name).into(),
                        tuist_cargo_cache_core::CacheDigest::blake3(value),
                    )
                })
                .collect(),
            inputs: inputs
                .iter()
                .map(|(path, value)| {
                    (
                        (*path).into(),
                        tuist_cargo_cache_core::CacheDigest::blake3(value),
                    )
                })
                .collect(),
        }
    }

    #[test]
    fn a_key_detail_change_is_not_reported_under_the_input_heading() {
        let previous = diagnostic(b"before", &[("environment OUT_DIR", b"old")], &[]);
        let current = diagnostic(b"after", &[("environment OUT_DIR", b"new")], &[]);

        assert_eq!(
            diff_lines(&previous, &current),
            [
                "  key details changed since the last recording:",
                "    - environment OUT_DIR",
            ]
        );
    }

    #[test]
    fn each_heading_appears_only_when_something_under_it_changed() {
        let previous = diagnostic(
            b"before",
            &[("argument --edition", b"same")],
            &[("x.rs", b"o")],
        );
        let current = diagnostic(
            b"after",
            &[("argument --edition", b"same")],
            &[("x.rs", b"n")],
        );

        let lines = diff_lines(&previous, &current);
        assert!(
            !lines.iter().any(|line| line.contains("key details")),
            "{lines:?}"
        );
        assert_eq!(
            lines.first().unwrap(),
            "  inputs changed since the last recording:"
        );
    }

    #[test]
    fn a_key_that_changed_for_no_recorded_reason_says_so() {
        // Rather than printing a heading with nothing under it, which reads as
        // though the miss had been explained.
        let previous = diagnostic(b"before", &[], &[]);
        let current = diagnostic(b"after", &[], &[]);

        assert_eq!(
            diff_lines(&previous, &current),
            ["  the action key changed, but the recorded details do not say which part did"]
        );
    }

    #[test]
    fn names_read_as_a_sentence() {
        assert_eq!(join_names(&["one".into()]), "one");
        assert_eq!(join_names(&["one".into(), "two".into()]), "one and two");
        assert_eq!(
            join_names(&["one".into(), "two".into(), "three".into()]),
            "one, two and three"
        );
    }

    fn recorded(workspace: &str, identity: Option<&str>, action: &str) -> RecordedSession {
        let diagnostic = ActionDiagnostic {
            action: tuist_cargo_cache_core::CacheDigest::blake3(action.as_bytes()),
            components: BTreeMap::from([(
                "compilation unit".into(),
                tuist_cargo_cache_core::CacheDigest::blake3(b"unit"),
            )]),
            inputs: BTreeMap::new(),
        };
        RecordedSession {
            workspace: workspace.into(),
            identity: identity.map(str::to_string),
            command: vec!["build".into()],
            events: vec![SessionEvent::Action {
                v: 1,
                ts_ms: 0,
                outcome: ActionOutcome::Unconsulted,
                crate_name: Some("build_script_build".into()),
                duration_ns: 0,
                detail: Default::default(),
                diagnostic: Some(diagnostic),
            }],
        }
    }

    #[test]
    fn checkout_hint_names_the_setting_for_a_path_difference() {
        let digest = |value: &str| tuist_cargo_cache_core::CacheDigest::blake3(value.as_bytes());
        let diagnostic = |components: &[(&str, &str)], inputs: &[(&str, &str)]| ActionDiagnostic {
            action: digest("action"),
            components: components
                .iter()
                .map(|(name, value)| (name.to_string(), digest(value)))
                .collect(),
            inputs: inputs
                .iter()
                .map(|(name, value)| (name.to_string(), digest(value)))
                .collect(),
        };
        let hint = |a: &ActionDiagnostic, b: &ActionDiagnostic| checkout_hint(a, b).join("\n");

        let a = diagnostic(&[("environment CARGO_MANIFEST_DIR", "/a")], &[]);
        let b = diagnostic(&[("environment CARGO_MANIFEST_DIR", "/b")], &[]);
        assert!(hint(&a, &b).contains("TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT=1"));

        let a = diagnostic(&[("environment OUT_DIR", "/a")], &[]);
        let b = diagnostic(&[("environment OUT_DIR", "/b")], &[]);
        assert!(hint(&a, &b).contains("TUIST_CARGO_CACHE_SHARE_OUT_DIR"));

        let a = diagnostic(&[("environment FOO", "1")], &[]);
        let b = diagnostic(&[("environment FOO", "2")], &[]);
        let text = hint(&a, &b);
        assert!(text.contains("FOO differs"), "{text}");
        assert!(!text.contains("TUIST_CARGO_CACHE_SHARE"), "{text}");

        let a = diagnostic(&[], &[("${target}/debug/deps/libdep-1.rmeta", "1")]);
        let b = diagnostic(&[], &[("${target}/debug/deps/libdep-1.rmeta", "2")]);
        assert!(hint(&a, &b).contains("workspace member"));

        let a = diagnostic(&[("argument --opt-level", "1")], &[]);
        let b = diagnostic(&[("argument --opt-level", "3")], &[]);
        assert!(hint(&a, &b).is_empty());
    }

    #[test]
    fn only_a_baseline_from_another_checkout_is_other_checkout() {
        let target = recorded("/b", Some("project"), "missed-here");
        let elsewhere = Baselines::collect(&[recorded("/a", Some("project"), "p")], &target);
        let here = Baselines::collect(&[recorded("/b", Some("project"), "p")], &target);
        let key = |b: &Baselines| {
            b.here
                .keys()
                .chain(b.elsewhere.keys())
                .next()
                .cloned()
                .unwrap()
        };
        assert!(elsewhere.is_other_checkout(&key(&elsewhere)));
        assert!(!here.is_other_checkout(&key(&here)));
    }

    #[test]
    fn a_truncated_baseline_session_is_reported_as_such() {
        // The reason a cross-checkout miss has nothing to compare against is
        // worth telling apart: a cold cache is a different problem from a
        // build whose history stopped being written partway through.
        let mut session = recorded("/a", Some("project"), "published");
        session
            .events
            .push(SessionEvent::Truncated { v: 1, ts_ms: 0 });
        let target = recorded("/b", Some("project"), "missed-here");

        assert!(Baselines::collect(&[session], &target).truncated);
        assert!(!Baselines::collect(&[recorded("/a", Some("project"), "p")], &target).truncated);
    }

    #[test]
    fn a_session_that_stopped_recording_is_detected() {
        let mut session = recorded("/a", None, "published");
        assert!(!is_truncated(&session));
        session
            .events
            .push(SessionEvent::Truncated { v: 1, ts_ms: 0 });
        assert!(is_truncated(&session));
    }

    #[test]
    fn another_checkout_of_the_same_project_is_a_baseline() {
        let target = recorded("/b", Some("project"), "missed-here");
        let baselines =
            Baselines::collect(&[recorded("/a", Some("project"), "published")], &target);

        assert_eq!(baselines.here.len(), 0);
        assert_eq!(baselines.elsewhere.len(), 1);
    }

    #[test]
    fn an_unrelated_project_is_never_a_baseline() {
        // Every package's build script is crate `build_script_build` compiled
        // from `${workspace}/build.rs`, so the unit alone cannot tell two
        // repositories apart; without the identity this pairs a miss with a
        // recording that has nothing to do with it.
        let target = recorded("/b", Some("project"), "missed-here");
        for other in [
            recorded("/elsewhere", Some("another project"), "unrelated"),
            recorded("/older", None, "recorded before identities were written"),
        ] {
            let baselines = Baselines::collect(&[other], &target);
            assert!(baselines.here.is_empty() && baselines.elsewhere.is_empty());
        }
    }

    #[test]
    fn a_session_without_an_identity_still_uses_its_own_workspace() {
        let target = recorded("/b", None, "missed-here");
        let baselines = Baselines::collect(&[recorded("/b", None, "published")], &target);

        assert_eq!(baselines.here.len(), 1);
    }

    #[test]
    fn a_baseline_from_another_checkout_is_used_when_this_one_has_none() {
        let diagnostic = |action: &str| ActionDiagnostic {
            action: tuist_cargo_cache_core::CacheDigest::blake3(action.as_bytes()),
            components: BTreeMap::from([(
                "compilation unit".into(),
                tuist_cargo_cache_core::CacheDigest::blake3(b"unit"),
            )]),
            inputs: BTreeMap::new(),
        };
        let elsewhere = diagnostic("published-in-another-worktree");
        let current = diagnostic("missed-here");
        let key = (
            "shared_name".to_string(),
            compilation_unit(&current).unwrap(),
        );
        let baselines = Baselines {
            here: RecordedKeys::new(),
            elsewhere: RecordedKeys::from([(key, elsewhere)]),
            truncated: false,
        };

        let matched = previous_recording(&baselines, "shared_name", Some(&current)).unwrap();
        assert_eq!(
            matched.action,
            tuist_cargo_cache_core::CacheDigest::blake3(b"published-in-another-worktree")
        );
    }

    #[test]
    fn this_workspace_outranks_another_checkout_as_a_baseline() {
        let diagnostic = |action: &str| ActionDiagnostic {
            action: tuist_cargo_cache_core::CacheDigest::blake3(action.as_bytes()),
            components: BTreeMap::from([(
                "compilation unit".into(),
                tuist_cargo_cache_core::CacheDigest::blake3(b"unit"),
            )]),
            inputs: BTreeMap::new(),
        };
        let current = diagnostic("missed-here");
        let key = (
            "shared_name".to_string(),
            compilation_unit(&current).unwrap(),
        );
        let baselines = Baselines {
            here: RecordedKeys::from([(key.clone(), diagnostic("here"))]),
            elsewhere: RecordedKeys::from([(key, diagnostic("elsewhere"))]),
            truncated: false,
        };

        let matched = previous_recording(&baselines, "shared_name", Some(&current)).unwrap();
        assert_eq!(
            matched.action,
            tuist_cargo_cache_core::CacheDigest::blake3(b"here")
        );
    }

    #[test]
    fn matches_history_by_compilation_unit_not_only_crate_name() {
        let diagnostic = |unit: &str, action: &str| ActionDiagnostic {
            action: tuist_cargo_cache_core::CacheDigest::blake3(action.as_bytes()),
            components: BTreeMap::from([(
                "compilation unit".into(),
                tuist_cargo_cache_core::CacheDigest::blake3(unit.as_bytes()),
            )]),
            inputs: BTreeMap::new(),
        };
        let lib = diagnostic("lib-unit", "lib-hit");
        let test = diagnostic("test-unit", "test-hit");
        let current = diagnostic("lib-unit", "lib-miss");
        let baselines = Baselines {
            here: RecordedKeys::from([
                (("shared_name".into(), compilation_unit(&lib).unwrap()), lib),
                (
                    ("shared_name".into(), compilation_unit(&test).unwrap()),
                    test,
                ),
            ]),
            elsewhere: RecordedKeys::new(),
            truncated: false,
        };

        let matched = previous_recording(&baselines, "shared_name", Some(&current)).unwrap();
        assert_eq!(
            matched.action,
            tuist_cargo_cache_core::CacheDigest::blake3(b"lib-hit")
        );
    }
}
