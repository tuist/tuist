use super::cache::{
    GcActionStoreReport, GcGeneratedReport, GcIncrementalReport, GcReport, GcTargetReport,
    print_json,
};
use crate::config::{Config, MinFree, RetentionSettings};
use crate::{store, target};
use bytesize::ByteSize;
use eyre::{Context, Result};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

/// Where the collector a build started leaves what it freed, for the next
/// build to say. Claimed by rename, so two builds finishing together cannot
/// both report it.
pub(super) const SWEEP_REPORT: &str = "gc/v1/last-sweep-report";

/// The detached collector's stderr: warnings a sweep logs have no terminal
/// to reach, and a sweep that never finished is diagnosed from here.
const SWEEP_LOG: &str = "gc/v1/sweep.log";

/// Held by a collector for as long as it sweeps. A build's due check is
/// unlocked and a zero interval makes every build due, so without this two
/// collectors could walk the same store at once and each report only its own
/// half; an automatic collector that finds it held has nothing left to do, and
/// an explicit `tuist_cargo_cache gc` waits its turn.
const COLLECTOR_LOCK: &str = "gc/v1/collector.lock";

/// The longest a build waits between sweeps while a disk is short of
/// `gc.min_free_size`. Several builds at once can fill a disk well inside the
/// usual hour, and a sweep that finds nothing left to free costs a walk in a
/// detached process, not time on a build.
pub(super) const LOW_DISK_INTERVAL: Duration = Duration::from_secs(5 * 60);

/// A low-disk sweep may need several passes over one tier, because links and
/// reflinks can make the physical space recovered smaller than the bytes
/// removed from a tree. The bound is per tier, so a tier that frees a little
/// on every pass cannot use up the rounds the shared store needs, and a disk
/// filled by unrelated data cannot make collection unbounded.
const LOW_DISK_ROUNDS_PER_TIER: usize = 4;

#[derive(usage_rs::Args)]
pub(super) struct GcArgs {
    /// Size the action store may occupy afterwards, such as `20GiB`.
    ///
    /// Defaults to `gc.max_size`. Managed targets, learned incremental state,
    /// and generated source trees are still collected to their own budgets.
    /// With `gc.max_total_size` set, they share what is left of that total
    /// after the action store, whose share this flag caps.
    #[usage(long, value_name = "SIZE")]
    pub(super) max_size: Option<ByteSize>,
    /// Print a stable machine-readable report.
    #[usage(long)]
    pub(super) json: bool,
    /// Show what collection would remove without changing any files.
    ///
    /// While a disk has less free space than `gc.min_free_size`, a real run
    /// can remove a different amount than the preview, because it measures the
    /// disk again after each step. To free the cache disk, a real run can also
    /// evict more store objects than the action-store budget requires, and the
    /// preview never lists them.
    #[usage(long)]
    pub(super) dry_run: bool,
    /// Run the throttled sweep a build schedules, if one is due. Builds start
    /// this in the background; it is not meant to be typed.
    #[usage(long, hide = true)]
    pub(super) automatic: bool,
}

pub(super) fn run(
    config: &Config,
    max_bytes: u64,
    dry_run: bool,
    json: bool,
    retention: &RetentionSettings,
) -> Result<()> {
    let store = config.store_dir();
    let mut collector = collector_lock(&store)?;
    if !dry_run {
        collector.lock()?;
    }
    let mut low_disk = None;
    let store_reserve = occupied_store_budget(config, retention, max_bytes);
    let incremental_limit = incremental_limit(config, retention, store_reserve, &mut low_disk);
    // The collector below remains the authority for store errors. Estimating
    // a combined budget must not prevent independent target collection when
    // the action store is damaged.
    let mut accounting_complete = true;
    let incremental = match crate::incremental::collect(
        &config.cache_dir.join("incremental"),
        incremental_limit,
        retention.incremental_max_age,
        dry_run,
    ) {
        Ok(outcome) => outcome,
        Err(error) => {
            log::warn!("learned incremental state was not collected: {error}");
            let stats = crate::incremental::stats(&config.cache_dir.join("incremental"))
                .unwrap_or_else(|_| {
                    accounting_complete = false;
                    Default::default()
                });
            crate::incremental::PruneOutcome {
                remaining_directories: stats.directories,
                remaining_bytes: stats.bytes,
                untracked_directories: stats.untracked_directories,
                ..crate::incremental::PruneOutcome::default()
            }
        }
    };
    // Generated source trees share the learned incremental budget: both are
    // per-checkout state that a compilation reads, and both come back on
    // their own when evicted.
    let generated = collect_generated(
        config,
        incremental_limit.map(|budget| budget.saturating_sub(incremental.remaining_bytes)),
        retention.target_max_age,
        dry_run,
        &mut accounting_complete,
    );
    // What survives counts against the combined budget the same as learned
    // incremental state: bytes on the disk the limit was set for.
    let reserved_bytes = incremental
        .remaining_bytes
        .saturating_add(generated.remaining_bytes);
    let target_budget = target_limit(
        config,
        retention,
        store_reserve,
        reserved_bytes,
        &mut low_disk,
    );
    // First, ahead of the removals it explains, all of which print below.
    if let Some(disk) = &low_disk
        && !json
    {
        println!("{}", disk.describe(dry_run));
        if dry_run {
            println!(
                "a real run measures the disk again after each step, so it may remove fewer target directories"
            );
        }
    }
    let pruned = target::collect_by(
        &config.target.root,
        target_budget,
        retention.target_max_age,
        &retention.target_precedence,
        dry_run,
    );
    let projected_target_bytes = match &pruned {
        Ok(outcome) => Some(outcome.remaining_bytes),
        Err(_) if retention.max_total_bytes.is_some() => target::stats(&config.target.root)
            .ok()
            .map(|stats| stats.bytes),
        Err(_) => None,
    };
    let non_store_bytes = projected_target_bytes
        .filter(|_| accounting_complete)
        .map(|bytes| bytes.saturating_add(reserved_bytes));
    let store_budget = store_budget(retention, max_bytes, non_store_bytes);
    // Small and never load-bearing: a swept flight costs at most one
    // compilation that would have been a hit, so it is not part of the
    // budget arithmetic or the dry run's accounting.
    if !dry_run {
        crate::scheduler::prune_flights(&config.cache_dir);
    }
    let outcome = if dry_run {
        store::gc_dry_run(&store, store_budget)
    } else {
        store::gc(&store, store_budget)
    };
    // Independent collections: a broken action store must not prevent the
    // command from freeing the usually much larger target directories.
    let outcome = match outcome {
        Ok(outcome) => outcome,
        Err(error) => {
            let mut freed_bytes = incremental.removed_bytes + generated.removed_bytes;
            match pruned {
                Ok(pruned) => {
                    // Credit what the targets gave back even though the store
                    // sweep failed: those bytes are gone from the disk either way.
                    freed_bytes = freed_bytes.saturating_add(pruned.freed_bytes());
                    if !json {
                        for line in target_removals(&pruned, dry_run) {
                            println!("{line}");
                        }
                    }
                }
                Err(prune_error) => {
                    log::warn!("target directories were not collected: {prune_error}");
                }
            }
            let low_disk = if dry_run {
                // A dry run keeps the one-shot preview: it cannot measure the
                // physical bytes each hypothetical removal would return.
                LowDiskCollection::default()
            } else {
                collect_low_disk(config, retention)
            };
            let low_store_bytes = low_disk
                .store
                .as_ref()
                .map_or(0, |outcome| outcome.removed_bytes);
            freed_bytes = freed_bytes.saturating_add(low_disk.freed_target_bytes);
            record_collection(&store, low_store_bytes, freed_bytes, dry_run);
            if !json {
                print_incremental_removals(&incremental, dry_run);
                print_generated_removals(&generated, dry_run);
                for line in low_disk.lines {
                    println!("{line}");
                }
            }
            if !dry_run {
                warn_if_still_low(config, retention);
            }
            return Err(error);
        }
    };
    let mut low_disk = if dry_run {
        // A dry run keeps the one-shot preview: it cannot measure the
        // physical bytes each hypothetical removal would return.
        LowDiskCollection::default()
    } else {
        collect_low_disk(config, retention)
    };
    let low_disk_freed = low_disk.freed_bytes();
    let mut report_outcome = outcome;
    if let Some(low_store) = low_disk.store.take() {
        add_gc_outcome(&mut report_outcome, low_store);
    }
    let target_freed_bytes = pruned
        .as_ref()
        .map_or(0, target::CollectionOutcome::freed_bytes)
        .saturating_add(incremental.removed_bytes)
        .saturating_add(generated.removed_bytes)
        .saturating_add(low_disk.freed_target_bytes);
    record_collection(
        &store,
        report_outcome.removed_bytes,
        target_freed_bytes,
        dry_run,
    );
    let final_non_store_bytes =
        remeasured_non_store_bytes(config, retention, non_store_bytes, low_disk_freed);
    if let Some(warning) = total_budget_warning(
        retention,
        final_non_store_bytes.map(|bytes| report_outcome.remaining_bytes.saturating_add(bytes)),
        dry_run,
    ) {
        log::warn!("{warning}");
    }
    if json {
        let pruned = pruned?;
        print_json(&GcReport {
            version: 1,
            byte_accounting: "logical",
            max_bytes,
            max_total_bytes: retention.max_total_bytes,
            target_max_bytes: retention.target_max_bytes,
            incremental_max_bytes: retention.incremental_max_bytes,
            dry_run,
            action_store: GcActionStoreReport {
                removed_objects: report_outcome.removed_objects,
                removed_action_results: report_outcome.removed_action_results,
                removed_checkout_records: report_outcome.removed_checkout_records,
                removed_session_streams: report_outcome.removed_session_streams,
                removed_bytes: report_outcome.removed_bytes,
                remaining_bytes: report_outcome.remaining_bytes,
            },
            targets: low_disk.target_report(&pruned),
            incremental: merged_incremental_report(&incremental, low_disk.incremental.as_ref()),
            generated: merged_generated_report(&generated, low_disk.generated.as_ref()),
        })?;
    } else {
        print_gc_store_outcome(&report_outcome, dry_run);
        // This collection is independent of the managed-target walk below,
        // so report it even if that walk failed.
        print_incremental_removals(&incremental, dry_run);
        print_generated_removals(&generated, dry_run);
        let pruned = pruned?;
        for line in target_removals(&pruned, dry_run) {
            println!("{line}");
        }
        for line in low_disk.lines {
            println!("{line}");
        }
    }
    if !dry_run {
        warn_if_still_low(config, retention);
    }
    Ok(())
}

