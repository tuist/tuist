//! The C and C++ shim: identity, lookup, compilation, and publication.
//!
//! This mirrors [`crate::rustc`] with one structural difference. Cargo leaves a
//! dep-info file in the target directory that the rustc shim can read *before*
//! deciding what to compile, so that adapter has two ways to build a key. A C
//! compile leaves nothing behind -- the dependency list this adapter asks for
//! is its own, and publishing it would add a file the uncached build never
//! produced. So a warm lookup here is always prediction-driven: the invocation
//! fingerprint finds the inputs the last identical compile read, and those are
//! rehashed to rebuild the full key.

use crate::materialize::{
    CachedCompilation, CachedOutput, Materialization, StagedOutputs, denormalize_output_text,
    executable_mode_matches, exit_code, file_mode, find_blobs, normalize_output_text,
    persist_outputs, read_canonical_blob, read_verified_blob, record_action_hit,
    record_verification, replay_bytes, resolve_executable, stage_verified_cached_output,
    staging_directory, validate_file_mode,
};
use crate::session;
use eyre::{Context, Result, bail};
use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Output};
use std::time::{Instant, SystemTime};
use tuist_cargo_cache_cc::{
    CcAction, CcActionContext, CcBypassReason, CcCompilerFamily, CcCompilerIdentity, CcDepfile,
    CcDiscoveredInputs, CcInputPrediction, CcInvocation, CcLanguage, environment_inputs_for,
    is_system_path, manifest_snapshot,
};
use tuist_cargo_cache_core::{
    ActionPrediction, AgentRequest, AgentResponse, CacheDigest, CacheDirectory, CacheFileNode,
    CcMetadata, FileDigestScope, FileIdentity, FileSnapshot, PathMapping, RecordedFileDigest,
    RemoteActionResult, RestoreStats, canonical_json, normalize_mapped_path,
};

const ADAPTER: &str = "cc";
// Keep the extended prediction payload out of older shims' manifests and
// flights. They reject unknown fields before checking the payload version.
const PREDICTION_ADAPTER: &str = "cc-path-binding-v1";

