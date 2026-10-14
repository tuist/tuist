use crate::materialize::{
    CachedCompilation, CachedOutput, Materialization, StagedOutputs, apply_file_mode,
    denormalize_output_text, executable_mode_matches, exit_code, file_mode, find_blobs,
    normalize_output_text, persist_outputs, read_canonical_blob, read_verified_blob,
    record_action_hit_with_diagnostic, record_verification, replay_bytes, resolve_executable,
    stage_verified_cached_output, staging_directory, validate_file_mode,
};
use crate::{session, util::workspace_root};
use eyre::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::{OsStr, OsString};
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Output, Stdio};
use std::sync::OnceLock;
use std::time::{Instant, SystemTime};
use tuist_cargo_cache_core::{
    ActionDiagnostic, ActionPrediction, AgentRequest, AgentResponse, CacheDigest, CacheDirectory,
    CacheFileNode, FileDigestResolution, FileDigestScope, FileIdentity, FileSnapshot, PinnedFile,
    RecordedFileDigest, RemoteActionResult, RestoreStats, RustcMetadata, canonical_json,
};
use tuist_cargo_cache_rustc::{
    ActionContext, ActionInput, BypassReason, CompilerIdentity, DiscoveredInputs, LinkerIdentity,
    ParseOptions, PathMapping, RustcAction, RustcDepInfo, RustcInputPrediction, RustcInvocation,
    RustcOutputs, normalize_mapped_path,
};

#[derive(Clone, Debug, Default)]
struct CompileTiming {
    crate_name: String,
    duration_ns: u64,
}

/// Consecutive misses with changed content before an external unit compiles
/// incrementally.
///
/// One changed key is an edit; a run of them is a developer working here. The
/// threshold is what separates the two, and it is small because the cost of
/// guessing wrong is one uncached compilation the unit was going to pay anyway.
const HOT_STREAK_THRESHOLD: u32 = 3;

/// A workspace unit is hot on its first edit. Churn is measured from each
/// unit's own sources, so a dependent is only dragged along when it links
/// the private artifact the hot unit produced; see [`links_private_artifact`].
const WORKSPACE_HOT_STREAK_THRESHOLD: u32 = 1;

/// Schema version of the per-checkout churn record.
const CHURN_STATE_VERSION: u8 = 1;

/// Schema version of a private-artifact marker.
const PRIVATE_ARTIFACT_VERSION: u8 = 1;

/// What a churning unit gets: its own incremental state, and no publication.
#[derive(Clone, Debug, Default)]
struct LearnedPlan {
    /// Whether this unit has churned often enough to keep incremental state.
    hot: bool,
    /// Consecutive changed-content misses, including this one.
    streak: u32,
    /// Where that state lives, once somewhere to put it has been resolved.
    directory: Option<PathBuf>,
    /// Where to record what this compilation compiled, and what that was.
    record: Option<(PathBuf, CacheDigest)>,
}

impl LearnedPlan {
    /// Find somewhere to keep the state, for a unit that earned it.
    fn resolved(mut self, invocation: &CacheDigest, crate_name: &str) -> Self {
        if self.hot {
            self.directory = incremental_directory(invocation, crate_name);
        }
        self
    }

    /// Record what this crate compiled, now that it has.
    ///
    /// Deliberately after the compiler succeeds rather than before it runs. A
    /// failed compilation leaves nothing behind to compare against, so
    /// recording its sources would make the retry that follows -- with nothing
    /// edited in between -- look like a crate that had settled, and drop it
    /// back to compiling from scratch.
    fn record_compiled(&self) {
        let Some((path, sources)) = &self.record else {
            return;
        };
        if let Err(error) = write_churn_state(path, sources, self.streak) {
            session::report_shim_warning(&format!(
                "churn was not recorded for this crate: {error:#}"
            ));
        }
    }

    /// Whether this compilation actually carries incremental state. A hot unit
    /// with nowhere to keep it compiles and publishes like any other miss.
    fn engaged(&self) -> bool {
        self.directory.is_some()
    }
}

/// What one checkout last compiled for one unit, and how long its sources have
/// been moving.
///
/// Kept beside the incremental state it decides, in a checkout-specific cache
/// directory, rather than in the prediction manifest: a manifest is shared by
/// every worktree resolving the same lockfile, so a streak recorded there would
/// let one developer's edit loop mark a crate hot for a sibling worktree that
/// is merely building it.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ChurnState {
    /// Version of this record's schema.
    version: u8,
    /// Digest of the sources compiled here last time.
    sources: String,
    /// Consecutive compilations whose sources had changed.
    streak: u32,
}

/// An output this checkout last compiled with private incremental state.
///
/// Kept beside the churn records, keyed by the output's path, so the crates
/// that link it can tell a private artifact from a published one without
/// knowing which unit produced it. Written before the compiler runs rather
/// than after: Cargo starts a dependent as soon as this unit's metadata
/// exists, while the compiler is still running here.
#[derive(Debug, Serialize, Deserialize)]
struct PrivateArtifact {
    /// Version of this marker's schema.
    version: u8,
    /// Absolute path of the artifact, as the compiler was told to write it.
    path: PathBuf,
}

#[derive(Serialize)]
struct BuildScriptBinaryIdentity<'a> {
    digest: &'a CacheDigest,
    kind: &'static str,
    output_name: &'a str,
    version: u8,
}

/// What every step of one compilation needs to identify it.
struct Compilation<'a> {
    rustc: &'a OsStr,
    invocation: &'a RustcInvocation,
    working_dir: &'a Path,
    portable: &'a Portable,
    /// Identity of the linker, for an invocation whose key must describe it.
    linker: Option<LinkerIdentity>,
}