fn merged_incremental_report(
    initial: &crate::incremental::PruneOutcome,
    low_disk: Option<&crate::incremental::PruneOutcome>,
) -> GcIncrementalReport {
    let last = low_disk.unwrap_or(initial);
    GcIncrementalReport {
        removed_directories: initial
            .removed_directories
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_directories)),
        removed_bytes: initial
            .removed_bytes
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_bytes)),
        remaining_directories: last.remaining_directories,
        remaining_bytes: last.remaining_bytes,
        skipped_active_directories: last.skipped_active_directories,
        untracked_directories: last.untracked_directories,
    }
}

fn merged_generated_report(
    initial: &crate::out_dir::PruneOutcome,
    low_disk: Option<&crate::out_dir::PruneOutcome>,
) -> GcGeneratedReport {
    let last = low_disk.unwrap_or(initial);
    GcGeneratedReport {
        removed_directories: initial
            .removed_directories
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_directories)),
        removed_bytes: initial
            .removed_bytes
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_bytes)),
        remaining_directories: last.remaining_directories,
        remaining_bytes: last.remaining_bytes,
    }
}

fn merged_target_report(
    initial: &target::CollectionOutcome,
    low_disk: Option<&target::CollectionOutcome>,
) -> GcTargetReport {
    let last = low_disk.unwrap_or(initial);
    GcTargetReport {
        removed_directories: initial
            .removed_views
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_views)),
        removed_bytes: initial
            .removed_bytes
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_bytes)),
        removed_units: initial
            .removed_units
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_units)),
        removed_unit_bytes: initial
            .removed_unit_bytes
            .saturating_add(low_disk.map_or(0, |outcome| outcome.removed_unit_bytes)),
        remaining_directories: last.remaining_views,
        remaining_bytes: last.remaining_bytes,
        kept_active_directories: last.kept_active_views,
    }
}

/// Collect the stable copies of build-script output nothing has used lately.
///
/// Aged like target directories: a copy is only ever reached through a
/// compilation in some checkout, so what keeps a checkout's target also keeps
/// what its compilations read. A failure is logged and counts as nothing
/// freed; the trees are small beside what the rest of a sweep handles.
fn collect_generated(
    config: &Config,
    max_bytes: Option<u64>,
    max_age: Option<std::time::Duration>,
    dry_run: bool,
    accounting_complete: &mut bool,
) -> crate::out_dir::PruneOutcome {
    match crate::out_dir::collect(
        &config.cache_dir.join(crate::out_dir::ROOT),
        max_bytes,
        max_age,
        dry_run,
    ) {
        Ok(outcome) => outcome,
        Err(error) => {
            log::warn!("generated source trees were not collected: {error}");
            // Still on the disk, so still against the budget: measure what
            // remains rather than let a failed walk count as empty space. A
            // root that cannot be listed cannot be measured either, and the
            // sweep goes on without the number rather than not at all, since
            // one unreadable directory must not stop every other collection.
            match crate::out_dir::stats(&config.cache_dir.join(crate::out_dir::ROOT)) {
                Some(outcome) => outcome,
                None => {
                    *accounting_complete = false;
                    log::warn!("generated source trees could not be measured");
                    crate::out_dir::PruneOutcome::default()
                }
            }
        }
    }
}

