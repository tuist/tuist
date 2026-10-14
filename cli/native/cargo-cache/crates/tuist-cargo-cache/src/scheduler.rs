//! Machine-wide scheduling of real compiler processes.
//!
//! Cargo plans one build at a time: three simultaneous worktree builds each
//! believe they own the machine and multiply `-j`. The shims sit in front of
//! every expensive process across all of those builds at once, so this module
//! coordinates what Cargo cannot -- a permit pool under the cache directory
//! that real compilations draw from. Cache hits never touch it, and Cargo
//! keeps its own dependency scheduling; only the processes that actually cost
//! CPU and memory wait their turn. With `scheduler.tests`, the test binaries
//! `cargo test` runs draw from the same pool (see `cli::test_runner`).
//!
//! The pool is a directory of *lease* files, one per admitted compilation,
//! each held under an OS file lock for the life of the compile. The kernel
//! releases those locks when their holder dies, so a killed shim can never
//! leak capacity; a lease whose lock can be taken is stale and is reclaimed
//! by the next admission scan. Admission itself serializes on one registrar
//! lock, held only long enough to scan and grant.
//!
//! Weights make links and historically memory-heavy crates cost more than one
//! permit: the sum of admitted weights never exceeds the capacity, so the
//! *predicted* memory of everything running stays inside the configured
//! budget. Prediction comes from a small ledger of peak RSS per crate name,
//! measured after every real compile on Unix; the static link weight is only
//! the guess that stands in until one has been measured. Two things remain
//! out of reach and are accepted: a single compilation larger than the
//! machine will still be too large when it runs alone, and a simultaneous
//! pile-up of never-measured crates can overshoot before the ledger has
//! learned them.
//!
//! Concurrent sessions may be configured with different capacities; each
//! enforces its own bound against the same leases, so the loosest
//! configuration wins and nothing deadlocks. Every failure here degrades to
//! compiling without a permit -- the pool is a courtesy, never a dependency.
//!
//! This sits above Cargo's jobserver rather than beside it. A shim waiting
//! for a permit is holding the implicit jobserver token Cargo gave it, so the
//! two systems do hold each other's resources -- but they cannot deadlock,
//! because rustc never needs a *second* token to finish: it keeps the
//! implicit one and falls back to compiling its codegen units on fewer
//! threads. The worst case is a permit holder running single-threaded, which
//! costs time and always ends.
//!
//! Beside the pool live the *flights*: one lock per invocation identity, so
//! concurrent builds that reach the same compilation deduplicate it instead
//! of merely pacing it -- see [`Flight`]. The lock ordering between the two
//! is fixed and acyclic: a flight is joined before its permit is requested,
//! never around the other way, and a waiter blocked on a flight holds no
//! permit.

use crate::config::{Config, SchedulerPriority};
use eyre::{Context, Result};
use log::debug;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// Directory under the cache root holding the pool.
const SCHEDULER_DIR: &str = "scheduler";
/// Subdirectory holding one locked lease file per admitted compilation.
const LEASES_DIR: &str = "leases";
/// Subdirectory holding one locked flight file per compiling invocation.
const INFLIGHT_DIR: &str = "inflight";
/// Registrar lock serializing admission scans.
const POOL_LOCK: &str = "pool.lock";
/// Stamp a waiting normal-priority build touches so low-priority builds yield.
const PRIORITY_WAIT_STAMP: &str = "priority-wait";
/// Ledger of peak compiler RSS by crate name.
const LEDGER_FILE: &str = "memory.json";
/// Lock serializing ledger updates.
const LEDGER_LOCK: &str = "memory.lock";

/// Where the pool lives; empty means the session turned scheduling off.
pub(crate) const SCHED_DIR_ENV: &str = "TUIST_CARGO_CACHE_SCHED_DIR";
/// Keep scheduler shims off for work already covered by an outer reservation.
///
/// A nested `tuist_cargo_cache` command otherwise constructs a new session and re-resolves
/// configuration, which would replace an inherited empty `TUIST_CARGO_CACHE_SCHED_DIR`.
pub(crate) const SCHED_DISABLE_ENV: &str = "TUIST_CARGO_CACHE_SCHED_DISABLE";
/// Machine-wide concurrent compile permits.
pub(crate) const SCHED_SLOTS_ENV: &str = "TUIST_CARGO_CACHE_SCHED_SLOTS";
/// Memory one permit stands for; zero disables memory weighting.
pub(crate) const SCHED_SLOT_BYTES_ENV: &str = "TUIST_CARGO_CACHE_SCHED_SLOT_BYTES";
/// Permit priority of this build's compilations.
pub(crate) const SCHED_PRIORITY_ENV: &str = "TUIST_CARGO_CACHE_SCHED_PRIORITY";
/// Identity shared by every compiler shim in one Cargo build.
const SCHED_PRESSURE_ENV: &str = "TUIST_CARGO_CACHE_SCHED_PRESSURE";
const SCHED_BUILD_ID_ENV: &str = "TUIST_CARGO_CACHE_SCHED_BUILD_ID";
/// Most weighted permits one Cargo build may hold at once.
const SCHED_BUILD_SLOTS_ENV: &str = "TUIST_CARGO_CACHE_SCHED_BUILD_SLOTS";