/// Restore a compilation or run rustc and publish a validated result. Cargo's
/// build-script declarations supplement dep-info when identifying inputs;
/// unsupported or unsafe input trees let the caller fall back to uncached rustc.
pub(crate) fn compile(
    rustc: &OsStr,
    arguments: &[OsString],
    wrapper_argument: Option<&OsStr>,
) -> Result<ExitCode> {
    let setup = crate::phase_timing::phase("key");
    let working_dir = std::env::current_dir()?;
    // The orchestrated session supplies the target root. A persistent wrapper
    // has no parent session, so first parse just enough of the invocation to
    // learn its output directory and use that as the stable target mapping.
    let cache_native_links = session::cache_links_requested();
    // Scanned after response-file expansion, so a `--target`, `--out-dir`, or
    // crate type inside an `@argfile` is seen; an expansion the parser would
    // refuse is left as is, since parsing fails on it below anyway.
    let expanded = RustcInvocation::expand_arguments(arguments);
    let scanned = expanded.as_deref().unwrap_or(arguments);
    // A platform without native-link action caching still needs to observe a
    // build-script executable so execution caching can key it by its exact
    // bytes. Parsing it is safe: the linked output itself is not published.
    let execution_only_build_script = session::build_script_execution_requested()
        && !cache_native_links
        && session::compiles_only_a_binary(scanned)
        && session::crate_name_argument(scanned)
            .is_some_and(|name| session::is_cargo_build_script(&name));
    let options =
        ParseOptions::caching_native_links(cache_native_links || execution_only_build_script)
            .with_custom_target_search(custom_target_may_resolve(rustc, scanned));
    // Appended before anything parses: the debug-map rule inside the parser is
    // exactly what this flag satisfies, so an invocation that would bypass
    // without it has to carry it going in.
    let arguments = with_oso_prefix(arguments, cache_native_links || execution_only_build_script);
    let arguments = arguments.as_ref();
    let initial_invocation = RustcInvocation::parse_with(arguments, options)?;
    // Keep Cargo's original OUT_DIR: stabilization moves generated sources to
    // a content-addressed tree that has no Cargo-recorded build-script stdout.
    let build_script_inputs = if session::is_cargo_build_script(initial_invocation.crate_name())
        && session::compiles_only_a_binary(scanned)
    {
        None
    } else {
        std::env::var_os("OUT_DIR")
            .map(|out_dir| {
                let manifest_dir = std::env::var_os("CARGO_MANIFEST_DIR")
                    .ok_or_else(|| eyre::eyre!("OUT_DIR has no CARGO_MANIFEST_DIR"))?;
                crate::build_script::CompilationInputs::for_package(
                    Path::new(&out_dir),
                    Path::new(&manifest_dir),
                )
            })
            .transpose()?
            .flatten()
    };
    // Before the key, remapping, or compiler reads OUT_DIR, decide which
    // generated tree this compilation will use.
    crate::out_dir::stabilize_for(initial_invocation.source());
    let initial_outputs = initial_invocation.outputs(&working_dir)?;
    let mut portable = Portable::detect(
        &working_dir,
        Some(&initial_outputs.directory),
        initial_invocation.target(),
    );
    portable.build_script_inputs = build_script_inputs;
    portable.map_external_native_paths(&initial_invocation, &working_dir);
    let mut arguments = portable.applied_to(arguments);
    // Include the flag in both parsing/key construction and execution. This
    // separates old path-bearing artifacts without changing content hashing.
    if let Some(argument) = initial_invocation.portable_install_name(&initial_outputs) {
        arguments.push(argument.into());
    }
    let invocation = RustcInvocation::parse_with(&arguments, options)?;
    let outputs = invocation.outputs(&working_dir)?;

    drop(setup);
    if execution_only_build_script {
        return compile_execution_only_build_script(
            rustc,
            wrapper_argument,
            &arguments,
            &working_dir,
            &invocation,
            &outputs,
            &portable,
        );
    }

    // Whatever this compilation ends up doing -- restoring, publishing, or
    // keeping private state -- the outputs it is about to write are no longer
    // the private artifacts an earlier compilation marked them as. A hot
    // compilation marks them again below, before the compiler starts.
    if let Some(root) = incremental_root() {
        forget_private_artifacts(&root, &outputs);
    }
    let _verification = session::verification::select(|| {
        let context = base_action_context(rustc, &working_dir, &portable)?;
        Ok(invocation.invocation_digest(&context)?)
    })?;
    let verify = session::verify_requested();
    // A shadow compilation compares its result against a cached one, which an
    // incremental artifact would never match, so the two modes are exclusive.
    let learned_enabled = session::learned_incremental_requested() && !verify;
    let mut verification = None;
    let mut action_lookup_attempted = false;
    let mut current_diagnostic = None;
    // Probed once, before anything that would swallow the answer: a host whose
    // linker cannot be described bypasses here, where the reason is recorded,
    // rather than deep inside key construction where it becomes a warning
    // nobody counts.
    let compilation = Compilation {
        rustc,
        invocation: &invocation,
        working_dir: &working_dir,
        portable: &portable,
        linker: linker_for(&invocation)?,
    };
    // Verification may select a consumer of an unsampled private artifact,
    // and Cargo may also retain such an artifact from an earlier build. The
    // consumer must stay private even when it compiles without incremental state.
    let private_inputs = links_private_artifact(&compilation);
    let mut learned = if !verify
        && (session::eager_incremental_requested() || (learned_enabled && private_inputs))
    {
        eager_incremental_plan(&compilation)
    } else {
        reuse_hot_workspace_plan(&compilation, &outputs, learned_enabled)
    };
    let mut unshareable = false;
    if !private_inputs
        && !learned.engaged()
        && outputs.dep_info.is_file()
        && let Ok((candidates, discovered)) =
            action_from_current_dep_info(&compilation, &outputs.dep_info)
                .inspect_err(|error| unshareable = is_unshareable_search_path(error))
    {
        current_diagnostic = candidates
            .ordered()
            .next()
            .and_then(|action| compilation_action_diagnostic(&compilation, action).ok());
        action_lookup_attempted = true;
        match restore_candidates(
            &candidates,
            &outputs,
            &discovered,
            !verify,
            &portable.mappings,
        ) {
            Ok(Some((action, mut cached))) => {
                match refresh_prediction(&compilation, &action, &discovered) {
                    Ok(timing) => {
                        cached.restore.avoided_compiler_duration_ns = timing.duration_ns;
                    }
                    Err(error) => {
                        session::report_shim_warning(&format!(
                            "compiler timing was not refreshed: {error:#}"
                        ));
                    }
                }
                if learned_enabled && source_is_in_workspace(&compilation) {
                    record_learned_baseline(&compilation, &discovered);
                }
                if verify {
                    verification = Some(cached);
                } else {
                    let diagnostic = candidates
                        .ordered()
                        .find(|candidate| candidate.digest == action)
                        .and_then(|candidate| {
                            compilation_action_diagnostic(&compilation, candidate).ok()
                        });
                    record_action_hit_with_diagnostic(
                        &action,
                        cached.restore,
                        invocation.crate_name(),
                        diagnostic,
                    );
                    install_build_script_shim(&invocation, &outputs, &action);
                    let _ = replay_bytes(&cached.stdout, &cached.stderr);
                    return Ok(ExitCode::SUCCESS);
                }
            }
            Ok(None) => {
                learned = plan_learned_reuse(&compilation, &discovered, learned_enabled);
            }
            Err(error) => {
                session::report_shim_warning(&format!("result was not restored: {error:#}"));
            }
        }
    }
    // A compilation that cannot be keyed for the cache still has sources worth
    // watching: private incremental state needs no shareable key.
    if unshareable && learned_enabled && !learned.engaged() && learned.record.is_none() {
        learned = plan_learned_without_action_key(&compilation, &outputs);
    }
    let mut prediction_missing = private_inputs;
    if !private_inputs && !learned.engaged() && !action_lookup_attempted {
        match restore_predicted_result(
            &compilation,
            &outputs,
            !verify,
            &mut action_lookup_attempted,
            learned_enabled,
            &mut learned,
            Some(&mut current_diagnostic),
        ) {
            Ok(Some(cached)) => {
                if verify {
                    verification = Some(cached);
                } else {
                    install_build_script_shim(&invocation, &outputs, &cached.action);
                    let _ = replay_bytes(&cached.stdout, &cached.stderr);
                    return Ok(ExitCode::SUCCESS);
                }
            }
            Ok(None) => {
                prediction_missing = !action_lookup_attempted;
            }
            Err(error) => {
                session::report_shim_warning(&format!("prediction was not restored: {error:#}"));
            }
        }
    }

    // Everything past this point would run the real compiler, so this is
    // where machine-wide coordination starts. The flight comes before the
    // permit: if another build is compiling this exact invocation right now,
    // waiting for its result costs less than any amount of capacity -- and
    // waking from that wait, or finding the prediction a finished flight left
    // behind, is one more chance to restore instead of compile. Never in
    // verify mode, whose whole point is running the compiler.
    let flight = if verify || private_inputs || learned.engaged() {
        None
    } else {
        join_flight(&compilation)
    };
    if let Some(flight) = &flight
        // Only when the payload can say something a lookup this session has
        // not already said: either we waited and it is freshly published, or
        // nothing was ever looked up and it is the first prediction we have.
        && (flight.flight.waited() || !action_lookup_attempted)
        && let Some(payload) = flight.flight.inherited()
    {
        match restore_flight_prediction(
            &compilation,
            &outputs,
            &flight.invocation,
            payload,
            &mut action_lookup_attempted,
            learned_enabled,
            &mut learned,
            Some(&mut current_diagnostic),
        ) {
            Ok(Some(cached)) => {
                install_build_script_shim(&invocation, &outputs, &cached.action);
                let _ = replay_bytes(&cached.stdout, &cached.stderr);
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
    if let Some(flight) = &flight
        // Incremental artifacts are deliberately never published, so they
        // must not acquire a fleet lease whose promise they cannot fulfill.
        && !learned.engaged()
    {
        match session::request_agent(&[AgentRequest::JoinActionPromise {
            adapter: "rustc".into(),
            invocation: flight.invocation.clone(),
        }]) {
            Ok(responses) => match responses.into_iter().next() {
                Some(AgentResponse::ActionPromise {
                    claim: Some(claim),
                    prediction: None,
                }) => remote_claim = Some(claim),
                Some(AgentResponse::ActionPromise {
                    claim: None,
                    prediction: Some(prediction),
                }) if prediction.adapter == "rustc"
                    && prediction.invocation == flight.invocation =>
                {
                    let context = base_action_context(
                        compilation.rustc,
                        compilation.working_dir,
                        compilation.portable,
                    );
                    let restored = context.and_then(|context| {
                        restore_prediction_payload(
                            &compilation,
                            &outputs,
                            context,
                            &flight.invocation,
                            &prediction.payload,
                            Some(&prediction.action),
                            true,
                            &mut action_lookup_attempted,
                            learned_enabled,
                            &mut learned,
                            Some(&mut current_diagnostic),
                        )
                    });
                    match restored {
                        Ok(Some(cached)) => {
                            // Mirror the successful fleet handoff locally:
                            // the remote promise is ephemeral, while this
                            // record survives for the next local flight.
                            flight.flight.leave(&prediction.payload);
                            let _ = replay_bytes(&cached.stdout, &cached.stderr);
                            return Ok(ExitCode::SUCCESS);
                        }
                        Ok(None) => {}
                        Err(error) => session::report_shim_warning(&format!(
                            "a remote flight prediction was not restored: {error:#}"
                        )),
                    }
                }
                Some(AgentResponse::ActionPromise { .. }) => {}
                Some(AgentResponse::Error { message }) => {
                    session::report_shim_warning(&format!(
                        "remote flight coordination failed: {message}"
                    ));
                }
                _ => {}
            },
            Err(error) => {
                session::report_shim_warning(&format!(
                    "remote flight coordination failed: {error:#}"
                ));
            }
        }
    }
    // No usable action key, and now no flight prediction either: this
    // compilation runs without an action-result lookup ever being made, which
    // is not a miss and has to be counted as its own thing or the summary
    // reads as though a lookup happened and found nothing. Recorded here
    // rather than where the prediction came up empty, because a flight can
    // still turn such a compilation into a real lookup.
    if prediction_missing && !action_lookup_attempted {
        session::record_unconsulted();
    }
    // The machine-wide permit is taken after every chance to hit the cache,
    // and before anything expensive starts. The timer starts afterwards: time
    // spent waiting for the machine is not time this compilation cost.
    let demand =
        crate::scheduler::Demand::new(invocation.crate_name(), invocation.links_natively())
            .with_link_profile(&profile_arguments(&arguments));
    let permit = crate::scheduler::pool().and_then(|pool| pool.admit(&demand));
    // Capture these after admission: an edit while this compile waits for
    // capacity happened before rustc ran and belongs to the valid compilation
    // it is about to perform, not to the overlap this snapshot detects.
    let required_inputs = invocation.required_inputs_in(&working_dir);
    let source = working_dir.join(invocation.source());
    let input_snapshots = crate::util::snapshot_compiler_inputs(
        required_inputs.iter().map(PathBuf::as_path),
        Some(&source),
    );
    let compilation_started = SystemTime::now();
    let compiler_timer = Instant::now();
    let mut command = compiler_command(rustc, wrapper_argument);
    command.args(&arguments).current_dir(&working_dir);
    let private_outputs = private_inputs || learned.engaged();
    if let Some(directory) = learned.directory.as_deref() {
        // Appended here rather than to the parsed argument vector: the parser
        // treats incremental state as uncacheable and would bypass the whole
        // compilation, which is the opposite of what this is for.
        let mut flag = OsString::from("-Cincremental=");
        flag.push(directory);
        command.arg(flag);
    }
    if private_outputs {
        // Before the compiler starts, so that a dependent Cargo pipelines
        // behind this unit's metadata already finds the marker in place.
        let root = incremental_root();
        let marked = root
            .as_deref()
            .ok_or_else(|| eyre::eyre!("no private artifact directory is available"))
            .and_then(|root| record_private_artifacts(root, &outputs));
        if let Err(error) = marked {
            if let Some(root) = root.as_deref() {
                forget_private_artifacts(root, &outputs);
            }
            session::report_shim_error(&format!(
                "private artifacts could not be marked: {error:#}"
            ));
            // An Err asks the outer shim to compile transparently. A private
            // consumer must not take that fallback: its own dependents need
            // these markers before Cargo sees any compiler notifications.
            return Ok(ExitCode::FAILURE);
        }
    }
    let forwarded = session::forward_compiler_notifications_requested();
    // An earlier hit may have linked these very paths to the store's objects,
    // which are read-only so that nothing rewrites them in place. rustc would
    // refuse them rather than overwrite them.
    crate::materialize::clear_linked_outputs(
        outputs
            .files
            .iter()
            .chain(std::iter::once(&outputs.dep_info))
            .map(PathBuf::as_path),
    );
    let output = crate::phase_timing::measure("compiler", || {
        run_compiler(
            &mut command,
            forwarded,
            wrapper_argument.is_none() && !invocation.crate_name().starts_with("build_script_"),
        )
    })
    .wrap_err("failed to execute rustc")?;
    // Released before the outputs are read back and published: hashing and
    // storing cost I/O, not the CPU and memory the permit stands for.
    drop(permit);
    crate::scheduler::record_compiler_memory(&demand, &output.status);
    let timing = CompileTiming {
        crate_name: invocation.crate_name().to_string(),
        duration_ns: compiler_timer
            .elapsed()
            .as_nanos()
            .try_into()
            .unwrap_or(u64::MAX),
    };
    // Whether the cache was consulted and whether the result may be stored are
    // separate facts, and one outcome could only carry one of them. A unit
    // re-entering hot workspace state never looks anything up; one whose
    // incremental state arrived from a prediction did, and missed. Reporting
    // both as "incremental" left the summary unable to say which, so a build
    // was either overcounted or the whole class went missing.
    let recorded_outcome = match (
        verification.is_some(),
        learned.engaged(),
        action_lookup_attempted,
    ) {
        (true, _, _) => "verification",
        (_, true, true) => "incremental-miss",
        (_, true, false) => "incremental-unconsulted",
        (_, false, true) => "miss",
        (_, false, false) => "unconsulted",
    };
    if output.status.success()
        && let Some(inputs) = &portable.build_script_inputs
        && let Err(error) = inputs.verify()
    {
        let invalid = discard_modified_compiler_result(&outputs, &input_snapshots, &error)
            || (verification.is_none()
                && validate_compiler_inputs(
                    &invocation,
                    &outputs,
                    &working_dir,
                    &portable,
                    compilation_started,
                    &input_snapshots,
                )
                .is_err_and(|error| {
                    discard_modified_compiler_result(&outputs, &input_snapshots, &error)
                }));
        // A shadow compilation still audits the cached outputs below. That
        // path records the invocation and validates rustc's own dep-info;
        // ordinary bypasses and invalid results finish here instead.
        if invalid || verification.is_none() {
            session::record_compiler_invocation_with_diagnostic(
                recorded_outcome,
                Some(&timing.crate_name),
                timing.duration_ns,
                current_diagnostic.take(),
            );
        }
        if invalid {
            if !forwarded {
                let _ = replay_bytes(&[], &output.stderr);
            }
            return Ok(ExitCode::FAILURE);
        }
        session::report_shim_warning(&format!(
            "build-script inputs were not validated: {error:#}"
        ));
        if verification.is_none() {
            if !forwarded {
                replay_bytes(&output.stdout, &output.stderr)?;
            }
            return Ok(exit_code(output.status));
        }
    }
    if let Some(cached) = verification {
        session::record_compiler_invocation_with_diagnostic(
            recorded_outcome,
            Some(&timing.crate_name),
            timing.duration_ns,
            current_diagnostic,
        );
        if output.status.success()
            && let Err(error) = validate_compiler_inputs(
                &invocation,
                &outputs,
                &working_dir,
                &portable,
                compilation_started,
                &input_snapshots,
            )
        {
            if discard_modified_compiler_result(&outputs, &input_snapshots, &error) {
                // The same reasoning as the discard below the publication
                // path: Cargo may already have read the notification.
                if !forwarded {
                    let _ = replay_bytes(&[], &output.stderr);
                }
                return Ok(ExitCode::FAILURE);
            }
            session::report_shim_warning(&format!(
                "verification inputs were not validated: {error:#}"
            ));
        }
        let divergence = verification_divergence(&cached, &output);
        record_verification(divergence.is_none(), cached.restore);
        if let Some(divergence) = divergence {
            session::report_shim_warning(&crate::materialize::verification_warning(
                "rustc",
                invocation.crate_name(),
                &cached.action,
                &divergence,
            ));
        }
        if !forwarded {
            let _ = replay_output(&output);
        }
        return Ok(exit_code(output.status));
    }
    let mut compiler_input_invalid = false;
    if output.status.success() {
        // A private artifact is never published, and its inputs were
        // already fingerprinted while checking whether the manifest still
        // predicts them. Reuse that discovery to validate the result without
        // rebuilding an action key nobody looks up. A build script still needs
        // that key for its execution shim, and a changed input set needs it to
        // refresh the manifest.
        let current_manifest_inputs =
            if private_outputs && cargo_build_script_executable(&outputs, &invocation).is_none() {
                current_manifest_inputs(&compilation, &outputs)
            } else {
                None
            };
        let publication: Result<Option<ActionDiagnostic>> =
            if let Some(discovered) = current_manifest_inputs {
                (|| {
                    let input_snapshots = input_snapshots
                        .as_ref()
                        .map_err(|error| eyre::eyre!(error.to_string()))?;
                    discovered.verify_not_modified_since_with_snapshots(
                        compilation_started,
                        input_snapshots,
                    )?;
                    discovered.verify()?;
                    learned.record_compiled();
                    Ok(None)
                })()
            } else {
                (|| {
                    let input_snapshots = input_snapshots
                        .as_ref()
                        .map_err(|error| eyre::eyre!(error.to_string()))?;
                    let (candidates, discovered) =
                        match action_from_dep_info(&compilation, &outputs.dep_info) {
                            Ok(keyed) => keyed,
                            Err(error) if is_unshareable_search_path(&error) => {
                                if learned_enabled {
                                    record_compiled_without_action_key(
                                        &compilation,
                                        &outputs,
                                        &learned,
                                        compilation_started,
                                        input_snapshots,
                                    )?;
                                }
                                // Private state is withheld from the store on
                                // purpose, so only a compilation that could
                                // have been stored reports that it was not.
                                return if learned.engaged() {
                                    Ok(None)
                                } else {
                                    Err(error)
                                };
                            }
                            Err(error) => return Err(error),
                        };
                    discovered.verify_not_modified_since_with_snapshots(
                        compilation_started,
                        input_snapshots,
                    )?;
                    discovered.verify()?;
                    learned.record_compiled();
                    if learned_enabled
                        && learned.record.is_none()
                        && source_is_in_workspace(&compilation)
                    {
                        record_learned_baseline(&compilation, &discovered);
                    }
                    // An incremental artifact carries state from this checkout's edit
                    // history, so it is recorded as what the unit currently contains --
                    // which is how the next build notices the churn ended -- but never
                    // published for another checkout to restore. The literal key is
                    // enough for that, and it skips reading the outputs back.
                    let action = if private_outputs {
                        &candidates.literal
                    } else {
                        publish_result(&candidates, &outputs, &output, &portable.mappings)?
                    };
                    install_build_script_shim(&invocation, &outputs, &action.digest);
                    // The flight prediction is only left behind a *published* result:
                    // an incremental artifact was withheld from the store, so a
                    // waiter restoring through its key could only miss.
                    record_prediction(
                        &compilation,
                        &action.digest,
                        &discovered,
                        &timing,
                        flight
                            .as_ref()
                            .filter(|_| !private_outputs)
                            .map(|flight| &flight.flight),
                        remote_claim.as_deref().filter(|_| !private_outputs),
                    );
                    Ok(compilation_action_diagnostic(&compilation, action).ok())
                })()
            };
        match publication {
            Ok(diagnostic) => current_diagnostic = diagnostic,
            Err(error) if discard_modified_compiler_result(&outputs, &input_snapshots, &error) => {
                compiler_input_invalid = true;
            }
            Err(error) => {
                session::report_shim_warning(&format!("result was not stored: {error:#}"));
            }
        }
    }
    session::check_low_disk_after_compile();
    session::record_compiler_invocation_with_diagnostic(
        recorded_outcome,
        Some(&timing.crate_name),
        timing.duration_ns,
        current_diagnostic,
    );
    if compiler_input_invalid {
        // The result was rejected because its inputs moved while rustc read
        // them, and its files are gone. When the output was forwarded live,
        // Cargo has already seen the metadata notification rustc printed on
        // standard error and may have started dependents against the .rmeta.
        // That is wasted work, not a wrong build:
        //
        // - This shim exits non-zero, so Cargo fails the unit, never writes
        //   its fingerprint, and stops scheduling. The unit and everything
        //   above it are dirty on the next build, whether or not a dependent
        //   managed to finish first.
        // - A dependent that did finish read a complete .rmeta: rustc prints
        //   the notification only after writing it. Its tuist_cargo_cache entry is keyed on
        //   the content digest of that exact .rmeta, so the entry answers
        //   only a lookup that presents the same bytes again, for which it is
        //   the right answer. A dependent whose .rmeta was removed before it
        //   was hashed fails to publish instead.
        // - The rejected result itself is never stored, and no prediction or
        //   flight record is left behind pointing at it.
        //
        // The dependent's own input check has to tolerate one thing this
        // overlap makes visible: rustc hardlinks a finished .rmeta into its
        // incremental session directory as it exits, so the file a pipelined
        // dependent snapshotted changes its metadata token without changing a
        // byte. `snapshot_compiler_inputs` therefore snapshots artifacts by
        // content, which still rejects a replaced or rewritten one.
        //
        // Holding the output back until here never changed any of that: the
        // notification travels on standard error, which this branch always
        // replayed. Without forwarding, keep doing so for the diagnostics.
        if !forwarded {
            let _ = replay_bytes(&[], &output.stderr);
        }
        Ok(ExitCode::FAILURE)
    } else {
        // Forwarded output already reached Cargo while rustc ran, so a
        // dependent could start against this crate's metadata before its code
        // generation and this publication finished. Otherwise it goes out now.
        if !forwarded {
            let _ = replay_output(&output);
        }
        Ok(exit_code(output.status))
    }
}

/// Run the compiler and capture both of its streams, forwarding each line to
/// the shim's own stream the moment it arrives when `forward` is set.
///
/// Cargo learns that a crate's metadata is ready from an artifact notification
/// rustc prints on standard error, and starts the crate's dependents against
/// the `.rmeta` while code generation continues. Holding the output until the
/// process exits, as `Command::output` does, serializes that: no dependent can
/// start before this compilation ends and its result is published. The bytes
/// are still captured whole, because a cache entry stores them for replay on a
/// hit and a verification run compares them.
fn run_compiler(command: &mut Command, forward: bool, eligible: bool) -> std::io::Result<Output> {
    let started = SystemTime::now();
    let elapsed = Instant::now();
    let result = if !forward {
        crate::supervision::output(command, eligible)
    } else {
        let action = crate::supervision::prepare(command, eligible);
        run_compiler_forwarding(command, std::io::stdout(), std::io::stderr(), action)
    };
    if let Ok(output) = &result {
        crate::tuist_observer::record_command(
            command,
            started,
            elapsed.elapsed(),
            output.status.success(),
            &output.stderr,
        );
    }
    result
}

/// [`run_compiler`] with the forwarding destinations spelled out, so a test can
/// see what would have reached Cargo.
fn run_compiler_forwarding(
    command: &mut Command,
    stdout_sink: impl Write + Send + 'static,
    stderr_sink: impl Write,
    mut action: Option<crate::supervision::Action>,
) -> std::io::Result<Output> {
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    if let Some(action) = &mut action {
        action.started();
    }
    let stdout = child.stdout.take().expect("stdout was piped");
    let stderr = child.stderr.take().expect("stderr was piped");
    // Standard error carries the diagnostics and the notifications, so it is
    // read here; standard output is drained alongside so that neither pipe
    // can fill up and stall the compiler.
    let stdout = std::thread::spawn(move || forward_stream(stdout, stdout_sink));
    let stderr = forward_stream(stderr, stderr_sink);
    let status = child.wait()?;
    let stdout = stdout
        .join()
        .map_err(|_| std::io::Error::other("the compiler's stdout reader panicked"))??;
    Ok(Output {
        status,
        stdout,
        stderr: stderr?,
    })
}

/// Copy a stream into a buffer, handing each line to `sink` as soon as it is
/// complete. A final line without a newline is forwarded when the stream ends.
///
/// Forwarding is best effort: once the sink fails, the rest of the stream is
/// still captured, because the compiler must be drained for it to finish and
/// its exit status is what decides the build.
fn forward_stream(source: impl Read, mut sink: impl Write) -> std::io::Result<Vec<u8>> {
    let mut reader = BufReader::new(source);
    let mut captured = Vec::new();
    let mut forwarding = true;
    loop {
        let start = captured.len();
        if reader.read_until(b'\n', &mut captured)? == 0 {
            break;
        }
        if forwarding {
            forwarding = sink
                .write_all(&captured[start..])
                .and_then(|()| sink.flush())
                .is_ok();
        }
    }
    Ok(captured)
}

/// Whether publication failed because the compiler's inputs moved underneath it.
///
/// Other publication failures only prevent caching: rustc's local result is
/// still valid and Cargo can use it. A content change or an overlap proved by
/// a pre-compilation file snapshot instead means the artifact cannot be
/// trusted. A timestamp-only overlap remains a conservative cache bypass: it
/// is not reliable enough across skewed filesystem clocks to fail the build.
fn compiler_input_was_modified(
    error: &eyre::Report,
    input_snapshots: &std::io::Result<BTreeMap<PathBuf, FileSnapshot>>,
) -> bool {
    match error.downcast_ref::<BypassReason>() {
        Some(BypassReason::InputChanged(_) | BypassReason::BuildScriptInputsChanged(_)) => true,
        Some(BypassReason::InputModifiedDuringCompilation(path)) => input_snapshots
            .as_ref()
            .ok()
            .and_then(|snapshots| snapshots.get(path))
            .is_some_and(FileSnapshot::proves_content_change),
        _ => false,
    }
}

/// Reject and remove a successful compiler result whose inputs changed while it ran.
fn discard_modified_compiler_result(
    outputs: &RustcOutputs,
    input_snapshots: &std::io::Result<BTreeMap<PathBuf, FileSnapshot>>,
    error: &eyre::Report,
) -> bool {
    if !compiler_input_was_modified(error, input_snapshots) {
        return false;
    }
    if let Err(discard_error) = discard_compiler_outputs(outputs) {
        session::report_shim_warning(&format!(
            "some invalid compiler outputs could not be removed: {discard_error:#}"
        ));
    }
    session::report_shim_error(&format!("compilation result was discarded: {error:#}"));
    true
}

fn validate_compiler_inputs(
    invocation: &RustcInvocation,
    outputs: &RustcOutputs,
    working_dir: &Path,
    portable: &Portable,
    compilation_started: SystemTime,
    input_snapshots: &std::io::Result<BTreeMap<PathBuf, FileSnapshot>>,
) -> Result<()> {
    let input_snapshots = input_snapshots
        .as_ref()
        .map_err(|error| eyre::eyre!(error.to_string()))?;
    let dep_info = RustcDepInfo::read(&outputs.dep_info)?;
    let discovered = invocation.discover_inputs_with_mappings(
        &dep_info,
        working_dir,
        &portable.mappings,
        session::file_digest_cache(),
    )?;
    discovered.verify_not_modified_since_with_snapshots(compilation_started, input_snapshots)?;
    discovered.verify()?;
    Ok(())
}

/// Remove an invalid compiler result before Cargo can consume or fingerprint it.
fn discard_compiler_outputs(outputs: &RustcOutputs) -> Result<()> {
    let mut failures = Vec::new();
    for path in outputs
        .files
        .iter()
        .chain(std::iter::once(&outputs.dep_info))
    {
        match std::fs::remove_file(path) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => failures.push(format!("{}: {error}", path.display())),
        }
    }
    if !failures.is_empty() {
        bail!("{}", failures.join("; "));
    }
    Ok(())
}

/// The arguments rustc effectively sees, with `@argfile` contents inline, for
/// reading code-generation settings out of.
fn profile_arguments(arguments: &[OsString]) -> Vec<OsString> {
    RustcInvocation::expand_arguments(arguments).unwrap_or_else(|_| arguments.to_vec())
}

/// Compile a build script whose native link cannot be action-cached, then
/// install the execution-cache launcher keyed by its compilation action.
fn compile_execution_only_build_script(
    rustc: &OsStr,
    wrapper_argument: Option<&OsStr>,
    arguments: &[OsString],
    working_dir: &Path,
    invocation: &RustcInvocation,
    outputs: &RustcOutputs,
    portable: &Portable,
) -> Result<ExitCode> {
    let demand = crate::scheduler::Demand::new(invocation.crate_name(), true)
        .with_link_profile(&profile_arguments(arguments));
    let permit = crate::scheduler::pool().and_then(|pool| pool.admit(&demand));
    let required_inputs = invocation.required_inputs_in(working_dir);
    let source = working_dir.join(invocation.source());
    let input_snapshots = crate::util::snapshot_compiler_inputs(
        required_inputs.iter().map(PathBuf::as_path),
        Some(&source),
    );
    let compilation_started = SystemTime::now();
    let started = Instant::now();
    let forwarded = session::forward_compiler_notifications_requested();
    let mut command = compiler_command(rustc, wrapper_argument);
    command.args(arguments).current_dir(working_dir);
    crate::materialize::clear_linked_outputs(
        outputs
            .files
            .iter()
            .chain(std::iter::once(&outputs.dep_info))
            .map(PathBuf::as_path),
    );
    let output =
        run_compiler(&mut command, forwarded, false).wrap_err("failed to execute rustc")?;
    drop(permit);
    crate::scheduler::record_compiler_memory(&demand, &output.status);
    session::record_compiler_invocation(
        "bypass",
        Some(invocation.crate_name()),
        started.elapsed().as_nanos().try_into().unwrap_or(u64::MAX),
    );
    if output.status.success()
        && let Err(error) = validate_compiler_inputs(
            invocation,
            outputs,
            working_dir,
            portable,
            compilation_started,
            &input_snapshots,
        )
    {
        if discard_modified_compiler_result(outputs, &input_snapshots, &error) {
            if !forwarded {
                let _ = replay_bytes(&[], &output.stderr);
            }
            session::check_low_disk_after_compile();
            return Ok(ExitCode::FAILURE);
        }
        session::report_shim_warning(&format!(
            "build-script inputs were not validated: {error:#}"
        ));
    }
    if output.status.success()
        && let Some(executable) = cargo_build_script_executable(outputs, invocation)
    {
        let installed = (|| -> Result<()> {
            // Prefer the modeled compilation action. Unlike linked executable
            // bytes on Windows, this is reproducible across equivalent
            // checkouts while still naming every compiler, source,
            // environment, and linker input that can affect the program. If
            // this host's native link cannot be modeled, exact bytes remain a
            // conservative local fallback.
            let modeled = (|| -> Result<CacheDigest> {
                let compilation = Compilation {
                    rustc,
                    invocation,
                    working_dir,
                    portable,
                    linker: linker_for(invocation)?,
                };
                Ok(
                    action_from_current_dep_info(&compilation, &outputs.dep_info)?
                        .0
                        .literal
                        .digest,
                )
            })();
            // Cargo's extra-filename disambiguator distinguishes package units
            // but can vary across equivalent Windows checkouts. The modeled
            // action already contains Cargo's compilation metadata; retain the
            // output name only for the conservative exact-byte fallback, where
            // portability has already been surrendered.
            let output_name = executable
                .file_name()
                .and_then(OsStr::to_str)
                .ok_or_else(|| eyre::eyre!("build-script output name is not UTF-8"))?;
            let binary = match modeled {
                Ok(action) => action,
                Err(_) => {
                    let digest = CacheDigest::blake3_file(executable)
                        .wrap_err("failed to identify the build-script binary")?;
                    CacheDigest::blake3(&canonical_json(&BuildScriptBinaryIdentity {
                        digest: &digest,
                        kind: "build-script-binary",
                        output_name,
                        version: 1,
                    })?)
                }
            };
            crate::build_script::install(executable, &binary)
        })();
        if let Err(error) = installed {
            session::report_shim_warning(&format!(
                "build-script shim was not installed: {error:#}"
            ));
        }
    }
    session::check_low_disk_after_compile();
    if !forwarded {
        let _ = replay_output(&output);
    }
    Ok(exit_code(output.status))
}

/// Whether rustc could load this invocation's bare `--target` name from a
/// custom target specification instead of a built-in target.
///
/// rustc tries its built-in targets first, then `<dir>/<NAME>.json` under each
/// `RUST_TARGET_PATH` directory, then `lib/rustlib/<NAME>/target.json` in the
/// sysroot. A specification found in either place chooses its own
/// static-library file names, so the parser is told not to guess them. A
/// `--target` that is already a path is the parser's own case.
///
/// The sysroot is `--sysroot` when given. Otherwise it is the directory above
/// the compiler's `bin` when that holds a `lib/rustlib`, which is what a
/// toolchain's own rustc sits in; a compiler laid out any other way, such as
/// a rustup proxy at `~/.cargo/bin/rustc`, is asked for its sysroot.
fn custom_target_may_resolve(rustc: &OsStr, arguments: &[OsString]) -> bool {
    let Some(target) = flag_value(arguments, "--target") else {
        return false;
    };
    if target.ends_with(".json") || target.contains(['/', '\\']) {
        return false;
    }
    let under_target_path = std::env::var_os("RUST_TARGET_PATH").is_some_and(|paths| {
        std::env::split_paths(&paths)
            .any(|directory| directory.join(format!("{target}.json")).is_file())
    });
    if under_target_path {
        return true;
    }
    // With no sysroot to look in, the name cannot be proven built in, so it
    // is reported as possibly custom and `-l static` bypasses: the only job
    // of this check is to never guess a file name rustc would not use.
    let Some(sysroot) = flag_value(arguments, "--sysroot")
        .map(PathBuf::from)
        .or_else(|| compiler_sysroot(rustc))
    else {
        return true;
    };
    sysroot
        .join("lib/rustlib")
        .join(&target)
        .join("target.json")
        .is_file()
}

/// The sysroot of the compiler the shim was handed. See
/// [`custom_target_may_resolve`] for the order.
///
/// A compiler whose layout does not show its sysroot is asked for it. That
/// is a rustup proxy at `~/.cargo/bin/rustc`, or any compiler installed
/// apart from its libraries; rustup's own `cargo` puts the toolchain's real
/// `rustc` first on `PATH`, so the usual build never gets here.
fn compiler_sysroot(rustc: &OsStr) -> Option<PathBuf> {
    if let Ok(executable) = resolve_executable(rustc)
        && let Some(root) = executable.parent().and_then(Path::parent)
        && root.join("lib/rustlib").is_dir()
    {
        return Some(root.to_path_buf());
    }
    let output = Command::new(rustc)
        .args(["--print", "sysroot"])
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| PathBuf::from(String::from_utf8_lossy(&output.stdout).trim()))
}

/// The value of `--flag=VALUE` or `--flag VALUE`, whichever comes first.
fn flag_value(arguments: &[OsString], flag: &str) -> Option<String> {
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        if argument == flag {
            return arguments.next()?.to_str().map(str::to_string);
        }
        // A non-UTF-8 argument is skipped, not the end of the scan: the
        // parser refuses the invocation for it later, and the target must
        // still be found so that refusal is the only reason it bypasses.
        if let Some(value) = argument
            .to_str()
            .and_then(|argument| argument.strip_prefix(flag))
            .and_then(|value| value.strip_prefix('='))
        {
            return Some(value.to_string());
        }
    }
    None
}

