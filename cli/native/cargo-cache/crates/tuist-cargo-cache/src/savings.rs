//! What tuist_cargo_cache has saved on this machine, accumulated across builds.
//!
//! A single build's statistics say what just happened; they cannot say what
//! switching to tuist_cargo_cache has been worth, because the compilations it skipped and the
//! directories it collected are spread over months. This module keeps a running
//! total beside the store and turns it into one line after a build.
//!
//! ```text
//! <store>/savings/v1/tally.json   the totals
//! <store>/savings/v1/tally.lock   held while they are updated
//! ```
//!
//! The tally is bookkeeping, not cache content: it is never an input to a
//! cache key, and the collector never walks it. Losing it costs a number in a
//! message, so every failure here is logged and forgotten rather than raised.

use crate::config::SavingsStyle;
use crate::util::{format_clock, format_duration, write_advisory};
use bytesize::ByteSize;
use eyre::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub(crate) const TALLY_FILE: &str = "savings/v1/tally.json";
const TALLY_LOCK: &str = "savings/v1/tally.lock";
const TALLY_VERSION: u8 = 1;

/// Running totals for one machine.
///
/// `serde(default)` rather than `deny_unknown_fields`: a tally written by a
/// newer tuist_cargo_cache must degrade to a smaller number, never to an error that costs a
/// build its savings line.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub(crate) struct Tally {
    pub version: u8,
    /// When counting started, so a total can say what it spans.
    pub since_secs: u64,
    pub builds: u64,
    pub cached_compilations: u64,
    pub avoided_compiler_ns: u64,
    /// Output bytes shared with the store rather than copied, by reflink or
    /// by hard link. Named for the mechanism that came first, because the
    /// on-disk ledger persists under this key.
    pub reflinked_bytes: u64,
    /// Sum of removed file lengths; does not measure physical reclamation.
    pub freed_target_bytes: u64,
    /// Logical bytes removed from the store.
    pub freed_store_bytes: u64,
    /// Logical bytes removed by automatic sweeps only. Older ledgers combined automatic and explicit GC,
    /// so this counter has its own start date instead of backfilling a guess.
    pub auto_pruned_bytes: u64,
    pub auto_pruned_since_secs: u64,
    /// Logical bytes the user asked to have removed: a confirmed `target/` migration,
    /// or `tuist_cargo_cache cache remove`. Kept apart from the collection counters because
    /// every line about those brags that nobody had to do anything -- which is
    /// exactly untrue of a removal somebody confirmed.
    pub freed_requested_bytes: u64,
    /// Counters a newer tuist_cargo_cache wrote that this one does not know about.
    ///
    /// Every record rewrites the whole file, so without this an older binary
    /// would silently drop a newer one's totals while leaving its version
    /// number in place. Carried through untouched instead.
    #[serde(flatten)]
    unknown: BTreeMap<String, serde_json::Value>,
}

/// What one command contributed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct Delta {
    pub builds: u64,
    pub cached_compilations: u64,
    pub avoided_compiler_ns: u64,
    /// Output bytes shared with the store rather than copied, by reflink or
    /// by hard link. Named for the mechanism that came first, because the
    /// on-disk ledger persists under this key.
    pub reflinked_bytes: u64,
    /// Sum of removed file lengths; does not measure physical reclamation.
    pub freed_target_bytes: u64,
    /// Logical bytes removed from the store.
    pub freed_store_bytes: u64,
    pub auto_pruned_bytes: u64,
    pub freed_requested_bytes: u64,
}

impl Delta {
    fn is_empty(&self) -> bool {
        *self == Self::default()
    }
}

/// What this one command did, for the lines that describe the run rather than
/// the lifetime.
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct SessionFacts {
    pub hits: u64,
    pub avoided_compiler_ns: u64,
}

fn tally_path(store: &Path) -> PathBuf {
    store.join(TALLY_FILE)
}