fn print_generated_removals(outcome: &crate::out_dir::PruneOutcome, dry_run: bool) {
    for line in generated_removal_lines(outcome, dry_run) {
        println!("{line}");
    }
}

/// One line describing the generated source trees a sweep freed.
fn generated_removal_lines(outcome: &crate::out_dir::PruneOutcome, dry_run: bool) -> Vec<String> {
    if outcome.removed_directories == 0 {
        return Vec::new();
    }
    let verb = if dry_run { "would remove" } else { "removed" };
    vec![format!(
        "{verb} {} generated source trees ({} logical); {} logical remain",
        outcome.removed_directories,
        ByteSize::b(outcome.removed_bytes).display().iec(),
        ByteSize::b(outcome.remaining_bytes).display().iec(),
    )]
}

fn generated_removals(outcome: &crate::out_dir::PruneOutcome, dry_run: bool) -> String {
    generated_removal_lines(outcome, dry_run)
        .into_iter()
        .next()
        .unwrap_or_default()
}

fn print_incremental_removals(outcome: &crate::incremental::PruneOutcome, dry_run: bool) {
    for line in incremental_removal_lines(outcome, dry_run) {
        println!("{line}");
    }
}

fn incremental_removal_lines(
    outcome: &crate::incremental::PruneOutcome,
    dry_run: bool,
) -> Vec<String> {
    if outcome.removed_directories == 0
        && outcome.skipped_active_directories == 0
        && outcome.untracked_directories == 0
    {
        return Vec::new();
    }
    let verb = if dry_run { "would remove" } else { "removed" };
    let mut lines = vec![format!(
        "{verb} {} learned incremental directories ({} logical); {} logical remain",
        outcome.removed_directories,
        ByteSize::b(outcome.removed_bytes).display().iec(),
        ByteSize::b(outcome.remaining_bytes).display().iec(),
    )];
    if outcome.skipped_active_directories > 0 {
        lines.push(format!(
            "kept {} learned incremental directories used by active builds",
            outcome.skipped_active_directories
        ));
    }
    if outcome.untracked_directories > 0 {
        lines.push(format!(
            "kept {} learned incremental directories with unreadable checkout records",
            outcome.untracked_directories
        ));
    }
    lines
}

/// Add what a collection reclaimed to this machine's lifetime totals.
///
/// A dry run reclaimed nothing, so it contributes nothing.
pub(super) fn record_collection(store: &Path, store_bytes: u64, target_bytes: u64, dry_run: bool) {
    if dry_run || (store_bytes == 0 && target_bytes == 0) {
        return;
    }
    crate::savings::record_quietly(
        store,
        &crate::savings::Delta {
            freed_store_bytes: store_bytes,
            freed_target_bytes: target_bytes,
            ..crate::savings::Delta::default()
        },
    );
}

pub(super) fn print_gc_store_outcome(outcome: &store::GcOutcome, dry_run: bool) {
    let prefix = if dry_run { "would have " } else { "" };
    println!("{prefix}{}", evictions(outcome));
    if outcome.removed_checkout_records > 0 {
        println!(
            "{prefix}dropped {} stale checkout records",
            outcome.removed_checkout_records
        );
    }
    if outcome.removed_session_streams > 0 {
        println!(
            "{prefix}dropped {} session event streams",
            outcome.removed_session_streams
        );
    }
}

/// The lines describing the target directories and unused build units a
/// sweep freed; none when it freed neither.
pub(super) fn target_removals(outcome: &target::CollectionOutcome, dry_run: bool) -> Vec<String> {
    let verb = if dry_run { "would remove" } else { "removed" };
    let mut lines = Vec::new();
    let kept = if outcome.kept_active_views > 0 {
        format!(
            ", {} kept for running commands or builds that started meanwhile",
            outcome.kept_active_views
        )
    } else {
        String::new()
    };
    if outcome.removed_views > 0 {
        lines.push(format!(
            "{verb} {} target directories ({} logical, {} abandoned and {} live{kept}); {} logical remain",
            outcome.removed_views,
            ByteSize::b(outcome.removed_bytes).display().iec(),
            outcome.removed_stale_views,
            outcome.removed_live_views,
            ByteSize::b(outcome.remaining_bytes).display().iec(),
        ));
    } else if outcome.kept_active_views > 0 {
        // Said on its own when nothing else went, so a collection that could
        // not free a directory somebody is using does not look like one that
        // found nothing to do.
        lines.push(format!(
            "kept {} target directories in use by running commands",
            outcome.kept_active_views
        ));
    }
    if outcome.removed_units > 0 {
        lines.push(format!(
            "{verb} {} unused build units from live target directories ({} logical)",
            outcome.removed_units,
            ByteSize::b(outcome.removed_unit_bytes).display().iec(),
        ));
    } else if outcome.removed_unit_bytes > 0 {
        // Only what an interrupted collection left: no units to count, but
        // space freed all the same.
        lines.push(format!(
            "{verb} build units an interrupted collection left in live target directories ({} logical)",
            ByteSize::b(outcome.removed_unit_bytes).display().iec(),
        ));
    }
    lines
}

/// One line describing what a sweep evicted.
///
/// Shared so the explicit command and the automatic sweep cannot drift into
/// describing the same outcome two different ways.
pub(super) fn evictions(outcome: &store::GcOutcome) -> String {
    format!(
        "evicted {} objects and {} action results ({} logical); {} logical remain",
        outcome.removed_objects,
        outcome.removed_action_results,
        ByteSize::b(outcome.removed_bytes).display().iec(),
        ByteSize::b(outcome.remaining_bytes).display().iec(),
    )
}

/// What an automatic sweep freed, and the lines that say so.
#[derive(Debug, Default)]
pub(super) struct Sweep {
    pub(super) delta: crate::savings::Delta,
    /// One line per collection that removed something, without the `tuist_cargo_cache[gc]`
    /// prefix: a sweep that evicted nothing says nothing.
    pub(super) lines: Vec<String>,
}

/// Keep the store inside its budget, at most once per configured interval.
///
/// A sweep that fails is logged and forgotten: the build that scheduled it
/// is already over, and its exit status is the build's answer, not the
/// collector's. What it freed is returned so the lifetime totals can count it.
pub(super) fn sweep_store(config: &Config, retention: &RetentionSettings) -> Sweep {
    if !config.gc.auto {
        return Sweep::default();
    }
    match store::claim_sweep(&config.store_dir(), sweep_interval(config, retention)) {
        Ok(false) => Sweep::default(),
        Ok(true) => {
            start_sweep_log(&config.store_dir());
            run_sweep_body(config, retention)
        }
        Err(error) => {
            log::warn!("the store was not swept: {error}");
            // The stamp only throttles automatic work. The collector lock is
            // the mutual exclusion, so a failed claim must still run the
            // complete sweep while the disk is already under pressure.
            start_sweep_log(&config.store_dir());
            run_sweep_body(config, retention)
        }
    }
}

