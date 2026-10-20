use super::note;
use crate::config::{Config, SummaryStyle};
use crate::util::{format_duration, write_atomic};
use bytesize::ByteSize;
use eyre::Result;
use log::warn;
use serde::Serialize;
use std::collections::BTreeMap;
use std::path::Path;
use tuist_cargo_cache_core::AgentStats;

#[derive(Serialize)]
pub(super) struct StatsReport {
    version: u8,
    session_duration_ns: u64,
    wrapper_phases_ns: BTreeMap<String, u64>,
    lookups: u64,
    hits: u64,
    misses: u64,
    unconsulted: u64,
    incremental_compilations: u64,
    compiler_invocations_avoided: u64,
    estimated_compiler_duration_avoided_ns: u64,
    compiler: BTreeMap<String, CompilerStatsReport>,
    slow_compilations: Vec<SlowCompilationReport>,
    verifications: u64,
    divergences: u64,
    prefetched_actions: u64,
    predictions_loaded: u64,
    prefetch_runs: u64,
    bypasses: BTreeMap<String, u64>,
    downloaded_bytes: u64,
    uploaded_bytes: u64,
    background_uploads: u64,
    background_upload_failures: u64,
    remote_blob_pack_uploads: u64,
    remote_blob_pack_upload_blobs: u64,
    upload_drain_duration_ns: u64,
    stored_bytes: u64,
    restored_output_files: u64,
    restored_output_bytes: u64,
    reflinked_output_files: u64,
    reflinked_output_bytes: u64,
    hardlinked_output_files: u64,
    hardlinked_output_bytes: u64,
    copied_output_files: u64,
    copied_output_bytes: u64,
    reused_output_files: u64,
    reused_output_bytes: u64,
    remote_failures: u64,
    remote_manifest_lookups: u64,
    remote_action_lookups: u64,
    remote_blob_requests: u64,
    remote_blob_pack_requests: u64,
    remote_blob_pack_blobs: u64,
    remote_manifest_lookup_duration_ns: u64,
    remote_action_lookup_duration_ns: u64,
    remote_blob_transfer_duration_ns: u64,
    local_cas_write_duration_ns: u64,
    prefetch_duration_ns: u64,
    materialization_duration_ns: u64,
}

#[derive(Serialize)]
struct CompilerStatsReport {
    invocations: u64,
    duration_ns: u64,
}

#[derive(Serialize)]
struct SlowCompilationReport {
    crate_name: String,
    duration_ns: u64,
}

impl From<&AgentStats> for StatsReport {
    fn from(stats: &AgentStats) -> Self {
        Self {
            version: 5,
            wrapper_phases_ns: stats.wrapper_phases_ns.clone(),
            session_duration_ns: stats.session_duration_ns,
            lookups: stats.lookups,
            hits: stats.hits,
            misses: cache_misses(stats),
            unconsulted: stats.unconsulted,
            incremental_compilations: incremental_compilations(stats),
            compiler_invocations_avoided: stats.hits,
            estimated_compiler_duration_avoided_ns: stats.avoided_compiler_duration_ns,
            compiler: stats
                .compiler
                .iter()
                .map(|(outcome, stats)| {
                    (
                        outcome.clone(),
                        CompilerStatsReport {
                            invocations: stats.invocations,
                            duration_ns: stats.duration_ns,
                        },
                    )
                })
                .collect(),
            slow_compilations: slow_compilations(stats)
                .into_iter()
                .map(|(crate_name, duration_ns)| SlowCompilationReport {
                    crate_name: crate_name.clone(),
                    duration_ns: *duration_ns,
                })
                .collect(),
            verifications: stats.verifications,
            divergences: stats.divergences,
            prefetched_actions: stats.prefetched_actions,
            predictions_loaded: stats.predictions_loaded,
            prefetch_runs: stats.prefetch_runs,
            bypasses: stats.bypasses.clone(),
            downloaded_bytes: stats.downloaded_bytes,
            uploaded_bytes: stats.uploaded_bytes,
            background_uploads: stats.background_uploads,
            background_upload_failures: stats.background_upload_failures,
            remote_blob_pack_uploads: stats.remote_blob_pack_uploads,
            remote_blob_pack_upload_blobs: stats.remote_blob_pack_upload_blobs,
            upload_drain_duration_ns: stats.upload_drain_duration_ns,
            stored_bytes: stats.stored_bytes,
            restored_output_files: stats.restored_output_files,
            restored_output_bytes: stats.restored_output_bytes,
            reflinked_output_files: stats.reflinked_output_files,
            reflinked_output_bytes: stats.reflinked_output_bytes,
            hardlinked_output_files: stats.hardlinked_output_files,
            hardlinked_output_bytes: stats.hardlinked_output_bytes,
            copied_output_files: stats.copied_output_files,
            copied_output_bytes: stats.copied_output_bytes,
            reused_output_files: stats.reused_output_files,
            reused_output_bytes: stats.reused_output_bytes,
            remote_failures: stats.remote_failures,
            remote_manifest_lookups: stats.remote_manifest_lookups,
            remote_action_lookups: stats.remote_action_lookups,
            remote_blob_requests: stats.remote_blob_requests,
            remote_blob_pack_requests: stats.remote_blob_pack_requests,
            remote_blob_pack_blobs: stats.remote_blob_pack_blobs,
            remote_manifest_lookup_duration_ns: stats.remote_manifest_lookup_duration_ns,
            remote_action_lookup_duration_ns: stats.remote_action_lookup_duration_ns,
            remote_blob_transfer_duration_ns: stats.remote_blob_transfer_duration_ns,
            local_cas_write_duration_ns: stats.local_cas_write_duration_ns,
            prefetch_duration_ns: stats.prefetch_duration_ns,
            materialization_duration_ns: stats.materialization_duration_ns,
        }
    }
}