/// Compile one C or C++ translation unit, consulting the cache around it.
///
/// An `Err` is a bypass: the caller runs the real compiler transparently. Only
/// a successful compile is ever published, so a compiler error always reaches
/// the build exactly as it would have without tuist_cargo_cache.
pub fn compile(compiler: &OsStr, arguments: &[OsString], language: CcLanguage) -> Result<ExitCode> {
    let _timing = crate::phase_timing::start("cc", None);
    let setup = crate::phase_timing::phase("key");
    let working_dir = std::env::current_dir()?;
    let mappings = path_mappings(&working_dir);
    let identity = compiler_identity(compiler, language)?;
    // Prefix maps enter the final parse so they are keyed like caller flags.
    // Named preprocessor output retains its original path spellings instead.
    let preprocessing = CcInvocation::parse_for(arguments, identity.family)?.is_preprocessing();
    let portable = if preprocessing {
        // Preprocessor output retains literal line markers and macro values;
        // its action identity includes the working directory and path roots.
        Portable {
            arguments: Vec::new(),
            values: Vec::new(),
        }
    } else {
        Portable::detect(&mappings, identity.family, &working_dir)
    };
    let arguments = portable.applied_to(arguments);
    let arguments = arguments.as_ref();
    let invocation = CcInvocation::parse_for(arguments, identity.family)?;
    // The driver honors one `-MF`, and the shim's own dependency list is the
    // one it needs; the caller's is written by the shim once the files this
    // compilation read are known.
    let compiler_arguments = invocation.compiler_arguments(arguments);
    let mut environment = environment_inputs_for(
        |name| std::env::var(name).ok(),
        invocation.sysroot(),
        identity.family,
    )?;
    if preprocessing {
        // With debug working-directory markers, GCC can honor a logical PWD
        // alias. It is output text, so it must also be part of the action key.
        environment.insert("PWD".into(), std::env::var("PWD").ok());
    }
    let mut context = CcActionContext {
        compiler: identity,
        working_dir: working_dir.clone(),
        path_mappings: mappings,
        environment,
        inputs: Vec::new(),
    };

    drop(setup);
    let invocation_digest = prediction_invocation(&invocation.invocation_digest(&context)?);
    let _verification = session::verification::select(|| Ok(invocation_digest.clone()))?;
    let verify = session::verify_requested();
    let task = prediction_task(&invocation_digest);
    let mut verification = None;
    // A prediction that no longer describes the tree -- a header it named has
    // been deleted, say -- is not an error, it is simply no longer usable. It
    // must not abort the cache path: this adapter has no second way to build a
    // key, so bypassing here would leave the compilation permanently uncached,
    // with the same stale prediction failing the same way on every later build.
    // Falling through compiles and republishes, which replaces it.
    let usable = find_prediction(&task, &invocation_digest)?.and_then(|prediction| {
        let _phase = crate::phase_timing::phase("key");
        let discovered = prediction
            .discover(
                &working_dir,
                &context.path_mappings,
                session::file_digest_cache(),
            )
            .ok()?;
        Some((prediction, discovered))
    });
    // Whether an action lookup actually ran. A cold compilation has no
    // prediction to build a key from, so nothing was ever asked of the cache --
    // which the summary and the TUI report separately from a lookup that missed.
    let mut lookup = LookupState::default();
    if let Some((prediction, discovered)) = usable {
        let mut candidate = context.clone();
        discovered.clone().apply_to(&mut candidate)?;
        let action = crate::phase_timing::measure("key", || {
            invocation.action_with_path_binding(candidate, prediction.path_specific)
        })?;
        lookup.record(&action, &invocation_digest, prediction.path_specific);
        // A restore that fails is a miss, not a bypass. Bypassing would leave
        // the compilation uncached and publish nothing, so a partial or corrupt
        // entry would fail the same way on every later build; compiling and
        // republishing is what repairs it.
        let restored = match restore_result(
            &action,
            &invocation,
            &discovered,
            !verify,
            &context.path_mappings,
            &context.working_dir,
        ) {
            Ok(restored) => restored,
            Err(error) => {
                session::report_shim_warning(&format!("cc result was not restored: {error:#}"));
                None
            }
        };
        if let Some(cached) = restored {
            record_prediction(
                &task,
                &invocation_digest,
                &action.digest,
                &prediction,
                None,
                None,
            );
            if !verify {
                write_caller_depfile(
                    &invocation,
                    discovered.files().map(|input| input.path.as_path()),
                );
                replay_bytes(&cached.stdout, &cached.stderr)?;
                record_action_hit(
                    &action.digest,
                    cached.restore,
                    &compilation_name(&invocation),
                );
                return Ok(ExitCode::SUCCESS);
            }
            verification = Some(cached);
        }
    }

    // Everything past this point would run the real compiler, so this is
    // where machine-wide coordination starts. The flight comes before the
    // permit: another build compiling this exact invocation right now is
    // waited for rather than duplicated, and the prediction a finished
    // flight left behind is one more chance to restore. Never in verify
    // mode, whose whole point is running the compiler.
    let flight = if verify {
        None
    } else {
        crate::scheduler::flight(PREDICTION_ADAPTER, &invocation_digest.hash)
    };
    if let Some(flight) = &flight
        // Only when the payload can say something this session's own lookup
        // has not already said: either we waited and it is freshly
        // published, or nothing was ever looked up and it is the first
        // prediction we have.
        && (flight.waited() || !lookup.attempted)
        && let Some(payload) = flight.inherited()
    {
        match restore_flight_prediction(
            payload,
            &invocation,
            &context,
            &task,
            &invocation_digest,
            &mut lookup,
            None,
        ) {
            Ok(Some((action, cached, discovered))) => {
                write_caller_depfile(
                    &invocation,
                    discovered.files().map(|input| input.path.as_path()),
                );
                replay_bytes(&cached.stdout, &cached.stderr)?;
                record_action_hit(&action, cached.restore, &compilation_name(&invocation));
                return Ok(ExitCode::SUCCESS);
            }
            Ok(None) => {}
            Err(error) => {
                session::report_shim_warning(&format!(
                    "a flight prediction was not restored: {error:#}"
                ));
            }
        }
    }
    let mut remote_claim = None;
    if flight.is_some() {
        match session::request_agent(&[AgentRequest::JoinActionPromise {
            adapter: PREDICTION_ADAPTER.into(),
            invocation: invocation_digest.clone(),
        }]) {
            Ok(responses) => match responses.into_iter().next() {
                Some(AgentResponse::ActionPromise {
                    claim: Some(claim),
                    prediction: None,
                }) => remote_claim = Some(claim),
                Some(AgentResponse::ActionPromise {
                    claim: None,
                    prediction: Some(prediction),
                }) if prediction.adapter == PREDICTION_ADAPTER
                    && prediction.invocation == invocation_digest =>
                {
                    match restore_flight_prediction(
                        &prediction.payload,
                        &invocation,
                        &context,
                        &task,
                        &invocation_digest,
                        &mut lookup,
                        Some(&prediction.action),
                    ) {
                        Ok(Some((action, cached, discovered))) => {
                            // Mirror the successful fleet handoff locally:
                            // the remote promise is ephemeral, while this
                            // record survives for the next local flight.
                            if let Some(flight) = &flight {
                                flight.leave(&prediction.payload);
                            }
                            write_caller_depfile(
                                &invocation,
                                discovered.files().map(|input| input.path.as_path()),
                            );
                            replay_bytes(&cached.stdout, &cached.stderr)?;
                            record_action_hit(
                                &action,
                                cached.restore,
                                &compilation_name(&invocation),
                            );
                            return Ok(ExitCode::SUCCESS);
                        }
                        Ok(None) => {}
                        Err(error) => session::report_shim_warning(&format!(
                            "a remote flight prediction was not restored: {error:#}"
                        )),
                    }
                }
                Some(AgentResponse::ActionPromise { .. }) => {}
                Some(AgentResponse::Error { message }) => session::report_shim_warning(&format!(
                    "remote flight coordination failed: {message}"
                )),
                _ => {}
            },
            Err(error) => session::report_shim_warning(&format!(
                "remote flight coordination failed: {error:#}"
            )),
        }
    }
    // Recorded here rather than where the prediction came up empty, because
    // a flight can still turn such a compilation into a real lookup.
    if !lookup.attempted {
        session::record_unconsulted();
    }

    let depfile_staging = staging_directory()?;
    let depfile = depfile_staging.path().join("compile.d");
    // Taken before the compiler runs: the manifest that lands in the key is
    // computed afterwards, and comparing the two is what stops a header that
    // appeared mid-compile from being recorded as one the compiler had seen.
    let searchable = searchable_directories(&invocation, &working_dir);
    let before = crate::phase_timing::measure("include_scan", || manifest_snapshot(&searchable));
    // The machine-wide permit is taken after every chance to hit the cache,
    // and the timer starts afterwards: time spent waiting for the machine is
    // not time this compilation cost.
    let required_inputs = invocation
        .required_inputs()
        .iter()
        .map(|path| absolute(path, &working_dir))
        .collect::<Vec<_>>();
    let input_snapshots =
        crate::util::snapshot_compiler_inputs(required_inputs.iter().map(PathBuf::as_path), None);
    let demand = crate::scheduler::Demand::new(&compilation_name(&invocation), false);
    let permit = crate::scheduler::pool().and_then(|pool| pool.admit(&demand));
    let started = Instant::now();
    let compilation_started = SystemTime::now();
    let mut command = Command::new(compiler);
    command.args(&compiler_arguments);
    command.args(invocation.dependency_arguments_for(&depfile, context.compiler.family));
    // An earlier hit may have linked this object to the store's read-only
    // copy of it, which the compiler cannot write over.
    let object = invocation.output_in(&working_dir);
    crate::materialize::clear_linked_outputs(std::iter::once(object.as_path()));
    let output = crate::phase_timing::measure("compiler", || {
        crate::supervision::output(&mut command, true)
    })
    .wrap_err_with(|| format!("failed to run {}", Path::new(compiler).display()))?;
    drop(permit);
    crate::scheduler::record_compiler_memory(&demand, &output.status);
    if verification.is_none() {
        session::check_low_disk_after_compile();
    }
    let duration_ns = duration_ns(started.elapsed());
    session::record_compiler_invocation_with_diagnostic(
        if verification.is_some() {
            "verification"
        } else if lookup.attempted {
            "miss"
        } else {
            "unconsulted"
        },
        Some(&compilation_name(&invocation)),
        duration_ns,
        lookup.diagnostic,
    );

    let verified = verification.is_some();
    if let Some(cached) = verification {
        let divergence = verification_divergence(&cached, &output);
        record_verification(divergence.is_none(), cached.restore);
        if let Some(divergence) = divergence {
            session::report_shim_warning(&crate::materialize::verification_warning(
                "cc",
                &compilation_name(&invocation),
                &cached.action,
                &divergence,
            ));
        }
    }

    replay_bytes(&output.stdout, &output.stderr)?;
    if !output.status.success() {
        return Ok(exit_code(output.status));
    }
    // Shadow verification audits an existing result; it must not try to
    // replace it with the fresh result, especially when they differ.
    // A failure to publish must not fail a compilation that already succeeded.
    if !verified
        && let Err(error) = publish(
            &invocation,
            &mut context,
            &depfile,
            &output,
            compilation_started,
            &input_snapshots,
            &task,
            &invocation_digest,
            duration_ns,
            &searchable,
            before,
            flight.as_ref(),
            remote_claim.as_deref(),
            &portable,
        )
    {
        session::report_cc_publication_failure(&compilation_name(&invocation), &error);
    }
    // Owed whether or not the object was published: the build that asked for
    // the list reads it next. Written after publication, because the list
    // may land in a directory the compilation searched for headers, and a
    // file appearing there between the two manifest snapshots would read as
    // a header that appeared mid-compile.
    if invocation.caller_depfile().is_some() {
        match tuist_cargo_cache_cc::CcDepfile::read_for(&depfile, context.compiler.family) {
            Ok(listed) => {
                write_caller_depfile(&invocation, listed.files.iter().map(PathBuf::as_path))
            }
            Err(error) => session::report_shim_warning(&format!(
                "the caller's dependency list was not written: {error}"
            )),
        }
    }
    Ok(exit_code(output.status))
}