/// Run every collection belonging to one automatic sweep.
fn run_sweep_body(config: &Config, retention: &RetentionSettings) -> Sweep {
    let mut sweep = Sweep::default();
    let pruned = prune_targets(config, retention, config.gc.max_bytes);
    sweep.delta.freed_target_bytes = pruned.freed_bytes;
    sweep.lines.extend(pruned.removals);
    let non_store_bytes = pruned.remaining_bytes.or_else(|| {
        let target_bytes = target::stats(&config.target.root).ok()?.bytes;
        let incremental_bytes = crate::incremental::stats(&config.cache_dir.join("incremental"))
            .ok()?
            .bytes;
        let generated_bytes =
            crate::out_dir::stats(&config.cache_dir.join(crate::out_dir::ROOT))?.remaining_bytes;
        Some(
            target_bytes
                .saturating_add(incremental_bytes)
                .saturating_add(generated_bytes),
        )
    });
    let store_budget = store_budget(retention, config.gc.max_bytes, non_store_bytes);
    crate::scheduler::prune_flights(&config.cache_dir);
    let outcome = match store::gc(&config.store_dir(), store_budget) {
        Ok(outcome) => outcome,
        Err(error) => {
            log::warn!("the store was not swept: {error}");
            store::GcOutcome::default()
        }
    };
    sweep.delta.freed_store_bytes = outcome.removed_bytes;
    if outcome.removed_bytes > 0 {
        sweep.lines.push(evictions(&outcome));
    }

    // Budget-driven collection above is only an estimate of physical relief.
    // The loop measures the disk after every logical pass and reaches the
    // shared store only after private state and targets stop freeing bytes.
    let low_disk = collect_low_disk(config, retention);
    let low_disk_freed = low_disk.freed_bytes();
    let low_store_freed = low_disk
        .store
        .as_ref()
        .map_or(0, |outcome| outcome.removed_bytes);
    let mut report_outcome = outcome;
    if let Some(low_store) = low_disk.store {
        add_gc_outcome(&mut report_outcome, low_store);
    }
    sweep.delta.freed_target_bytes = sweep
        .delta
        .freed_target_bytes
        .saturating_add(low_disk.freed_target_bytes);
    sweep.delta.freed_store_bytes = sweep
        .delta
        .freed_store_bytes
        .saturating_add(low_store_freed);
    sweep.lines.extend(low_disk.lines);

    let non_store_bytes =
        remeasured_non_store_bytes(config, retention, non_store_bytes, low_disk_freed);
    let warning_remaining =
        non_store_bytes.map(|bytes| report_outcome.remaining_bytes.saturating_add(bytes));
    if let Some(warning) = total_budget_warning(retention, warning_remaining, false) {
        log::warn!("{warning}");
        sweep.lines.push(warning);
    }
    warn_if_still_low(config, retention);
    sweep
}

/// Begin the sweep log again for the collector that claimed this sweep.
///
/// The parent opened it for appending so a speculative collector could not
/// erase an earlier one's warnings; the one that swept owns it from here.
fn start_sweep_log(store: &Path) {
    if let Ok(log) = std::fs::OpenOptions::new()
        .write(true)
        .open(store.join(SWEEP_LOG))
    {
        let _ = log.set_len(0);
    }
}

/// Start the sweep a finished build leaves behind, in a process of its own.
///
/// The walk of every managed target and the whole store is the slowest thing
/// tuist_cargo_cache does after a build, and on a machine with many checkouts it takes
/// longer than the edit-loop build that happened to come due: measured at
/// twelve seconds added to a two-second build. Nothing the build printed
/// depends on it, so the build exits and the collector runs on without a
/// terminal. What it frees is written for the next build to report, and the
/// lifetime totals are updated by the collector itself.
///
/// The due check here is unlocked, so two builds finishing together may both
/// start a collector; the claim inside the collector lets exactly one sweep.
/// A collector that cannot be started sweeps in this process instead, as
/// builds always did, so a machine where spawning fails is still collected.
pub(super) fn schedule_sweep(config: &Config, retention: &RetentionSettings) {
    if !config.gc.auto {
        return;
    }
    let store = config.store_dir();
    if !store::sweep_is_due(&store, sweep_interval(config, retention)) {
        return;
    }
    if let Err(error) = spawn_collector(config) {
        log::debug!("the automatic sweep runs in the foreground: {error:#}");
        if let Err(error) = run_automatic(config, retention) {
            log::warn!("the store was not swept: {error:#}");
        }
    }
}

/// Start a detached collector after a real compiler miss finds a disk short.
///
/// The probes and spawner are parameters so the decision stays cheap to test;
/// the shim supplies the real functions and swallows every failure at its
/// boundary. The collector claims the sweep stamp again after it starts, so
/// concurrent shims can race here without sweeping in the foreground.
pub(crate) fn schedule_low_disk_sweep(
    config: &Config,
    min_free: MinFree,
    disk_space: &dyn Fn(&Path) -> Option<crate::util::DiskSpace>,
    spawn: &dyn Fn(&Config) -> Result<()>,
) {
    if !config.gc.auto {
        return;
    }

    let is_short = |path: &Path| {
        disk_space(path).is_some_and(|space| space.available < min_free.bytes(space.total))
    };
    let cache_short = is_short(&config.cache_dir);
    let target_short = config.target.views
        && !crate::util::same_disk(&config.cache_dir, &config.target.root)
        && is_short(&config.target.root);
    if !(cache_short || target_short) {
        return;
    }

    let interval = config.gc.interval.min(LOW_DISK_INTERVAL);
    if !store::sweep_is_due(&config.store_dir(), interval) {
        return;
    }
    if let Err(error) = spawn(config) {
        log::debug!("the low-disk collector could not be started: {error:#}");
    }
}

pub(crate) fn spawn_collector(config: &Config) -> Result<()> {
    let executable = std::env::current_exe().wrap_err("failed to locate tuist_cargo_cache")?;
    spawn_collector_from(&executable, config)
}