/// Schema version of one lease record.
const LEASE_VERSION: u8 = 1;
/// Schema version of one flight record.
const FLIGHT_VERSION: u8 = 1;
/// Largest prediction one finished compilation leaves behind for the next.
///
/// A payload is one crate's input list, tens of kilobytes for anything real;
/// this cap is not a budget but a refusal to persist something that has
/// plainly stopped being that.
const MAX_FLIGHT_PAYLOAD: usize = 4 * 1024 * 1024;
/// Schema version of the peak-RSS ledger.
const LEDGER_VERSION: u8 = 1;
/// Most crates the ledger retains; the smallest are dropped first.
const MAX_LEDGER_ENTRIES: usize = 1024;
/// Link measurements the window keeps, newest last.
///
/// Small on purpose: it stands for what *this* machine's links cost lately,
/// and a window long enough to remember a toolchain ago would keep quoting a
/// number nothing here produces any more.
const MAX_LINK_SAMPLES: usize = 16;
/// Measurements the window needs before it may speak for an unmeasured link.
///
/// One link is an anecdote -- the first one on a machine is as likely to be a
/// trivial build script as the program itself -- so the static floor stands
/// until a few have been seen.
const MIN_LINK_SAMPLES: usize = 3;
/// Permits a native link costs before it has ever been measured.
///
/// Links are the out-of-memory class -- rust-lang/cargo#12912 is about little
/// else -- so they start heavy rather than waiting for history to say so.
const LINK_WEIGHT: u64 = 2;
/// First delay after a refused admission.
const POLL_INITIAL: Duration = Duration::from_millis(2);
/// Longest delay between admission attempts.
///
/// A permit is released the instant its compiler exits and nothing wakes the
/// waiters, so this bounds how long a core sits idle with work queued for
/// it. Kept short for that reason: one attempt is a readdir and a handful of
/// `try_lock`s, which even a full pool of waiters can afford at this rate.
///
/// Waking waiters on the release itself -- watching the leases directory, so
/// the wait ends when a lease disappears -- was built and measured and did
/// not pay, so it is deliberately not here. The reason is not that the win
/// was small enough to lose in the noise: this interval is not what a waiter
/// is waiting on. Waiters poll at independent jittered phases, so a released
/// permit is found by whichever of them wakes first, and the more waiters
/// there are the sooner that is.
///
/// Measured on hk, which is the shape that makes this look worst -- one
/// build, permits deliberately scarce so the pool really is the constraint:
///
/// - at the default permit count, the whole build spends 0.2 s waiting for
///   permits across ten admissions, so nothing here is worth reaching for;
/// - at two permits, where admissions wait 1100 s in aggregate, cutting this
///   interval by twelve and a half times -- to 2 ms, past what any wake could
///   save -- moved the build from 62.5 s to 63.0 s, and the aggregate wait
///   from 1105 s to 1073 s. Both are inside the run-to-run spread.
///
/// What that aggregate wait is, then, is capacity that genuinely was not
/// free. No mechanism for noticing sooner can return it.
const POLL_MAX: Duration = Duration::from_millis(25);
/// How recently the stamp must have been touched to hold low priority back.
const PRIORITY_WAIT_FRESHNESS: Duration = Duration::from_secs(2);
/// How often one waiter refreshes that stamp, well inside its freshness.
const PRIORITY_STAMP_INTERVAL: Duration = Duration::from_millis(500);
/// How long one compilation waits before saying so in the debug log.
const SLOW_WAIT_NOTICE: Duration = Duration::from_secs(60);
/// How long the available-memory gate may defer one compilation.
///
/// The gate exists to avoid piling predicted-heavy work onto a machine that is
/// already short, but a machine that stays short must not starve a build
/// forever: past this deadline the permit arithmetic alone decides.
const GATE_DEADLINE: Duration = Duration::from_secs(120);

/// Distinguishes leases created by one process, which may hold several.
static LEASE_NONCE: AtomicU64 = AtomicU64::new(0);

fn next_lease_nonce() -> u64 {
    LEASE_NONCE.fetch_add(1, Ordering::Relaxed)
}

/// Names tried before giving up on finding an unused one.
///
/// A collision needs two processes to draw the same token, so one retry
/// already makes it vanishingly unlikely; the rest are for the pathological
/// case where the token source is not what it claims to be.
const LEASE_NAME_ATTEMPTS: usize = 8;

/// A token drawn once, distinguishing this process from one that shares its
/// pid in another namespace.
fn process_token() -> &'static str {
    static TOKEN: OnceLock<String> = OnceLock::new();
    TOKEN.get_or_init(|| crate::util::random_string(8))
}

/// What one compilation -- or one test binary -- asks the pool for.
pub(crate) struct Demand {
    /// Compiler crate name, keying the peak-RSS ledger.
    name: String,
    /// Whether the invocation links a native program.
    links: bool,
    /// Permits the process's threads need whatever its memory, or `None` for
    /// half the pool: a test harness sized to the machine that has not said
    /// how many threads it will really use.
    threads: Option<u64>,
    /// Whether the ledger's record of cores this process kept busy replaces
    /// `threads`. Only test binaries are measured; a compiler is one thread.
    learns_cpu: bool,
    /// The code-generation settings of a link, which key its window of recent
    /// measurements: a release link's peaks must not stand in for a dev
    /// link that has none of its own yet.
    profile: Option<String>,
}

impl Demand {
    pub(crate) fn new(name: &str, links: bool) -> Self {
        Self {
            name: name.to_string(),
            links,
            threads: Some(1),
            learns_cpu: false,
            profile: None,
        }
    }

    /// Remember a link apart from the same crate's links under other
    /// code-generation settings.
    ///
    /// A release build with fat LTO and one codegen unit peaks several times
    /// higher than a dev link of the same binary, and the ledger never lowers
    /// a recorded peak, so without this one release build would charge every
    /// later dev link its memory. Read from the rustc flags rather than the
    /// profile name, since a custom profile inherits from `release`.
    pub(crate) fn with_link_profile(mut self, arguments: &[std::ffi::OsString]) -> Self {
        if self.links {
            let profile = link_profile(arguments);
            self.name = format!("{} [{profile}]", self.name);
            self.profile = Some(profile);
        }
        self
    }

    /// A test binary, remembered apart from the crate that compiled it.
    ///
    /// Half the pool by default rather than all of it. libtest starts a
    /// thread per CPU, but most suites spend much of their time waiting, and
    /// a demand for the whole pool is admitted only once the pool is idle --
    /// which a stream of other builds' compilations can postpone
    /// indefinitely. Half still keeps two suites from each running at full
    /// width beside a third build's compiles.
    ///
    /// A binary run with a stated thread count is remembered apart from the
    /// same binary at its default width: the two keep different numbers of
    /// cores busy.
    pub(crate) fn test(name: &str, threads: Option<u64>) -> Self {
        Self {
            // The suffix cannot collide with a crate name, for the reason
            // `ledger_key` gives.
            name: match threads {
                Some(threads) => format!("{name} [test, {threads} threads]"),
                None => format!("{name} [test]"),
            },
            links: false,
            threads,
            learns_cpu: true,
            profile: None,
        }
    }
}

/// One admitted compilation's capacity, released on drop or process death.
pub(crate) struct Permit {
    /// Taken before the file is removed. Windows refuses to delete a file
    /// anyone still holds open, so closing the handle -- not merely unlocking
    /// it -- is what lets the lease go away rather than accumulate.
    lock: Option<fslock::LockFile>,
    path: PathBuf,
}

impl Drop for Permit {
    fn drop(&mut self) {
        // Between the close and the removal this lease reads as stale to
        // anyone scanning, which is exactly what it is: its holder has
        // finished. The worst a concurrent scan does is remove it first.
        drop(self.lock.take());
        let _ = std::fs::remove_file(&self.path);
    }
}

/// One lease record, stored beside the lock that proves its holder is alive.
#[derive(Debug, Serialize, Deserialize)]
struct Lease {
    version: u8,
    weight: u64,
    priority: String,
    #[serde(default)]
    build_id: Option<String>,
}

/// What one finished compilation leaves in its flight file: the prediction
/// that lets whoever comes next rebuild the action key and restore instead of
/// compiling.
#[derive(Debug, Serialize, Deserialize)]
struct FlightRecord {
    version: u8,
    adapter: String,
    invocation: String,
    payload: String,
}