fn compiler_command(rustc: &OsStr, wrapper_argument: Option<&OsStr>) -> Command {
    let mut command = Command::new(rustc);
    if let Some(argument) = wrapper_argument {
        command.arg(argument);
    }
    command
}

/// The executable Cargo will run as a build script, when this compilation
/// produced one; see [`session::is_cargo_build_script`].
fn cargo_build_script_executable<'a>(
    outputs: &'a RustcOutputs,
    invocation: &RustcInvocation,
) -> Option<&'a Path> {
    outputs
        .build_script_executable(invocation.crate_name())
        .filter(|_| session::is_cargo_build_script(invocation.crate_name()))
}

fn install_build_script_shim(
    invocation: &RustcInvocation,
    outputs: &RustcOutputs,
    binary_action: &CacheDigest,
) {
    if !session::build_script_execution_requested() {
        return;
    }
    let Some(executable) = cargo_build_script_executable(outputs, invocation) else {
        return;
    };
    if let Err(error) = crate::build_script::install(executable, binary_action) {
        session::report_shim_warning(&format!("build-script shim was not installed: {error:#}"));
    }
}

/// Decide whether a missed compilation should carry its own incremental state.
///
/// The comparison is against this crate's own sources, not against its action
/// key: a key also hashes the artifacts the crate links against, so a rebuilt
/// dependency changes it without anybody having touched this crate. Watching
/// the key would send the whole cone above any rebuilt crate hot, including
/// the cone above a dependency that was rebuilt normally and published, whose
/// dependents can publish results other checkouts will restore.
///
/// Unchanged sources are therefore never churn, however the compilation got
/// here. A miss on them means something else lost the result -- a wiped target
/// directory, a first build in this checkout -- and recompiling normally
/// republishes it for everyone. The one exception is decided by the caller:
/// a crate linking an artifact that was itself kept private, see
/// [`links_private_artifact`].
fn learned_plan(
    recorded: Option<&ChurnState>,
    sources: &CacheDigest,
    enabled: bool,
    threshold: u32,
) -> LearnedPlan {
    let streak = match recorded {
        Some(recorded) if recorded.sources == sources.key() => 0,
        // Capped at the threshold: the streak is a state, not a tally, and
        // letting it climb would only delay noticing that the churn stopped.
        Some(recorded) => recorded.streak.saturating_add(1).min(threshold),
        None => 0,
    };
    LearnedPlan {
        hot: enabled && streak >= threshold,
        streak,
        directory: None,
        record: None,
    }
}

/// Where one unit keeps its incremental state.
///
/// A session gives it a persistent per-checkout root outside Cargo's target
/// directory. A standalone shim falls back to its target directory when one is
/// available, and compiles normally when it has nowhere to put state.
fn incremental_directory(invocation: &CacheDigest, crate_name: &str) -> Option<PathBuf> {
    let root = incremental_root()?;
    let key = invocation.key();
    let shard = key.get(..16)?;
    let directory = root.join(shard);
    match prepare_incremental_directory(&directory, session::learned_incremental_max_size()) {
        Ok(discarded) => {
            if let Some(bytes) = discarded {
                // Said out loud: the build goes on to report this compilation
                // as incremental, and a crate whose state is discarded on
                // every edit is indistinguishable from the outside from
                // incremental compilation that simply does not help.
                session::report_shim_warning(&format!(
                    "discarded {} of incremental state for {crate_name}: it passed learned_incremental_max_size, which can be raised to keep it",
                    bytesize::ByteSize::b(bytes).display().iec()
                ));
            }
            Some(directory)
        }
        Err(error) => {
            session::report_shim_warning(&format!("incremental state was not prepared: {error:#}"));
            None
        }
    }
}

/// Make sure the unit's state directory exists and is inside its budget.
///
/// rustc keeps about one session's worth of state per crate and removes the
/// sessions it has superseded, so the state is proportional to the crate rather
/// than to how long it has been edited. The budget is a backstop against state
/// rustc could not clean up, not a ceiling ordinary crates should reach: state
/// discarded before every compile is a full recompilation reported as
/// incremental, the opposite of what it is for. Returns how many bytes were
/// discarded, if any.
fn prepare_incremental_directory(directory: &Path, budget: Option<u64>) -> Result<Option<u64>> {
    let discarded = budget.and_then(|budget| {
        let bytes = directory_bytes(directory);
        (bytes > budget).then_some(bytes)
    });
    if discarded.is_some() {
        std::fs::remove_dir_all(directory)
            .wrap_err("failed to discard oversized incremental state")?;
    }
    std::fs::create_dir_all(directory).wrap_err("failed to create the incremental directory")?;
    Ok(discarded)
}