/// Report a finished session to stderr, and to a JSON file when configured.
pub(crate) fn display_stats(stats: &AgentStats, config: &Config, style: SummaryStyle) {
    if let Some(path) = &config.stats_report
        && let Err(error) = write_stats_report(path, stats)
    {
        warn!(
            "the statistics report could not be written to {}: {error}",
            path.display()
        );
    }
    match style.resolve(crate::policy::is_ci()) {
        SummaryStyle::Auto => unreachable!("auto summary was resolved"),
        SummaryStyle::Off => return,
        SummaryStyle::Short => {
            if should_display_short_stats(stats) {
                note(&short_summary(stats));
            }
            return;
        }
        SummaryStyle::Ci => {
            if should_display_short_stats(stats) {
                note(&ci_summary(stats));
            }
            return;
        }
        SummaryStyle::Full => {}
    }
    if !should_display_stats(stats) {
        return;
    }
    note(&format!(
        "tuist_cargo_cache[cache]: {} hits, {} misses, {} prefetched; {} downloaded, {} uploaded, {} stored locally",
        stats.hits,
        cache_misses(stats),
        stats.prefetched_actions,
        ByteSize::b(stats.downloaded_bytes).display().iec(),
        ByteSize::b(stats.uploaded_bytes).display().iec(),
        ByteSize::b(stats.stored_bytes).display().iec(),
    ));
    if stats.remote_failures > 0 {
        // A remote cache that fails every request reports the same hits, misses
        // and bytes as one that was simply empty, and the warnings explaining
        // why scroll past hundreds of lines earlier. Without this line the
        // summary reads as "the remote had nothing for us" no matter which it
        // was, and a cache that has stopped working looks like a cold one.
        note(&format!(
            "tuist_cargo_cache[cache]: the remote cache failed {} of its requests; this build ran without what it could not reach, and the warnings above say why",
            stats.remote_failures,
        ));
    }
    if stats.unconsulted > 0 {
        // A cold target directory hits this for everything it compiles, and
        // reporting only hits and misses there says "0 hits, 0 misses" -- which
        // reads as though the cache was asked and had nothing, rather than that
        // it was never asked. These compilations are still stored afterwards.
        note(&format!(
            "tuist_cargo_cache[cache]: could not look up {} compilations: no usable dep-info from an earlier build and no prediction to derive an action key from",
            stats.unconsulted,
        ));
        if let Some(explanation) = stale_manifest_note(stats) {
            note(&explanation);
        }
    }
    if !stats.bypasses.is_empty() {
        let total: u64 = stats.bypasses.values().sum();
        // Most frequent first: the head of this list is where the next win is.
        let mut reasons: Vec<_> = stats.bypasses.iter().collect();
        reasons.sort_by(|left, right| right.1.cmp(left.1).then(left.0.cmp(right.0)));
        let detail = reasons
            .iter()
            .map(|(kind, count)| format!("{count} {kind}"))
            .collect::<Vec<_>>()
            .join(", ");
        note(&format!(
            "tuist_cargo_cache[cache]: bypassed {total} compilations: {detail}"
        ));
    }
    if !stats.compiler.is_empty() || stats.avoided_compiler_duration_ns > 0 {
        let spent = stats.compiler.values().fold(0_u64, |total, compiler| {
            total.saturating_add(compiler.duration_ns)
        });
        let detail = stats
            .compiler
            .iter()
            .map(|(outcome, compiler)| {
                format!(
                    "{} {} in {}",
                    compiler.invocations,
                    outcome,
                    format_nanos(compiler.duration_ns)
                )
            })
            .collect::<Vec<_>>()
            .join(", ");
        note(&format!(
            "tuist_cargo_cache[cache]: compiler time: {} estimated avoided; {} spent ({detail})",
            format_nanos(stats.avoided_compiler_duration_ns),
            format_nanos(spent),
        ));
        if incremental_compilations(stats) > 0 {
            // The compiler-time line above already counts these; what it cannot
            // say is why they are absent from the store.
            note(&format!(
                "tuist_cargo_cache[cache]: {} compilations kept their own incremental state, so they were not stored",
                incremental_compilations(stats)
            ));
        }
        let slow = slow_compilations(stats);
        if !slow.is_empty() {
            note(&format!(
                "tuist_cargo_cache[cache]: slowest uncached crates: {}",
                slow.into_iter()
                    .map(|(name, duration)| format!("{name} {}", format_nanos(*duration)))
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
        }
    }
    if !stats.wrapper_phases_ns.is_empty() {
        note(&format!(
            "tuist_cargo_cache[cache]: wrapper phases (cumulative, exclusive): {}",
            stats
                .wrapper_phases_ns
                .iter()
                .map(|(phase, ns)| format!("{phase} {}", format_nanos(*ns)))
                .collect::<Vec<_>>()
                .join(", ")
        ));
    }
    let remote_lookup_duration_ns = stats
        .remote_manifest_lookup_duration_ns
        .saturating_add(stats.remote_action_lookup_duration_ns);
    note(&format!(
        "tuist_cargo_cache[cache]: timing: {} session, {} prefetch; cumulative {} remote lookup, {} blob transfer, {} CAS write, {} materialization",
        format_nanos(stats.session_duration_ns),
        format_nanos(stats.prefetch_duration_ns),
        format_nanos(remote_lookup_duration_ns),
        format_nanos(stats.remote_blob_transfer_duration_ns),
        format_nanos(stats.local_cas_write_duration_ns),
        format_nanos(stats.materialization_duration_ns),
    ));
    if stats.background_uploads > 0 || stats.background_upload_failures > 0 {
        let packed = if stats.remote_blob_pack_uploads > 0 {
            format!(
                " ({} of them in {} packs)",
                stats.remote_blob_pack_upload_blobs, stats.remote_blob_pack_uploads
            )
        } else {
            String::new()
        };
        note(&format!(
            "tuist_cargo_cache[cache]: uploads: {} published{packed}, {} not published; {} waited for after the build",
            stats.background_uploads,
            stats.background_upload_failures,
            format_nanos(stats.upload_drain_duration_ns),
        ));
    }
    if stats.restored_output_files > 0 {
        note(&format!(
            "tuist_cargo_cache[cache]: materialization: {} outputs ({}) reflinked, {} outputs ({}) hard linked, {} outputs ({}) copied, {} outputs ({}) already in place",
            stats.reflinked_output_files,
            ByteSize::b(stats.reflinked_output_bytes).display().iec(),
            stats.hardlinked_output_files,
            ByteSize::b(stats.hardlinked_output_bytes).display().iec(),
            stats.copied_output_files,
            ByteSize::b(stats.copied_output_bytes).display().iec(),
            stats.reused_output_files,
            ByteSize::b(stats.reused_output_bytes).display().iec(),
        ));
    }
    if stats.verifications > 0 {
        note(&format!(
            "tuist_cargo_cache[cache]: qualification: {} verified, {} diverged",
            stats.verifications, stats.divergences,
        ));
    }
}

/// The one-line result leaves routine compiler probes out of both its bypass
/// count and its activity gate. Cargo and build scripts make these calls to
/// identify a compiler or feed it source, so a no-op build should remain a
/// no-op to somebody reading its output.
pub(super) fn short_summary(stats: &AgentStats) -> String {
    let unexpected_bypasses = unexpected_bypasses(stats);
    let mut outcomes = vec![
        format!("{} hits", stats.hits),
        format!("{} misses", cache_misses(stats)),
    ];
    if stats.unconsulted > 0 {
        outcomes.push(format!("{} not looked up", stats.unconsulted));
    }
    // Without this, an edit loop that compiled every unit from its own
    // incremental state reports "0 hits, 0 misses" and reads as though nothing
    // had happened. The full summary explains why they were not stored; the
    // one-liner at least has to admit they exist.
    if incremental_compilations(stats) > 0 {
        outcomes.push(format!("{} incremental", incremental_compilations(stats)));
    }
    if stats.prefetched_actions > 0 {
        outcomes.push(format!("{} prefetched", stats.prefetched_actions));
    }
    if unexpected_bypasses > 0 {
        outcomes.push(format!("{unexpected_bypasses} bypassed"));
    }
    if stats.verifications > 0 {
        outcomes.push(format!(
            "{} verified, {} diverged",
            stats.verifications, stats.divergences
        ));
    }
    if stats.remote_failures > 0 {
        outcomes.push(format!("{} remote failures", stats.remote_failures));
    }
    format!(
        "tuist_cargo_cache[cache]: {}; {} downloaded, {} uploaded, {} stored locally",
        outcomes.join(", "),
        ByteSize::b(stats.downloaded_bytes).display().iec(),
        ByteSize::b(stats.uploaded_bytes).display().iec(),
        ByteSize::b(stats.stored_bytes).display().iec(),
    )
}

/// These counters cover tuist_cargo_cache objects, not a CI action's archive transfers or
/// artifacts Cargo found fresh before invoking a compiler wrapper.
pub(super) fn ci_summary(stats: &AgentStats) -> String {
    let mut lines = vec![short_summary(stats).replacen(
        "tuist_cargo_cache[cache]: ",
        "tuist_cargo_cache[cache]: object cache: ",
        1,
    )];
    lines.push(format!(
        "tuist_cargo_cache[cache]: {} session; {} estimated compiler time avoided (summed across compilations)",
        format_nanos(stats.session_duration_ns),
        format_nanos(stats.avoided_compiler_duration_ns),
    ));
    if stats.unconsulted > 0 {
        lines.push(format!(
            "tuist_cargo_cache[cache]: {} compilations had no usable prior inputs or matching prediction for a lookup",
            stats.unconsulted,
        ));
        if let Some(explanation) = stale_manifest_note(stats) {
            lines.push(explanation);
        }
    }
    let mut bypasses = stats
        .bypasses
        .iter()
        .filter(|(kind, _)| !routine_probe(kind))
        .collect::<Vec<_>>();
    bypasses.sort_by(|left, right| right.1.cmp(left.1).then(left.0.cmp(right.0)));
    if !bypasses.is_empty() {
        lines.push(format!(
            "tuist_cargo_cache[cache]: bypass reasons: {}",
            bypasses
                .into_iter()
                .map(|(kind, count)| format!("{count} {kind}"))
                .collect::<Vec<_>>()
                .join(", "),
        ));
    }
    if stats.background_upload_failures > 0 {
        lines.push(format!(
            "tuist_cargo_cache[cache]: {} background uploads failed; see warnings above",
            stats.background_upload_failures,
        ));
    }
    lines.push(
        "tuist_cargo_cache[cache]: Cargo artifact reuse and CI cache archive transfers are not included above"
            .to_string(),
    );
    lines.join("\n")
}

/// Identify compiler discovery and stdin probes that are routine build traffic.
fn routine_probe(kind: &str) -> bool {
    matches!(
        kind,
        "compiler-query" | "standard-input" | "cc-compiler-query" | "cc-standard-input"
    )
}

/// Count bypasses worth reporting, excluding routine compiler probes.
pub(crate) fn unexpected_bypasses(stats: &AgentStats) -> u64 {
    stats
        .bypasses
        .iter()
        .filter(|(kind, _)| !routine_probe(kind))
        .map(|(_, count)| count)
        .sum()
}

/// Show short and CI reports only for cache activity or failures, so compiler
/// probes alone do not turn a no-op build into a cache report.
pub(super) fn should_display_short_stats(stats: &AgentStats) -> bool {
    stats.lookups > 0
        || stats.unconsulted > 0
        || incremental_compilations(stats) > 0
        || stats.prefetched_actions > 0
        || stats.stores > 0
        || stats.verifications > 0
        || stats.downloaded_bytes > 0
        || stats.uploaded_bytes > 0
        || stats.background_uploads > 0
        || stats.background_upload_failures > 0
        || unexpected_bypasses(stats) > 0
        || stats.avoided_compiler_duration_ns > 0
        || stats.remote_failures > 0
}

/// Explain a session that loaded a full manifest and matched none of it.
///
/// "No prediction to derive an action key from" reads as an empty store, and
/// for a warm store that just watched its compiler change underneath it -- a
/// CI runner image updating its preinstalled toolchain is the common way --
/// that reading sends people hunting for restore failures. The distinction is
/// observable: predictions were loaded, and not one lookup was ever made.
///
/// Only when what compiled is a real share of what was predicted, though. The
/// manifest is shared by every Cargo command in a workspace, so the first
/// `cargo test --no-run` after `cargo build` compiles a couple of test
/// harnesses the manifest has never seen and looks nothing up, while a
/// toolchain change recompiles everything the manifest predicted. A handful
/// of new units against hundreds of predictions is the former.
pub(super) fn stale_manifest_note(stats: &AgentStats) -> Option<String> {
    (stats.unconsulted > 0
        && stats.lookups == 0
        && stats.predictions_loaded > 0
        && stats.unconsulted.saturating_mul(2) >= stats.predictions_loaded)
        .then(|| {
        format!(
            "tuist_cargo_cache[cache]: a manifest predicting {} compilations was loaded, but none matched this build; the compiler or its flags changed since they were recorded (a toolchain update does this)",
            stats.predictions_loaded,
        )
    })
}

/// Whether the cache took part in this build at all.
///
/// A run that never consulted or stored anything -- `cargo --help`, a build
/// cargo declined -- has nothing to report and should not be counted as a
/// build in the lifetime totals.
pub(crate) fn session_was_active(stats: &AgentStats) -> bool {
    should_display_stats(stats)
}

pub(super) fn should_display_stats(stats: &AgentStats) -> bool {
    stats.lookups > 0
        || stats.unconsulted > 0
        || stats.stores > 0
        || stats.verifications > 0
        || stats.downloaded_bytes > 0
        || stats.uploaded_bytes > 0
        // An action result published on its own moves no payload bytes, and is
        // still the whole of what a session did.
        || stats.background_uploads > 0
        || !stats.bypasses.is_empty()
        || !stats.compiler.is_empty()
        || stats.avoided_compiler_duration_ns > 0
        // A session that reached a remote cache and got nothing but failures has
        // nothing else to report, and is the session most worth reporting.
        || stats.remote_failures > 0
}

pub(super) fn write_stats_report(path: &Path, stats: &AgentStats) -> Result<()> {
    let mut report = serde_json::to_vec_pretty(&StatsReport::from(stats))?;
    report.push(b'\n');
    write_atomic(path, &report)
}

fn format_nanos(nanoseconds: u64) -> String {
    format_duration(std::time::Duration::from_nanos(nanoseconds))
}

fn slow_compilations(stats: &AgentStats) -> Vec<(&String, &u64)> {
    let mut slow = stats.slow_compilations.iter().collect::<Vec<_>>();
    slow.sort_by(|left, right| right.1.cmp(left.1).then(left.0.cmp(right.0)));
    slow.truncate(5);
    slow
}

/// Compilations that consulted the cache and had to compile anyway.
///
/// Counted from the compiler invocations the adapters record, not from
/// `lookups`, because one compilation may probe more than one action key: a
/// crate that reads a portable environment value is looked up under both its
/// portable and its literal key. Deriving misses by subtraction counted the
/// second probe as a miss of its own, so a crate that hit on its literal key
/// was reported as a hit and a miss at once, and a crate that missed both was
/// reported twice. This is the number the per-action ledger holds, which is
/// what `tuist_cargo_cache explain` reads back.
///
/// An incremental compilation counts when its lookup missed, and not when it
/// never made one: those are separate outcomes now rather than one word
/// covering both. Keeping private incremental state is reported beside this
/// rather than instead of it, because it says what became of the result, not
/// what the cache was asked.
pub(crate) fn cache_misses(stats: &AgentStats) -> u64 {
    stats
        .compiler
        .get("miss")
        .map_or(0, |compiler| compiler.invocations)
}

/// Compilations that kept private incremental state, and so were not stored.
pub(super) fn incremental_compilations(stats: &AgentStats) -> u64 {
    stats.incremental_compilations
}