/// Add `delta` to the stored totals and return the result.
///
/// Runs after cargo has exited, so the lock it takes and the two small files it
/// touches are not on anything the user is waiting for. Concurrent commands
/// serialize on the lock the same way sweeps do.
pub(crate) fn record(store: &Path, delta: &Delta) -> Result<Tally> {
    let lock_path = store.join(TALLY_LOCK);
    std::fs::create_dir_all(
        lock_path
            .parent()
            .expect("the tally lock path has a parent"),
    )
    .wrap_err_with(|| format!("failed to create {}", lock_path.display()))?;
    let mut lock = fslock::LockFile::open(&lock_path)?;
    lock.lock()?;

    let path = tally_path(store);
    let mut tally = read(&path);
    if tally.version == 0 {
        tally.version = TALLY_VERSION;
        tally.since_secs = now_secs();
    }
    if tally.auto_pruned_since_secs == 0 {
        tally.auto_pruned_since_secs = now_secs();
    }
    tally.auto_pruned_bytes = tally
        .auto_pruned_bytes
        .saturating_add(delta.auto_pruned_bytes);
    tally.builds = tally.builds.saturating_add(delta.builds);
    tally.cached_compilations = tally
        .cached_compilations
        .saturating_add(delta.cached_compilations);
    tally.avoided_compiler_ns = tally
        .avoided_compiler_ns
        .saturating_add(delta.avoided_compiler_ns);
    tally.reflinked_bytes = tally.reflinked_bytes.saturating_add(delta.reflinked_bytes);
    tally.freed_target_bytes = tally
        .freed_target_bytes
        .saturating_add(delta.freed_target_bytes);
    tally.freed_store_bytes = tally
        .freed_store_bytes
        .saturating_add(delta.freed_store_bytes);
    tally.freed_requested_bytes = tally
        .freed_requested_bytes
        .saturating_add(delta.freed_requested_bytes);

    let mut contents = serde_json::to_vec_pretty(&tally)?;
    contents.push(b'\n');
    write_advisory(&path, &contents)?;
    Ok(tally)
}

/// Read the tally, treating anything unreadable as a fresh start.
///
/// A tally that cannot be parsed has already lost its history, and refusing to
/// count from here would lose every future build's as well.
fn read(path: &Path) -> Tally {
    std::fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

/// The stored totals for `store`, or an empty tally when there are none yet.
pub(crate) fn read_tally(store: &Path) -> Tally {
    read(&tally_path(store))
}

/// A fixed UTC date makes a lifetime total unambiguous, including after a pause.
pub(crate) fn since(seconds: u64) -> String {
    i64::try_from(seconds)
        .ok()
        .filter(|seconds| *seconds > 0)
        .and_then(|seconds| jiff::Timestamp::from_second(seconds).ok())
        .map(|timestamp| format!("since {}", timestamp.strftime("%Y-%m-%d")))
        .unwrap_or_else(|| "since an unknown date".into())
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.as_secs())
        .unwrap_or_default()
}

/// Thresholds below which a number is not worth a line of the user's attention.
const MIN_SESSION_HITS: u64 = 5;
const MIN_SESSION_AVOIDED: Duration = Duration::from_secs(30);
const MIN_LIFETIME_AVOIDED: Duration = Duration::from_secs(30 * 60);
const MIN_FREED_BYTES: u64 = 1024 * 1024 * 1024;
const MIN_FREED_TARGET_BYTES: u64 = 5 * 1024 * 1024 * 1024;
const MIN_REFLINKED_BYTES: u64 = 1024 * 1024 * 1024;
const MIN_CACHED_COMPILATIONS: u64 = 250;

/// One `format!` per line, with the locals in scope: a pool of tellings reads
/// as copy to be edited, not as code, so every telling gets exactly one line.
macro_rules! tellings {
    ($($line:literal),+ $(,)?) => { vec![$(format!($line)),+] };
}

/// One fact worth telling, in every voice it can be told in.
struct Candidate {
    /// The mascot's variants: a cache box in a monocle, deadpan, mentioning
    /// the chores exactly once. One is chosen at random per build.
    cheeky: Vec<String>,
    /// The same fact in the register of the `tuist_cargo_cache[cache]:` and `tuist_cargo_cache[gc]:` lines.
    plain: String,
}