fn directory_bytes(directory: &Path) -> u64 {
    let mut total = 0;
    let mut pending = vec![directory.to_path_buf()];
    while let Some(next) = pending.pop() {
        let Ok(listing) = std::fs::read_dir(&next) else {
            continue;
        };
        for entry in listing.flatten() {
            let Ok(metadata) = entry.metadata() else {
                continue;
            };
            if metadata.is_dir() {
                pending.push(entry.path());
            } else if metadata.is_file() {
                total += metadata.len();
            }
        }
    }
    total
}

/// Work out the plan for a compilation that is about to miss.
///
/// Reads what this checkout last compiled for the unit, decides, and records
/// what it is about to compile now. A checkout with nowhere to keep that -- a
/// shim running without a session -- compiles normally.
fn plan_learned_reuse(
    compilation: &Compilation<'_>,
    discovered: &DiscoveredInputs,
    enabled: bool,
) -> LearnedPlan {
    let planned = (|| {
        let sources = compilation.invocation.source_fingerprint(discovered);
        let context = base_action_context(
            compilation.rustc,
            compilation.working_dir,
            compilation.portable,
        )?;
        let unit = compilation.invocation.invocation_digest(&context)?;
        let Some(state_path) = churn_state_path(&unit) else {
            return Result::<LearnedPlan>::Ok(LearnedPlan::default());
        };
        let threshold = if source_is_in_workspace(compilation) {
            WORKSPACE_HOT_STREAK_THRESHOLD
        } else {
            HOT_STREAK_THRESHOLD
        };
        let plan = learned_plan(
            read_churn_state(&state_path).as_ref(),
            &sources,
            enabled,
            threshold,
        );
        let hot = plan.hot || (enabled && links_private_artifact(compilation));
        Ok(LearnedPlan {
            hot,
            record: Some((state_path, sources)),
            ..plan
        }
        .resolved(&unit, compilation.invocation.crate_name()))
    })();
    match planned {
        Ok(plan) => plan,
        Err(error) => {
            session::report_shim_warning(&format!(
                "churn was not tracked for this crate: {error:#}"
            ));
            LearnedPlan::default()
        }
    }
}

/// Whether a native search directory kept the compilation from being described
/// to the shared cache: one the cache cannot model, or one holding an entry
/// that cannot be read, such as a dangling symlink rustc never touched. Source
/// discovery then runs without the directory, so a real read failure of a
/// source file still surfaces from it.
fn is_unshareable_search_path(error: &eyre::Report) -> bool {
    matches!(
        error.downcast_ref::<BypassReason>(),
        Some(BypassReason::UnsupportedSearchPath(_) | BypassReason::InputRead { .. })
    )
}

/// The inputs a churn decision compares, which are the crate's own sources.
///
/// Native search directories are part of a shared key but not of that
/// question, and some can never be part of one: a system directory holding
/// symlinks into other trees, for instance, which a build script reaches through
/// pkg-config. Falling back to the sources alone keeps those crates' edits
/// recognizable, so they can still switch to private incremental state.
fn discover_for_churn(
    compilation: &Compilation<'_>,
    dep_info: &RustcDepInfo,
) -> Result<DiscoveredInputs> {
    match compilation.invocation.discover_inputs_with_mappings(
        dep_info,
        compilation.working_dir,
        &compilation.portable.mappings,
        session::file_digest_cache(),
    ) {
        Err(BypassReason::UnsupportedSearchPath(_) | BypassReason::InputRead { .. }) => {
            Ok(compilation.invocation.discover_source_inputs(
                dep_info,
                compilation.working_dir,
                session::file_digest_cache(),
            )?)
        }
        discovered => Ok(discovered?),
    }
}

/// [`plan_learned_reuse`] for a workspace unit whose action key could not be
/// built, so there is no lookup to take its inputs from.
fn plan_learned_without_action_key(
    compilation: &Compilation<'_>,
    outputs: &RustcOutputs,
) -> LearnedPlan {
    if !source_is_in_workspace(compilation) {
        return LearnedPlan::default();
    }
    let discovered = RustcDepInfo::read(&outputs.dep_info)
        .map_err(eyre::Report::from)
        .and_then(|dep_info| {
            verify_environment(&dep_info.environment)?;
            Ok(compilation.invocation.discover_source_inputs(
                &dep_info,
                compilation.working_dir,
                session::file_digest_cache(),
            )?)
        });
    match discovered {
        Ok(discovered) => plan_learned_reuse(compilation, &discovered, true),
        Err(error) => {
            session::report_shim_warning(&format!(
                "churn was not tracked for this crate: {error:#}"
            ));
            LearnedPlan::default()
        }
    }
}

/// Record what a workspace unit compiled when the compilation could not be
/// keyed for the cache, as [`LearnedPlan::record_compiled`] does for one that
/// could.
fn record_compiled_without_action_key(
    compilation: &Compilation<'_>,
    outputs: &RustcOutputs,
    learned: &LearnedPlan,
    started: SystemTime,
    snapshots: &BTreeMap<PathBuf, FileSnapshot>,
) -> Result<()> {
    if !source_is_in_workspace(compilation) {
        return Ok(());
    }
    let dep_info = RustcDepInfo::read(&outputs.dep_info)?;
    let discovered = compilation.invocation.discover_source_inputs(
        &dep_info,
        compilation.working_dir,
        session::file_digest_cache(),
    )?;
    discovered.verify_not_modified_since_with_snapshots(started, snapshots)?;
    discovered.verify()?;
    learned.record_compiled();
    if learned.record.is_none() {
        record_learned_baseline(compilation, &discovered);
    }
    Ok(())
}

/// Eager builds and consumers of private artifacts can prepare state before any source
/// edits, including when Cargo's target directory has been discarded. Units
/// linking private artifacts must stay private too, even outside the workspace.
fn eager_incremental_plan(compilation: &Compilation<'_>) -> LearnedPlan {
    if !source_is_in_workspace(compilation) && !links_private_artifact(compilation) {
        return LearnedPlan::default();
    }
    let planned = (|| {
        let context = base_action_context(
            compilation.rustc,
            compilation.working_dir,
            compilation.portable,
        )?;
        let unit = compilation.invocation.invocation_digest(&context)?;
        Ok::<_, eyre::Report>(
            LearnedPlan {
                hot: true,
                ..LearnedPlan::default()
            }
            .resolved(&unit, compilation.invocation.crate_name()),
        )
    })();
    planned.unwrap_or_else(|error| {
        session::report_shim_warning(&format!(
            "eager incremental state was not prepared: {error:#}"
        ));
        LearnedPlan::default()
    })
}

/// Re-enter a workspace unit's established private state without rebuilding a
/// shared action key first.
///
/// An intact dep-info file supplies the source fingerprint without constructing
/// a shared action. A missing target, settled source, or changed environment
/// deliberately takes the slower path so it can restore or republish. Settled
/// sources above a private artifact are the exception: no shared action can
/// describe what they link, so the lookup would only ever miss.
fn reuse_hot_workspace_plan(
    compilation: &Compilation<'_>,
    outputs: &RustcOutputs,
    enabled: bool,
) -> LearnedPlan {
    if !enabled || !outputs.dep_info.is_file() || !source_is_in_workspace(compilation) {
        return LearnedPlan::default();
    }
    let planned = (|| {
        let context = base_action_context(
            compilation.rustc,
            compilation.working_dir,
            compilation.portable,
        )?;
        let unit = compilation.invocation.invocation_digest(&context)?;
        let Some(state_path) = churn_state_path(&unit) else {
            return Result::<LearnedPlan>::Ok(LearnedPlan::default());
        };
        let Some(recorded) = read_churn_state(&state_path) else {
            return Ok(LearnedPlan::default());
        };
        let dep_info = RustcDepInfo::read(&outputs.dep_info)?;
        verify_environment(&dep_info.environment)?;
        let discovered = discover_for_churn(compilation, &dep_info)?;
        let sources = compilation.invocation.source_fingerprint(&discovered);
        let changed = recorded.sources != sources.key();
        let edited = changed && recorded.streak >= WORKSPACE_HOT_STREAK_THRESHOLD;
        if !edited && !links_private_artifact(compilation) {
            return Ok(LearnedPlan::default());
        }
        // The streak keeps counting this unit's own sources, as the slower
        // path would: a unit riding along on a private artifact with settled
        // sources records no churn of its own.
        let streak = if changed {
            recorded
                .streak
                .saturating_add(1)
                .min(WORKSPACE_HOT_STREAK_THRESHOLD)
        } else {
            0
        };
        Ok(LearnedPlan {
            hot: true,
            streak,
            directory: None,
            record: Some((state_path, sources)),
        }
        .resolved(&unit, compilation.invocation.crate_name()))
    })();
    match planned {
        Ok(plan) => plan,
        Err(error) => {
            session::report_shim_warning(&format!("incremental state was not reused: {error:#}"));
            LearnedPlan::default()
        }
    }
}

/// Inputs from dep-info when they still match this unit's manifest prediction.
///
/// The payload is paths and environment names, never digests, so the common
/// edit, the one that changes a file's contents and nothing else, leaves it
/// current. Only an edit that changed which files the crate reads makes the
/// caller record a fresh one, and it pays the full read-back for that.
fn current_manifest_inputs(
    compilation: &Compilation<'_>,
    outputs: &RustcOutputs,
) -> Option<DiscoveredInputs> {
    let current = (|| -> Result<Option<DiscoveredInputs>> {
        let context = base_action_context(
            compilation.rustc,
            compilation.working_dir,
            compilation.portable,
        )?;
        let invocation_digest = compilation.invocation.invocation_digest(&context)?;
        let responses = session::request_agent(&[AgentRequest::FindActionPrediction {
            task: prediction_task(&invocation_digest),
            invocation: invocation_digest.clone(),
        }])?;
        let Some(AgentResponse::ActionPrediction {
            prediction: Some(prediction),
        }) = responses.into_iter().next()
        else {
            return Ok(None);
        };
        if prediction.adapter != "rustc" || prediction.invocation != invocation_digest {
            return Ok(None);
        }
        let recorded: RustcInputPrediction = serde_json::from_str(&prediction.payload)?;
        let dep_info = RustcDepInfo::read(&outputs.dep_info)?;
        let discovered = compilation.invocation.discover_inputs_with_mappings(
            &dep_info,
            compilation.working_dir,
            &compilation.portable.mappings,
            session::file_digest_cache(),
        )?;
        let now = compilation.invocation.prediction(&context, &discovered)?;
        Ok(
            (now.inputs == recorded.inputs && now.environment == recorded.environment)
                .then_some(discovered),
        )
    })();
    current.ok().flatten()
}

/// Whether the crate root belongs to the checkout Cargo is building.
fn source_is_in_workspace(compilation: &Compilation<'_>) -> bool {
    let Some(root) = std::env::var_os(session::WORKSPACE_ROOT_ENV).map(PathBuf::from) else {
        return false;
    };
    let source = compilation.invocation.source();
    let source = if source.is_absolute() {
        source.to_path_buf()
    } else {
        compilation.working_dir.join(source)
    };
    let root = std::fs::canonicalize(&root).unwrap_or(root);
    let source = std::fs::canonicalize(&source).unwrap_or(source);
    source.starts_with(root)
}

/// Establish the baseline after a first successful compilation, when dep-info
/// finally supplies the complete set of sources. The next edit can then be
/// recognized immediately.
fn record_learned_baseline(compilation: &Compilation<'_>, discovered: &DiscoveredInputs) {
    let recorded = (|| {
        let context = base_action_context(
            compilation.rustc,
            compilation.working_dir,
            compilation.portable,
        )?;
        let unit = compilation.invocation.invocation_digest(&context)?;
        let Some(path) = churn_state_path(&unit) else {
            return Result::<()>::Ok(());
        };
        let sources = compilation.invocation.source_fingerprint(discovered);
        if read_churn_state(&path)
            .is_some_and(|recorded| recorded.sources == sources.key() && recorded.streak == 0)
        {
            return Ok(());
        }
        write_churn_state(&path, &sources, 0)
    })();
    if let Err(error) = recorded {
        session::report_shim_warning(&format!("initial churn state was not recorded: {error:#}"));
    }
}

/// Where this checkout records what it last compiled for one unit.
///
/// A sibling of the unit's incremental directory, so the decision and the
/// state survive or disappear together.
fn churn_state_path(unit: &CacheDigest) -> Option<PathBuf> {
    let root = incremental_root()?;
    let key = unit.key();
    let shard = key.get(..16)?;
    Some(root.join(format!("{shard}.json")))
}

/// Persistent per-checkout storage for learned incremental state. Sessions
/// keep it outside Cargo's target directory so `cargo clean` does not erase the
/// edit history it is meant to accelerate. Standalone shims retain the older
/// target-local fallback because they have no configured cache root.
fn incremental_root() -> Option<PathBuf> {
    std::env::var_os(session::INCREMENTAL_ROOT_ENV)
        .or_else(|| {
            std::env::var_os(session::TARGET_DIR_ENV).map(|target| {
                PathBuf::from(target)
                    .join("tuist_cargo_cache-incremental")
                    .into_os_string()
            })
        })
        .map(PathBuf::from)
}

/// Where the marker for one output path lives, beside the churn records.
fn private_artifact_path(root: &Path, artifact: &Path) -> Option<PathBuf> {
    let key = CacheDigest::blake3(artifact.as_os_str().as_encoded_bytes()).key();
    let shard = key.get(..16)?;
    Some(root.join("private").join(format!("{shard}.json")))
}

/// Mark every output of a compilation about to run with private incremental
/// state, so the crates that link them know not to publish either.
fn record_private_artifacts(root: &Path, outputs: &RustcOutputs) -> Result<()> {
    for artifact in &outputs.files {
        let Some(path) = private_artifact_path(root, artifact) else {
            continue;
        };
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .wrap_err("failed to create the private artifact directory")?;
        }
        let marker = PrivateArtifact {
            version: PRIVATE_ARTIFACT_VERSION,
            path: artifact.clone(),
        };
        crate::util::write_advisory(&path, &serde_json::to_vec(&marker)?)
            .wrap_err_with(|| format!("failed to mark {} as private", artifact.display()))?;
    }
    Ok(())
}

/// Withdraw the markers for outputs this compilation is about to replace.
///
/// Best effort: a marker that cannot be removed costs the crates above one
/// publication they could have made, never a wrong result.
fn forget_private_artifacts(root: &Path, outputs: &RustcOutputs) {
    for artifact in &outputs.files {
        if let Some(path) = private_artifact_path(root, artifact)
            && let Err(error) = std::fs::remove_file(&path)
            && error.kind() != std::io::ErrorKind::NotFound
        {
            session::report_shim_warning(&format!(
                "a private artifact marker was not removed for {}: {error}",
                artifact.display()
            ));
        }
    }
}

/// Whether this compilation links an artifact another unit kept private.
///
/// A private artifact describes one checkout's edit history, so an action
/// keyed on it can never be restored anywhere else: compiling normally here
/// would pay for a full compilation and a publication nobody can use. Taking
/// private state instead costs nothing that was available, and gives the edit
/// loop above an edited dependency the same reuse the dependency itself gets.
fn links_private_artifact(compilation: &Compilation<'_>) -> bool {
    let Some(root) = incremental_root() else {
        return false;
    };
    let inputs = compilation
        .invocation
        .required_inputs_in(compilation.working_dir);
    links_private_artifact_in(&root, &inputs)
}

fn links_private_artifact_in(root: &Path, inputs: &[PathBuf]) -> bool {
    inputs.iter().any(|input| {
        private_artifact_path(root, input)
            .and_then(|path| std::fs::read(path).ok())
            .and_then(|bytes| serde_json::from_slice::<PrivateArtifact>(&bytes).ok())
            .is_some_and(|marker| {
                marker.version == PRIVATE_ARTIFACT_VERSION && marker.path == *input
            })
    })
}

/// A record this version cannot read is treated as no record: the cost is one
/// compilation that does not count toward a streak.
fn read_churn_state(path: &Path) -> Option<ChurnState> {
    let bytes = std::fs::read(path).ok()?;
    serde_json::from_slice::<ChurnState>(&bytes)
        .ok()
        .filter(|state| state.version == CHURN_STATE_VERSION)
}