/// Digest the inputs the compiler reported, build the key, and store the
/// object under it.
#[allow(clippy::too_many_arguments)]
fn publish(
    invocation: &CcInvocation,
    context: &mut CcActionContext,
    depfile: &Path,
    output: &Output,
    compilation_started: SystemTime,
    input_snapshots: &std::io::Result<BTreeMap<PathBuf, FileSnapshot>>,
    task: &str,
    invocation_digest: &CacheDigest,
    duration_ns: u64,
    searchable: &BTreeSet<PathBuf>,
    before: Result<BTreeMap<PathBuf, CacheDigest>, CcBypassReason>,
    flight: Option<&crate::scheduler::Flight>,
    remote_claim: Option<&str>,
    portable: &Portable,
) -> Result<()> {
    let _phase = crate::phase_timing::phase("store");
    let input_snapshots = input_snapshots
        .as_ref()
        .map_err(|error| eyre::eyre!(error.to_string()))?;
    let discovered = discover(invocation, context, depfile)?;
    discovered.verify_not_modified_since_with_snapshots(compilation_started, input_snapshots)?;
    verify_search_path_unchanged(searchable, before)?;
    discovered.verify()?;
    discovered.clone().apply_to(context)?;
    // Debug remapping does not change runtime strings such as __FILE__. If
    // an object retains a path, bind its action to the literal paths instead
    // of discarding it or restoring another checkout's runtime strings.
    // Addressed absolutely from here on: `-o` may be relative to the compiler's
    // working directory, and the cache agent that stores the object does not
    // share it. OpenSSL's makefiles compile every object that way.
    let object = invocation.output_in(&context.working_dir);
    let mut prediction = invocation.prediction(context, duration_ns)?;
    prediction.path_specific = !portable.outputs_are_clean(&object, &context.path_mappings);
    if prediction.path_specific
        && std::env::var_os("TUIST_CARGO_CACHE_CC_STORE_PATH_SPECIFIC")
            .is_some_and(|value| value == "0" || value.is_empty())
    {
        return Err(CcBypassReason::PathSpecificStorageDisabled.into());
    }
    let action = invocation.action_with_path_binding(context.clone(), prediction.path_specific)?;
    if let Err(error) = publish_result(&action, &object, output, &context.path_mappings) {
        // GCC can name a random assembler tempfile in stderr. An immutable
        // result may already exist even though this task has no prediction.
        // Validate it without replacing this compile's output, and only reuse
        // its prediction when stdout and the object (including mode) agree.
        let existing = restore_result(
            &action,
            invocation,
            &discovered,
            false,
            &context.path_mappings,
            &context.working_dir,
        );
        if !matches!(existing, Ok(Some(ref cached)) if publication_outputs_match(cached, output)) {
            return Err(error);
        }
    }
    record_prediction(
        task,
        invocation_digest,
        &action.digest,
        &prediction,
        flight,
        remote_claim,
    );
    Ok(())
}

/// The last actual lookup, including one supplied by a local or remote flight.
#[derive(Default)]
struct LookupState {
    attempted: bool,
    diagnostic: Option<tuist_cargo_cache_core::ActionDiagnostic>,
}

impl LookupState {
    fn record(&mut self, action: &CcAction, invocation: &CacheDigest, path_specific: bool) {
        self.attempted = true;
        self.diagnostic = path_specific.then(|| tuist_cargo_cache_core::ActionDiagnostic {
            action: action.digest.clone(),
            components: BTreeMap::from([
                ("compilation unit".into(), invocation.clone()),
                (
                    "path-specific C object".into(),
                    CacheDigest::blake3(b"path-specific"),
                ),
            ]),
            inputs: Default::default(),
        });
    }
}

/// Restore through the prediction a flight left behind.
///
/// The payload gets exactly the treatment a manifest prediction does -- its
/// inputs rehashed, the key rebuilt, the store consulted -- so the worst a
/// stale or foreign record can do is miss. A restore that works is recorded
/// into this session's own manifest, which is how the next build finds it
/// without a flight.
fn restore_flight_prediction(
    payload: &str,
    invocation: &CcInvocation,
    context: &CcActionContext,
    task: &str,
    invocation_digest: &CacheDigest,
    lookup: &mut LookupState,
    recorded_action: Option<&CacheDigest>,
) -> Result<Option<(CacheDigest, CachedCompilation, CcDiscoveredInputs)>> {
    let _phase = crate::phase_timing::phase("key");
    let prediction: CcInputPrediction = serde_json::from_str(payload)?;
    let discovered = prediction.discover(
        &context.working_dir,
        &context.path_mappings,
        session::file_digest_cache(),
    )?;
    let mut candidate = context.clone();
    discovered.clone().apply_to(&mut candidate)?;
    let action = crate::phase_timing::measure("key", || {
        invocation.action_with_path_binding(candidate, prediction.path_specific)
    })?;
    if recorded_action.is_some_and(|recorded| recorded != &action.digest) {
        bail!("the action promise no longer matches its predicted inputs");
    }
    lookup.record(&action, invocation_digest, prediction.path_specific);
    let restored = restore_result(
        &action,
        invocation,
        &discovered,
        true,
        &context.path_mappings,
        &context.working_dir,
    )?;
    let Some(cached) = restored else {
        return Ok(None);
    };
    record_prediction(
        task,
        invocation_digest,
        &action.digest,
        &prediction,
        None,
        None,
    );
    Ok(Some((action.digest, cached, discovered)))
}

/// Write the dependency list the caller asked the driver for, from the files
/// this compilation is known to have read.
///
/// Best-effort: the object is already in place, and a build whose list is
/// missing rebuilds that object at worst. For `-MMD` the system headers are
/// left out the way the driver would leave them out; a header the shim cannot
/// tell is a system one stays in, which only makes the list more cautious.
fn write_caller_depfile<'a>(invocation: &CcInvocation, files: impl Iterator<Item = &'a Path>) {
    let Some(caller) = invocation.caller_depfile() else {
        return;
    };
    let files = files
        .filter(|path| !caller.user_headers_only || !tuist_cargo_cache_cc::is_system_path(path))
        .map(Path::to_path_buf)
        .collect::<Vec<_>>();
    let rendered = tuist_cargo_cache_cc::CcDepfile::render(
        &caller.targets,
        &files,
        invocation.source(),
        caller.phony_targets,
    );
    let written = (|| {
        if let Some(parent) = caller
            .path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&caller.path, rendered)
    })();
    if let Err(error) = written {
        session::report_shim_warning(&format!(
            "the caller's dependency list {} was not written: {error}",
            caller.path.display()
        ));
    }
}