/// The facts this machine has earned the right to mention.
///
/// Every line carries a number this machine actually produced -- a line that
/// could have been written before the build ran is an advertisement, not a
/// report. Thresholds keep small numbers quiet.
fn facts_worth_telling(tally: &Tally, facts: &SessionFacts) -> Vec<Candidate> {
    let freed = tally
        .freed_target_bytes
        .saturating_add(tally.freed_store_bytes);
    let mut eligible = Vec::new();

    if facts.hits >= MIN_SESSION_HITS
        && facts.avoided_compiler_ns >= duration_ns(MIN_SESSION_AVOIDED)
    {
        let hits = facts.hits;
        let dur = nanos(facts.avoided_compiler_ns);
        eligible.push(Candidate {
            cheeky: tellings![
                "tuist_cargo_cache[savings]: served {hits} compilations from cache; rustc showed up ready to do {dur} of work and was sent home",
                "tuist_cargo_cache[savings]: {hits} compilations you did not wait for. the {dur} is yours now. spend it wisely.",
                "tuist_cargo_cache[savings]: this build borrowed {hits} compilations from an earlier one. rustc was not informed. ({dur} saved)",
                "tuist_cargo_cache[savings]: {hits} compilations arrived precompiled. somewhere a fan is not spinning. ({dur} saved)",
                "tuist_cargo_cache[savings]: cargo asked for {hits} compilations; tuist_cargo_cache had them filed under already-done. ({dur} saved)",
                "tuist_cargo_cache[savings]: {hits} compilations replayed from cache. rustc's services were not required. ({dur} saved)",
                "tuist_cargo_cache[savings]: intercepted {hits} compilations before rustc could get attached. ({dur} saved)",
                "tuist_cargo_cache[savings]: rustc had {dur} of work planned. tuist_cargo_cache had {hits} of its answers already.",
                "tuist_cargo_cache[savings]: {hits} compilations answered from memory. rustc can finish its coffee. ({dur} saved)",
                "tuist_cargo_cache[savings]: rustc arrived to find {hits} compilations already done. awkward. ({dur} saved)",
                "tuist_cargo_cache[savings]: quietly substituted {hits} cached compilations. nobody noticed. that is the job. ({dur} saved)",
                "tuist_cargo_cache[savings]: {hits} compilations in, zero compiled. {dur} returned to circulation.",
            ],
            plain: format!(
                "tuist_cargo_cache[savings]: {hits} compilations restored from cache this build, avoiding {dur} of compiler time"
            ),
        });
    }
    if tally.avoided_compiler_ns >= duration_ns(MIN_LIFETIME_AVOIDED) {
        let dur = nanos(tally.avoided_compiler_ns);
        let over = builds(tally.builds);
        eligible.push(Candidate {
            cheeky: tellings![
                "tuist_cargo_cache[savings]: {dur} of compiling skipped across {over}. rustc suspects nothing.",
                "tuist_cargo_cache[savings]: {dur} refunded over {over}. no receipt necessary.",
                "tuist_cargo_cache[savings]: rustc believes it compiled everything. it is down {dur} across {over}. let it believe.",
                "tuist_cargo_cache[savings]: has saved {dur} across {over}. this line is the only thanks it needs.",
                "tuist_cargo_cache[savings]: across {over}, rustc has been excused from {dur} of its duties.",
                "tuist_cargo_cache[savings]: {dur} not spent compiling, over {over}. what you did instead is between you and the terminal.",
                "tuist_cargo_cache[savings]: the running total stands at {dur} across {over}. nobody is counting except the box.",
                "tuist_cargo_cache[savings]: {dur} of compilation avoided across {over}. imagine the fan noise. now stop.",
                "tuist_cargo_cache[savings]: {dur} saved across {over}. put it toward something with a progress bar.",
                "tuist_cargo_cache[savings]: {dur} of rustc's calendar cleared across {over}.",
                "tuist_cargo_cache[savings]: {dur} unspent across {over}. compounding, in a sense.",
            ],
            plain: format!("tuist_cargo_cache[savings]: {dur} of compiler time avoided across {over}"),
        });
    }
    if freed >= MIN_FREED_BYTES {
        let size = format!("{} logical", iec(freed));
        eligible.push(Candidate {
            cheeky: tellings![
                "tuist_cargo_cache[savings]: {size} of build debris binned so far. cargo clean remains unemployed.",
                "tuist_cargo_cache[savings]: has quietly disposed of {size} of build leftovers. nobody saw anything.",
                "tuist_cargo_cache[savings]: {size} of old files removed to date. the broom sends its regards.",
                "tuist_cargo_cache[savings]: {size} of build debris has left the building.",
                "tuist_cargo_cache[savings]: swept up {size} so far. the broom is content-addressed.",
                "tuist_cargo_cache[savings]: {size} tidied away. you may continue not thinking about it.",
                "tuist_cargo_cache[savings]: {size} of old files removed while you were busy compiling other things.",
                "tuist_cargo_cache[savings]: {size} of old build output has been shown the door.",
                "tuist_cargo_cache[savings]: disposed of {size} without being asked. that is rather the point.",
                "tuist_cargo_cache[savings]: the sweep found {size} nobody would miss. nobody has.",
            ],
            plain: format!("tuist_cargo_cache[savings]: {size} of files removed by collection so far"),
        });
    }
    if tally.freed_target_bytes >= MIN_FREED_TARGET_BYTES {
        let size = format!("{} logical", iec(tally.freed_target_bytes));
        eligible.push(Candidate {
            cheeky: tellings![
                "tuist_cargo_cache[savings]: {size} of target/ had outlived its checkouts. it has been dealt with.",
                "tuist_cargo_cache[savings]: found {size} of target/ whose checkouts left long ago. the estate has been settled.",
                "tuist_cargo_cache[savings]: your deleted worktrees left {size} behind. left. past tense.",
                "tuist_cargo_cache[savings]: {size} of target/ belonged to checkouts that no longer exist. neither does it.",
                "tuist_cargo_cache[savings]: cleaned up {size} after checkouts that left without saying goodbye.",
                "tuist_cargo_cache[savings]: {size} of outputs had survived their checkouts. an unnatural state, now corrected.",
                "tuist_cargo_cache[savings]: the checkouts are gone. their {size} has gone to join them.",
                "tuist_cargo_cache[savings]: {size} of target/ was waiting for checkouts that are never coming back. it has stopped waiting.",
                "tuist_cargo_cache[savings]: escorted {size} of ownerless outputs off the premises.",
                "tuist_cargo_cache[savings]: worktrees come and go. their {size} now goes with them.",
            ],
            plain: format!("tuist_cargo_cache[savings]: {size} of abandoned target directories removed"),
        });
    }
    if tally.reflinked_bytes >= MIN_REFLINKED_BYTES {
        let size = iec(tally.reflinked_bytes);
        eligible.push(Candidate {
            cheeky: tellings![
                "tuist_cargo_cache[savings]: every checkout believes it owns {size} of outputs. the disk keeps one copy and says nothing.",
                "tuist_cargo_cache[savings]: {size} of outputs, one copy, several very confident checkouts.",
                "tuist_cargo_cache[savings]: linked {size} into place. copying is for people with disk to spare.",
                "tuist_cargo_cache[savings]: {size} of outputs exist once and appear everywhere. do not tell the checkouts.",
                "tuist_cargo_cache[savings]: {size} of target/ is an elaborate illusion. the disk is in on it.",
                "tuist_cargo_cache[savings]: lent the same {size} to every checkout at once. none of them has checked.",
                "tuist_cargo_cache[savings]: {size} shared among checkouts that each believe they are an only child.",
                "tuist_cargo_cache[savings]: {size} on loan to every checkout simultaneously. the paperwork is an inode.",
                "tuist_cargo_cache[savings]: {size} of outputs materialized without a copy. the copy machine stays off.",
                "tuist_cargo_cache[savings]: {size} in every checkout, {size} on disk. arithmetic declined to comment.",
            ],
            plain: format!("tuist_cargo_cache[savings]: {size} of outputs shared rather than copied"),
        });
    }
    if tally.cached_compilations >= MIN_CACHED_COMPILATIONS {
        let count = tally.cached_compilations;
        eligible.push(Candidate {
            cheeky: tellings![
                "tuist_cargo_cache[savings]: {count} compilations, each compiled once and served warm ever since",
                "tuist_cargo_cache[savings]: {count} cache hits and counting. rustc thinks it has been busy.",
                "tuist_cargo_cache[savings]: {count} compilations on file. the box remembers.",
                "tuist_cargo_cache[savings]: {count} compilations old. not one compiled twice.",
                "tuist_cargo_cache[savings]: {count} compilations served. the monocle stays on.",
                "tuist_cargo_cache[savings]: {count} compilations dispensed from stock. inventory immaculate.",
                "tuist_cargo_cache[savings]: {count} compilations, and the box has forgotten none of them.",
                "tuist_cargo_cache[savings]: {count} compilations retrieved with a straight face.",
                "tuist_cargo_cache[savings]: {count} compilations. rustc did each once; tuist_cargo_cache did the rest of the showing up.",
                "tuist_cargo_cache[savings]: {count} compilations served. ask rustc how many it remembers doing.",
            ],
            plain: format!("tuist_cargo_cache[savings]: {count} compilations served from cache to date"),
        });
    }
    eligible
}