fn write_churn_state(path: &Path, sources: &CacheDigest, streak: u32) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .wrap_err("failed to create the incremental state directory")?;
    }
    let state = ChurnState {
        version: CHURN_STATE_VERSION,
        sources: sources.key(),
        streak,
    };
    crate::util::write_advisory(path, &serde_json::to_vec(&state)?)
        .wrap_err("failed to record what this crate last compiled")
}

fn restore_predicted_result(
    compilation: &Compilation<'_>,
    outputs: &RustcOutputs,
    restore_outputs: bool,
    action_lookup_attempted: &mut bool,
    learned_enabled: bool,
    learned: &mut LearnedPlan,
    diagnostic: Option<&mut Option<ActionDiagnostic>>,
) -> Result<Option<CachedCompilation>> {
    let Compilation {
        invocation,
        working_dir,
        portable,
        ..
    } = compilation;
    let context = base_action_context(compilation.rustc, working_dir, portable)?;
    let invocation_digest = invocation.invocation_digest(&context)?;
    let task = prediction_task(&invocation_digest);
    let responses = session::request_agent(&[AgentRequest::FindActionPrediction {
        task,
        invocation: invocation_digest.clone(),
    }])?;
    let Some(response) = responses.into_iter().next() else {
        bail!("cache agent did not return an action prediction response");
    };
    let prediction = match response {
        AgentResponse::ActionPrediction {
            prediction: Some(prediction),
        } => prediction,
        AgentResponse::ActionPrediction { prediction: None } => {
            // No usable action key: either no dep-info from an earlier build or
            // dep-info that did not yield one, and now no prediction either.
            // Whether that leaves the compilation unconsulted is decided by
            // the caller, after the flight has had its chance to look it up.
            return Ok(None);
        }
        AgentResponse::Error { message } => bail!(message),
        _ => bail!("cache agent returned an unexpected action prediction response"),
    };
    if prediction.adapter != "rustc" || prediction.invocation != invocation_digest {
        bail!("cache agent returned an incompatible rustc action prediction");
    }
    restore_prediction_payload(
        compilation,
        outputs,
        context,
        &invocation_digest,
        &prediction.payload,
        // A manifest prediction intentionally survives source changes: its
        // payload is rehashed to derive the action for the current inputs.
        // Only a completed remote promise must still name the exact action it
        // promised before any of that action's outputs may be materialized.
        None,
        restore_outputs,
        action_lookup_attempted,
        learned_enabled,
        learned,
        diagnostic,
    )
}

/// Rebuild the action key from one prediction payload and restore through it.
///
/// Shared by the manifest path and the flight path: both hold a payload of
/// predicted inputs, and everything after that -- rehashing them, building
/// the candidates, the lookup itself -- has to be identical, or the two
/// paths would drift in what they accept.
#[allow(clippy::too_many_arguments)]
fn restore_prediction_payload(
    compilation: &Compilation<'_>,
    outputs: &RustcOutputs,
    mut context: ActionContext,
    invocation_digest: &CacheDigest,
    payload: &str,
    expected_action: Option<&CacheDigest>,
    restore_outputs: bool,
    action_lookup_attempted: &mut bool,
    learned_enabled: bool,
    learned: &mut LearnedPlan,
    diagnostic: Option<&mut Option<ActionDiagnostic>>,
) -> Result<Option<CachedCompilation>> {
    let _phase = crate::phase_timing::phase("key");
    let Compilation {
        invocation,
        working_dir,
        portable,
        ..
    } = compilation;
    let input_prediction: RustcInputPrediction = serde_json::from_str(payload)?;
    if String::from_utf8(canonical_json(&input_prediction)?)? != payload {
        bail!("the rustc action prediction is not canonical");
    }
    let discovered = input_prediction.discover(
        working_dir,
        &context.path_mappings,
        session::file_digest_cache(),
    )?;
    discovered.clone().apply_to(&mut context)?;
    let candidates = ActionCandidates::build(invocation, context, compilation.linker.clone())?;
    if let Some(diagnostic) = diagnostic {
        *diagnostic = candidates
            .ordered()
            .next()
            .and_then(|action| compilation_action_diagnostic(compilation, action).ok());
    }
    if expected_action.is_some_and(|expected| !candidates.contains(expected)) {
        bail!("the action prediction no longer matches its predicted inputs");
    }
    // From this point onward, every return follows at least one action-result
    // request, including error responses from a corrupt local record.
    *action_lookup_attempted = true;
    let restored = restore_candidates(
        &candidates,
        outputs,
        &discovered,
        restore_outputs,
        &portable.mappings,
    )?;
    match restored {
        Some((action, mut cached)) => {
            cached.restore.avoided_compiler_duration_ns = input_prediction.compiler_duration_ns;
            if learned_enabled && source_is_in_workspace(compilation) {
                record_learned_baseline(compilation, &discovered);
            }
            if restore_outputs {
                let diagnostic = candidates
                    .ordered()
                    .find(|candidate| candidate.digest == action)
                    .and_then(|candidate| {
                        compilation_action_diagnostic(compilation, candidate).ok()
                    });
                record_action_hit_with_diagnostic(
                    &action,
                    cached.restore,
                    invocation.crate_name(),
                    diagnostic,
                );
            }
            // Re-record even an identical manifest prediction: the cumulative
            // manifest already inherits it, but this run's build receipt must
            // say that the restored action was actually used.
            record_prediction_value(
                invocation_digest.clone(),
                action,
                payload.to_string(),
                invocation.crate_name(),
            );
            Ok(Some(cached))
        }
        None => {
            // A plan an earlier lookup already made carries this checkout's
            // churn record; replacing it would only repeat the work.
            if learned.record.is_none() {
                *learned = plan_learned_reuse(compilation, &discovered, learned_enabled);
            }
            Ok(None)
        }
    }
}

/// The keys one compilation may be published under, most portable first.
///
/// A compilation whose environment holds nothing portable has exactly one key,
/// the literal one, which is what every action looked like before
/// [`Portable`] existed.
struct ActionCandidates {
    /// The key this compilation is published under and looked up by.
    literal: RustcAction,
}

impl ActionCandidates {
    fn build(
        invocation: &RustcInvocation,
        context: ActionContext,
        linker: Option<LinkerIdentity>,
    ) -> Result<Self> {
        Ok(Self {
            literal: invocation.action_linked_by(context, linker)?,
        })
    }

    fn contains(&self, digest: &CacheDigest) -> bool {
        &self.literal.digest == digest
    }

    /// The key this compilation is published under.
    fn publishable(&self) -> &RustcAction {
        &self.literal
    }

    /// Every key to look up.
    ///
    /// One, since a compilation that reads a remapped value is keyed for the
    /// checkout it ran in. It was two while a second, checkout-independent key
    /// was offered as well, and the pair is what let one checkout's artifact be
    /// restored into another.
    fn ordered(&self) -> impl Iterator<Item = &RustcAction> {
        std::iter::once(&self.literal)
    }
}

/// Split a canonical rustc action into named hashes suitable for session
/// history. The hashes preserve comparison fidelity without retaining source
/// contents or environment values.
fn compilation_action_diagnostic(
    compilation: &Compilation<'_>,
    action: &RustcAction,
) -> Result<ActionDiagnostic> {
    let source = normalize_mapped_path(
        compilation.invocation.source(),
        compilation.working_dir,
        &PathMapping::ordered(&compilation.portable.mappings),
    )?;
    action_diagnostic(action, &source)
}

fn action_diagnostic(action: &RustcAction, source: &str) -> Result<ActionDiagnostic> {
    let mut descriptor: serde_json::Map<String, serde_json::Value> =
        serde_json::from_slice(&action.bytes)?;
    let mut components = BTreeMap::new();

    if let Some(serde_json::Value::Object(compiler)) = descriptor.remove("compiler") {
        for (name, value) in compiler {
            components.insert(
                format!("compiler {}", name.replace('_', " ")),
                CacheDigest::blake3(&canonical_json(&value)?),
            );
        }
    }
    if let Some(serde_json::Value::Array(arguments)) = descriptor.remove("arguments") {
        let unit_arguments = arguments
            .iter()
            .filter(|value| {
                value.as_str().is_some_and(|argument| {
                    argument == "--test"
                        || ["--crate-name=", "--crate-type=", "--target="]
                            .iter()
                            .any(|prefix| argument.starts_with(prefix))
                })
            })
            .collect::<Vec<_>>();
        components.insert(
            "compilation unit".into(),
            CacheDigest::blake3(&canonical_json(&(source, unit_arguments))?),
        );
        let mut occurrences = BTreeMap::<String, usize>::new();
        for (index, value) in arguments.into_iter().enumerate() {
            let base = value
                .as_str()
                .filter(|argument| argument.starts_with('-'))
                .map(|argument| {
                    let argument = argument.trim_start_matches('-');
                    let (flag, value) = argument.split_once('=').unwrap_or((argument, ""));
                    let nested = matches!(flag, "C" | "Z" | "codegen")
                        .then(|| value.split_once('=').map_or(value, |(name, _)| name))
                        .filter(|name| !name.is_empty());
                    nested.map_or_else(
                        || format!("argument --{flag}"),
                        |name| format!("argument --{flag} {name}"),
                    )
                })
                .unwrap_or_else(|| format!("argument #{}", index + 1));
            let occurrence = occurrences.entry(base.clone()).or_default();
            *occurrence += 1;
            let name = if *occurrence == 1 {
                base
            } else {
                format!("{base} #{}", *occurrence)
            };
            components.insert(name, CacheDigest::blake3(&canonical_json(&value)?));
        }
    }
    if let Some(serde_json::Value::Object(linker)) = descriptor.remove("linker") {
        for (name, value) in linker {
            components.insert(
                format!("linker {}", name.replace('_', " ")),
                CacheDigest::blake3(&canonical_json(&value)?),
            );
        }
    }
    if let Some(serde_json::Value::Object(environment)) = descriptor.remove("environment") {
        for (name, value) in environment {
            components.insert(
                format!("environment {name}"),
                CacheDigest::blake3(&canonical_json(&value)?),
            );
        }
    }

    let mut inputs = BTreeMap::new();
    if let Some(serde_json::Value::Array(entries)) = descriptor.remove("inputs") {
        for entry in entries {
            let Some(entry) = entry.as_object() else {
                continue;
            };
            let Some(path) = entry.get("path").and_then(serde_json::Value::as_str) else {
                continue;
            };
            let Some(digest) = entry.get("digest") else {
                continue;
            };
            inputs.insert(path.to_string(), serde_json::from_value(digest.clone())?);
        }
    }

    // Version, kind, and adapter version rarely move, but when they do they
    // are the reason every otherwise-identical key changed.
    components.insert(
        "action model".into(),
        CacheDigest::blake3(&canonical_json(&descriptor)?),
    );
    Ok(ActionDiagnostic {
        action: action.digest.clone(),
        components,
        inputs,
    })
}

/// Try each candidate key, returning the digest that hit alongside its result.
///
/// Both keys are tried because either shape may be on the other side of the
/// lookup: a crate that keeps `OUT_DIR` in a string was published literally,
/// and without the second lookup it would never hit, not even in the checkout
/// that compiled it.
fn restore_candidates(
    candidates: &ActionCandidates,
    outputs: &RustcOutputs,
    discovered: &DiscoveredInputs,
    restore_outputs: bool,
    mappings: &[PathMapping],
) -> Result<Option<(CacheDigest, CachedCompilation)>> {
    for action in candidates.ordered() {
        if let Some(cached) =
            restore_result(action, outputs, discovered, restore_outputs, mappings)?
        {
            return Ok(Some((action.digest.clone(), cached)));
        }
    }
    Ok(None)
}

fn action_from_dep_info(
    compilation: &Compilation<'_>,
    dep_info: &Path,
) -> Result<(ActionCandidates, DiscoveredInputs)> {
    let dep_info = RustcDepInfo::read(dep_info)?;
    action_from_parsed_dep_info(compilation, &dep_info)
}

fn action_from_current_dep_info(
    compilation: &Compilation<'_>,
    dep_info: &Path,
) -> Result<(ActionCandidates, DiscoveredInputs)> {
    let dep_info = RustcDepInfo::read(dep_info)?;
    verify_environment(&dep_info.environment)?;
    action_from_parsed_dep_info(compilation, &dep_info)
}

fn action_from_parsed_dep_info(
    compilation: &Compilation<'_>,
    dep_info: &RustcDepInfo,
) -> Result<(ActionCandidates, DiscoveredInputs)> {
    let _phase = crate::phase_timing::phase("key");
    let Compilation {
        invocation,
        working_dir,
        portable,
        ..
    } = compilation;
    let discovered = invocation.discover_inputs_with_mappings(
        dep_info,
        working_dir,
        &portable.mappings,
        session::file_digest_cache(),
    )?;
    let mut context = base_action_context(compilation.rustc, working_dir, portable)?;
    discovered.clone().apply_to(&mut context)?;
    let candidates = ActionCandidates::build(invocation, context, compilation.linker.clone())?;
    Ok((candidates, discovered))
}

/// Build the shared key context for dep-info and prediction lookups, including
/// the build-script input signature captured before OUT_DIR stabilization.
fn base_action_context(
    rustc: &OsStr,
    working_dir: &Path,
    portable: &Portable,
) -> Result<ActionContext> {
    let _phase = crate::phase_timing::phase("key");
    let compiler = compiler_identity(rustc)?;
    let mut context = ActionContext {
        compiler,
        working_dir: working_dir.to_path_buf(),
        path_mappings: portable.mappings.clone(),
        environment: compiler_environment(|name| std::env::var(name).ok()),
        portable_environment: BTreeSet::new(),
        inputs: Vec::new(),
    };
    if let Some(inputs) = &portable.build_script_inputs {
        context.inputs.push(inputs.input.clone());
    }
    if Path::new(rustc).file_stem() == Some(OsStr::new("clippy-driver"))
        && let Some(path) = selected_clippy_config(working_dir)
    {
        context.inputs.push(ActionInput {
            digest: CacheDigest::blake3_file(&path)?,
            path,
        });
    }
    Ok(context)
}

/// Variables rustc reads itself rather than through `env!`, so dep-info never
/// records them, yet they change what a compilation produces.
///
/// `RUSTC_BOOTSTRAP` decides whether unstable features and `-Z` flags are
/// accepted, and how diagnostics describe them. Cargo sets it for every
/// standard library unit under `-Zbuild-std`, alongside
/// `-Zforce-unstable-if-unmarked`.
const COMPILER_ENVIRONMENT: [&str; 1] = ["RUSTC_BOOTSTRAP"];

/// The [`COMPILER_ENVIRONMENT`] values this compilation runs with.
///
/// Only a set variable enters the key, so a compilation that sets none keeps
/// the key it always had. A value that is not UTF-8 is left out, matching
/// rustc, which reads these with `std::env::var` and treats that as unset.
fn compiler_environment(
    lookup: impl Fn(&str) -> Option<String>,
) -> BTreeMap<String, Option<String>> {
    COMPILER_ENVIRONMENT
        .into_iter()
        .filter_map(|name| lookup(name).map(|value| (name.into(), Some(value))))
        .collect()
}

/// Find the config Clippy would load before consulting stale dep-info.
///
/// Clippy records a loaded config in dep-info, but absence cannot be recorded.
/// Looking it up while constructing the base context makes a newly added or
/// newly higher-priority config change the action before an old result can be
/// restored.
fn selected_clippy_config(working_dir: &Path) -> Option<PathBuf> {
    let start = std::env::var_os("CLIPPY_CONF_DIR")
        .or_else(|| std::env::var_os("CARGO_MANIFEST_DIR"))
        .map_or_else(|| working_dir.to_path_buf(), PathBuf::from);
    let mut directory = std::fs::canonicalize(start).ok()?;
    loop {
        for name in [".clippy.toml", "clippy.toml"] {
            let path = directory.join(name);
            if path.is_file() {
                return Some(path);
            }
        }
        if !directory.pop() {
            return None;
        }
    }
}