/// Start the collector from `executable`, which must be the `tuist_cargo_cache` binary
/// itself. A compiler shim passes the session's binary because its own
/// executable is the shim, and a shim started with `gc --automatic` would run
/// as a shim and never sweep.
pub(crate) fn spawn_collector_from(executable: &Path, config: &Config) -> Result<()> {
    // The collector reads its configuration for itself, so the cache it was
    // started for is named absolutely: a relative `TUIST_CARGO_CACHE_DIR` would resolve
    // against the collector's working directory, and that is not the
    // checkout. The checkout is left as the working directory of nothing here,
    // because a process holding it open would stop it being renamed or
    // removed on Windows.
    let cache_dir =
        std::path::absolute(&config.cache_dir).wrap_err("failed to resolve the cache directory")?;
    let store = cache_dir.join("actions");
    let log_path = store.join(SWEEP_LOG);
    // A full disk can prevent the first sweep log from being created. The
    // collector still needs to run to free the space that caused the failure.
    // Its stderr is discarded when creating or opening the log fails.
    let stderr =
        match std::fs::create_dir_all(log_path.parent().expect("the sweep log has a parent")) {
            Ok(()) => {
                // Appended, not truncated: a collector that loses the claim must
                // not erase what the one that swept had to say. The winner starts
                // the log afresh.
                match std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&log_path)
                {
                    Ok(log) => Stdio::from(log),
                    Err(error) => {
                        log::debug!("failed to open {}: {error}", log_path.display());
                        Stdio::null()
                    }
                }
            }
            Err(error) => {
                log::debug!(
                    "failed to create {}: {error}",
                    log_path
                        .parent()
                        .expect("the sweep log has a parent")
                        .display()
                );
                Stdio::null()
            }
        };
    let mut command = Command::new(executable);
    if std::env::var_os("TUIST_CARGO_NATIVE").is_some() {
        command.arg("__tuist_gc_automatic");
    } else {
        command.args(["gc", "--automatic"]);
    }
    command
        .current_dir(&cache_dir)
        .env("TUIST_CARGO_CACHE_DIR", &cache_dir)
        // The build may have arrived through the Cargo shim. The collector is
        // an tuist_cargo_cache command even when current_exe() is a hardlink named cargo;
        // removing the mode alone would still let argv[0] select the shim.
        .env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "0")
        .env_remove("TUIST_CARGO_CACHE_CARGO_SHIM_PATH")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(stderr);
    detach(&mut command);
    command.spawn().wrap_err("failed to start the collector")?;
    Ok(())
}

pub(super) fn collector_lock(store: &Path) -> Result<fslock::LockFile> {
    let path = store.join(COLLECTOR_LOCK);
    std::fs::create_dir_all(path.parent().expect("the collector lock has a parent"))?;
    Ok(fslock::LockFile::open(&path)?)
}

/// Keep the collector out of the terminal's process group, so the interrupt
/// that stops the next build does not stop a sweep halfway through.
#[cfg(unix)]
fn detach(command: &mut Command) {
    use std::os::unix::process::CommandExt as _;
    command.process_group(0);
}

#[cfg(windows)]
fn detach(command: &mut Command) {
    use std::os::windows::process::CommandExt as _;
    const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    command.creation_flags(CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW);
}

/// The sweep a build scheduled: `tuist_cargo_cache gc --automatic`.
///
/// Claims the throttle stamp like the in-process sweep always did, counts what
/// it freed toward the lifetime totals, and leaves the description for the
/// next build to print. Its own stderr is the sweep log.
pub(super) fn run_automatic(config: &Config, retention: &RetentionSettings) -> Result<()> {
    let store = config.store_dir();
    let mut collector = collector_lock(&store)?;
    if !collector.try_lock()? {
        log::debug!("another collector is sweeping the store");
        return Ok(());
    }
    let sweep = sweep_store(config, retention);
    log::debug!(
        "the automatic sweep freed {} target bytes and {} store bytes: {:?}",
        sweep.delta.freed_target_bytes,
        sweep.delta.freed_store_bytes,
        sweep.lines
    );
    let mut delta = sweep.delta;
    delta.auto_pruned_bytes = delta
        .freed_target_bytes
        .saturating_add(delta.freed_store_bytes);
    if delta != crate::savings::Delta::default() {
        crate::savings::record_quietly(&store, &delta);
    }
    if sweep.lines.is_empty() {
        return Ok(());
    }
    // Appended: a report nobody has printed yet is not this sweep's to
    // replace, and the next build says both.
    let report = sweep.lines.join("\n") + "\n";
    let path = store.join(SWEEP_REPORT);
    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .and_then(|mut file| std::io::Write::write_all(&mut file, report.as_bytes()))
        .wrap_err_with(|| format!("failed to write {}", path.display()))
}

/// What the last background sweep freed, said once.
///
/// The report is claimed by renaming it away before it is read, so of two
/// builds finishing at the same moment, the one whose rename succeeds prints
/// it and the other finds nothing. The collector lock is held for the read,
/// and is what a running collector holds while it appends.
pub(super) fn take_sweep_report(store: &Path) -> Vec<String> {
    // A collector appends while it holds the lock. Reading under it would
    // catch a report half written; a held lock means the report keeps until
    // the next build, which is when the collector would have been done anyway.
    let Ok(mut collector) = collector_lock(store) else {
        return Vec::new();
    };
    if !collector.try_lock().unwrap_or(false) {
        return Vec::new();
    }
    let path = store.join(SWEEP_REPORT);
    let claimed = claimed_report_path(&path);
    if std::fs::rename(&path, &claimed).is_err() {
        return Vec::new();
    }
    let report = std::fs::read_to_string(&claimed).unwrap_or_default();
    let _ = std::fs::remove_file(&claimed);
    report
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(str::to_owned)
        .collect()
}

fn claimed_report_path(report: &Path) -> PathBuf {
    report.with_extension(format!("claimed-{}", std::process::id()))
}

/// What one target collection left behind, and what it reclaimed.
pub(super) struct PruneReport {
    /// `None` when collection failed, so a caller sizing a combined budget
    /// knows to measure rather than assume.
    remaining_bytes: Option<u64>,
    pub(super) freed_bytes: u64,
    /// The lines describing removed target directories and units.
    pub(super) removals: Vec<String>,
}