/// Exclusive occupancy of one invocation identity, machine-wide.
///
/// Concurrent builds duplicate work the permit pool can only pace: four CI
/// jobs compiling the same dependency graph run the same `rustc` invocation
/// four times, each burning a permit on a result the store is about to hold
/// anyway. A flight is a lock keyed by the invocation digest, taken just
/// before a real compilation starts. Whoever holds it compiles; anyone else
/// arriving at the same invocation blocks on the lock instead of the
/// compiler, which is never slower -- the holder finishes no later than the
/// duplicate would have -- and wakes to a store that already has the result.
///
/// The handoff needs more than the lock, because a cold waiter has no way to
/// build the action key on its own: the key hashes inputs only the compiler's
/// dependency output names. So the holder leaves its input prediction in the
/// flight file when it publishes, and the waiter rehashes those inputs to
/// rebuild the key -- the same validation a manifest prediction gets, so a
/// stale or foreign record can only miss, never restore the wrong thing. The
/// file outlives the flight: a later build of the same invocation finds the
/// prediction even when its own manifest carries nothing, which is what turns
/// jobs that merely overlap -- rather than collide -- into hits.
///
/// Like the pool, this degrades to compiling: every failure returns `None`
/// and the compilation proceeds as if flights did not exist. A holder that
/// dies releases the lock with its process; a holder that publishes nothing
/// -- a failed or uncacheable compile -- wakes its waiters to a miss, and the
/// first of them compiles. That serializes what would have run in parallel,
/// which is the accepted cost: it is rare (the compile usually failed for
/// them all), and for the out-of-memory case it is the desirable behavior.
pub(crate) struct Flight {
    lock: Option<fslock::LockFile>,
    path: PathBuf,
    adapter: &'static str,
    invocation: String,
    /// Whether another process held this invocation when we arrived.
    waited: bool,
    /// The prediction found under the lock, when it describes this invocation.
    inherited: Option<String>,
}

impl Flight {
    /// Whether this process blocked behind another compiling the same thing.
    pub(crate) fn waited(&self) -> bool {
        self.waited
    }

    /// The prediction the previous holder left, if any.
    pub(crate) fn inherited(&self) -> Option<&str> {
        self.inherited.as_deref()
    }

    /// Leave this compilation's prediction for whoever comes next.
    ///
    /// Written beside the lock file rather than into it, because the lock
    /// file's contents belong to the lock: releasing one truncates it. The
    /// record is only ever read and written under the lock, and the write is
    /// atomic besides, so a reader can never see half of one. It is not
    /// fsynced: a record lost to a crash costs the next build of this
    /// invocation a cold key, and a torn one fails to parse and is ignored.
    /// The disk round trip was paid once per compilation, on the shim's
    /// critical path, and build scripts that compile many C files at once
    /// queued behind each other on it.
    pub(crate) fn leave(&self, payload: &str) {
        if payload.len() > MAX_FLIGHT_PAYLOAD {
            return;
        }
        let record = FlightRecord {
            version: FLIGHT_VERSION,
            adapter: self.adapter.into(),
            invocation: self.invocation.clone(),
            payload: payload.into(),
        };
        let written = serde_json::to_vec(&record)
            .map_err(eyre::Report::from)
            .and_then(|bytes| crate::util::write_advisory(&record_path(&self.path), &bytes));
        if let Err(error) = written {
            debug!("a flight prediction was not left behind: {error:#}");
        }
    }
}

/// Where one flight's prediction record lives, beside its lock.
fn record_path(lock_path: &Path) -> PathBuf {
    let mut path = lock_path.as_os_str().to_owned();
    path.push(".prediction");
    PathBuf::from(path)
}

/// How long an untouched flight is kept for.
///
/// Both of a flight's files get a fresh timestamp every time its invocation
/// really compiles, so age here means nobody has compiled this identity in a
/// month -- and identities churn with every toolchain and dependency bump,
/// which is why the directory needs a sweep at all.
const FLIGHT_MAX_AGE: Duration = Duration::from_secs(30 * 24 * 60 * 60);

/// Drop flight files whose invocations nobody compiles any more.
///
/// Run from `tuist_cargo_cache gc` beside the store's own collection. Losing a record
/// costs at most one compilation that would have been a hit; a lock that
/// cannot be taken belongs to a live compilation and is left alone together
/// with its record.
pub(crate) fn prune_flights(cache_dir: &Path) {
    let dir = cache_dir.join(SCHEDULER_DIR).join(INFLIGHT_DIR);
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return;
    };
    let stale = |path: &Path| {
        std::fs::metadata(path)
            .and_then(|metadata| metadata.modified())
            .ok()
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|age| age > FLIGHT_MAX_AGE)
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path
            .extension()
            .is_some_and(|extension| extension == "prediction")
        {
            // Swept with its lock below while the lock exists; on its own it
            // is a leftover from an interrupted sweep.
            if stale(&path) && !path.with_extension("").exists() {
                let _ = std::fs::remove_file(&path);
            }
            continue;
        }
        let record = record_path(&path);
        if !stale(&path) || (record.exists() && !stale(&record)) {
            continue;
        }
        let Ok(mut lock) = fslock::LockFile::open(&path) else {
            continue;
        };
        if lock.try_lock().is_ok_and(|taken| taken) {
            let _ = std::fs::remove_file(&record);
            // Closed before the removal, because Windows will not delete a
            // file that is still open anywhere.
            drop(lock);
            let _ = std::fs::remove_file(&path);
        }
    }
}

impl Drop for Flight {
    fn drop(&mut self) {
        // The file stays: it holds the prediction the next build of this
        // invocation restores from. Only the lock is released.
        drop(self.lock.take());
    }
}

/// Join the flight for one invocation, becoming its compiler.
///
/// Returns holding the lock. If another process was already compiling this
/// invocation, that means having waited for it to finish -- which is the
/// point: on waking, `inherited` usually restores and the compiler never
/// runs. `None` means flights could not be used; the compilation just runs.
pub(crate) fn flight(adapter: &'static str, invocation: &str) -> Option<Flight> {
    let pool = pool()?;
    match flight_at(&pool.dir, adapter, invocation) {
        Ok(flight) => Some(flight),
        Err(error) => {
            debug!("compiling outside a flight: {error:#}");
            None
        }
    }
}

fn flight_at(pool_dir: &Path, adapter: &'static str, invocation: &str) -> Result<Flight> {
    let _phase = crate::phase_timing::phase("flight_wait");
    let dir = pool_dir.join(INFLIGHT_DIR);
    std::fs::create_dir_all(&dir)
        .wrap_err_with(|| format!("failed to create {}", dir.display()))?;
    let path = dir.join(format!("{adapter}-{invocation}"));
    let mut lock = fslock::LockFile::open(&path)?;
    let waited = !lock.try_lock()?;
    if waited {
        lock.lock()?;
    }
    let inherited = std::fs::read(record_path(&path))
        .ok()
        .and_then(|bytes| serde_json::from_slice::<FlightRecord>(&bytes).ok())
        .filter(|record| {
            record.version == FLIGHT_VERSION
                && record.adapter == adapter
                && record.invocation == invocation
        })
        .map(|record| record.payload);
    Ok(Flight {
        lock: Some(lock),
        path,
        adapter,
        invocation: invocation.to_string(),
        waited,
        inherited,
    })
}