/// The environment values whose absolute paths a compilation is made
/// independent of, and the check that says it really was.
///
/// This is the C and C++ half of what [`crate::rustc::Portable`] does, and it
/// exists for the same reason. `OUT_DIR` differs per checkout and per target
/// directory, a build script that generates headers there passes it as an
/// include directory, and the compiler records that directory in the debug
/// information of every object it produces. The key already normalizes those
/// paths, so without this the cache serves an object naming a directory it
/// was not built in -- equivalent, but not the artifact this compilation
/// would have written, and every qualification run says so once per object.
///
/// Two things must hold, exactly as they must for rustc.
/// `-fdebug-prefix-map` makes the compiler record the placeholder instead of
/// the real path, covering the debug information it writes itself. It does
/// not cover a path the source keeps as a string, so the object is read
/// before publishing and a compilation whose output still carries the value
/// is not published at all.
///
/// `-fdebug-prefix-map` rather than `-ffile-prefix-map`: the latter also
/// rewrites `__FILE__`, which a C program can print or assert on, and
/// changing what a program says at runtime is not this cache's business.
struct Portable {
    /// Flags appended to the real compiler invocation, one per value.
    arguments: Vec<OsString>,
    /// The literal values, for the check before publishing.
    values: Vec<String>,
}

impl Portable {
    /// Normalize debug paths for the working directory and shared build outputs.
    fn detect(mappings: &[PathMapping], family: CcCompilerFamily, working_dir: &Path) -> Self {
        // Debug information records the compiler's working directory even
        // when every source argument is relative. Normalize it as well as
        // OUT_DIR so equivalent checkouts produce identical debug objects.
        // Clang honors the logical PWD (e.g. /var on macOS), while Rust's
        // current_dir reports /private/var. Map both spellings only when they
        // identify the same directory.
        let physical_dir =
            std::fs::canonicalize(working_dir).unwrap_or_else(|_| working_dir.to_path_buf());
        let logical_dir = std::env::var("PWD").ok().filter(|value| {
            Path::new(value).is_absolute()
                && std::fs::canonicalize(value).is_ok_and(|path| path == physical_dir)
        });
        // This working-directory remap is for GCC/Clang debug objects. MSVC
        // ignores /pathmap without /experimental:deterministic; preserve its
        // existing compilation mode rather than injecting an ignored map.
        let values = working_dir
            .to_str()
            .map(str::to_owned)
            .into_iter()
            .chain(logical_dir)
            .filter(|_| !family.is_msvc())
            .chain(
                PORTABLE_ENVIRONMENT
                    .iter()
                    .filter(|_| session::share_out_dir_requested())
                    .filter_map(|name| std::env::var(name).ok()),
            );
        Self::from_values(mappings, family, values)
    }

    /// Map each spelling once, retaining distinct aliases needed by the compiler.
    fn from_values(
        mappings: &[PathMapping],
        family: CcCompilerFamily,
        values: impl IntoIterator<Item = String>,
    ) -> Self {
        let mut portable = Self {
            arguments: Vec::new(),
            values: Vec::new(),
        };
        let mut seen = BTreeSet::new();
        for value in values
            .into_iter()
            .filter(|value| Path::new(value).is_absolute())
        {
            if !seen.insert(value.clone()) {
                continue;
            }
            // Resolve aliases for mapping without changing the spelling the
            // compiler's debug information needs to replace.
            let canonical = std::fs::canonicalize(&value).unwrap_or_else(|_| PathBuf::from(&value));
            let Ok(placeholder) =
                normalize_mapped_path(Path::new(&value), Path::new("/"), mappings)
                    .or_else(|_| normalize_mapped_path(&canonical, Path::new("/"), mappings))
            else {
                continue;
            };
            let mut flag = OsString::from(if family.is_msvc() {
                "/pathmap:"
            } else {
                "-fdebug-prefix-map="
            });
            flag.push(&value);
            flag.push("=");
            flag.push(&placeholder);
            portable.arguments.push(flag);
            portable.values.push(value);
        }
        portable
    }

    fn applied_to<'a>(&self, arguments: &'a [OsString]) -> Cow<'a, [OsString]> {
        if self.arguments.is_empty() {
            return Cow::Borrowed(arguments);
        }
        let mut applied = arguments.to_vec();
        applied.extend(self.arguments.iter().cloned());
        Cow::Owned(applied)
    }

    /// Whether an output is free of every value the flags normalized away.
    fn outputs_are_clean(&self, path: &Path, mappings: &[PathMapping]) -> bool {
        // Keys normalize every mapped root, even when no debug-prefix flag
        // was injected for it (for example a generated source under target).
        // Check both logical and canonical spellings, as the key builder does.
        let values = self
            .values
            .iter()
            .cloned()
            .chain(mappings.iter().flat_map(|mapping| {
                [
                    Some(mapping.root.clone()),
                    std::fs::canonicalize(&mapping.root).ok(),
                ]
                .into_iter()
                .flatten()
                .flat_map(mapping_root_spellings)
            }))
            .collect::<BTreeSet<_>>();
        if values.is_empty() {
            return true;
        }
        let Ok(contents) = std::fs::read(path) else {
            // Unreadable is not evidence of cleanliness.
            return false;
        };
        !values.iter().any(|value| {
            let slashes = value.replace('\\', "/");
            // Windows canonicalization returns verbatim paths, while compiler
            // strings usually use ordinary drive or UNC spellings.
            let plain = if let Some(unc) = slashes.strip_prefix("//?/UNC/") {
                format!("//{unc}")
            } else {
                slashes.strip_prefix("//?/").unwrap_or(&slashes).to_owned()
            };
            [value.as_str(), &slashes, &plain, &plain.replace('/', "\\")]
                .iter()
                .any(|spelling| memchr::memmem::find(&contents, spelling.as_bytes()).is_some())
        })
    }
}

/// Include the logical spellings of macOS's system directory aliases only
/// when they resolve to the same root. Canonicalization alone loses them.
fn mapping_root_spellings(path: PathBuf) -> Vec<String> {
    let mut spellings = Vec::new();
    if let Some(value) = path.to_str() {
        spellings.push(value.to_owned());
    }
    #[cfg(target_os = "macos")]
    if let Ok(relative) = path.strip_prefix("/private") {
        let logical = Path::new("/").join(relative);
        if let (Ok(physical), Ok(alias)) = (
            std::fs::canonicalize(&path),
            std::fs::canonicalize(&logical),
        ) && physical == alias
            && let Some(value) = logical.to_str()
        {
            spellings.push(value.to_owned());
        }
    }
    spellings
}

/// The environment values a C or C++ compilation may be made independent of.
///
/// `OUT_DIR` alone, for the same reason the rustc adapter names only that one:
/// it is what a build script hands its own compilations, and what differs
/// between two checkouts and two target directories.
const PORTABLE_ENVIRONMENT: &[&str] = &["OUT_DIR"];

