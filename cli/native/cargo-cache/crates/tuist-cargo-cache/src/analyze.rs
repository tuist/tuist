//! Where a recorded build's compiler time went, ranked by the cause behind it.
//!
//! `tuist_cargo_cache explain --last` walks a build's misses one crate at a time. This reads
//! the same recordings and ranks them by cost instead: every uncached
//! compilation is given one cause, and the causes are listed largest first with
//! what would remove them.
//!
//! A crate whose own key material did not change missed because an artifact it
//! consumes did. Its time is charged to the crate where that change started,
//! followed through as many dependency levels as the recordings show, because
//! that crate is the one a reader can do something about. An edit to a crate
//! with many dependents therefore reads as one large cause, which is what it
//! cost, rather than as many small misses.
//!
//! Compiler time says what a build spent, not what it waited for, because
//! compilations overlap. The [`critical_path`] section answers the second
//! question from the recorded start, end, and dependencies of each unit.

mod critical_path;

use crate::config::Config;
use crate::events::{ActionOutcome, SessionEvent};
use crate::explain::{
    Baselines, RecordedSession, changed_keys, dependencies_behind, dependency_name, guidance,
    is_truncated, join_names, previous_recording,
};
use crate::util::format_duration;
use critical_path::CriticalPath;
use eyre::Result;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write as _;
use std::process::ExitCode;
use std::time::Duration;
use tuist_cargo_cache_core::ActionDiagnostic;

/// Analyze the newest recorded build for this workspace.
pub(crate) fn run(config: &Config) -> Result<ExitCode> {
    let (target, baselines) = crate::explain::last_recorded(config)?;
    print!("{}", Analysis::of(&target, &baselines).text());
    Ok(ExitCode::SUCCESS)
}

/// Bypass kinds that describe work with nothing to cache, such as Cargo
/// asking rustc about itself. They are reported, but never as something to fix.
const EXPECTED_BYPASSES: &[&str] = &[
    "compiler-query",
    "standard-input",
    "cc-compiler-query",
    "cc-not-a-compile",
    "cc-non-object-output",
];

/// Why one compilation ran instead of being restored.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum Cause {
    /// The inputs of the named crate changed: its sources, or a dependency
    /// that is not recorded as having missed in this build.
    Changed(String),
    /// Key settings other than inputs changed.
    Settings(Setting),
    /// The key was seen before, but its result was not available.
    Unavailable,
    /// The key was seen before, but this build had no prediction naming it,
    /// so it never looked the key up.
    Unpredicted,
    /// Nothing earlier was recorded to compare this miss against.
    NoHistory,
    /// The store had no key to look up; the result was stored for next time.
    FirstBuild,
    /// tuist_cargo_cache does not cache this compilation, for the named reason.
    Bypass(String),
}

/// The part of a key that changed, when it was not an input.
///
/// Which flags or variables changed are details of the group rather than part
/// of the cause, so that one RUSTFLAGS change reads as one cause even where it
/// moved a different set of arguments in each crate.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum Setting {
    /// The compiler itself.
    Toolchain,
    /// How tuist_cargo_cache builds its keys, which changes with tuist_cargo_cache versions.
    ActionModel,
    /// Compiler arguments.
    Flags,
    /// Environment variables in the key.
    Environment,
    /// The linker identity of a native link.
    Linker,
    /// A component outside the categories above.
    Other,
}

/// What one miss says about itself before dependencies are followed.
enum Own {
    /// The cause, and what changed under it: flag or variable names.
    Cause(Cause, Vec<String>),
    /// Nothing of its own changed; these crates' artifacts did.
    Dependencies(Vec<String>),
}

/// One cause and everything charged to it.
#[derive(Debug, Default)]
struct Group {
    duration_ns: u64,
    /// Compilations that had the cause themselves, by crate.
    direct: BTreeMap<String, u64>,
    direct_count: u64,
    /// Compilations charged here because a dependency had the cause.
    dependents: BTreeMap<String, u64>,
    dependent_count: u64,
    /// How many direct compilations each changed detail appeared in.
    details: BTreeMap<String, u64>,
}

/// A recorded build, with its uncached compiler time grouped by cause.
#[derive(Debug)]
pub(crate) struct Analysis {
    command: String,
    hits: u64,
    /// Hits rebuilt to check them; restored, but not counted as hits.
    verifications: u64,
    /// Verifications whose rebuild did not match the cached result.
    divergences: u64,
    avoided_ns: u64,
    uncached_count: u64,
    uncached_ns: u64,
    groups: BTreeMap<Cause, Group>,
    critical: Option<CriticalPath>,
    truncated: bool,
    baseline_truncated: bool,
}