/// One line about what tuist_cargo_cache has saved, or nothing worth saying yet.
///
/// Which fact appears -- and, in the default style, which telling of it -- is
/// random. A machine that qualifies for several facts should not recite them
/// in a fixed order, and a joke wears out at exactly the speed it repeats.
/// `pick` is injected so tests can reach every line; callers use [`quip`].
fn quip_choosing(
    tally: &Tally,
    facts: &SessionFacts,
    style: SavingsStyle,
    mut pick: impl FnMut(usize) -> usize,
) -> Option<String> {
    if style == SavingsStyle::Off {
        return None;
    }
    let mut eligible = facts_worth_telling(tally, facts);
    if eligible.is_empty() {
        return None;
    }
    let index = pick(eligible.len()) % eligible.len();
    let candidate = eligible.swap_remove(index);
    match style {
        SavingsStyle::Quips => {
            let mut variants = candidate.cheeky;
            let index = pick(variants.len()) % variants.len();
            Some(variants.swap_remove(index))
        }
        SavingsStyle::Plain => Some(candidate.plain),
        SavingsStyle::Off => unreachable!("handled above"),
    }
}

pub(crate) fn quip(tally: &Tally, facts: &SessionFacts, style: SavingsStyle) -> Option<String> {
    use rand::RngExt as _;
    quip_choosing(tally, facts, style, |len| rand::rng().random_range(0..len))
}