/// Read the dependency list and turn it into digested inputs.
fn discover(
    invocation: &CcInvocation,
    context: &CcActionContext,
    depfile: &Path,
) -> Result<CcDiscoveredInputs> {
    let dependencies = CcDepfile::read_for(depfile, context.compiler.family)?;
    let mut files = BTreeSet::new();
    for path in dependencies
        .files
        .into_iter()
        .chain(invocation.required_inputs().iter().map(ToOwned::to_owned))
    {
        files.insert(absolute(&path, &context.working_dir));
    }
    invocation.validate_discovered_inputs(files.iter().map(PathBuf::as_path))?;
    Ok(CcDiscoveredInputs::collect(
        &context.working_dir,
        files.clone(),
        manifest_directories(invocation, context, &files),
        session::file_digest_cache(),
    )?)
}

/// Directories a shadowing header could appear in that are known before the
/// compiler runs.
///
/// The include search path and the source's own directory are named on the
/// command line, so they can be snapshotted up front. A directory reached only
/// through a header that includes its neighbour is not known until the
/// dependency list names it, and is covered by the digests of the files that
/// were actually read.
fn searchable_directories(invocation: &CcInvocation, working_dir: &Path) -> BTreeSet<PathBuf> {
    invocation
        .include_dirs()
        .iter()
        .map(|directory| absolute(directory, working_dir))
        .chain(
            invocation
                .source()
                .parent()
                .map(|parent| absolute(parent, working_dir)),
        )
        .filter(|directory| !is_system_include_path(directory))
        .collect()
}

/// Reject a compilation whose include search path shifted underneath it.
fn verify_search_path_unchanged(
    searchable: &BTreeSet<PathBuf>,
    before: Result<BTreeMap<PathBuf, CacheDigest>, CcBypassReason>,
) -> Result<()> {
    // A later successful walk cannot establish what the compiler saw when
    // the pre-compilation snapshot failed. Compile normally, but do not cache.
    let before = before?;
    let after = crate::phase_timing::measure("include_scan", || manifest_snapshot(searchable))?;
    for (directory, digest) in &before {
        if after.get(directory) != Some(digest) {
            return Err(
                CcBypassReason::SearchPathModifiedDuringCompilation(directory.clone()).into(),
            );
        }
    }
    Ok(())
}

/// Directories whose contents could change which file a future include
/// resolves to.
///
/// Every search directory named on the command line qualifies, and so does the
/// directory each discovered header actually came from -- a quoted include
/// searches the includer's own directory, which never appears in argv. System
/// roots are left out: enumerating an SDK per compile costs more than the
/// residual risk, and anything actually read from one is digested anyway.
fn manifest_directories(
    invocation: &CcInvocation,
    context: &CcActionContext,
    files: &BTreeSet<PathBuf>,
) -> BTreeSet<PathBuf> {
    invocation
        .include_dirs()
        .iter()
        .map(|directory| absolute(directory, &context.working_dir))
        .chain(
            files
                .iter()
                .filter_map(|file| file.parent().map(Path::to_path_buf)),
        )
        .filter(|directory| !is_system_include_path(directory))
        .collect()
}

fn absolute(path: &Path, working_dir: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        working_dir.join(path)
    }
}