impl Analysis {
    pub(crate) fn of(session: &RecordedSession, baselines: &Baselines) -> Self {
        let mut hits = 0;
        let mut verifications = 0;
        let mut divergences = 0;
        let mut avoided_ns = 0u64;
        // Each uncached compilation with its crate, time, and own verdict.
        let mut records = Vec::new();
        for event in &session.events {
            let SessionEvent::Action {
                outcome,
                crate_name,
                duration_ns,
                detail,
                diagnostic,
                ..
            } = event
            else {
                continue;
            };
            let name = crate_name
                .clone()
                .unwrap_or_else(|| "<unknown crate>".into());
            let own = match outcome {
                ActionOutcome::Hit => {
                    hits += 1;
                    avoided_ns = avoided_ns.saturating_add(detail.avoided_compiler_ns);
                    continue;
                }
                // A verification rebuilds a hit on purpose; it is not a
                // cache loss.
                ActionOutcome::Verification { matched } => {
                    verifications += 1;
                    if !matched {
                        divergences += 1;
                    }
                    continue;
                }
                // No prediction named a key to look up, which is what happens
                // the first time a crate builds with a set of inputs and
                // settings. Its key can still be compared with an earlier
                // recording of the same unit, and that says what was new.
                ActionOutcome::Unconsulted => {
                    match (
                        diagnostic.as_ref(),
                        previous_recording(baselines, &name, diagnostic.as_ref()),
                    ) {
                        (Some(current), Some(previous)) if current.action == previous.action => {
                            Own::Cause(Cause::Unpredicted, Vec::new())
                        }
                        (Some(current), Some(previous)) => {
                            classify_miss(&name, Some(current), Some(previous))
                        }
                        _ => Own::Cause(Cause::FirstBuild, Vec::new()),
                    }
                }
                ActionOutcome::Bypass { reason } => {
                    Own::Cause(Cause::Bypass(reason.clone()), Vec::new())
                }
                ActionOutcome::Miss => classify_miss(
                    &name,
                    diagnostic.as_ref(),
                    previous_recording(baselines, &name, diagnostic.as_ref()),
                ),
            };
            records.push((name, *duration_ns, own));
        }

        // The first verdict recorded under a name stands for that name. Names
        // are not unique -- a crate built for the host and the target shares
        // one -- so this is the nearest the recordings come to a unit graph.
        let mut verdicts: BTreeMap<&str, &Own> = BTreeMap::new();
        let mut own_time: BTreeMap<&str, u64> = BTreeMap::new();
        for (name, duration_ns, own) in &records {
            verdicts.entry(name).or_insert(own);
            *own_time.entry(name).or_default() += duration_ns;
        }

        let mut groups: BTreeMap<Cause, Group> = BTreeMap::new();
        let mut uncached_ns = 0u64;
        let mut uncached_count = 0u64;
        for (name, duration_ns, own) in &records {
            // Work with nothing to cache still counts once it took compiler
            // time; Cargo's probes record none, and are not work.
            if *duration_ns > 0 || !matches!(own, Own::Cause(cause, _) if is_expected(cause)) {
                uncached_ns = uncached_ns.saturating_add(*duration_ns);
                uncached_count += 1;
            }
            let (cause, details) = match own {
                Own::Cause(cause, details) => (cause.clone(), Some(details)),
                Own::Dependencies(dependencies) => {
                    let mut seen = BTreeSet::from([name.as_str()]);
                    let mut roots = BTreeSet::new();
                    for dependency in dependencies {
                        collect_roots(dependency, &verdicts, &mut seen, &mut roots);
                    }
                    // Several roots are rare; the costliest is the likeliest
                    // place the change began.
                    let root = roots
                        .into_iter()
                        .max_by_key(|root| (own_time.get(root).copied().unwrap_or(0), *root))
                        .unwrap_or(name.as_str());
                    (root_cause(root, &verdicts), None)
                }
            };
            let group = groups.entry(cause).or_default();
            group.duration_ns = group.duration_ns.saturating_add(*duration_ns);
            if let Some(details) = details {
                group.direct_count += 1;
                *group.direct.entry(name.clone()).or_default() += duration_ns;
                for detail in details {
                    *group.details.entry(detail.clone()).or_default() += 1;
                }
            } else {
                group.dependent_count += 1;
                *group.dependents.entry(name.clone()).or_default() += duration_ns;
            }
        }

        Self {
            command: if session.command.is_empty() {
                "cargo".into()
            } else {
                format!("cargo {}", session.command.join(" "))
            },
            hits,
            verifications,
            divergences,
            avoided_ns,
            uncached_count,
            uncached_ns,
            groups,
            critical: CriticalPath::of(&session.events),
            truncated: is_truncated(session),
            baseline_truncated: baselines.truncated,
        }
    }