/// Peak compiler RSS by crate name, machine-wide.
///
/// Read the way the savings tally is: anything unreadable is an empty ledger,
/// because refusing to schedule over a corrupt file would help nobody.
#[derive(Debug, Default, Serialize, Deserialize)]
struct MemoryLedger {
    version: u8,
    crates: BTreeMap<String, u64>,
    /// Recent link measurements, newest last, whatever crate they came from.
    link_peaks: Vec<u64>,
    /// Average cores each test binary kept busy, by demand name.
    #[serde(default)]
    cpus: BTreeMap<String, u64>,
    /// Recent link measurements by code-generation profile, newest last.
    #[serde(default)]
    profile_link_peaks: BTreeMap<String, Vec<u64>>,
}

/// The machine-wide permit pool one process draws from.
pub(crate) struct Pool {
    pub(crate) dir: PathBuf,
    capacity: u64,
    /// A per-Cargo-build ceiling, separate from the machine-wide capacity.
    build: Option<(String, u64)>,
    /// Memory one permit stands for. Zero turns memory weighting and the
    /// available-memory gate off, leaving plain CPU permits.
    bytes_per_permit: u64,
    priority: SchedulerPriority,
    /// Probe for currently available memory, injectable for tests.
    available_memory: fn() -> Option<u64>,
    pressure: bool,
    pressure_probe: fn() -> crate::pressure::Reading,
    /// The memory domain `pressure_probe` reads, injectable for tests. Pools
    /// in different containers share leases but not pressure state.
    pressure_domain: &'static str,
    clock: fn() -> u64,
    /// Source of the counter in lease names, injectable for tests.
    lease_nonce: fn() -> u64,
}

/// The pool this process schedules against, or `None` when scheduling is off.
///
/// Resolved once: from the session's environment when one is running, and from
/// configuration for a persistent wrapper that has no session. Resolution
/// failures turn scheduling off rather than failing the compilation.
pub(crate) fn pool() -> Option<&'static Pool> {
    static POOL: OnceLock<Option<Pool>> = OnceLock::new();
    POOL.get_or_init(resolve_pool).as_ref()
}

/// Construct the pool used by `tuist_cargo_cache reserve`.
///
/// Reservations are explicit user requests, unlike compiler shims where a
/// broken scheduler must fail open. Keep their priority separate from the
/// configured default: an unattended external job may deliberately yield to
/// normal builds without changing the priority of every later Cargo command.
pub(crate) fn reservation_pool(config: &Config, priority: SchedulerPriority) -> Option<Pool> {
    let scheduler = &config.scheduler;
    scheduler.enabled.then(|| {
        let permits = scheduler.permits();
        let mut pool = Pool::new(
            config.cache_dir.join(SCHEDULER_DIR),
            permits,
            bytes_per_permit(scheduler.memory_bytes, permits),
            priority,
        );
        pool.pressure = scheduler.pressure;
        pool
    })
}

fn resolve_pool() -> Option<Pool> {
    match std::env::var_os(SCHED_DIR_ENV) {
        Some(dir) if dir.is_empty() => None,
        Some(dir) => {
            let capacity = env_number(SCHED_SLOTS_ENV).unwrap_or_else(default_capacity);
            let mut pool = Pool::new(
                PathBuf::from(dir),
                capacity,
                env_number(SCHED_SLOT_BYTES_ENV).unwrap_or(0),
                std::env::var(SCHED_PRIORITY_ENV)
                    .ok()
                    .and_then(|value| value.parse().ok())
                    .unwrap_or_default(),
            );
            pool.pressure = env_number(SCHED_PRESSURE_ENV) == Some(1);
            pool.build = std::env::var(SCHED_BUILD_ID_ENV)
                .ok()
                .filter(|id| !id.is_empty())
                .map(|id| {
                    let slots = env_number(SCHED_BUILD_SLOTS_ENV)
                        .unwrap_or(capacity)
                        .clamp(1, capacity.max(1));
                    (id, slots)
                });
            Some(pool)
        }
        None => match Config::load() {
            Ok(config) => Pool::from_config(&config),
            Err(error) => {
                debug!("compile scheduling is off; configuration did not load: {error:#}");
                None
            }
        },
    }
}

fn env_number(name: &str) -> Option<u64> {
    std::env::var(name).ok()?.parse().ok()
}

fn default_capacity() -> u64 {
    std::thread::available_parallelism().map_or(1, |cpus| cpus.get() as u64)
}

/// The environment a session hands its shims so they schedule consistently.
///
/// An explicit empty directory means "off", stated rather than omitted for the
/// reason `VERIFY_ENV` always is: an absent key would leave a shim resolving
/// configuration on its own, which is the standalone path, not a disabled one.
/// The environment for a Cargo build whose own jobserver may be narrower.
pub(crate) fn session_environment_with_jobs(
    config: &Config,
    cargo_jobs: Option<u64>,
) -> Vec<(String, String)> {
    let scheduler = &config.scheduler;
    if !scheduler.enabled || std::env::var_os(SCHED_DISABLE_ENV).is_some() {
        return vec![(SCHED_DIR_ENV.into(), String::new())];
    }
    let permits = scheduler.permits();
    let build_permits = cargo_jobs.map_or(permits, |jobs| permits.min(jobs.max(1)));
    vec![
        (
            SCHED_DIR_ENV.into(),
            config
                .cache_dir
                .join(SCHEDULER_DIR)
                .to_string_lossy()
                .into_owned(),
        ),
        (SCHED_SLOTS_ENV.into(), permits.to_string()),
        (
            SCHED_PRESSURE_ENV.into(),
            u8::from(scheduler.pressure).to_string(),
        ),
        (
            SCHED_SLOT_BYTES_ENV.into(),
            bytes_per_permit(scheduler.memory_bytes, permits).to_string(),
        ),
        (
            SCHED_PRIORITY_ENV.into(),
            scheduler.priority.as_str().into(),
        ),
        (
            "TUIST_CARGO_CACHE_SCHED_SUSPEND".into(),
            u8::from(scheduler.suspend && scheduler.pressure && scheduler.memory_bytes.is_some())
                .to_string(),
        ),
        (
            "TUIST_CARGO_CACHE_SCHED_CGROUP_ROOT".into(),
            scheduler
                .cgroup_root
                .as_ref()
                .map_or_else(String::new, |path| path.to_string_lossy().into_owned()),
        ),
        (SCHED_BUILD_ID_ENV.into(), crate::util::random_string(12)),
        (SCHED_BUILD_SLOTS_ENV.into(), build_permits.to_string()),
    ]
}

fn bytes_per_permit(memory_bytes: Option<u64>, cpus: u64) -> u64 {
    memory_bytes.map_or(0, |memory| memory / cpus.max(1))
}