/// Roots the key replaces with placeholders.
///
/// Deliberately the same roots the rustc shim maps, and read from the same
/// session variables, so both adapters agree on which paths belong to a
/// checkout rather than to the machine.
fn path_mappings(working_dir: &Path) -> Vec<PathMapping> {
    let mut mappings = Vec::new();
    let mut add = |root: Option<PathBuf>, placeholder: &str| {
        if let Some(root) = root.filter(|root| root.is_absolute())
            && !mappings
                .iter()
                .any(|existing: &PathMapping| existing.root == root)
        {
            mappings.push(PathMapping::new(root, placeholder));
        }
    };
    add(session_path(session::TARGET_DIR_ENV), "target");
    add(session_path(session::WORKSPACE_ROOT_ENV), "workspace");
    let cargo_home = std::env::var_os("CARGO_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs::home_dir().map(|home| home.join(".cargo")));
    add(
        cargo_home.as_ref().map(|home| home.join("registry")),
        "cargo_registry",
    );
    add(cargo_home, "cargo_home");
    add(
        std::env::var_os("RUSTUP_HOME")
            .map(PathBuf::from)
            .or_else(|| dirs::home_dir().map(|home| home.join(".rustup"))),
        "rustup_home",
    );
    add(dirs::home_dir(), "home");
    add(std::env::var_os("VCINSTALLDIR").map(PathBuf::from), "msvc");
    add(
        std::env::var_os("WindowsSdkDir").map(PathBuf::from),
        "windows_sdk",
    );
    add(
        std::env::var_os("UniversalCRTSdkDir").map(PathBuf::from),
        "ucrt_sdk",
    );
    // A build script of a path dependency outside the workspace compiles
    // sources from its own package, which none of the roots above but home
    // can name -- and home only when the checkout happens to be below it.
    if let Some(root) = session_path("CARGO_MANIFEST_DIR").filter(|root| {
        root.is_absolute()
            && !mappings
                .iter()
                .any(|existing| existing.placeholder != "home" && root.starts_with(&existing.root))
    }) {
        mappings.push(PathMapping::new(root, "package"));
    }
    let _ = working_dir;
    mappings
}

fn is_system_include_path(path: &Path) -> bool {
    is_system_path(path)
        || ["VCINSTALLDIR", "WindowsSdkDir", "UniversalCRTSdkDir"]
            .iter()
            .filter_map(std::env::var_os)
            .map(PathBuf::from)
            .any(|root| path.starts_with(root))
}

fn rustc_path_mappings(mappings: &[PathMapping]) -> Vec<tuist_cargo_cache_rustc::PathMapping> {
    mappings
        .iter()
        .map(|mapping| {
            tuist_cargo_cache_rustc::PathMapping::new(&mapping.root, &mapping.placeholder)
        })
        .collect()
}

fn session_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

/// Fingerprint the driver, and for gcc the assembler it hands objects to.
///
/// The probe output is memoized through the agent, because a build script may
/// compile hundreds of translation units and each one would otherwise re-run
/// the compiler just to ask its version.
fn compiler_identity(compiler: &OsStr, language: CcLanguage) -> Result<CcCompilerIdentity> {
    let _phase = crate::phase_timing::phase("key");
    let executable = resolve_executable(compiler)?;
    let is_cl = executable
        .file_stem()
        .and_then(OsStr::to_str)
        .is_some_and(|stem| stem.eq_ignore_ascii_case("cl"));
    let probe = if is_cl {
        probe_msvc(&executable)?
    } else {
        probe_executable(&executable, &["-v"], &executable)?
    };
    let family = CcCompilerFamily::classify(&probe)?;
    let target = if family.is_msvc() {
        std::env::var("VSCMD_ARG_TGT_ARCH").unwrap_or_default()
    } else {
        probe
            .lines()
            .find_map(|line| line.strip_prefix("Target: "))
            .unwrap_or_default()
            .to_string()
    };
    let assembler = if family.uses_external_assembler() {
        assembler_identity(&executable)
    } else {
        String::new()
    };
    let _ = language;
    Ok(CcCompilerIdentity {
        family,
        version_text: probe,
        target,
        assembler,
    })
}

/// MSVC prints its detailed `/Bv` identity before complaining that no source
/// was supplied. That non-zero exit is a property of the query shape, not a
/// failed identity probe, so accept it only when the expected banner is there.
fn probe_msvc(executable: &Path) -> Result<String> {
    let environment = BTreeMap::new();
    if let Ok(responses) = session::request_agent(&[AgentRequest::FindExecutableIdentity {
        executable: executable.to_path_buf(),
        environment: environment.clone(),
    }]) && let Some(AgentResponse::ExecutableIdentity { stdout: Some(text) }) =
        responses.into_iter().next()
    {
        return Ok(String::from_utf8_lossy(&text).into_owned());
    }
    let output = Command::new(executable)
        .arg("/Bv")
        .output()
        .map_err(|error| CcBypassReason::CompilerIdentityUnavailable(error.to_string()))?;
    let mut text = String::from_utf8_lossy(&output.stderr).into_owned();
    text.push_str(&String::from_utf8_lossy(&output.stdout));
    if !text.contains("Microsoft (R) C/C++ Optimizing Compiler") {
        return Err(CcBypassReason::CompilerIdentityUnavailable(format!(
            "{} did not report an MSVC compiler identity",
            executable.display()
        ))
        .into());
    }
    let _ = session::request_agent(&[AgentRequest::StoreExecutableIdentity {
        executable: executable.to_path_buf(),
        environment,
        stdout: text.clone().into_bytes(),
        pins: Vec::new(),
    }]);
    Ok(text)
}

/// The assembler path a driver named, if it named one at all.
///
/// `-print-prog-name` echoes the bare name back when the driver cannot resolve
/// the tool, which is not a path and means the driver would search `PATH` for
/// it -- so the caller does the same.
fn named_assembler(printed: &str) -> Option<PathBuf> {
    let trimmed = printed.trim();
    Path::new(trimmed)
        .is_absolute()
        .then(|| PathBuf::from(trimmed))
}

/// The assembler gcc will hand objects to.
///
/// Its version changes object bytes without changing anything `gcc -v` prints,
/// so it belongs in the identity.
///
/// The driver is asked which assembler it will run rather than the first `as`
/// on `PATH`: gcc resolves the tool through its own exec prefix and whatever it
/// was configured with, so a toolchain shipping its own binutils runs one
/// assembler while `PATH` names another. Keying the wrong one would let two
/// toolchains share an entry whose object bytes they do not agree on.
///
/// An assembler that cannot be resolved yields a marker rather than a bypass:
/// the compile still happens, and the key is simply less specific than it could
/// have been -- which every machine in that state shares.
fn assembler_identity(compiler: &Path) -> String {
    // A driver that cannot resolve the tool echoes the bare name back, and then
    // searching PATH is exactly what it does itself.
    let named = probe_executable(compiler, &["-print-prog-name=as"], &compiler.join("as"))
        .unwrap_or_default();
    let assembler = match named_assembler(&named) {
        Some(assembler) => assembler,
        None => match resolve_executable(OsStr::new("as")) {
            Ok(found) => found,
            Err(_) => return "unresolved".into(),
        },
    };
    let version = probe_executable(&assembler, &["--version"], &assembler)
        .ok()
        .and_then(|probe| probe.lines().next().map(ToOwned::to_owned))
        .unwrap_or_default();
    format!("{}; {version}", assembler.display())
}

/// Run a probe once per session, memoized by the agent.
///
/// `memo` is the key the answer is stored under. The agent keys an executable
/// identity by path alone, so two probes of the same binary would otherwise
/// return each other's output; a caller asking a compiler something other than
/// its version passes a key that cannot collide with a real path.
fn probe_executable(executable: &Path, arguments: &[&str], memo: &Path) -> Result<String> {
    let key = memo.to_path_buf();
    // No environment variable changes what a C driver prints for these, so the
    // memo needs nothing beyond the key.
    let environment = BTreeMap::new();
    let responses = session::request_agent(&[AgentRequest::FindExecutableIdentity {
        executable: key.clone(),
        environment: environment.clone(),
    }]);
    if let Ok(responses) = responses
        && let Some(AgentResponse::ExecutableIdentity { stdout: Some(text) }) =
            responses.into_iter().next()
    {
        return Ok(String::from_utf8_lossy(&text).into_owned());
    }
    let output = Command::new(executable)
        .args(arguments)
        .output()
        .map_err(|error| CcBypassReason::CompilerIdentityUnavailable(error.to_string()))?;
    if !output.status.success() {
        return Err(CcBypassReason::CompilerIdentityUnavailable(format!(
            "{} exited with {}",
            executable.display(),
            output.status
        ))
        .into());
    }
    // Drivers print their banner on stderr; clang and gcc both do.
    let mut text = String::from_utf8_lossy(&output.stderr).into_owned();
    if text.trim().is_empty() {
        text = String::from_utf8_lossy(&output.stdout).into_owned();
    }
    let _ = session::request_agent(&[AgentRequest::StoreExecutableIdentity {
        executable: key,
        environment,
        stdout: text.clone().into_bytes(),
        pins: Vec::new(),
    }]);
    Ok(text)
}

/// Separate extended predictions from legacy manifests and flight identities.
fn prediction_invocation(invocation: &CacheDigest) -> CacheDigest {
    CacheDigest::blake3(format!("{PREDICTION_ADAPTER}\0{}", invocation.hash).as_bytes())
}

fn find_prediction(task: &str, invocation: &CacheDigest) -> Result<Option<CcInputPrediction>> {
    let responses = session::request_agent(&[AgentRequest::FindActionPrediction {
        task: task.to_string(),
        invocation: invocation.clone(),
    }])?;
    let Some(AgentResponse::ActionPrediction { prediction }) = responses.into_iter().next() else {
        return Ok(None);
    };
    let Some(prediction) = prediction else {
        return Ok(None);
    };
    if prediction.adapter != PREDICTION_ADAPTER {
        return Ok(None);
    }
    let payload: CcInputPrediction = serde_json::from_str(&prediction.payload)?;
    Ok(Some(payload))
}

fn record_prediction(
    task: &str,
    invocation: &CacheDigest,
    action: &CacheDigest,
    prediction: &CcInputPrediction,
    flight: Option<&crate::scheduler::Flight>,
    remote_claim: Option<&str>,
) {
    let _phase = crate::phase_timing::phase("predict");
    let Ok(payload) = serde_json::to_string(prediction) else {
        return;
    };
    // Anyone waiting on this flight -- and any later build of the same
    // invocation -- restores through this instead of compiling.
    if let Some(flight) = flight {
        flight.leave(&payload);
    }
    let wire_prediction = ActionPrediction {
        invocation: invocation.clone(),
        action: action.clone(),
        adapter: PREDICTION_ADAPTER.into(),
        payload,
    };
    // Best-effort like the rest of publication, but not silent in a debug
    // build: a prediction that is never recorded is a compilation that is
    // never looked up again, with nothing in the summary to say why.
    let recorded = session::request_agent(&[AgentRequest::RecordActionPrediction {
        task: task.to_string(),
        prediction: wire_prediction.clone(),
    }]);
    #[cfg(debug_assertions)]
    match recorded.map(|responses| responses.into_iter().next()) {
        Ok(Some(AgentResponse::ActionPredictionRecorded)) => {}
        Ok(other) => session::report_shim_warning(&format!(
            "cc prediction was not recorded: unexpected agent response {other:?}"
        )),
        Err(error) => {
            session::report_shim_warning(&format!("cc prediction was not recorded: {error:#}"))
        }
    }
    #[cfg(not(debug_assertions))]
    let _ = recorded;
    if let Some(claim) = remote_claim {
        let _ = session::request_agent(&[AgentRequest::CompleteActionPromise {
            claim: claim.to_string(),
            prediction: wire_prediction,
        }]);
    }
}

/// Task identity for a compilation's predictions.
///
/// Inside a build this is the session's own run, the same manifest the rustc
/// shim records into: it is the one the session loads before the build and
/// commits after it, so a prediction written by one checkout is there to be
/// found by the next. A shim running outside a session falls back to sharding
/// by the invocation fingerprint, which keeps each manifest bounded.
fn prediction_task(invocation: &CacheDigest) -> String {
    std::env::var(session::BUILD_ENV).unwrap_or_else(|_| standalone_prediction_task(invocation))
}

/// Shard predictions by invocation fingerprint, which is what a shim outside a
/// session has to fall back to. A single manifest would eventually reach the
/// protocol's prediction limit.
fn standalone_prediction_task(invocation: &CacheDigest) -> String {
    let shard = invocation.hash.get(..2).unwrap_or(&invocation.hash);
    CacheDigest::blake3(format!("cc-standalone-predictions-v1\0{shard}").as_bytes()).hash
}

fn restore_result(
    action: &CcAction,
    invocation: &CcInvocation,
    discovered: &CcDiscoveredInputs,
    restore_outputs: bool,
    mappings: &[PathMapping],
    working_dir: &Path,
) -> Result<Option<CachedCompilation>> {
    let _phase = crate::phase_timing::phase("restore");
    let text_mappings = rustc_path_mappings(mappings);
    let responses = session::request_agent(&[AgentRequest::FindActionResult {
        action: action.digest.clone(),
    }])?;
    let Some(response) = responses.into_iter().next() else {
        bail!("cache agent did not return an action lookup response");
    };
    let result = match response {
        AgentResponse::ActionResult { result } => match result {
            Some(result) => result,
            None => return Ok(None),
        },
        AgentResponse::Error { message } => bail!(message),
        _ => bail!("cache agent returned an unexpected action lookup response"),
    };
    if result.version != 1 || result.action != action.digest {
        bail!("cached cc action result has an invalid identity");
    }
    let metadata_digest = result
        .metadata
        .ok_or_else(|| eyre::eyre!("cached cc action result has no metadata"))?;
    let output_root_digest = result
        .output_root
        .ok_or_else(|| eyre::eyre!("cached cc action result has no output root"))?;
    let roots = find_blobs(&[
        action.digest.clone(),
        metadata_digest.clone(),
        output_root_digest.clone(),
    ])?;
    let cached_action = read_verified_blob(&roots[0], &action.digest, "action descriptor")?;
    if cached_action != action.bytes {
        bail!("cached cc action descriptor does not match the invocation");
    }
    let metadata: CcMetadata = read_canonical_blob(&roots[1], &metadata_digest, "cc metadata")?;
    if !metadata.validate() {
        bail!("cached cc metadata is unsupported");
    }
    let directory: CacheDirectory =
        read_canonical_blob(&roots[2], &output_root_digest, "output directory")?;
    let node = validated_object(directory, invocation)?;
    let destination = invocation.output_in(working_dir);

    let blobs = find_blobs(&[
        metadata.stdout.clone(),
        metadata.stderr.clone(),
        node.digest.clone(),
    ])?;
    // A compiler diagnostic names the file it is about, so a warning stored by
    // one checkout would otherwise be replayed in another pointing at paths
    // that belong to the checkout that published it.
    let stdout = denormalize_output_text(
        &read_verified_blob(&blobs[0], &metadata.stdout, "stdout")?,
        &text_mappings,
    );
    let stderr = denormalize_output_text(
        &read_verified_blob(&blobs[1], &metadata.stderr, "stderr")?,
        &text_mappings,
    );

    let materialization_started = Instant::now();
    let parent = destination
        .parent()
        .ok_or_else(|| eyre::eyre!("cc output has no parent directory"))?;
    std::fs::create_dir_all(parent)?;
    let staging = tempfile::tempdir_in(parent)?;
    let mut restore = RestoreStats {
        output_files: 1,
        output_bytes: node.digest.size,
        ..RestoreStats::default()
    };
    // An object already holding these bytes is kept, not rewritten: the
    // rewrite would only refresh its modification time, which is what keeps
    // downstream freshness checks re-dirtying whatever reads it.
    let mut staged_files = Vec::new();
    if restore_outputs
        && crate::rustc::output_already_in_place(&node, &destination, session::file_digest_cache())
    {
        restore.reused_output_files = 1;
        restore.reused_output_bytes = node.digest.size;
    } else {
        let (temporary, materialization) =
            stage_verified_cached_output(staging.path(), 0, &blobs[2], &node)?;
        match materialization {
            Materialization::Reflink => {
                restore.reflinked_output_files = 1;
                restore.reflinked_output_bytes = node.digest.size;
            }
            Materialization::Hardlink => {
                restore.hardlinked_output_files = 1;
                restore.hardlinked_output_bytes = node.digest.size;
            }
            Materialization::Copy => {
                restore.copied_output_files = 1;
                restore.copied_output_bytes = node.digest.size;
            }
        }
        staged_files.push((temporary, destination.clone()));
    }
    let staged = StagedOutputs {
        directory: staging,
        files: staged_files,
    };

    // Re-check the inputs after staging: a header rewritten while the lookup
    // was in flight must not be answered from the key it no longer matches.
    discovered.verify()?;
    if restore_outputs {
        persist_outputs(staged)?;
        // The restored object is what a later native link hashes as an input,
        // so its digest enters the content ledger the moment its identity is
        // fixed by the rename.
        if let Ok(metadata) = std::fs::metadata(&destination)
            && metadata.len() == node.digest.size
            && let Ok(Some(file)) = FileIdentity::for_digest_cache(&destination, &metadata)
        {
            session::record_file_digests(
                FileDigestScope::Content,
                vec![RecordedFileDigest {
                    file,
                    digest: node.digest.clone(),
                }],
            );
        }
    }
    restore.duration_ns = duration_ns(materialization_started.elapsed());
    Ok(Some(CachedCompilation {
        action: action.digest.clone(),
        stdout,
        stderr,
        outputs: vec![CachedOutput {
            path: destination,
            digest: node.digest,
            executable: node.executable,
            mode: node.mode,
        }],
        restore,
    }))
}

/// Confirm the cached directory holds exactly the one object this compile
/// produces.
fn validated_object(directory: CacheDirectory, invocation: &CcInvocation) -> Result<CacheFileNode> {
    if directory.version != 1 || !directory.directories.is_empty() || !directory.symlinks.is_empty()
    {
        bail!("cached cc output directory has unsupported entries");
    }
    let name = invocation
        .output()
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| eyre::eyre!("cc output name is not UTF-8"))?;
    let [node] = <[CacheFileNode; 1]>::try_from(directory.files)
        .map_err(|_| eyre::eyre!("cached cc output set does not match the invocation"))?;
    if node.name != name {
        bail!("cached cc output is unexpected: {}", node.name);
    }
    validate_file_mode(&node, false)?;
    Ok(node)
}