/// Collect managed targets as the other half of a due automatic sweep.
pub(super) fn prune_targets(
    config: &Config,
    retention: &RetentionSettings,
    store_reserve: u64,
) -> PruneReport {
    // A target directory whose checkout is gone is the largest thing
    // collection ever frees, and walking for it on every build would be the
    // slowest, so callers keep this inside the store sweep's throttle.
    let mut low_disk = None;
    let store_reserve = occupied_store_budget(config, retention, store_reserve);
    let incremental_limit = incremental_limit(config, retention, store_reserve, &mut low_disk);
    let incremental = crate::incremental::collect(
        &config.cache_dir.join("incremental"),
        incremental_limit,
        retention.incremental_max_age,
        false,
    );
    let mut accounting_complete = true;
    let (incremental_bytes, incremental_remaining) = match incremental {
        Ok(outcome) => (outcome.removed_bytes, outcome.remaining_bytes),
        Err(error) => {
            log::warn!("learned incremental state was not collected: {error}");
            let remaining = crate::incremental::stats(&config.cache_dir.join("incremental"))
                .map_or_else(
                    |_| {
                        accounting_complete = false;
                        0
                    },
                    |stats| stats.bytes,
                );
            (0, remaining)
        }
    };
    let generated = collect_generated(
        config,
        incremental_limit.map(|budget| budget.saturating_sub(incremental_remaining)),
        retention.target_max_age,
        false,
        &mut accounting_complete,
    );
    if generated.removed_directories > 0 {
        crate::session::note(&format!(
            "tuist_cargo_cache[gc]: {}",
            generated_removals(&generated, false)
        ));
    }
    let incremental_bytes = incremental_bytes.saturating_add(generated.removed_bytes);
    let incremental_remaining = incremental_remaining.saturating_add(generated.remaining_bytes);
    let target_budget = target_limit(
        config,
        retention,
        store_reserve,
        incremental_remaining,
        &mut low_disk,
    );
    let mut report = match target::collect_by(
        &config.target.root,
        target_budget,
        retention.target_max_age,
        &retention.target_precedence,
        false,
    ) {
        Ok(pruned) => {
            log::debug!(
                "target collection removed {} directories ({} abandoned) and kept {}",
                pruned.removed_views,
                pruned.removed_stale_views,
                pruned.remaining_views
            );
            PruneReport {
                remaining_bytes: accounting_complete
                    .then_some(pruned.remaining_bytes.saturating_add(incremental_remaining)),
                freed_bytes: pruned.freed_bytes().saturating_add(incremental_bytes),
                removals: target_removals(&pruned, false),
            }
        }
        Err(error) => {
            log::warn!("target directories were not collected: {error}");
            PruneReport {
                remaining_bytes: None,
                freed_bytes: incremental_bytes,
                removals: Vec::new(),
            }
        }
    };
    // Said only beside something it explains: a disk nothing here can relieve
    // would otherwise repeat the same line after every low-disk sweep.
    if let Some(disk) = low_disk
        && report.freed_bytes > 0
    {
        report.removals.insert(0, disk.describe(false));
    }
    report
}

#[derive(Debug, Default)]
pub(super) struct LowDiskCollection {
    incremental: Option<crate::incremental::PruneOutcome>,
    generated: Option<crate::out_dir::PruneOutcome>,
    targets: Option<target::CollectionOutcome>,
    store: Option<store::GcOutcome>,
    freed_target_bytes: u64,
    lines: Vec<String>,
}

#[derive(Clone, Copy)]
enum LowDiskTier {
    Incremental,
    Generated,
    Targets,
    Store,
}

/// Keep collecting the next private tier until it stops making progress.
///
/// The disk probe is deliberately between every round. A target restored by
/// reflink or hardlink can lose a large logical tree while returning only a
/// few physical blocks, so one logical budget adjustment cannot stand in for
/// the disk measurement. The shared store is last because every checkout pays
/// for a miss there.
pub(super) fn collect_low_disk(
    config: &Config,
    retention: &RetentionSettings,
) -> LowDiskCollection {
    let mut collection = LowDiskCollection::default();
    for tier in [
        LowDiskTier::Incremental,
        LowDiskTier::Generated,
        LowDiskTier::Targets,
        LowDiskTier::Store,
    ] {
        collect_low_disk_tier(config, retention, tier, &mut collection);
    }
    collection
}

fn collect_low_disk_tier(
    config: &Config,
    retention: &RetentionSettings,
    tier: LowDiskTier,
    collection: &mut LowDiskCollection,
) {
    for _ in 0..LOW_DISK_ROUNDS_PER_TIER {
        let Some(shortfall) =
            low_disk_for_tier(config, retention, tier).map(|disk| disk.shortfall())
        else {
            return;
        };
        let freed = match tier {
            LowDiskTier::Incremental => {
                collect_low_disk_incremental(config, retention, shortfall, collection)
            }
            LowDiskTier::Generated => {
                collect_low_disk_generated(config, retention, shortfall, collection)
            }
            LowDiskTier::Targets => {
                collect_low_disk_targets(config, retention, shortfall, collection)
            }
            LowDiskTier::Store => collect_low_disk_store(config, shortfall, collection),
        };
        if freed == 0 {
            return;
        }
    }
}

fn low_disk_for_tier(
    config: &Config,
    retention: &RetentionSettings,
    tier: LowDiskTier,
) -> Option<LowDisk> {
    match tier {
        LowDiskTier::Incremental | LowDiskTier::Generated | LowDiskTier::Store => {
            low_disk(retention, &config.cache_dir)
        }
        LowDiskTier::Targets => low_disk(retention, &config.target.root),
    }
}

fn collect_low_disk_incremental(
    config: &Config,
    retention: &RetentionSettings,
    shortfall: u64,
    collection: &mut LowDiskCollection,
) -> u64 {
    let root = config.cache_dir.join("incremental");
    let Some(usage) = crate::incremental::stats(&root)
        .ok()
        .map(|stats| stats.bytes)
    else {
        log::warn!("learned incremental state could not be measured during low-disk collection");
        return 0;
    };
    let limit = usage.saturating_sub(shortfall);
    let outcome =
        match crate::incremental::collect(&root, Some(limit), retention.incremental_max_age, false)
        {
            Ok(outcome) => outcome,
            Err(error) => {
                log::warn!("learned incremental state was not collected: {error}");
                return 0;
            }
        };
    let freed = outcome.removed_bytes;
    collection.freed_target_bytes = collection.freed_target_bytes.saturating_add(freed);
    collection
        .lines
        .extend(incremental_removal_lines(&outcome, false));
    collection.add_incremental(outcome);
    freed
}

fn collect_low_disk_generated(
    config: &Config,
    retention: &RetentionSettings,
    shortfall: u64,
    collection: &mut LowDiskCollection,
) -> u64 {
    let root = config.cache_dir.join(crate::out_dir::ROOT);
    let Some(usage) = crate::out_dir::stats(&root).map(|stats| stats.remaining_bytes) else {
        log::warn!("generated source trees could not be measured during low-disk collection");
        return 0;
    };
    let limit = usage.saturating_sub(shortfall);
    let outcome = match crate::out_dir::collect(&root, Some(limit), retention.target_max_age, false)
    {
        Ok(outcome) => outcome,
        Err(error) => {
            log::warn!("generated source trees were not collected: {error}");
            return 0;
        }
    };
    let freed = outcome.removed_bytes;
    collection.freed_target_bytes = collection.freed_target_bytes.saturating_add(freed);
    collection
        .lines
        .extend(generated_removal_lines(&outcome, false));
    collection.add_generated(outcome);
    freed
}

fn collect_low_disk_targets(
    config: &Config,
    retention: &RetentionSettings,
    shortfall: u64,
    collection: &mut LowDiskCollection,
) -> u64 {
    let Some(usage) = target::stats(&config.target.root)
        .ok()
        .map(|stats| stats.bytes)
    else {
        log::warn!("managed target directories could not be measured during low-disk collection");
        return 0;
    };
    let limit = usage.saturating_sub(shortfall);
    let outcome = match target::collect_by(
        &config.target.root,
        Some(limit),
        retention.target_max_age,
        &retention.target_precedence,
        false,
    ) {
        Ok(outcome) => outcome,
        Err(error) => {
            log::warn!("target directories were not collected: {error}");
            return 0;
        }
    };
    let freed = outcome.freed_bytes();
    collection.freed_target_bytes = collection.freed_target_bytes.saturating_add(freed);
    collection.lines.extend(target_removals(&outcome, false));
    collection.add_targets(outcome);
    freed
}