    /// The report a person reads.
    pub(crate) fn text(&self) -> String {
        let mut out = String::new();
        let _ = writeln!(out, "last recorded build: {}", self.command);
        let _ = write!(
            out,
            "compiler time: {} in {} uncached {}",
            duration(self.uncached_ns),
            self.uncached_count,
            plural(self.uncached_count, "compilation", "compilations"),
        );
        if self.hits > 0 {
            let _ = write!(
                out,
                "; {} {} avoided an estimated {}",
                self.hits,
                plural(self.hits, "hit", "hits"),
                duration(self.avoided_ns),
            );
        }
        if self.verifications > 0 {
            let _ = write!(
                out,
                "; {} {} rebuilt to verify",
                self.verifications,
                plural(self.verifications, "hit", "hits"),
            );
            if self.divergences > 0 {
                let _ = write!(out, ", {} diverged", self.divergences);
            }
        }
        out.push('\n');
        if self.truncated {
            let _ = writeln!(
                out,
                "this build reached the per-session history limit, so only part of it was recorded; raise TUIST_CARGO_CACHE_EVENTS_MAX_SIZE and build again to analyze all of it"
            );
        }

        let mut ranked: Vec<_> = self
            .groups
            .iter()
            .filter(|(cause, _)| !is_expected(cause))
            .collect();
        ranked.sort_by(|(left_cause, left), (right_cause, right)| {
            right
                .duration_ns
                .cmp(&left.duration_ns)
                .then_with(|| {
                    (right.direct_count + right.dependent_count)
                        .cmp(&(left.direct_count + left.dependent_count))
                })
                .then_with(|| left_cause.cmp(right_cause))
        });
        if self.divergences > 0 {
            let _ = writeln!(
                out,
                "\nwarning: {} verified {} did not match {} cached result: the rebuild failed or produced different output",
                self.divergences,
                plural(self.divergences, "hit", "hits"),
                plural(self.divergences, "its", "their"),
            );
            // The details were build-time warnings, which session history does
            // not keep, and which the agent stops printing past its limit.
            for line in wrap(
                "The build printed the details as warnings, which this history does not keep. Rebuilding with TUIST_CARGO_CACHE_VERIFY=1 in a fresh target directory repeats the comparison.",
                72,
            ) {
                let _ = writeln!(out, "         {line}");
            }
        }
        let restored = self.hits + self.verifications;
        if ranked.is_empty() && restored == 0 && self.uncached_count == 0 {
            let _ = writeln!(
                out,
                "\nnothing was compiled or restored; Cargo found every unit up to date"
            );
        } else if ranked.is_empty() && restored == 0 {
            let _ = writeln!(
                out,
                "\nnothing was restored; only work with nothing to cache ran"
            );
        } else if ranked.is_empty() {
            let _ = writeln!(out, "\nevery compilation that could be cached was restored");
        } else {
            let _ = writeln!(out, "\nuncached compiler time by cause");
            for (cause, group) in ranked {
                self.write_group(&mut out, cause, group);
            }
        }

        if let Some(critical) = &self.critical {
            write_critical_path(&mut out, critical);
        }

        let expected: Vec<_> = self
            .groups
            .iter()
            .filter(|(cause, _)| is_expected(cause))
            .collect();
        if !expected.is_empty() {
            let summary = expected
                .iter()
                .map(|(cause, group)| {
                    let Cause::Bypass(reason) = cause else {
                        unreachable!("only bypasses are expected");
                    };
                    format!("{reason} ({})", group.direct_count)
                })
                .collect::<Vec<_>>()
                .join(", ");
            let _ = writeln!(out, "\nexpected, nothing to cache: {summary}");
        }
        out
    }