fn publish_result(
    action: &CcAction,
    object: &Path,
    output: &Output,
    mappings: &[PathMapping],
) -> Result<()> {
    let _phase = crate::phase_timing::phase("store");
    let text_mappings = rustc_path_mappings(mappings);
    let metadata = std::fs::metadata(object)
        .wrap_err_with(|| format!("failed to inspect cc output {}", object.display()))?;
    if !metadata.is_file() {
        bail!("cc output is not a regular file: {}", object.display());
    }
    let staging = staging_directory()?;
    let mut blobs = vec![staged_bytes(staging.path(), "action.json", &action.bytes)?];
    let stdout = staged_bytes(
        staging.path(),
        "stdout",
        &normalize_output_text(&output.stdout, &text_mappings),
    )?;
    let stderr = staged_bytes(
        staging.path(),
        "stderr",
        &normalize_output_text(&output.stderr, &text_mappings),
    )?;
    blobs.extend([stdout.clone(), stderr.clone()]);

    let digest = CacheDigest::blake3_file(object)?;
    blobs.push((digest.clone(), object.to_path_buf()));
    // A freshly compiled object is a future native-link input; the hash just
    // taken is the read a ledger entry stands in for.
    if metadata.len() == digest.size
        && let Ok(Some(file)) = FileIdentity::for_digest_cache(object, &metadata)
    {
        session::record_file_digests(
            FileDigestScope::Content,
            vec![RecordedFileDigest {
                file,
                digest: digest.clone(),
            }],
        );
    }
    let files = vec![CacheFileNode {
        digest,
        // An object file is never executable, which is what makes the mode
        // model here trivial compared with the rustc adapter's.
        executable: false,
        mode: file_mode(&metadata),
        name: object
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| eyre::eyre!("cc output name is not UTF-8"))?
            .to_string(),
    }];

    let metadata_bytes = canonical_json(&CcMetadata {
        version: 1,
        kind: ADAPTER.into(),
        stdout: stdout.0,
        stderr: stderr.0,
    })?;
    let metadata = staged_bytes(staging.path(), "metadata.json", &metadata_bytes)?;
    blobs.push(metadata.clone());
    let directory_bytes = canonical_json(&CacheDirectory {
        directories: Vec::new(),
        files,
        symlinks: Vec::new(),
        version: 1,
    })?;
    let directory = staged_bytes(staging.path(), "directory.json", &directory_bytes)?;
    blobs.push(directory.clone());

    let mut requests = Vec::new();
    let mut published = BTreeSet::new();
    for (digest, source) in blobs {
        if published.insert(digest.clone()) {
            requests.push(AgentRequest::StoreBlob { digest, source });
        }
    }
    requests.push(AgentRequest::StoreActionResult {
        result: RemoteActionResult {
            action: action.digest.clone(),
            metadata: Some(metadata.0),
            output_root: Some(directory.0),
            version: 1,
        },
    });
    for response in session::request_agent(&requests)? {
        match response {
            AgentResponse::Stored { .. } | AgentResponse::ActionStored { .. } => {}
            AgentResponse::Error { message } => bail!(message),
            _ => bail!("cache agent returned an unexpected publish response"),
        }
    }
    Ok(())
}