/// Record what the compiler that just ran cost, for the next admission.
///
/// Crates that fit inside one permit are not worth remembering -- except
/// links that succeeded, whose measurement is what retires the static floor
/// they are otherwise charged. A compiler killed by SIGKILL -- the Linux OOM
/// killer's signature -- is recorded *heavier* than it measured, so the retry
/// runs with more room instead of repeating the crash.
pub(crate) fn record_compiler_memory(demand: &Demand, status: &ExitStatus) {
    let Some(pool) = pool() else {
        return;
    };
    pool.note_compilation(demand, status);
}

/// Record the average cores a test binary kept busy, for its next admission.
pub(crate) fn record_test_cpu(demand: &Demand, cores: u64) {
    let Some(pool) = pool() else {
        return;
    };
    if let Err(error) = pool.record_cpu(&demand.name, cores) {
        debug!("test CPU use was not recorded: {error:#}");
    }
}

/// Cores kept busy on average: CPU time over the wall time it took, to the
/// nearest whole core and never less than one. The nearest rather than the
/// next, because a suite that averaged just over one core is a one-core suite
/// with a helper thread, not a two-core one.
pub(crate) fn average_cores(cpu: Duration, wall: Duration) -> u64 {
    if wall.is_zero() {
        return 1;
    }
    (cpu.as_secs_f64() / wall.as_secs_f64()).round().max(1.0) as u64
}

impl Pool {
    fn new(
        dir: PathBuf,
        capacity: u64,
        bytes_per_permit: u64,
        priority: SchedulerPriority,
    ) -> Self {
        Self {
            dir,
            capacity: capacity.max(1),
            build: None,
            bytes_per_permit,
            priority,
            available_memory: crate::util::memory_available_bytes,
            pressure: true,
            pressure_probe: crate::pressure::probe,
            pressure_domain: crate::pressure::domain(),
            clock: crate::pressure::now_ms,
            lease_nonce: next_lease_nonce,
        }
    }

    fn from_config(config: &Config) -> Option<Self> {
        let scheduler = &config.scheduler;
        let permits = scheduler.permits();
        scheduler.enabled.then(|| {
            let mut pool = Self::new(
                config.cache_dir.join(SCHEDULER_DIR),
                permits,
                bytes_per_permit(scheduler.memory_bytes, permits),
                scheduler.priority,
            );
            pool.pressure = scheduler.pressure;
            pool
        })
    }

    /// Wait for capacity to run one real compilation.
    ///
    /// `None` means the pool could not be used and the compilation should run
    /// unscheduled; it never means the compilation should not run.
    pub(crate) fn admit(&self, demand: &Demand) -> Option<Permit> {
        let _phase = crate::phase_timing::phase("permit_wait");
        let (weight, predicted) = self.plan(demand);
        let started = Instant::now();
        let mut delay = POLL_INITIAL;
        let mut stamped: Option<Instant> = None;
        let mut complained = false;
        loop {
            // The gate stops applying at its deadline so a machine that stays
            // short of memory delays this compilation rather than starving it.
            let gate = predicted.filter(|_| started.elapsed() < GATE_DEADLINE);
            match self.try_admit(weight, gate) {
                Ok(Some(permit)) => return Some(permit),
                Ok(None) => {}
                Err(error) => {
                    debug!("compiling without a machine-wide permit: {error:#}");
                    return None;
                }
            }
            // Refreshed well inside the freshness window rather than on every
            // attempt: this says "somebody is waiting", which does not become
            // truer for being written forty times a second by every waiter.
            if self.priority == SchedulerPriority::Normal
                && stamped.is_none_or(|last| last.elapsed() >= PRIORITY_STAMP_INTERVAL)
            {
                let _ = std::fs::write(self.dir.join(PRIORITY_WAIT_STAMP), b"");
                stamped = Some(Instant::now());
            }
            // A pool that is genuinely full is a pool doing its job, so this
            // waits rather than giving up. Said once, because the alternative
            // is a build that looks hung with nothing to explain it: the
            // permits are held by compilers that are really running.
            if !complained && started.elapsed() >= SLOW_WAIT_NOTICE {
                complained = true;
                if self.pressure && self.bytes_per_permit > 0 {
                    debug!(
                        "compiler admission may be waiting for memory pressure to recover ({})",
                        demand.name
                    );
                }
                debug!(
                    "waiting for {weight} of {} machine-wide compile permits ({})",
                    self.capacity, demand.name
                );
            }
            std::thread::sleep(jittered(delay));
            delay = (delay * 2).min(POLL_MAX);
        }
    }

    /// Wait for and hold capacity for work tuist_cargo_cache does not launch itself.
    ///
    /// Unlike compiler admission this propagates scheduler errors: silently
    /// running an explicitly reserved command without its reservation would
    /// defeat the command's purpose.
    pub(crate) fn reserve(&self, cpus: Option<u64>, memory_bytes: Option<u64>) -> Result<Permit> {
        let cpu_weight = cpus.unwrap_or(0);
        let memory_weight = match memory_bytes {
            Some(_) if self.bytes_per_permit == 0 => {
                eyre::bail!("--memory needs scheduler.memory to be configured")
            }
            Some(memory) => memory.div_ceil(self.bytes_per_permit),
            None => 0,
        };
        let weight = cpu_weight.max(memory_weight);
        if weight == 0 {
            eyre::bail!("reserve needs --cpus, --memory, or both")
        }

        let started = Instant::now();
        let mut delay = POLL_INITIAL;
        let mut stamped: Option<Instant> = None;
        loop {
            // Like compiler admission, a persistently low available-memory
            // reading must not turn an advisory gate into permanent starvation.
            let gate = memory_bytes.filter(|_| started.elapsed() < GATE_DEADLINE);
            if let Some(permit) = self.try_admit(weight, gate)? {
                return Ok(permit);
            }
            if self.priority == SchedulerPriority::Normal
                && stamped.is_none_or(|last| last.elapsed() >= PRIORITY_STAMP_INTERVAL)
            {
                let _ = std::fs::write(self.dir.join(PRIORITY_WAIT_STAMP), b"");
                stamped = Some(Instant::now());
            }
            std::thread::sleep(jittered(delay));
            delay = (delay * 2).min(POLL_MAX);
        }
    }