    fn write_group(&self, out: &mut String, cause: &Cause, group: &Group) {
        let count = group.direct_count + group.dependent_count;
        let time = if group.duration_ns == 0 {
            "      -".to_string()
        } else {
            format!("{:>7}", duration(group.duration_ns))
        };
        let _ = writeln!(out, "\n{time}  {} ({count})", title(cause));
        let indent = "         ";
        if group.duration_ns == 0 {
            let _ = writeln!(
                out,
                "{indent}compiler time was not recorded for these compilations"
            );
        }
        if !group.details.is_empty() {
            let mut details: Vec<_> = group.details.iter().collect();
            details.sort_by(|left, right| right.1.cmp(left.1).then_with(|| left.0.cmp(right.0)));
            let details = details
                .into_iter()
                .map(|(detail, count)| format!("{detail} ({count})"))
                .collect::<Vec<_>>()
                .join(", ");
            let _ = writeln!(out, "{indent}changed: {details}");
        }
        if !group.direct.is_empty() {
            let _ = writeln!(out, "{indent}{}", top_crates(&group.direct));
        }
        if group.dependent_count > 0 {
            let (subject, verb) = if group.dependent_count == 1 {
                ("crate", "depends")
            } else {
                ("crates", "depend")
            };
            let _ = writeln!(
                out,
                "{indent}then {} {subject} that {verb} on it rebuilt: {}",
                group.dependent_count,
                top_crates(&group.dependents),
            );
        }
        if let Some(advice) = advice(cause, group, self.baseline_truncated) {
            for line in wrap(&advice, 72) {
                let _ = writeln!(out, "{indent}{line}");
            }
        }
    }
}

/// The chain the build waited on, with short steps folded together.
fn write_critical_path(out: &mut String, critical: &CriticalPath) {
    let micros = |us: u64| duration(us.saturating_mul(1_000));
    let share = critical
        .path_us
        .saturating_mul(100)
        .checked_div(critical.span_us)
        .unwrap_or(100);
    let _ = writeln!(
        out,
        "\ncritical path: {}, {share}% of the {} between the first unit starting and the last finishing",
        micros(critical.path_us),
        micros(critical.span_us),
    );
    // A step under one percent of the path is folded into the line after it,
    // which keeps a deep graph readable without hiding where the time went.
    let threshold = critical.path_us / 100;
    let mut folded = (0u64, 0u64);
    let flush = |out: &mut String, folded: &mut (u64, u64)| {
        if folded.0 > 0 {
            let _ = writeln!(
                out,
                "{:>7}  {} shorter {}",
                micros(folded.1),
                folded.0,
                plural(folded.0, "step", "steps"),
            );
            *folded = (0, 0);
        }
    };
    for step in &critical.steps {
        if step.span_us < threshold {
            folded.0 += 1;
            folded.1 += step.span_us;
            continue;
        }
        flush(out, &mut folded);
        let waited = if step.waited_us > 0 && step.waited_us * 10 >= step.span_us {
            format!(", {} of it waiting to start", micros(step.waited_us))
        } else {
            String::new()
        };
        let _ = writeln!(out, "{:>7}  {}{waited}", micros(step.span_us), step.label);
    }
    flush(out, &mut folded);
    let indent = "         ";
    for line in wrap(
        "The build could not finish sooner than this chain; other work overlapped with it. Shortening a step, or removing a dependency between two steps, shortens the build.",
        72,
    ) {
        let _ = writeln!(out, "{indent}{line}");
    }
    if critical.alone_us > 0 {
        let names: Vec<_> = critical
            .alone
            .iter()
            .take(3)
            .map(|(label, us)| format!("{label} {}", micros(*us)))
            .collect();
        let _ = writeln!(
            out,
            "\nonly one recorded unit running for {}: {}",
            micros(critical.alone_us),
            join_names(&names),
        );
    }
}