fn staged_bytes(directory: &Path, name: &str, bytes: &[u8]) -> Result<(CacheDigest, PathBuf)> {
    let path = directory.join(name);
    std::fs::write(&path, bytes)?;
    Ok((CacheDigest::blake3(bytes), path))
}

/// Why a shadow compilation disagreed with the cached result, if it did.
///
/// Said in words rather than as a bare `false`, the way the rustc adapter
/// says it. A qualification run reports a count, and a count with no reason
/// attached is not something anybody can act on: every divergence looks
/// alike in the log, so a systematic one and a real modeling bug read the
/// same.
fn verification_divergence(cached: &CachedCompilation, output: &Output) -> Option<String> {
    if !output.status.success() {
        return Some("the shadow compilation failed".into());
    }
    if let Some(difference) =
        crate::materialize::stream_divergence("standard output", &cached.stdout, &output.stdout)
            .or_else(|| {
                crate::materialize::stream_divergence(
                    "standard error",
                    &cached.stderr,
                    &output.stderr,
                )
            })
    {
        return Some(difference);
    }
    output_divergence(cached)
}

/// A stderr-only publication conflict may retain the validated first result.
/// Verification still compares both streams and reports every byte difference.
fn publication_outputs_match(cached: &CachedCompilation, output: &Output) -> bool {
    output.status.success() && cached.stdout == output.stdout && output_divergence(cached).is_none()
}

fn output_divergence(cached: &CachedCompilation) -> Option<String> {
    for expected in &cached.outputs {
        let name = expected.path.display();
        let Ok(metadata) = std::fs::metadata(&expected.path) else {
            return Some(format!("{name} is missing"));
        };
        if file_mode(&metadata) != expected.mode {
            return Some(format!("{name} has a different file mode"));
        }
        if !executable_mode_matches(&metadata, expected.executable) {
            return Some(format!("{name} has a different executable bit"));
        }
        if !expected
            .digest
            .matches_file(&expected.path)
            .unwrap_or(false)
        {
            return Some(format!("{name} has different contents"));
        }
    }
    None
}

/// Name this compilation goes by in build statistics.
///
/// Prefixed so a C source cannot be mistaken for a crate in the same table.
fn compilation_name(invocation: &CcInvocation) -> String {
    format!("{ADAPTER}:{}", invocation.source_name())
}

fn duration_ns(duration: std::time::Duration) -> u64 {
    duration.as_nanos().try_into().unwrap_or(u64::MAX)
}

#[cfg(test)]
#[path = "cc_tests.rs"]
mod tests;