fn collect_low_disk_store(
    config: &Config,
    shortfall: u64,
    collection: &mut LowDiskCollection,
) -> u64 {
    let store = config.store_dir();
    let Some(usage) = store::stats(&store).ok().map(|stats| stats.total_bytes()) else {
        log::warn!("the shared store could not be measured during low-disk collection");
        return 0;
    };
    let limit = usage.saturating_sub(shortfall);
    let outcome = match store::gc(&store, limit) {
        Ok(outcome) => outcome,
        Err(error) => {
            log::warn!("the store was not swept: {error}");
            return 0;
        }
    };
    let freed = outcome.removed_bytes;
    let removed_objects = outcome.removed_objects;
    let removed_action_results = outcome.removed_action_results;
    if let Some(total) = &mut collection.store {
        add_gc_outcome(total, outcome);
    } else {
        collection.store = Some(outcome);
    }
    if freed > 0 {
        collection.lines.push(format!(
            "evicted {} shared cache objects and {} action results below gc.max_size because the disk was under gc.min_free_size ({} logical freed)",
            removed_objects,
            removed_action_results,
            ByteSize::b(freed).display().iec(),
        ));
    }
    freed
}

fn add_gc_outcome(total: &mut store::GcOutcome, outcome: store::GcOutcome) {
    total.removed_objects = total
        .removed_objects
        .saturating_add(outcome.removed_objects);
    total.removed_action_results = total
        .removed_action_results
        .saturating_add(outcome.removed_action_results);
    total.removed_checkout_records = total
        .removed_checkout_records
        .saturating_add(outcome.removed_checkout_records);
    total.removed_session_streams = total
        .removed_session_streams
        .saturating_add(outcome.removed_session_streams);
    total.removed_bytes = total.removed_bytes.saturating_add(outcome.removed_bytes);
    total.remaining_bytes = outcome.remaining_bytes;
}

impl LowDiskCollection {
    pub(super) fn target_report(&self, initial: &target::CollectionOutcome) -> GcTargetReport {
        merged_target_report(initial, self.targets.as_ref())
    }

    fn add_incremental(&mut self, outcome: crate::incremental::PruneOutcome) {
        let mut total = self.incremental.take().unwrap_or_default();
        total.removed_directories = total
            .removed_directories
            .saturating_add(outcome.removed_directories);
        total.removed_bytes = total.removed_bytes.saturating_add(outcome.removed_bytes);
        total.remaining_directories = outcome.remaining_directories;
        total.remaining_bytes = outcome.remaining_bytes;
        total.skipped_active_directories = outcome.skipped_active_directories;
        total.untracked_directories = outcome.untracked_directories;
        self.incremental = Some(total);
    }

    fn add_generated(&mut self, outcome: crate::out_dir::PruneOutcome) {
        let mut total = self.generated.take().unwrap_or_default();
        total.removed_directories = total
            .removed_directories
            .saturating_add(outcome.removed_directories);
        total.removed_bytes = total.removed_bytes.saturating_add(outcome.removed_bytes);
        total.remaining_directories = outcome.remaining_directories;
        total.remaining_bytes = outcome.remaining_bytes;
        self.generated = Some(total);
    }

    fn add_targets(&mut self, outcome: target::CollectionOutcome) {
        let mut total = self.targets.take().unwrap_or_default();
        total.removed_views = total.removed_views.saturating_add(outcome.removed_views);
        total.removed_bytes = total.removed_bytes.saturating_add(outcome.removed_bytes);
        total.removed_stale_views = total
            .removed_stale_views
            .saturating_add(outcome.removed_stale_views);
        total.removed_live_views = total
            .removed_live_views
            .saturating_add(outcome.removed_live_views);
        total.kept_active_views = outcome.kept_active_views;
        total.removed_units = total.removed_units.saturating_add(outcome.removed_units);
        total.removed_unit_bytes = total
            .removed_unit_bytes
            .saturating_add(outcome.removed_unit_bytes);
        total.remaining_bytes = outcome.remaining_bytes;
        total.remaining_views = outcome.remaining_views;
        self.targets = Some(total);
    }

    fn freed_bytes(&self) -> u64 {
        self.store
            .as_ref()
            .map_or(0, |outcome| outcome.removed_bytes)
            .saturating_add(self.freed_target_bytes)
    }
}

/// What the managed data outside the store occupies after collection.
///
/// Measured again only when the low-disk loop removed something. Otherwise
/// the measurement taken before the store sweep is still right, and walking
/// every target and learned incremental tree again would cost every sweep
/// for a warning that only `gc.max_total_size` asks for.
fn remeasured_non_store_bytes(
    config: &Config,
    retention: &RetentionSettings,
    before: Option<u64>,
    low_disk_freed: u64,
) -> Option<u64> {
    if retention.max_total_bytes.is_none() || low_disk_freed == 0 {
        return before;
    }
    current_non_store_bytes(config).or(before)
}

fn current_non_store_bytes(config: &Config) -> Option<u64> {
    let target = target::stats(&config.target.root).ok()?.bytes;
    let incremental = crate::incremental::stats(&config.cache_dir.join("incremental"))
        .ok()?
        .bytes;
    let generated =
        crate::out_dir::stats(&config.cache_dir.join(crate::out_dir::ROOT))?.remaining_bytes;
    Some(target.saturating_add(incremental).saturating_add(generated))
}

/// A disk found with less free space than `gc.min_free_size` asks for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct LowDisk {
    path: PathBuf,
    available: u64,
    min_free: u64,
}

impl LowDisk {
    pub(super) fn shortfall(&self) -> u64 {
        self.min_free.saturating_sub(self.available)
    }

    pub(super) fn describe(&self, dry_run: bool) -> String {
        let verb = if dry_run {
            "would collect"
        } else {
            "collecting"
        };
        format!(
            "{} free on the disk holding {}, under the {} minimum; {verb} private state and managed targets past their budgets, then shared cache objects if the cache disk is short",
            ByteSize::b(self.available).display().iec(),
            self.path.display(),
            ByteSize::b(self.min_free).display().iec(),
        )
    }
}

/// The disk holding `path`, when it is short of the configured free space.
///
/// `None` also when there is no minimum or the disk cannot be measured: a
/// probe that fails is no reason to delete anything.
pub(super) fn low_disk(retention: &RetentionSettings, path: &Path) -> Option<LowDisk> {
    let min_free = retention.min_free?;
    let space = crate::util::disk_space(path)?;
    let disk = LowDisk {
        path: path.to_path_buf(),
        available: space.available,
        min_free: min_free.bytes(space.total),
    };
    (disk.shortfall() > 0).then_some(disk)
}