fn iec(bytes: u64) -> String {
    ByteSize::b(bytes).display().iec().to_string()
}

/// A duration the way a person would say it: "6h 14m", "2m 51s", "45s".
///
/// A brag is stated in whole units, so this rounds to the nearest second:
/// "45s", not "45.32s". Below a second there is nothing left to round away and
/// the measurement itself is the friendliest thing to say.
pub(crate) fn nanos(nanoseconds: u64) -> String {
    let duration = Duration::from_nanos(nanoseconds);
    if duration.as_secs() == 0 && !duration.is_zero() {
        return format_duration(duration);
    }
    format_clock(duration)
}

/// "1 build" is not "1 builds", and the one machine that hits it would be the
/// machine of someone deciding whether to keep tuist_cargo_cache.
fn builds(count: u64) -> String {
    if count == 1 {
        "1 build".to_string()
    } else {
        format!("{count} builds")
    }
}

fn duration_ns(duration: Duration) -> u64 {
    crate::util::duration_ns(duration)
}

/// Record `delta` without letting a bookkeeping failure reach the build.
///
/// Callers are past the point where anything can be done about an error: cargo
/// has exited and its status is the answer the user came for.
pub(crate) fn record_quietly(store: &Path, delta: &Delta) -> Option<Tally> {
    match record(store, delta) {
        Ok(tally) => Some(tally),
        Err(error) => {
            log::debug!("savings were not recorded: {error}");
            None
        }
    }
}

/// Record and, when there is something worth saying, return the line to say.
pub(crate) fn record_and_describe(
    store: &Path,
    delta: &Delta,
    facts: &SessionFacts,
    style: SavingsStyle,
) -> Option<String> {
    // A run that neither compiled nor collected anything moves no counter, so
    // it does not write -- not even to start the file. A sweep that came due
    // during `cargo build --help` did free bytes, and that delta is not empty,
    // so those are still counted.
    if delta.is_empty() && facts.hits == 0 {
        return None;
    }
    let tally = record_quietly(store, delta)?;
    quip(&tally, facts, style)
}

#[cfg(test)]
#[path = "savings_tests.rs"]
mod tests;