/// Identify the linker, for the invocations whose key has to describe it.
///
/// Only a native link needs one, and probing costs several processes on the
/// first one, so nothing else pays for it.
///
/// A host that cannot be described is reported as a bypass rather than as a
/// failure: not knowing the linker is a reason this compilation cannot be
/// cached, which is what a bypass is, and reporting it as anything else leaves
/// it out of the summary and out of `tuist_cargo_cache explain`.
/// Ask ld64 to strip this build's output directory from the debug map.
///
/// On macOS a linked binary records the absolute path and timestamp of every
/// object behind it, which is what makes a debug-info link unportable across
/// checkouts. The target root covers both the executable's output directory
/// and its dependencies, including sibling directories for examples. When
/// native links are being cached on this platform, the shim appends the
/// prefix itself rather than asking anyone to discover it. An invocation that
/// already carries one keeps what its caller chose, and an invocation without
/// an output directory has no linker to hand this to.
///
/// Read straight off the argument list, because this runs before anything
/// parses: the parser's own debug-map rule is exactly what the flag
/// satisfies, so it has to be present going in.
fn with_oso_prefix(arguments: &[OsString], cache_links: bool) -> Cow<'_, [OsString]> {
    if !cfg!(target_os = "macos") || !cache_links {
        return Cow::Borrowed(arguments);
    }
    let mut out_dir = None;
    for (index, argument) in arguments.iter().enumerate() {
        let Some(argument) = argument.to_str() else {
            continue;
        };
        if argument.contains("-oso_prefix,") {
            return Cow::Borrowed(arguments);
        }
        // Only a host link is ld64's to read. An explicit `--target` never
        // classifies as one -- wasm links in particular stay cacheable -- and
        // handing those invocations this flag would turn it into the
        // unmodeled link argument that bypasses them.
        if argument == "--target" || argument.starts_with("--target=") {
            return Cow::Borrowed(arguments);
        }
        if argument == "--out-dir" {
            out_dir = arguments.get(index + 1).map(PathBuf::from);
        } else if let Some(value) = argument.strip_prefix("--out-dir=") {
            out_dir = Some(PathBuf::from(value));
        }
    }
    let Some(out_dir) = out_dir.filter(|out_dir| out_dir.is_absolute()) else {
        return Cow::Borrowed(arguments);
    };
    // Examples link rlibs from the sibling deps directory, and build scripts
    // can live further below build/. Strip the shared target root rather than
    // only the directory receiving this particular executable.
    let prefix = std::env::var_os(session::TARGET_DIR_ENV)
        .map(PathBuf::from)
        .filter(|root| root.is_absolute() && out_dir.starts_with(root))
        .unwrap_or_else(|| standalone_target_root(&out_dir, None));
    // ld64 resolves archive paths through Cargo's target symlink before
    // recording them, so the prefix must use the same physical spelling.
    let prefix = std::fs::canonicalize(&prefix).unwrap_or(prefix);
    let mut extended = arguments.to_vec();
    // Direct object paths use rustc's output spelling while archive paths are
    // canonicalized by ld64. Give both the same spelling so one prefix covers
    // them. This still writes through Cargo's target symlink to the same files.
    let native_output = arguments.iter().enumerate().any(|(index, argument)| {
        argument == "--test"
            || matches!(
                argument.to_str(),
                Some("--crate-type=bin" | "--crate-type=proc-macro")
            )
            || (argument == "--crate-type"
                && arguments
                    .get(index + 1)
                    .is_some_and(|value| matches!(value.to_str(), Some("bin" | "proc-macro"))))
    });
    if native_output && let Ok(output) = std::fs::canonicalize(&out_dir) {
        for index in 0..extended.len() {
            if extended[index] == "--out-dir" {
                if let Some(value) = extended.get_mut(index + 1) {
                    *value = output.as_os_str().to_owned();
                }
            } else if extended[index]
                .to_str()
                .is_some_and(|arg| arg.starts_with("--out-dir="))
            {
                let mut value = OsString::from("--out-dir=");
                value.push(&output);
                extended[index] = value;
            }
        }
    }
    extended.push(format!("-Clink-arg=-Wl,-oso_prefix,{}/", prefix.display()).into());
    Cow::Owned(extended)
}

fn linker_for(invocation: &RustcInvocation) -> Result<Option<LinkerIdentity>> {
    if !invocation.links_natively() {
        return Ok(None);
    }
    match crate::linker::identity_for(invocation.linker_override(), invocation.fuse_ld()) {
        Ok(identity) => Ok(Some(identity)),
        Err(error) => Err(BypassReason::UnportableNativeLink(format!(
            "the linker could not be identified: {error:#}"
        ))
        .into()),
    }
}

fn record_prediction(
    compilation: &Compilation<'_>,
    action: &CacheDigest,
    discovered: &DiscoveredInputs,
    timing: &CompileTiming,
    flight: Option<&crate::scheduler::Flight>,
    remote_claim: Option<&str>,
) {
    let _phase = crate::phase_timing::phase("predict");
    let result = (|| {
        let invocation = compilation.invocation;
        let context = base_action_context(
            compilation.rustc,
            compilation.working_dir,
            compilation.portable,
        )?;
        let invocation_digest = invocation.invocation_digest(&context)?;
        let mut prediction = invocation.prediction(&context, discovered)?;
        prediction.compiler_duration_ns = timing.duration_ns;
        prediction.crate_name.clone_from(&timing.crate_name);
        let payload = String::from_utf8(canonical_json(&prediction)?)?;
        // Anyone waiting on this flight -- and any later build of the same
        // invocation -- restores through this instead of compiling.
        if let Some(flight) = flight {
            flight.leave(&payload);
        }
        record_prediction_value(
            invocation_digest.clone(),
            action.clone(),
            payload.clone(),
            invocation.crate_name(),
        );
        if let Some(claim) = remote_claim {
            let prediction = ActionPrediction {
                invocation: invocation_digest,
                action: action.clone(),
                adapter: "rustc".into(),
                payload,
            };
            let _ = session::request_agent(&[AgentRequest::CompleteActionPromise {
                claim: claim.to_string(),
                prediction,
            }]);
        }
        Result::<()>::Ok(())
    })();
    if let Err(error) = result {
        warn_prediction_not_recorded(compilation.invocation.crate_name(), &error);
    }
}

/// The machine-wide flight this compilation occupies, and the invocation
/// digest that keys it.
struct InvocationFlight {
    flight: crate::scheduler::Flight,
    invocation: CacheDigest,
}

/// Join the flight for this invocation, when one can be keyed.
///
/// `None` -- an invocation whose digest cannot be built, or a machine with
/// scheduling off -- just compiles, the way everything here degrades.
fn join_flight(compilation: &Compilation<'_>) -> Option<InvocationFlight> {
    let invocation = (|| -> Result<CacheDigest> {
        let context = base_action_context(
            compilation.rustc,
            compilation.working_dir,
            compilation.portable,
        )?;
        Ok(compilation.invocation.invocation_digest(&context)?)
    })()
    .ok()?;
    let flight = crate::scheduler::flight("rustc", &invocation.hash)?;
    Some(InvocationFlight { flight, invocation })
}

/// Restore through the prediction a flight left behind.
///
/// The payload gets exactly the treatment a manifest prediction does --
/// canonical-form check, every input rehashed, the store consulted -- so the
/// worst a stale or foreign record can do is miss.
#[allow(clippy::too_many_arguments)]
fn restore_flight_prediction(
    compilation: &Compilation<'_>,
    outputs: &RustcOutputs,
    invocation_digest: &CacheDigest,
    payload: &str,
    action_lookup_attempted: &mut bool,
    learned_enabled: bool,
    learned: &mut LearnedPlan,
    diagnostic: Option<&mut Option<ActionDiagnostic>>,
) -> Result<Option<CachedCompilation>> {
    let context = base_action_context(
        compilation.rustc,
        compilation.working_dir,
        compilation.portable,
    )?;
    restore_prediction_payload(
        compilation,
        outputs,
        context,
        invocation_digest,
        payload,
        None,
        true,
        action_lookup_attempted,
        learned_enabled,
        learned,
        diagnostic,
    )
}

/// Refresh the stored prediction behind a hit and recover the timing it holds.
///
/// A hit is recorded even when its prediction is byte-for-byte unchanged. The
/// task manifest merge makes that an idempotent write, while the run's exact
/// prediction set becomes its build receipt and must include restored actions.
fn refresh_prediction(
    compilation: &Compilation<'_>,
    action: &CacheDigest,
    discovered: &DiscoveredInputs,
) -> Result<CompileTiming> {
    let context = base_action_context(
        compilation.rustc,
        compilation.working_dir,
        compilation.portable,
    )?;
    let invocation_digest = compilation.invocation.invocation_digest(&context)?;
    let task = prediction_task(&invocation_digest);
    let responses = session::request_agent(&[AgentRequest::FindActionPrediction {
        task,
        invocation: invocation_digest.clone(),
    }])?;
    let Some(response) = responses.into_iter().next() else {
        bail!("cache agent did not return an action prediction response");
    };
    let stored = match response {
        AgentResponse::ActionPrediction { prediction } => prediction,
        AgentResponse::Error { message } => bail!(message),
        _ => bail!("cache agent returned an unexpected action prediction response"),
    };
    let timing = match &stored {
        Some(stored) => decode_prediction_timing(stored, &invocation_digest)?,
        None => CompileTiming::default(),
    };
    // Recording stays best-effort and separate from the timing, which the
    // caller credits to this hit either way. A prediction that cannot be
    // rebuilt costs the next build a lookup; it does not make the time this
    // build just saved any less real.
    let recorded = (|| {
        let mut prediction = compilation.invocation.prediction(&context, discovered)?;
        prediction.compiler_duration_ns = timing.duration_ns;
        prediction.crate_name.clone_from(&timing.crate_name);
        let payload = String::from_utf8(canonical_json(&prediction)?)?;
        record_prediction_value(
            invocation_digest,
            action.clone(),
            payload,
            compilation.invocation.crate_name(),
        );
        Result::<()>::Ok(())
    })();
    if let Err(error) = recorded {
        warn_prediction_not_recorded(compilation.invocation.crate_name(), &error);
    }
    Ok(timing)
}

fn decode_prediction_timing(
    prediction: &ActionPrediction,
    invocation: &CacheDigest,
) -> Result<CompileTiming> {
    if prediction.adapter != "rustc" || prediction.invocation != *invocation {
        bail!("cache agent returned an incompatible rustc timing prediction");
    }
    let timing: RustcInputPrediction = serde_json::from_str(&prediction.payload)?;
    if !matches!(timing.version, 2..=4)
        || timing.crate_name.len() > 256
        || timing.crate_name.contains(['\0', '\n', '\r'])
        || String::from_utf8(canonical_json(&timing)?)? != prediction.payload
    {
        bail!("cache agent returned an invalid rustc timing prediction");
    }
    Ok(CompileTiming {
        crate_name: timing.crate_name,
        duration_ns: timing.compiler_duration_ns,
    })
}

fn record_prediction_value(
    invocation: CacheDigest,
    action: CacheDigest,
    payload: String,
    crate_name: &str,
) {
    let result = (|| {
        let task = prediction_task(&invocation);
        let responses = session::request_agent(&[AgentRequest::RecordActionPrediction {
            task,
            prediction: ActionPrediction {
                invocation,
                action,
                adapter: "rustc".into(),
                payload,
            },
        }])?;
        match responses.into_iter().next() {
            Some(AgentResponse::ActionPredictionRecorded) => Ok(()),
            Some(AgentResponse::Error { message }) => bail!(message),
            _ => bail!("cache agent returned an unexpected prediction response"),
        }
    })();
    if let Err(error) = result {
        warn_prediction_not_recorded(crate_name, &error);
    }
}

/// Name the crate whose prediction was lost. Without it the warning says only
/// that one compilation out of thousands failed to record, which is not enough
/// to reproduce or to tell whether the same crate fails on every build.
fn warn_prediction_not_recorded(crate_name: &str, error: &eyre::Report) {
    session::report_shim_warning(&format!(
        "action prediction for {crate_name} was not recorded: {error:#}"
    ));
}

/// Select the session run, or a bounded persistent-manifest shard when this
/// shim was installed directly in Cargo configuration.
fn prediction_task(invocation: &CacheDigest) -> String {
    std::env::var(session::BUILD_ENV).unwrap_or_else(|_| {
        // A global manifest would eventually hit the prediction count limit.
        // Sharding by the invocation digest keeps related reads and writes
        // together while bounding each manifest independently.
        let shard = invocation.hash.get(..2).unwrap_or(&invocation.hash);
        CacheDigest::blake3(format!("standalone-predictions-v1\0{shard}").as_bytes()).hash
    })
}

fn verify_environment(environment: &BTreeMap<String, Option<String>>) -> Result<()> {
    for (name, expected) in environment {
        let actual = std::env::var_os(name)
            .map(|value| {
                value.into_string().map_err(|_| {
                    eyre::eyre!("compiler environment input is not valid UTF-8: {name}")
                })
            })
            .transpose()?;
        if &actual != expected {
            bail!("compiler environment input changed: {name}");
        }
    }
    Ok(())
}