/// Decide what a miss says about itself.
fn classify_miss(
    name: &str,
    current: Option<&ActionDiagnostic>,
    previous: Option<&ActionDiagnostic>,
) -> Own {
    let (Some(current), Some(previous)) = (current, previous) else {
        return Own::Cause(Cause::NoHistory, Vec::new());
    };
    if previous.action == current.action {
        return Own::Cause(Cause::Unavailable, Vec::new());
    }
    let components = changed_keys(&previous.components, &current.components);
    let inputs = changed_keys(&previous.inputs, &current.inputs);
    // Cargo derives a unit's metadata hash, its file names, and its `--extern`
    // paths from its dependencies' hashes, so a dependency that changed moves
    // those arguments too. They are consequences, never the cause.
    let settings: Vec<_> = components
        .into_iter()
        .filter(|name| !follows_dependencies(name))
        .collect();
    if !settings.is_empty() {
        let (setting, details) = setting(&settings);
        return Own::Cause(Cause::Settings(setting), details);
    }
    // A crate whose own sources changed is where its change started, even
    // when a dependency changed in the same build.
    if inputs.iter().any(|path| dependency_name(path).is_none()) {
        return Own::Cause(Cause::Changed(name.to_string()), Vec::new());
    }
    let dependencies = dependencies_behind(&inputs);
    if !dependencies.is_empty() {
        return Own::Dependencies(dependencies);
    }
    Own::Cause(Cause::Settings(Setting::Other), Vec::new())
}

/// Whether a key component changes only because a dependency did.
fn follows_dependencies(component: &str) -> bool {
    [
        "argument --extern",
        "argument --L",
        "argument --C metadata",
        "argument --C extra-filename",
        "argument --codegen metadata",
        "argument --codegen extra-filename",
    ]
    .iter()
    .any(|prefix| component.starts_with(prefix))
}

/// Name the kind of setting a set of changed components belongs to, and the
/// flags or variables that changed.
fn setting(components: &[String]) -> (Setting, Vec<String>) {
    if components.iter().any(|name| name.starts_with("compiler ")) {
        return (Setting::Toolchain, Vec::new());
    }
    if components.iter().any(|name| name == "action model") {
        return (Setting::ActionModel, Vec::new());
    }
    let flags: BTreeSet<_> = components
        .iter()
        .filter(|name| !follows_dependencies(name))
        .filter_map(|name| name.strip_prefix("argument "))
        .map(|flag| {
            // Repeated flags are numbered, and a value that is its own argument
            // is named by position; neither number means anything to a reader.
            let flag = flag.split(" #").next().unwrap_or(flag);
            if flag.starts_with('#') {
                return "argument values".to_string();
            }
            for (long, short) in [("--C ", "-C "), ("--codegen ", "-C "), ("--Z ", "-Z ")] {
                if let Some(name) = flag.strip_prefix(long) {
                    return format!("{short}{name}");
                }
            }
            flag.to_string()
        })
        .collect();
    if !flags.is_empty() {
        return (Setting::Flags, flags.into_iter().collect());
    }
    let environment: Vec<_> = components
        .iter()
        .filter_map(|name| name.strip_prefix("environment "))
        .map(str::to_string)
        .collect();
    if !environment.is_empty() {
        return (Setting::Environment, environment);
    }
    if components.iter().any(|name| name.starts_with("linker ")) {
        return (Setting::Linker, Vec::new());
    }
    (Setting::Other, components.to_vec())
}

/// Follow dependency verdicts to the crates where the changes began.
fn collect_roots<'a>(
    name: &'a str,
    verdicts: &BTreeMap<&'a str, &'a Own>,
    seen: &mut BTreeSet<&'a str>,
    roots: &mut BTreeSet<&'a str>,
) {
    match verdicts.get(name) {
        // A crate reached twice, as in a diamond, was already followed; it
        // is a path to the root, never a root of its own.
        Some(Own::Dependencies(dependencies)) => {
            if seen.insert(name) {
                for dependency in dependencies {
                    collect_roots(dependency, verdicts, seen, roots);
                }
            }
        }
        _ => {
            roots.insert(name);
        }
    }
}

/// The cause a root crate stands for.
///
/// A root this build did not compile changed in an earlier build, which is
/// still a change to that crate as far as its dependents are concerned.
fn root_cause(root: &str, verdicts: &BTreeMap<&str, &Own>) -> Cause {
    match verdicts.get(root) {
        Some(Own::Cause(cause, _)) => cause.clone(),
        _ => Cause::Changed(root.to_string()),
    }
}

fn is_expected(cause: &Cause) -> bool {
    matches!(cause, Cause::Bypass(reason) if EXPECTED_BYPASSES.contains(&reason.as_str()))
}