    /// The permits this demand costs, and its predicted memory when known.
    fn plan(&self, demand: &Demand) -> (u64, Option<u64>) {
        // What a test binary was measured using beats what it said or what
        // its harness would default to: libtest starts a thread per CPU
        // whether or not the tests keep them busy.
        let learned = demand
            .learns_cpu
            .then(|| {
                read_ledger(&self.ledger_path())
                    .cpus
                    .get(&demand.name)
                    .copied()
            })
            .flatten();
        let threads = learned
            .or(demand.threads)
            .unwrap_or_else(|| self.capacity.div_ceil(2))
            .max(1);
        let link_floor = demand.links.then_some(LINK_WEIGHT);
        if self.bytes_per_permit == 0 {
            return (
                link_floor.unwrap_or(1).max(threads).min(self.capacity),
                None,
            );
        }
        let ledger = read_ledger(&self.ledger_path());
        let recorded = ledger
            .crates
            .get(&ledger_key(&demand.name, demand.links))
            .copied();
        let link_bytes = link_floor.map(|weight| {
            // What this machine's links have actually cost beats a constant
            // chosen before anyone had seen one. Every test binary is its own
            // crate name, so a cold `cargo test --no-run` never gets to reuse
            // the measurement of the link it just made -- the per-crate entry
            // is always missing for the one in front of it -- and this is the
            // history it can use instead. The heaviest of the window rather
            // than its average, because the cost of guessing low is an
            // out-of-memory kill and the cost of guessing high is a wait.
            //
            // A link with a known profile consults only that profile's
            // window, so a release LTO link never speaks for a dev link.
            let window = match &demand.profile {
                Some(profile) => ledger
                    .profile_link_peaks
                    .get(profile)
                    .map_or(&[][..], Vec::as_slice),
                None => ledger.link_peaks.as_slice(),
            };
            let measured = (window.len() >= MIN_LINK_SAMPLES)
                .then(|| window.iter().copied().max())
                .flatten();
            measured.unwrap_or_else(|| weight.saturating_mul(self.bytes_per_permit))
        });
        // History replaces the floor rather than merely raising it. The floor
        // is a guess for links the pool has never seen; once one has been
        // measured, charging it the guess anyway would hold the tail of every
        // build -- the link-heavy stretch -- to half the concurrency its real
        // memory justifies. The ledger never lowers a recorded peak and an
        // OOM kill escalates past it, so trusting the measurement stays safe
        // in the direction that matters.
        //
        // Only a *link's* own history may retire the link floor, which is why
        // the two are separate ledger entries. One crate is compiled both
        // ways in a single build -- `cargo check` emits metadata where `cargo
        // build` links -- and the metadata-only measurement is the smaller of
        // the two by far. Keyed by name alone it would retire the floor for
        // the link beside it, which is over-admission with a plausible number
        // attached to it.
        let predicted = recorded.or(link_bytes);
        // Memory and threads are separate costs of the same process; it takes
        // whichever share of the pool is larger.
        let weight = predicted
            .map_or(1, |bytes| bytes.div_ceil(self.bytes_per_permit))
            .max(threads)
            .clamp(1, self.capacity);
        (weight, predicted)
    }

    /// One admission attempt under the registrar lock.
    fn try_admit(&self, weight: u64, predicted: Option<u64>) -> Result<Option<Permit>> {
        let leases = self.dir.join(LEASES_DIR);
        std::fs::create_dir_all(&leases)
            .wrap_err_with(|| format!("failed to create {}", leases.display()))?;
        let registrar_path = self.dir.join(POOL_LOCK);
        let mut registrar = fslock::LockFile::open(&registrar_path)?;
        registrar.lock()?;
        let live = scan_leases(&leases)?;
        let now = (self.clock)();
        // Broken sensing disables only this advisory gate, never CPU scheduling.
        let pressure_state = (self.pressure && self.bytes_per_permit > 0)
            .then(|| crate::pressure::domain_state(&self.dir, self.pressure_domain));
        let mut pressure = pressure_state
            .as_ref()
            .and_then(|path| crate::pressure::sample(path, now, self.pressure_probe).ok());
        if self.pressure
            && self.bytes_per_permit > 0
            && !live.is_empty()
            && crate::supervision::resumes_pending(&self.dir, now)
        {
            return Ok(None);
        }
        if !live.is_empty()
            && let Some(state) = &pressure
            && state.valid
            && (state.pressured
                || (state.recovered_ms.is_some()
                    && state.last_admission_ms.is_some_and(|last| {
                        now.saturating_sub(last) < crate::pressure::INTERVAL_MS
                    })))
        {
            return Ok(None);
        }
        let capacity = self.capacity - self.reserved();
        let used: u64 = live.iter().map(|lease| lease.weight).sum();
        if let Some((build_id, build_capacity)) = &self.build {
            let build_used = live
                .iter()
                .filter(|lease| lease.build_id.as_ref() == Some(build_id))
                .map(|lease| lease.weight)
                .sum::<u64>();
            // Like an oversized machine-wide demand, a single compilation
            // heavier than this build's ceiling must still be able to run.
            if build_used > 0 && build_used.saturating_add(weight) > *build_capacity {
                return Ok(None);
            }
        }
        // An oversized demand must still run alone, including when priority
        // reserves reduce capacity. Every grant uses the common path below so
        // other pools observe its recovery-ramp admission timestamp.
        if used > 0 && used.saturating_add(weight) > capacity {
            return Ok(None);
        }
        // The permit arithmetic bounds what history predicted; this bounds it
        // against the machine as it is right now, catching pressure the
        // ledger cannot see -- unmeasured crates already running, or memory
        // that was never the build's to spend.
        //
        // Only while somebody else holds a permit, though. With an idle pool
        // there is no compilation whose finishing would return the memory
        // this one is short of, so deferring would stall the one thing that
        // could proceed and wait out the deadline to reach the same answer.
        if used > 0
            && let Some(needed) = predicted
            && let Some(available) = (self.available_memory)()
            && available < needed
        {
            return Ok(None);
        }
        let permit = self.grant(&leases, weight)?;
        if let Some((path, state)) = pressure_state.as_ref().zip(pressure.as_mut()) {
            state.last_admission_ms = Some(now);
            let _ = crate::pressure::save(path, state);
        }
        Ok(Some(permit))
    }