fn restore_result(
    action: &RustcAction,
    outputs: &RustcOutputs,
    discovered: &DiscoveredInputs,
    restore_outputs: bool,
    mappings: &[PathMapping],
) -> Result<Option<CachedCompilation>> {
    let _phase = crate::phase_timing::phase("restore");
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
        bail!("cached rustc action result has an invalid identity");
    }
    let metadata_digest = result
        .metadata
        .ok_or_else(|| eyre::eyre!("cached rustc action result has no metadata"))?;
    let output_root_digest = result
        .output_root
        .ok_or_else(|| eyre::eyre!("cached rustc action result has no output root"))?;
    let roots = find_blobs(&[
        action.digest.clone(),
        metadata_digest.clone(),
        output_root_digest.clone(),
    ])?;
    let cached_action = read_verified_blob(&roots[0], &action.digest, "action descriptor")?;
    if cached_action != action.bytes {
        bail!("cached rustc action descriptor does not match the invocation");
    }
    let metadata: RustcMetadata =
        read_canonical_blob(&roots[1], &metadata_digest, "rustc metadata")?;
    if metadata.version != 1 || metadata.kind != "rustc" {
        bail!("cached rustc metadata is unsupported");
    }
    let directory: CacheDirectory =
        read_canonical_blob(&roots[2], &output_root_digest, "output directory")?;
    let files = validated_outputs(directory, outputs)?;
    let restored_output_files = files.len().try_into().unwrap_or(u64::MAX);
    let restored_output_bytes = files.iter().fold(0_u64, |total, (node, _)| {
        total.saturating_add(node.digest.size)
    });

    let mut digests = vec![metadata.stdout.clone(), metadata.stderr.clone()];
    digests.extend(files.iter().map(|(node, _)| node.digest.clone()));
    let blobs = find_blobs(&digests)?;
    let stdout = denormalize_output_text(
        &read_verified_blob(&blobs[0], &metadata.stdout, "stdout")?,
        mappings,
    );
    let stderr = denormalize_output_text(
        &read_verified_blob(&blobs[1], &metadata.stderr, "stderr")?,
        mappings,
    );

    let materialization_started = Instant::now();
    std::fs::create_dir_all(&outputs.directory)?;
    let staging = tempfile::tempdir_in(&outputs.directory)?;
    let mut staged = Vec::with_capacity(files.len());
    let mut restore = RestoreStats {
        output_files: restored_output_files,
        output_bytes: restored_output_bytes,
        ..RestoreStats::default()
    };
    let mut cached_outputs = Vec::with_capacity(files.len());
    for (index, ((node, destination), source)) in files.into_iter().zip(&blobs[2..]).enumerate() {
        // The dep-info was stored in placeholder form, so it is written out
        // rather than cloned: what belongs on disk is this checkout's spelling
        // of it, and that is what the verification below must compare against.
        if destination == outputs.dep_info {
            let bytes = denormalize_output_text(
                &read_verified_blob(source, &node.digest, "dep-info")?,
                mappings,
            );
            let digest = CacheDigest::blake3(&bytes);
            cached_outputs.push(CachedOutput {
                path: destination.clone(),
                digest: digest.clone(),
                executable: node.executable,
                mode: node.mode,
            });
            // A dep-info already spelling exactly this stays in place for the
            // same reason a matching artifact does below.
            if restore_outputs
                && std::fs::read(&destination).is_ok_and(|existing| existing == bytes)
            {
                mark_output_restored(&destination)?;
                restore.reused_output_files = restore.reused_output_files.saturating_add(1);
                restore.reused_output_bytes = restore
                    .reused_output_bytes
                    .saturating_add(bytes.len().try_into().unwrap_or(u64::MAX));
                continue;
            }
            let temporary = staging.path().join(format!("output-{index}"));
            std::fs::write(&temporary, &bytes)?;
            let temporary = tempfile::TempPath::try_from_path(temporary)?;
            apply_file_mode(&temporary, node.mode, node.executable)?;
            restore.copied_output_files = restore.copied_output_files.saturating_add(1);
            restore.copied_output_bytes = restore
                .copied_output_bytes
                .saturating_add(bytes.len().try_into().unwrap_or(u64::MAX));
            staged.push((temporary, destination));
            continue;
        }
        cached_outputs.push(CachedOutput {
            path: destination.clone(),
            digest: node.digest.clone(),
            executable: node.executable,
            mode: node.mode,
        });
        // Avoid copying bytes that are already here, but still make the output
        // look freshly produced. Cargo only invoked rustc because this unit
        // was stale; leaving its old mtime behind lets a newer dependency keep
        // the same unit stale forever, even though this cache hit rebuilt it
        // logically. Cargo writes the unit fingerprint after rustc returns, so
        // touching it here preserves the same ordering as a real compilation.
        if restore_outputs
            && output_already_in_place(&node, &destination, session::file_digest_cache())
        {
            mark_output_restored(&destination)?;
            restore.reused_output_files = restore.reused_output_files.saturating_add(1);
            restore.reused_output_bytes =
                restore.reused_output_bytes.saturating_add(node.digest.size);
            continue;
        }
        let (temporary, materialization) =
            stage_verified_cached_output(staging.path(), index, source, &node)?;
        match materialization {
            Materialization::Reflink => {
                restore.reflinked_output_files = restore.reflinked_output_files.saturating_add(1);
                restore.reflinked_output_bytes = restore
                    .reflinked_output_bytes
                    .saturating_add(node.digest.size);
            }
            Materialization::Hardlink => {
                restore.hardlinked_output_files = restore.hardlinked_output_files.saturating_add(1);
                restore.hardlinked_output_bytes = restore
                    .hardlinked_output_bytes
                    .saturating_add(node.digest.size);
            }
            Materialization::Copy => {
                restore.copied_output_files = restore.copied_output_files.saturating_add(1);
                restore.copied_output_bytes =
                    restore.copied_output_bytes.saturating_add(node.digest.size);
            }
        }
        staged.push((temporary, destination));
    }
    let staged = StagedOutputs {
        directory: staging,
        files: staged,
    };

    // The inputs were hashed moments ago in this same process to build the
    // action key, and nothing is published here, so rehashing them
    // (`discovered.verify()`) guards nothing: an input changing mid-restore is
    // the same width of race a real compile has with cargo's own freshness
    // check, and the next build degrades it to a miss. On a warm build that
    // second pass re-reads every source and upstream rlib per hit, which is
    // most of the restore.
    verify_environment(&discovered.environment)?;
    finalize_restored_outputs(staged, restore_outputs)?;
    if restore_outputs {
        record_output_digests(&cached_outputs);
    }
    restore.duration_ns = materialization_started
        .elapsed()
        .as_nanos()
        .try_into()
        .unwrap_or(u64::MAX);
    Ok(Some(CachedCompilation {
        action: action.digest.clone(),
        stdout,
        stderr,
        outputs: cached_outputs,
        restore,
    }))
}

/// Make an output already holding the cached bytes look freshly produced.
///
/// Through the same read-only open a restore uses: an output a previous hit
/// hard linked is the store's object and carries its read-only mode, and
/// demanding write access here would turn the cheapest kind of hit -- the
/// bytes are already in place -- into a dropped restore and a real compile.
fn mark_output_restored(path: &Path) -> Result<()> {
    crate::materialize::set_modified_now(path)
}

/// Whether the destination already holds exactly the bytes this hit would
/// place there.
///
/// The session ledger answers without a read when it can; otherwise the file
/// is read once and hashed, which costs what the copy it replaces would have
/// cost. A ledger entry whose digest disagrees is a content difference already
/// proven, so it refuses without reading either.
pub(crate) fn output_already_in_place(
    node: &CacheFileNode,
    destination: &Path,
    digests: &dyn tuist_cargo_cache_core::FileDigestCache,
) -> bool {
    let Ok(metadata) = std::fs::metadata(destination) else {
        return false;
    };
    if !metadata.is_file()
        || metadata.len() != node.digest.size
        || !executable_mode_matches(&metadata, node.executable)
    {
        return false;
    }
    if let Ok(Some(identity)) = FileIdentity::for_digest_cache(destination, &metadata) {
        match digests.resolve(FileDigestScope::Content, &[identity]).pop() {
            Some(FileDigestResolution::Digest(recorded)) => return recorded == node.digest,
            Some(FileDigestResolution::EmbeddedTimestampMacro) => return false,
            Some(FileDigestResolution::Unresolved) | None => {}
        }
    }
    CacheDigest::blake3_file(destination).is_ok_and(|digest| digest == node.digest)
}

/// Enter restored outputs into the session file-digest ledger.
///
/// The digests were verified when the blobs entered the store, and the rename
/// that placed each file fixed the identity being recorded; a crate that links
/// one of these artifacts can then key it without reading it back. Best-effort
/// throughout: a file that cannot be described is simply not recorded.
fn record_output_digests(outputs: &[CachedOutput]) {
    let entries = outputs
        .iter()
        .filter_map(|output| {
            let metadata = std::fs::metadata(&output.path).ok()?;
            if metadata.len() != output.digest.size {
                return None;
            }
            Some(RecordedFileDigest {
                file: FileIdentity::for_digest_cache(&output.path, &metadata).ok()??,
                digest: output.digest.clone(),
            })
        })
        .collect::<Vec<_>>();
    session::record_file_digests(FileDigestScope::Content, entries);
}

fn finalize_restored_outputs(staged: StagedOutputs, restore_outputs: bool) -> Result<()> {
    if restore_outputs {
        persist_outputs(staged)?;
    }
    Ok(())
}

/// Describe how a restore differs from the compilation it was checked against.
///
/// `None` means they agree. A divergence names what disagreed, because that is
/// the whole output of a qualification run: knowing that something differed is
/// not actionable, and the answer is usually one specific file.
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

fn validated_outputs(
    directory: CacheDirectory,
    outputs: &RustcOutputs,
) -> Result<Vec<(CacheFileNode, PathBuf)>> {
    if directory.version != 1 || !directory.directories.is_empty() || !directory.symlinks.is_empty()
    {
        bail!("cached rustc output directory has unsupported entries");
    }
    let mut expected = outputs
        .files
        .iter()
        .chain(std::iter::once(&outputs.dep_info))
        .map(|path| {
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| eyre::eyre!("expected rustc output name is not UTF-8"))?;
            if path.parent() != Some(outputs.directory.as_path()) {
                bail!("expected rustc output escapes its output directory");
            }
            Ok((
                name.to_string(),
                (path.clone(), outputs.is_executable(path)),
            ))
        })
        .collect::<Result<BTreeMap<_, _>>>()?;
    if directory.files.len() != expected.len() {
        bail!("cached rustc output set does not match the invocation");
    }
    let mut files = Vec::with_capacity(directory.files.len());
    for node in directory.files {
        let (destination, executable) = expected
            .remove(&node.name)
            .ok_or_else(|| eyre::eyre!("cached rustc output is unexpected: {}", node.name))?;
        validate_file_mode(&node, executable)?;
        files.push((node, destination));
    }
    if !expected.is_empty() {
        bail!("cached rustc output set is incomplete");
    }
    Ok(files)
}

fn compiler_identity(rustc: &OsStr) -> Result<CompilerIdentity> {
    let _phase = crate::phase_timing::phase("key");
    // One shim process serves one compiler, but several steps of one
    // compilation each build an action context. Asking the agent every time
    // turns one identity into several round trips per compilation.
    static IDENTITY: OnceLock<(OsString, CompilerIdentity)> = OnceLock::new();
    if let Some((known, identity)) = IDENTITY.get()
        && known.as_os_str() == rustc
    {
        return Ok(identity.clone());
    }
    let identity = query_compiler_identity(rustc)?;
    let _ = IDENTITY.set((rustc.to_os_string(), identity.clone()));
    Ok(identity)
}

fn query_compiler_identity(rustc: &OsStr) -> Result<CompilerIdentity> {
    let executable = resolve_executable(rustc)?;
    let clippy = Path::new(rustc).file_stem() == Some(OsStr::new("clippy-driver"));
    let environment = ["RUSTUP_HOME", "RUSTUP_TOOLCHAIN"]
        .into_iter()
        .map(|name| (name.into(), std::env::var(name).ok()))
        .collect::<BTreeMap<_, _>>();
    let responses = session::request_agent(&[AgentRequest::FindExecutableIdentity {
        executable: executable.clone(),
        environment: environment.clone(),
    }])?;
    let Some(AgentResponse::ExecutableIdentity { stdout }) = responses.into_iter().next() else {
        bail!("cache agent did not return the rustc identity");
    };
    let stdout = if let Some(stdout) = stdout {
        stdout
    } else {
        // Described before the compiler runs, so a binary replaced while it
        // prints its version is never recorded under the replacement.
        let mut pins = compiler_identity_pins(&executable);
        let mut command = Command::new(&executable);
        command.arg("-vV");
        for (name, value) in &environment {
            if let Some(value) = value {
                command.env(name, value);
            } else {
                command.env_remove(name);
            }
        }
        let output = crate::phase_timing::measure("compiler", || command.output())
            .wrap_err("failed to query the rustc identity")?;
        if !output.status.success() {
            bail!(
                "rustc identity command failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
        let mut stdout = output.stdout;
        let host = identity_field(&String::from_utf8_lossy(&stdout), "host")?.to_string();
        if clippy {
            let mut command = Command::new(&executable);
            command.arg("--version");
            for (name, value) in &environment {
                if let Some(value) = value {
                    command.env(name, value);
                } else {
                    command.env_remove(name);
                }
            }
            let output = crate::phase_timing::measure("compiler", || command.output())
                .wrap_err("failed to query the clippy-driver identity")?;
            if !output.status.success() {
                bail!(
                    "clippy-driver identity command failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                );
            }
            stdout.extend_from_slice(b"\ntuist_cargo_cache-driver: ");
            stdout.extend_from_slice(output.stdout.trim_ascii());
            stdout.push(b'\n');
        }
        let (backend_pins, backends) = codegen_backends(rustc, &host)?;
        // An unpinned compiler is probed every session, so it stays unpinned.
        if !pins.is_empty() {
            pins.extend(backend_pins);
        }
        stdout.extend_from_slice(backends.as_bytes());
        let responses = session::request_agent(&[AgentRequest::StoreExecutableIdentity {
            executable,
            environment,
            stdout,
            pins,
        }])?;
        let Some(AgentResponse::ExecutableIdentity {
            stdout: Some(stdout),
        }) = responses.into_iter().next()
        else {
            bail!("cache agent did not store the rustc identity");
        };
        stdout
    };
    let verbose = std::str::from_utf8(&stdout).wrap_err("rustc identity is not UTF-8")?;
    let release = identity_field(verbose, "release")?;
    let host = identity_field(verbose, "host")?;
    let rustc_version = verbose
        .lines()
        .filter(|line| {
            line.starts_with("rustc ")
                || line.starts_with("commit-hash:")
                || line.starts_with("commit-date:")
                || line.starts_with("LLVM version:")
                || line.starts_with("tuist_cargo_cache-codegen-backend:")
        })
        .collect::<Vec<_>>()
        .join("; ");
    if rustc_version.is_empty() {
        bail!("rustc identity is missing its version");
    }
    let toolchain = std::env::var("RUSTUP_TOOLCHAIN")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| release.to_string());
    Ok(CompilerIdentity {
        toolchain,
        rustc_version,
        host: host.to_string(),
        driver: verbose
            .lines()
            .find_map(|line| line.strip_prefix("tuist_cargo_cache-driver: "))
            .filter(|value| !value.is_empty())
            .map(str::to_string),
    })
}

/// The files that pin a compiler's identity across sessions: the binary and
/// the compiler library beside it, as they are right now.
///
/// Only a toolchain's own compiler is pinned. A rustup proxy, a version
/// manager's shim, or a wrapper script picks a compiler when it runs, so its
/// bytes say nothing about what `-vV` will print. What tells the two apart
/// is not where the file sits but what sits beside it: a compiler is linked
/// against `rustc_driver`, which its toolchain installs next to it, and a
/// dispatcher has no such thing. An executable without one is probed every
/// session.
fn compiler_identity_pins(executable: &Path) -> Vec<PinnedFile> {
    let Some(driver) = compiler_driver_library(executable) else {
        return Vec::new();
    };
    match (
        PinnedFile::describe(executable),
        PinnedFile::describe(&driver),
    ) {
        (Some(executable), Some(driver)) => vec![executable, driver],
        _ => Vec::new(),
    }
}

/// The backend libraries rustc loads by name from its host's directory in
/// its sysroot, each pinned before it is hashed into the identity.
fn codegen_backends(rustc: &OsStr, host: &str) -> Result<(Vec<PinnedFile>, String)> {
    let mut pins = Vec::new();
    let mut identity = String::new();
    let Some(sysroot) = compiler_sysroot(rustc) else {
        return Ok((pins, identity));
    };
    let directory = sysroot
        .join("lib/rustlib")
        .join(host)
        .join("codegen-backends");
    pins.extend(PinnedFile::describe(directory.clone()));
    for (path, metadata) in resolved_entries(&directory)? {
        if !metadata.is_file() {
            continue;
        }
        pins.extend(PinnedFile::describe(path.clone()));
        let digest = CacheDigest::blake3_file(&path)?;
        let name = path.file_name().unwrap_or_default();
        identity += &format!(
            "\ntuist_cargo_cache-codegen-backend: {:?} {}\n",
            name, digest.hash
        );
    }
    Ok((pins, identity))
}

/// The entries of `directory` sorted by path, with symlinks followed. An
/// absent directory or a dangling link contributes nothing; any other failure
/// is an error, so an incomplete listing never becomes an identity.
fn resolved_entries(directory: &Path) -> Result<Vec<(PathBuf, std::fs::Metadata)>> {
    let entries = match std::fs::read_dir(directory) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        entries => entries?,
    };
    let mut resolved = Vec::new();
    for entry in entries {
        let path = entry?.path();
        match std::fs::metadata(&path) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            metadata => resolved.push((path, metadata?)),
        }
    }
    resolved.sort_by(|(left, _), (right, _)| left.cmp(right));
    Ok(resolved)
}

/// The `rustc_driver` library a toolchain installs beside its compiler:
/// under `lib/` next to `bin/` on Unix, in `bin/` itself on Windows.
fn compiler_driver_library(executable: &Path) -> Option<PathBuf> {
    let bin = executable.parent()?;
    let mut directories = vec![bin.to_path_buf()];
    if let Some(root) = bin.parent() {
        directories.push(root.join("lib"));
    }
    directories.into_iter().find_map(|directory| {
        std::fs::read_dir(directory)
            .ok()?
            .flatten()
            .find_map(|entry| {
                let name = entry.file_name();
                let name = name.to_string_lossy();
                let library =
                    name.starts_with("librustc_driver") || name.starts_with("rustc_driver");
                (library && entry.file_type().is_ok_and(|kind| kind.is_file()))
                    .then(|| entry.path())
            })
    })
}

fn identity_field<'a>(verbose: &'a str, field: &str) -> Result<&'a str> {
    verbose
        .lines()
        .find_map(|line| line.strip_prefix(&format!("{field}: ")))
        .filter(|value| !value.is_empty())
        .ok_or_else(|| eyre::eyre!("rustc identity is missing {field}"))
}