fn title(cause: &Cause) -> String {
    match cause {
        Cause::Changed(name) => format!("inputs of {name} changed"),
        Cause::Settings(Setting::Toolchain) => "the Rust toolchain changed".into(),
        Cause::Settings(Setting::ActionModel) => "the tuist_cargo_cache key format changed".into(),
        Cause::Settings(Setting::Flags) => "compiler arguments changed".into(),
        Cause::Settings(Setting::Environment) => "environment changed".into(),
        Cause::Settings(Setting::Linker) => "the linker changed".into(),
        Cause::Settings(Setting::Other) => "other key details changed".into(),
        Cause::Unavailable => "results missing for keys built before".into(),
        Cause::Unpredicted => "keys built before, but not looked up".into(),
        Cause::NoHistory => "misses with no earlier recording".into(),
        Cause::FirstBuild => "first build of these compilations".into(),
        Cause::Bypass(reason) => format!("not cacheable: {reason}"),
    }
}

fn advice(cause: &Cause, group: &Group, baseline_truncated: bool) -> Option<String> {
    let advice = match cause {
        Cause::Changed(name) if group.dependent_count > 0 => format!(
            "Every crate that depends on {name} recompiled after it changed. Code that changes often costs less in a crate few others depend on."
        ),
        Cause::Changed(_) => return None,
        Cause::Settings(Setting::Toolchain) => "Every key includes the compiler, so a toolchain change rebuilds each crate once. A rust-toolchain.toml keeps every checkout and CI job on one toolchain.".into(),
        Cause::Settings(Setting::ActionModel) => {
            "A new tuist_cargo_cache version can change how keys are computed. This is paid once per update.".into()
        }
        Cause::Settings(Setting::Flags) => "These crates were built with different arguments than their last recording. Commands that differ in RUSTFLAGS, profile, or features keep separate cache entries, so alternating between them rebuilds each time.".into(),
        Cause::Settings(Setting::Environment) => "These variables are part of the key. A value that differs between shells, editors, and CI keeps separate cache entries.".into(),
        Cause::Settings(Setting::Linker) => {
            "A link's key includes its linker. Builds that switch linkers keep separate entries.".into()
        }
        Cause::Settings(Setting::Other) => "Run `tuist_cargo_cache explain --last` to see each crate's changed key details.".into(),
        Cause::Unavailable => "These keys were built before, but their results were no longer in the store or on the remote. `tuist_cargo_cache gc --dry-run` shows what the store budget keeps.".into(),
        Cause::NoHistory if baseline_truncated => "An earlier build stopped recording at the per-session size limit, so its details for these crates may be among the rows it dropped.".into(),
        Cause::NoHistory => "No earlier build recorded key details for these crates. The store may be new, its history may have expired, or they were built by another adapter.".into(),
        Cause::Unpredicted => "An earlier build produced these exact keys, but this build had no prediction naming them, so it did not look them up. The predictions this build recorded let the next run of the same command find them, except for crates tuist_cargo_cache is keeping private incremental state for while you edit them.".into(),
        Cause::FirstBuild => "Nothing recorded an earlier build of these crates to compare with, and there was no key to look up. The next build with the same inputs restores them, except for crates tuist_cargo_cache is keeping private incremental state for while you edit them.".into(),
        Cause::Bypass(reason) => guidance(reason).into(),
    };
    Some(advice)
}

/// The costliest crates in a group, as a reader would scan them.
fn top_crates(crates: &BTreeMap<String, u64>) -> String {
    const SHOWN: usize = 3;
    let mut ranked: Vec<_> = crates.iter().collect();
    ranked.sort_by(|left, right| right.1.cmp(left.1).then_with(|| left.0.cmp(right.0)));
    let mut names: Vec<_> = ranked
        .iter()
        .take(SHOWN)
        .map(|(name, duration_ns)| {
            if **duration_ns == 0 {
                (*name).clone()
            } else {
                format!("{name} {}", duration(**duration_ns))
            }
        })
        .collect();
    if ranked.len() > SHOWN {
        names.push(format!("{} more", ranked.len() - SHOWN));
    }
    join_names(&names)
}

fn duration(nanoseconds: u64) -> String {
    format_duration(Duration::from_nanos(nanoseconds))
}

fn plural<'a>(count: u64, one: &'a str, many: &'a str) -> &'a str {
    if count == 1 { one } else { many }
}

/// Break prose into lines no wider than `width`.
fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::new();
    for word in text.split_whitespace() {
        if !line.is_empty() && line.len() + 1 + word.len() > width {
            lines.push(std::mem::take(&mut line));
        }
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(word);
    }
    if !line.is_empty() {
        lines.push(line);
    }
    lines
}

#[cfg(test)]
#[path = "analyze_tests.rs"]
mod tests;