    /// Create and lock this process's lease. Runs under the registrar lock,
    /// which is what keeps the moment between creation and locking private.
    ///
    /// The name has to be unique against processes this one cannot see. A pid
    /// is only unique within its namespace, and two containers sharing a cache
    /// directory have separate ones -- pid 7 in each is two different
    /// processes. A name collision there would be silent and wrong in both
    /// directions: writing the lease would truncate a live holder's record,
    /// and this compilation would then run unscheduled. So the name carries a
    /// token drawn once per process, and the file is created exclusively so
    /// that a collision is an error to retry rather than an overwrite.
    fn grant(&self, leases: &Path, weight: u64) -> Result<Permit> {
        let lease = serde_json::to_vec(&Lease {
            version: LEASE_VERSION,
            weight,
            priority: self.priority.as_str().into(),
            build_id: self.build.as_ref().map(|(id, _)| id.clone()),
        })?;
        let mut last = None;
        for _ in 0..LEASE_NAME_ATTEMPTS {
            let path = leases.join(format!(
                "{}-{}-{}",
                std::process::id(),
                process_token(),
                (self.lease_nonce)()
            ));
            match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)
            {
                Ok(mut file) => {
                    std::io::Write::write_all(&mut file, &lease)
                        .wrap_err_with(|| format!("failed to write {}", path.display()))?;
                    drop(file);
                    let mut lock = fslock::LockFile::open(&path)?;
                    if !lock.try_lock()? {
                        eyre::bail!("a freshly created lease was already locked");
                    }
                    return Ok(Permit {
                        lock: Some(lock),
                        path,
                    });
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                    last = Some(error);
                }
                Err(error) => {
                    return Err(error)
                        .wrap_err_with(|| format!("failed to create {}", path.display()));
                }
            }
        }
        Err(last.expect("a name is only retried after a collision"))
            .wrap_err("failed to name a lease that was not already taken")
    }

    /// Permits this build holds back for somebody who is waiting on them.
    ///
    /// Never the whole pool. A reserve equal to the capacity -- which a
    /// single-permit machine would otherwise get -- stops a low-priority
    /// build admitting through the ordinary path at all, leaving the
    /// oversized-demand escape as the only way it ever runs, and that one
    /// hands over the entire machine at once. Yielding a quarter must not
    /// become yielding everything and then taking everything.
    fn reserved(&self) -> u64 {
        if self.priority == SchedulerPriority::Low && self.priority_wait_is_fresh() {
            (self.capacity / 4).max(1).min(self.capacity - 1)
        } else {
            0
        }
    }

    fn priority_wait_is_fresh(&self) -> bool {
        std::fs::metadata(self.dir.join(PRIORITY_WAIT_STAMP))
            .and_then(|metadata| metadata.modified())
            .ok()
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|since| since < PRIORITY_WAIT_FRESHNESS)
    }

    fn note_compilation(&self, demand: &Demand, status: &ExitStatus) {
        if self.bytes_per_permit == 0 {
            return;
        }
        let Some(measured) = child_peak_rss_bytes() else {
            return;
        };
        let Some(peak) = ledger_peak(
            measured,
            oom_killed(status),
            demand.links,
            status.success(),
            self.bytes_per_permit,
        ) else {
            return;
        };
        if let Err(error) = self.record_link_peak(
            &ledger_key(&demand.name, demand.links),
            peak,
            demand.links,
            demand.profile.as_deref(),
        ) {
            debug!("compiler memory was not recorded: {error:#}");
        }
    }

    fn ledger_path(&self) -> PathBuf {
        self.dir.join(LEDGER_FILE)
    }

    /// Raise the recorded peak for one crate, never lowering it, and add a
    /// link's measurement to the machine-wide window whatever the entry does.
    #[cfg(test)]
    fn record_peak(&self, name: &str, peak: u64, links: bool) -> Result<()> {
        self.record_link_peak(name, peak, links, None)
    }

    fn record_link_peak(
        &self,
        name: &str,
        peak: u64,
        links: bool,
        profile: Option<&str>,
    ) -> Result<()> {
        std::fs::create_dir_all(&self.dir)
            .wrap_err_with(|| format!("failed to create {}", self.dir.display()))?;
        let mut lock = fslock::LockFile::open(&self.dir.join(LEDGER_LOCK))?;
        lock.lock()?;
        let path = self.ledger_path();
        let mut ledger = read_ledger(&path);
        ledger.version = LEDGER_VERSION;
        // The window records every link, including one whose per-crate entry
        // is already higher: it says what links cost around here lately, which
        // a measurement no worse than the last one still answers.
        if links {
            let window = match profile {
                Some(profile) => ledger
                    .profile_link_peaks
                    .entry(profile.to_string())
                    .or_default(),
                None => &mut ledger.link_peaks,
            };
            window.push(peak);
            let surplus = window.len().saturating_sub(MAX_LINK_SAMPLES);
            window.drain(..surplus);
            while ledger.profile_link_peaks.len() > MAX_LEDGER_ENTRIES {
                ledger.profile_link_peaks.pop_first();
            }
        }
        let known = ledger.crates.get(name).is_some_and(|known| *known >= peak);
        if known && !links {
            // Nothing moved: the entry already stands higher and there is no
            // window entry to add. Rewriting the file identically would cost
            // every repeat compilation a write under this lock.
            return Ok(());
        }
        if !known {
            ledger.crates.insert(name.to_string(), peak);
        }
        while ledger.crates.len() > MAX_LEDGER_ENTRIES {
            let smallest = ledger
                .crates
                .iter()
                .min_by_key(|(_, peak)| **peak)
                .map(|(name, _)| name.clone())
                .expect("an overfull ledger has entries");
            ledger.crates.remove(&smallest);
        }
        let mut contents = serde_json::to_vec(&ledger)?;
        contents.push(b'\n');
        // A heuristic every link refreshes: a lost write costs one sample.
        crate::util::write_advisory(&path, &contents)
    }
}

impl Pool {
    /// Raise the recorded core count for one test binary, never lowering it.
    ///
    /// Never lowered for the reason memory is not, and one more: a suite
    /// measured while the machine was busy got fewer cores than it would
    /// have used, so the lower of two readings is the less trustworthy.
    fn record_cpu(&self, name: &str, cores: u64) -> Result<()> {
        std::fs::create_dir_all(&self.dir)
            .wrap_err_with(|| format!("failed to create {}", self.dir.display()))?;
        let mut lock = fslock::LockFile::open(&self.dir.join(LEDGER_LOCK))?;
        lock.lock()?;
        let path = self.ledger_path();
        let mut ledger = read_ledger(&path);
        if ledger.cpus.get(name).is_some_and(|known| *known >= cores) {
            return Ok(());
        }
        ledger.version = LEDGER_VERSION;
        ledger.cpus.insert(name.to_string(), cores);
        while ledger.cpus.len() > MAX_LEDGER_ENTRIES {
            let smallest = ledger
                .cpus
                .iter()
                .min_by_key(|(_, cores)| **cores)
                .map(|(name, _)| name.clone())
                .expect("an overfull ledger has entries");
            ledger.cpus.remove(&smallest);
        }
        let mut contents = serde_json::to_vec(&ledger)?;
        contents.push(b'\n');
        crate::util::write_advisory(&path, &contents)
    }
}

/// What one crate's memory is remembered under.
///
/// A link and a metadata-only compile of the same crate are different
/// workloads with the same name -- `cargo check` and `cargo build` run both
/// against one crate, often at the same moment -- so they are remembered
/// apart. The suffix cannot collide with a crate name, which is a Rust
/// identifier and can hold neither a space nor a bracket.
fn ledger_key(name: &str, links: bool) -> String {
    if links {
        format!("{name} [link]")
    } else {
        name.to_string()
    }
}