/// How long sweeps wait for one another: `gc.interval`, or less while a disk
/// the sweep could relieve is short of space.
pub(super) fn sweep_interval(config: &Config, retention: &RetentionSettings) -> Duration {
    let low = low_disk(retention, &config.cache_dir).is_some()
        || (config.target.views && low_disk(retention, &config.target.root).is_some());
    if low {
        config.gc.interval.min(LOW_DISK_INTERVAL)
    } else {
        config.gc.interval
    }
}

/// A budget lowered far enough that collecting `usage` down to it frees
/// `shortfall`. Only ever lower than the budget it was given.
pub(super) fn relieve(budget: Option<u64>, usage: u64, shortfall: u64) -> Option<u64> {
    if shortfall == 0 {
        return budget;
    }
    let relieved = usage.saturating_sub(shortfall);
    Some(budget.map_or(relieved, |budget| budget.min(relieved)))
}

/// The budget learned incremental state and generated source trees are
/// collected to, lowered while the cache disk is short of space.
///
/// Per-checkout state goes first because it is private: a checkout that loses
/// it recompiles its own crates, while every checkout reads the shared store.
fn incremental_limit(
    config: &Config,
    retention: &RetentionSettings,
    store_reserve: u64,
    low: &mut Option<LowDisk>,
) -> Option<u64> {
    let budget = incremental_budget(retention, store_reserve);
    let Some(disk) = low_disk(retention, &config.cache_dir) else {
        return budget;
    };
    // Measured only on a short disk: a walk ordinary sweeps do not pay for.
    let usage = crate::incremental::stats(&config.cache_dir.join("incremental"))
        .map_or(0, |stats| stats.bytes)
        .saturating_add(
            crate::out_dir::stats(&config.cache_dir.join(crate::out_dir::ROOT))
                .map_or(0, |stats| stats.remaining_bytes),
        );
    let limit = relieve(budget, usage, disk.shortfall());
    low.get_or_insert(disk);
    limit
}

/// The managed-target budget, lowered while the target disk is short of
/// space after the collections before it.
///
/// Measured again rather than carried over: the targets may be on another
/// disk, and on the same one, what learned incremental state gave back already
/// shows. A dry run's disk shows nothing freed, and what the steps before
/// would free is not credited either: removing a reflinked copy frees less
/// than its logical size, by an amount nothing short of removing it can tell.
/// The preview is the most a real run could remove.
fn target_limit(
    config: &Config,
    retention: &RetentionSettings,
    store_reserve: u64,
    incremental_reserve: u64,
    low: &mut Option<LowDisk>,
) -> Option<u64> {
    let budget = target_budget(retention, store_reserve, incremental_reserve);
    let Some(disk) = low_disk(retention, &config.target.root) else {
        return budget;
    };
    let usage = target::stats(&config.target.root).map_or(0, |stats| stats.bytes);
    let limit = relieve(budget, usage, disk.shortfall());
    low.get_or_insert(disk);
    limit
}

/// Say when collection could not bring a disk back above its minimum.
///
/// Active and most-recently-used state is protected, so a disk filled by
/// something else can stay short after collection has removed everything it
/// is allowed to remove.
fn warn_if_still_low(config: &Config, retention: &RetentionSettings) {
    let cache = low_disk(retention, &config.cache_dir);
    // The target root is its own disk only when it is not the cache's, and
    // then it can be short on its own account.
    let target = (!crate::util::same_disk(&config.cache_dir, &config.target.root))
        .then(|| low_disk(retention, &config.target.root))
        .flatten();
    for disk in cache.into_iter().chain(target) {
        log::warn!(
            "the disk holding {} still has {} free after collection, under the {} minimum; collection removed everything it is allowed to remove (active or most-recently-used state is kept), so something else may be using the disk",
            disk.path.display(),
            ByteSize::b(disk.available).display().iec(),
            ByteSize::b(disk.min_free).display().iec(),
        );
    }
}

/// Reserve only occupied store space, capped at what its own sweep will keep.
/// An empty store must not evict warm targets merely because it could grow.
/// If measurement fails, keep the former conservative allowance; the store
/// collector still reports the error without blocking independent cleanup.
pub(super) fn occupied_store_budget(
    config: &Config,
    retention: &RetentionSettings,
    max_bytes: u64,
) -> u64 {
    if retention.max_total_bytes.is_none() {
        return max_bytes;
    }
    store::stats(&config.store_dir()).map_or(max_bytes, |stats| stats.total_bytes().min(max_bytes))
}

fn total_budget_warning(
    retention: &RetentionSettings,
    remaining: Option<u64>,
    dry_run: bool,
) -> Option<String> {
    let budget = retention.max_total_bytes?;
    let Some(remaining) = remaining else {
        return Some("could not measure all managed data; gc.max_total_size could not be verified and no space was budgeted for the action store".to_string());
    };
    if remaining <= budget {
        return None;
    }
    let verb = if dry_run { "would remain" } else { "remain" };
    Some(format!(
        "{} logical {verb} after collection, over gc.max_total_size ({}); active, most-recently-used, kept, or untracked state can prevent reaching this collection target",
        ByteSize::b(remaining).display().iec(),
        ByteSize::b(budget).display().iec(),
    ))
}

pub(super) fn target_budget(
    retention: &RetentionSettings,
    store_reserve: u64,
    incremental_reserve: u64,
) -> Option<u64> {
    retention
        .max_total_bytes
        .map_or(retention.target_max_bytes, |total| {
            let combined = total.saturating_sub(store_reserve.saturating_add(incremental_reserve));
            Some(
                retention
                    .target_max_bytes
                    .map_or(combined, |target| target.min(combined)),
            )
        })
}

/// Bound incremental state independently and inside the space left after the
/// action-store reserve in a combined budget.
pub(super) fn incremental_budget(retention: &RetentionSettings, store_reserve: u64) -> Option<u64> {
    retention
        .max_total_bytes
        .map_or(retention.incremental_max_bytes, |total| {
            let combined = total.saturating_sub(store_reserve);
            Some(
                retention
                    .incremental_max_bytes
                    .map_or(combined, |incremental| incremental.min(combined)),
            )
        })
}

pub(super) fn store_budget(
    retention: &RetentionSettings,
    max_bytes: u64,
    non_store_bytes: Option<u64>,
) -> u64 {
    retention.max_total_bytes.map_or(max_bytes, |total| {
        // Unknown occupancy cannot establish any room for shared objects.
        // Independent cleanup still proceeds, and the sweep reports that the
        // combined budget could not be verified rather than claiming zero use.
        non_store_bytes.map_or(0, |bytes| max_bytes.min(total.saturating_sub(bytes)))
    })
}