/// Environment inputs eligible for remapping.
///
/// Deliberately just the one. `OUT_DIR` lives under the target directory, so
/// remapping it confines the change to generated sources, and it is the value
/// the plan identifies as the cross-checkout shortfall. Widening this list
/// widens which paths disappear from debug info, which is its own decision.
const PORTABLE_ENVIRONMENT: &[&str] = &["OUT_DIR"];

/// The environment values whose absolute paths this compilation was made
/// independent of.
///
/// `OUT_DIR` is the one that matters: every crate that includes build-script
/// output reads it, its value differs per checkout, and keeping it in the key
/// verbatim is what stops those compilations sharing between checkouts.
///
/// `--remap-path-prefix` makes rustc record the placeholder instead of the real
/// path, which covers debug info, spans and diagnostics -- everything rustc
/// writes itself. That is what makes the *artifact* the same in every checkout,
/// so the crates that depend on it share even though it does not.
///
/// The compilation's own key is not made to ignore the value. Deciding that it
/// could be ignored meant proving the artifact does not depend on it, and
/// nothing available here is a proof: reading the outputs back finds a path
/// that was kept verbatim, but not one a crate derived something from, and a
/// second compilation with the value spelled differently is a sample rather
/// than a proof. A key that claims more than it can show restores one
/// checkout's artifact into another.
struct Portable {
    /// Path mappings for this compilation, ordered as keys need them.
    mappings: Vec<PathMapping>,
    /// Flags appended to the real rustc invocation, one per remapped value.
    arguments: Vec<OsString>,
    /// Cargo's invalidation inputs, captured before OUT_DIR is stabilized.
    build_script_inputs: Option<crate::build_script::CompilationInputs>,
}

impl Portable {
    fn map_external_native_paths(&mut self, invocation: &RustcInvocation, working_dir: &Path) {
        for path in invocation.native_search_paths() {
            if normalize_mapped_path(path, working_dir, &self.mappings).is_ok() {
                continue;
            }
            let path = working_dir.join(path);
            let mapping = tuist_cargo_cache_core::PathMapping::new(&path, "");
            let identity = tuist_cargo_cache_core::resolve_path_mappings(&[mapping])
                .remove(0)
                .root;
            let Some(text) = identity.to_str().filter(|_| path.is_absolute()) else {
                continue;
            };
            // Keep installation locations in the key: these paths are not
            // remapped in the compiler's output. Only explicitly named search
            // directories are admitted, and discovery hashes their contents.
            let placeholder = format!("native_{}", CacheDigest::blake3(text.as_bytes()).hash);
            self.mappings.push(PathMapping::new(path, placeholder));
        }
        self.mappings = PathMapping::ordered(&self.mappings);
    }

    fn detect(working_dir: &Path, target_output: Option<&Path>, target: Option<&str>) -> Self {
        let mut portable = Self {
            mappings: PathMapping::ordered(&path_mappings(working_dir, target_output, target)),
            arguments: Vec::new(),
            build_script_inputs: None,
        };
        // Before the values below, because rustc takes the last mapping that
        // matches: `OUT_DIR` usually sits under the workspace, and its own
        // placeholder is the one its generated sources should carry.
        portable.map_workspace_root();
        if !session::share_out_dir_requested() {
            return portable;
        }
        for name in PORTABLE_ENVIRONMENT {
            let Some(value) = std::env::var(name)
                .ok()
                .filter(|value| Path::new(value).is_absolute())
            else {
                continue;
            };
            // A value under no known root is one no key could agree on anyway,
            // so there is nothing to remap and nothing to promise.
            let Ok(placeholder) =
                normalize_mapped_path(Path::new(&value), working_dir, &portable.mappings)
            else {
                continue;
            };
            let mut flag = OsString::from("--remap-path-prefix=");
            flag.push(&value);
            flag.push("=");
            flag.push(&placeholder);
            portable.arguments.push(flag);
        }
        portable
    }

    /// The compiler arguments, with the remapping flags appended.
    /// Keep the checkout out of what rustc records about a compilation.
    ///
    /// Cargo runs rustc with the crate's own directory as the working
    /// directory and rustc stores it, so a workspace member rebuilt in a second
    /// checkout produces a different artifact from the first even when every
    /// input matched -- and every crate above it rebuilds with it, because what
    /// it consumes differs. That is the cost a compilation keyed to its
    /// checkout imposes on crates that are not.
    ///
    /// Mapping the root removes the difference: two checkouts compiling the
    /// same crate produce the same bytes. The price is that every recorded
    /// source path under the workspace names the placeholder instead, in debug
    /// information, `file!()` and panic locations, which is why this is off
    /// until asked for.
    fn map_workspace_root(&mut self) {
        if !session::share_workspace_root_requested() {
            return;
        }
        let Some(mapping) = self
            .mappings
            .iter()
            .find(|mapping| mapping.placeholder == "workspace")
        else {
            return;
        };
        let mut flag = OsString::from("--remap-path-prefix=");
        flag.push(&mapping.root);
        flag.push("=");
        flag.push(format!("${{{}}}", mapping.placeholder));
        self.arguments.push(flag);
    }

    fn applied_to(&self, arguments: &[OsString]) -> Vec<OsString> {
        let mut applied = arguments.to_vec();
        applied.extend(self.arguments.iter().cloned());
        applied
    }
}

fn path_mappings(
    working_dir: &Path,
    target_output: Option<&Path>,
    target: Option<&str>,
) -> Vec<PathMapping> {
    path_mappings_with_env(working_dir, target_output, target, |name| {
        std::env::var_os(name)
    })
}

/// Construct compiler mappings from an injectable environment lookup.
fn path_mappings_with_env(
    working_dir: &Path,
    target_output: Option<&Path>,
    target: Option<&str>,
    environment: impl Fn(&str) -> Option<OsString>,
) -> Vec<PathMapping> {
    let mut mappings = Vec::new();
    let mut roots = BTreeSet::new();
    // A stable `OUT_DIR` is its own root, named for the variable rather than
    // for the tree: a prediction that lists `${out_dir}/generated.rs` resolves
    // in every checkout against that checkout's own tree, and the key then
    // compares the trees by the digest in the path rustc was given.
    if let (Some(root), Some(out_dir)) = (
        environment(crate::out_dir::ROOT_ENV).map(PathBuf::from),
        environment("OUT_DIR").map(PathBuf::from),
    ) && out_dir.is_absolute()
        && out_dir.starts_with(&root)
        && out_dir != root
    {
        add_mapping(
            &mut mappings,
            &mut roots,
            out_dir,
            crate::out_dir::PLACEHOLDER,
        );
    }
    let home_roots = ["HOME", "USERPROFILE"]
        .into_iter()
        .filter_map(|name| environment(name).map(PathBuf::from))
        .filter(|root| root.is_absolute())
        .collect::<Vec<_>>();
    // The target directory comes first, and before the workspace that usually
    // contains it: output paths are the ones that differ between checkouts, and
    // mapping them explicitly also keeps keys stable when the target directory
    // is moved out of the workspace.
    //
    // Cargo compiles a dependency with its working directory inside the
    // registry, not in the workspace, so neither root can be inferred from the
    // working directory -- the session passes both in.
    let configured_target = environment(session::TARGET_DIR_ENV)
        .map(PathBuf::from)
        .filter(|root| root.is_absolute())
        .map(|root| {
            // Match the spelling emitted by rustc when a macOS link uses the
            // physical target directory to share ld64's single OSO prefix.
            let physical = std::fs::canonicalize(&root).ok();
            physical
                .filter(|physical| {
                    target_output.is_some_and(|output| {
                        output.starts_with(physical) && !output.starts_with(&root)
                    })
                })
                .unwrap_or(root)
        });
    if let Some(root) = configured_target.or_else(|| {
        target_output
            .filter(|root| root.is_absolute())
            .map(|output| standalone_target_root(output, target))
    }) {
        add_mapping(&mut mappings, &mut roots, root, "target");
    }
    if let Some(root) = environment(session::WORKSPACE_ROOT_ENV)
        .map(PathBuf::from)
        .filter(|root| root.is_absolute())
    {
        add_mapping(&mut mappings, &mut roots, root, "workspace");
    }
    let cargo_home = environment("CARGO_HOME")
        .map(PathBuf::from)
        .filter(|root| root.is_absolute())
        .or_else(|| home_roots.first().map(|home| home.join(".cargo")));
    if let Some(root) = cargo_home {
        // The registry is its own semantic root because container builds often
        // mount it elsewhere and leave a symlink below CARGO_HOME. Resolving
        // this deeper mapping follows that symlink without making arbitrary
        // paths outside Cargo's registry portable.
        add_mapping(
            &mut mappings,
            &mut roots,
            root.join("registry"),
            "cargo_registry",
        );
        add_mapping(&mut mappings, &mut roots, root, "cargo_home");
    }
    if let Some(root) = environment("RUSTUP_HOME")
        .map(PathBuf::from)
        .filter(|root| root.is_absolute())
    {
        add_mapping(&mut mappings, &mut roots, root, "rustup_home");
    }
    if let Some(home) = home_roots.first()
        && !mappings
            .iter()
            .any(|mapping| mapping.placeholder == "rustup_home")
    {
        add_mapping(
            &mut mappings,
            &mut roots,
            home.join(".rustup"),
            "rustup_home",
        );
    }
    // Without a session, recover Cargo's workspace root from the outermost
    // lockfile so member crates use the same placeholder as session mode.
    if !mappings
        .iter()
        .any(|mapping| mapping.placeholder == "workspace")
        && !roots.iter().any(|root| working_dir.starts_with(root))
    {
        add_mapping(
            &mut mappings,
            &mut roots,
            workspace_root(working_dir),
            "workspace",
        );
    }
    // A path dependency outside the workspace is under none of the roots
    // above, so its own package directory is its root. Without one its sources
    // could be named only through home, and not at all when the checkout is
    // elsewhere -- `/tmp`, or a CI runner's work directory -- leaving it
    // uncached. Home is not consulted here: the package keeps the same name
    // whether or not it happens to live below home.
    if let Some(root) = environment("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .filter(|root| root.is_absolute())
        .filter(|root| !roots.iter().any(|existing| root.starts_with(existing)))
    {
        add_mapping(&mut mappings, &mut roots, root, "package");
    }
    // Home is deliberately last. Most real checkouts live under it, but a
    // checkout-specific prefix must be `${workspace}` so equivalent worktrees
    // agree on their source paths. Cargo and rustup roots come first because a
    // registry compilation uses one of those as its working directory.
    for root in home_roots {
        add_mapping(&mut mappings, &mut roots, root, "home");
    }
    mappings
}

/// Infer the profile subtree shared by rustc outputs and build-script output.
///
/// Before 1.100, Cargo writes compilations to `<target>/<profile>/deps` (or
/// the same shape below a target-triple directory) and build scripts to
/// `<profile>/build/<unit>`. From 1.100 every unit writes to
/// `<profile>/build/<package>/<hash>/out`. Mapping the profile parent, rather
/// than only the output directory, also covers the other units' outputs and
/// generated inputs below `build/`.
fn standalone_target_root(output: &Path, target: Option<&str>) -> PathBuf {
    let profile = if matches!(
        output.file_name().and_then(OsStr::to_str),
        Some("deps" | "examples")
    ) {
        output.parent()
    } else if output.parent().and_then(Path::file_name) == Some(OsStr::new("build")) {
        output.parent().and_then(Path::parent)
    } else if output.file_name() == Some(OsStr::new("out"))
        && output.ancestors().nth(3).and_then(Path::file_name) == Some(OsStr::new("build"))
    {
        output.ancestors().nth(4)
    } else {
        None
    };
    if let Some(profile_root) = profile.and_then(Path::parent) {
        let target_component = target.and_then(|target| Path::new(target).file_stem());
        if target_component.is_some_and(|target| profile_root.file_name() == Some(target))
            && let Some(root) = profile_root.parent()
        {
            return root.to_path_buf();
        }
        return profile_root.to_path_buf();
    }
    output.to_path_buf()
}

fn add_mapping(
    mappings: &mut Vec<PathMapping>,
    roots: &mut BTreeSet<PathBuf>,
    root: PathBuf,
    placeholder: &str,
) {
    if roots.insert(root.clone())
        && !mappings
            .iter()
            .any(|mapping| mapping.placeholder == placeholder)
    {
        mappings.push(PathMapping::new(root, placeholder));
    }
}

fn replay_output(output: &Output) -> Result<()> {
    replay_bytes(&output.stdout, &output.stderr)
}

fn publish_result<'a>(
    candidates: &'a ActionCandidates,
    outputs: &RustcOutputs,
    output: &Output,
    mappings: &[PathMapping],
) -> Result<&'a RustcAction> {
    let _phase = crate::phase_timing::phase("store");
    if outputs.files.is_empty() {
        bail!("rustc produced no cacheable outputs");
    }
    let staging = staging_directory()?;
    let mut blobs = Vec::new();
    let stdout = staged_bytes(
        staging.path(),
        "stdout",
        &normalize_output_text(&output.stdout, mappings),
    )?;
    let stderr = staged_bytes(
        staging.path(),
        "stderr",
        &normalize_output_text(&output.stderr, mappings),
    )?;
    blobs.extend([stdout.clone(), stderr.clone()]);

    let output_paths = outputs
        .files
        .iter()
        .chain(std::iter::once(&outputs.dep_info));
    let mut files = Vec::with_capacity(outputs.files.len() + 1);
    let mut hashed_outputs = Vec::with_capacity(outputs.files.len());

    for path in output_paths {
        let metadata = std::fs::metadata(path)
            .wrap_err_with(|| format!("failed to inspect rustc output {}", path.display()))?;
        if !metadata.is_file() {
            bail!("rustc output is not a regular file: {}", path.display());
        }
        // The dep-info is stored in its placeholder form, so the checkout that
        // restores it gets rules naming its own target directory rather than
        // the one that published them.
        let digest = if path == &outputs.dep_info {
            let normalized = normalize_output_text(&std::fs::read(path)?, mappings);
            let staged = staged_bytes(staging.path(), "dep-info", &normalized)?;
            blobs.push(staged.clone());
            staged.0
        } else {
            // When a portable key is possible, inspect the same bytes used to
            // hash the artifact. Reading first and then calling `blake3_file`
            // made cold builds read every output twice merely to decide which
            // action key could safely name it.
            let digest = CacheDigest::blake3_file(path)?;
            blobs.push((digest.clone(), path.clone()));
            // Freshly compiled artifacts enter the ledger too: on a cold
            // build these are exactly the rlibs every dependent is about to
            // key, and this hash is the read that ledger entries stand in
            // for. The dep-info stays out -- its stored digest describes the
            // placeholder form, not what is on disk.
            if metadata.len() == digest.size
                && let Ok(Some(file)) = FileIdentity::for_digest_cache(path, &metadata)
            {
                hashed_outputs.push(RecordedFileDigest {
                    file,
                    digest: digest.clone(),
                });
            }
            digest
        };
        files.push(CacheFileNode {
            digest,
            executable: outputs.is_executable(path),
            mode: file_mode(&metadata),
            name: path
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| eyre::eyre!("rustc output name is not UTF-8"))?
                .to_string(),
        });
    }
    files.sort_by(|left, right| left.name.cmp(&right.name));
    session::record_file_digests(FileDigestScope::Content, hashed_outputs);

    let action = candidates.publishable();
    blobs.push(staged_bytes(staging.path(), "action.json", &action.bytes)?);

    let metadata = canonical_json(&RustcMetadata {
        version: 1,
        kind: "rustc".into(),
        stdout: stdout.0,
        stderr: stderr.0,
    })?;
    let metadata = staged_bytes(staging.path(), "metadata.json", &metadata)?;
    blobs.push(metadata.clone());
    let directory = canonical_json(&CacheDirectory {
        directories: Vec::new(),
        files,
        symlinks: Vec::new(),
        version: 1,
    })?;
    let directory = staged_bytes(staging.path(), "directory.json", &directory)?;
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
    Ok(action)
}

fn staged_bytes(directory: &Path, name: &str, bytes: &[u8]) -> Result<(CacheDigest, PathBuf)> {
    let path = directory.join(name);
    std::fs::write(&path, bytes)?;
    Ok((CacheDigest::blake3(bytes), path))
}

#[cfg(test)]
#[path = "rustc_tests.rs"]
mod tests;