/// The rustc flags that decide how much memory a link takes: optimization,
/// LTO, codegen units and debug info. The last occurrence of each wins, as it
/// does in rustc.
fn link_profile(arguments: &[std::ffi::OsString]) -> String {
    let (mut opt, mut lto, mut units, mut debug) = (None, None, None, None);
    let mut arguments = arguments.iter().filter_map(|argument| argument.to_str());
    while let Some(argument) = arguments.next() {
        let setting = match argument {
            "-C" | "--codegen" => arguments.next(),
            "-O" => {
                opt = Some("3");
                continue;
            }
            "-g" => {
                debug = Some("2");
                continue;
            }
            _ => argument
                .strip_prefix("--codegen=")
                .or_else(|| argument.strip_prefix("-C")),
        };
        let Some(setting) = setting else { continue };
        let (key, value) = setting.split_once('=').unwrap_or((setting, ""));
        match key {
            "opt-level" => opt = Some(value),
            // A bare `-C lto` is fat LTO.
            "lto" => {
                lto = Some(match value {
                    "" | "yes" | "y" | "on" | "true" | "fat" => "fat",
                    "no" | "n" | "off" | "false" => "off",
                    other => other,
                })
            }
            "codegen-units" => units = Some(value),
            "debuginfo" => debug = Some(value),
            _ => {}
        }
    }
    format!(
        "opt{} lto-{} cgu{} debug{}",
        opt.unwrap_or("0"),
        lto.unwrap_or("default"),
        units.unwrap_or("-"),
        debug.unwrap_or("0"),
    )
}

fn read_ledger(path: &Path) -> MemoryLedger {
    std::fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

/// The live lease weights, reclaiming any lease whose holder has died.
fn scan_leases(leases: &Path) -> Result<Vec<Lease>> {
    let mut live = Vec::new();
    for entry in std::fs::read_dir(leases)? {
        let path = entry?.path();
        let mut lock = fslock::LockFile::open(&path)?;
        if lock.try_lock()? {
            // Nobody holds it: the process that created it is gone. Closed
            // before the removal, because Windows will not delete a file that
            // is still open anywhere.
            drop(lock);
            let _ = std::fs::remove_file(&path);
            continue;
        }
        // A live lease that cannot be read still occupies its holder, so it
        // counts as the smallest thing it could be rather than nothing.
        let lease = std::fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Lease>(&bytes).ok())
            .map_or_else(
                || Lease {
                    version: LEASE_VERSION,
                    weight: 1,
                    priority: SchedulerPriority::Normal.as_str().into(),
                    build_id: None,
                },
                |mut lease| {
                    lease.weight = lease.weight.max(1);
                    lease
                },
            );
        live.push(lease);
    }
    Ok(live)
}

/// What the ledger should remember about one finished compilation.
///
/// `None` means nothing worth writing: the compile fit comfortably inside a
/// single permit and carried no static weight worth correcting. An OOM kill
/// is recorded past what was measured -- the measurement is where the killer
/// stopped it, not what it needed -- and past one permit, so the retry
/// provably weighs more.
///
/// The link case is the reason this takes an outcome at all, and the rule is
/// deliberately asymmetric: a *successful* link is recorded whatever it
/// measured, because that is a true reading of what linking that crate costs
/// and it is what retires the static floor. A failed one is not. Whether an
/// invocation links is read off its crate type, so a binary that dies in type
/// checking never reached the linker at all -- and recording its small peak
/// would retire the floor using a number from a compilation that never did
/// the expensive thing, machine-wide, for every later build sharing the
/// cache. A failure is therefore held to the ordinary bar, where it can still
/// teach the ledger that something is *heavy* (a link that died reaching for
/// memory) but can never argue that anything is light.
fn ledger_peak(
    measured: u64,
    oom_killed: bool,
    links: bool,
    succeeded: bool,
    bytes_per_permit: u64,
) -> Option<u64> {
    if oom_killed {
        return Some(
            measured
                .saturating_mul(2)
                .max(bytes_per_permit.saturating_add(1)),
        );
    }
    if links && succeeded {
        return Some(measured);
    }
    (measured > bytes_per_permit).then_some(measured)
}

/// Peak RSS of the compiler this shim ran, from the child rusage counters.
///
/// Exact because a shim process runs exactly one compiler: `RUSAGE_CHILDREN`
/// reports the largest `ru_maxrss` among reaped children, and the identity
/// probes that also ran are orders of magnitude smaller.
///
/// It reaches the linker, which matters here more than anything else it
/// measures. A link is a grandchild -- rustc runs `cc`, which runs `ld` --
/// and the counter still covers it, because a process's own maximum is
/// folded into its parent's children total when it is reaped, all the way up.
#[cfg(unix)]
fn child_peak_rss_bytes() -> Option<u64> {
    let usage = children_usage()?;
    let maxrss = u64::try_from(usage.ru_maxrss).ok()?;
    // Apple counts bytes where everyone else counts kibibytes.
    let bytes = if cfg!(target_vendor = "apple") {
        maxrss
    } else {
        maxrss.saturating_mul(1024)
    };
    Some(bytes).filter(|bytes| *bytes > 0)
}

#[cfg(not(unix))]
fn child_peak_rss_bytes() -> Option<u64> {
    None
}

/// CPU time, user and system, of every child this process has reaped.
///
/// A test runner shim reaps one test binary, and the counter folds in
/// whatever that binary ran in turn -- the builds a test starts are charged
/// to it, as its permit is.
#[cfg(unix)]
pub(crate) fn child_cpu_time() -> Option<Duration> {
    let usage = children_usage()?;
    let time = |value: libc::timeval| {
        Some(Duration::new(
            u64::try_from(value.tv_sec).ok()?,
            u32::try_from(value.tv_usec).ok()?.saturating_mul(1000),
        ))
    };
    Some(time(usage.ru_utime)? + time(usage.ru_stime)?)
}

#[cfg(not(unix))]
pub(crate) fn child_cpu_time() -> Option<Duration> {
    None
}

#[cfg(unix)]
fn children_usage() -> Option<libc::rusage> {
    // SAFETY: `getrusage` only writes into the zeroed struct it is given.
    unsafe {
        let mut usage = std::mem::zeroed::<libc::rusage>();
        (libc::getrusage(libc::RUSAGE_CHILDREN, &mut usage) == 0).then_some(usage)
    }
}

/// Whether the compiler died the way the Linux OOM killer kills.
///
/// Only what rustc itself reports, which is the limit of this signal: a
/// linker killed as a grandchild leaves rustc to exit non-zero with a
/// "linking failed" message, and that is indistinguishable here from an
/// ordinary compile error. What saves the case is that the peak is recorded
/// whether or not the compilation succeeded, so a link that died reaching
/// for memory still teaches the ledger roughly what it was holding; it just
/// does not get the doubling on top.
#[cfg(unix)]
fn oom_killed(status: &ExitStatus) -> bool {
    use std::os::unix::process::ExitStatusExt as _;
    status.signal() == Some(libc::SIGKILL)
}

#[cfg(not(unix))]
fn oom_killed(_status: &ExitStatus) -> bool {
    false
}

/// Spread waiters out so they do not retry in lockstep.
fn jittered(delay: Duration) -> Duration {
    use rand::RngExt as _;
    delay + delay.mul_f64(rand::rng().random_range(0.0..0.5))
}

#[cfg(test)]
#[path = "scheduler_tests.rs"]
mod tests;
