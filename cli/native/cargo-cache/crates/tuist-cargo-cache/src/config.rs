//! Configuration, resolved from environment variables over optional files.
//!
//! Precedence is environment, then the workspace policy, then the platform
//! configuration file, then defaults.

use crate::util::parse_duration;
use bytesize::ByteSize;
use eyre::{Context, Result, bail};
use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};
use std::time::Duration;
use tuist_cargo_cache_core::{RemoteCacheMode, S3ConditionalWrites};
use usage_config::{EnvLayer, FileLayer, FileScope, Layers};

const DEFAULT_HTTP_TIMEOUT: Duration = Duration::from_secs(30);
const DEFAULT_HTTP_DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(600);
const DEFAULT_HTTP_READ_STALL_BUDGET: Duration = Duration::from_secs(90);
const DEFAULT_HTTP_RETRIES: i64 = 3;
const DEFAULT_GC_INTERVAL: Duration = Duration::from_secs(60 * 60);
/// How long a managed target directory may sit unused before collection.
const DEFAULT_TARGET_MAX_AGE: Duration = Duration::from_secs(30 * 24 * 60 * 60);

const GIB: u64 = 1024 * 1024 * 1024;

/// The largest the action-store budget nobody configured will grow to.
const MAX_STORE_BUDGET: u64 = 500 * GIB;

/// The largest the managed-target budget nobody configured will grow to.
const MAX_TARGET_BUDGET: u64 = 100 * GIB;
/// The largest learned-incremental budget nobody configured will grow to.
const MAX_INCREMENTAL_BUDGET: u64 = 100 * GIB;

/// Scaled budgets are rounded down to a multiple of this.
///
/// 5% of a disk is a number like 16.65GiB, which reads like a measurement
/// rather than a decision. Rounding down to whole increments makes the budget
/// tuist_cargo_cache reports back look like something chosen on purpose, and never rounds a
/// budget up past the share it was allowed.
const BUDGET_INCREMENT: u64 = 5 * GIB;

/// A default budget as a share of the disk, bounded at both ends.
///
/// A budget nobody configured should be generous on a large disk and modest on
/// a small one, but neither unbounded nor uselessly tiny: the floor keeps a
/// small disk from a cache too small to hit in. Sizes are stated in IEC units
/// so they read the way `tuist_cargo_cache gc` reports them back.
#[derive(Debug, Clone, Copy)]
struct ScaledBudget {
    /// Percent of the whole disk.
    percent: u64,
    floor: u64,
    ceiling: u64,
    /// Used when the disk cannot be measured. Guessing a disk size would be
    /// worse: this is the budget tuist_cargo_cache shipped with before it scaled them.
    fallback: u64,
}

const STORE_BUDGET: ScaledBudget = ScaledBudget {
    percent: 5,
    floor: 5 * GIB,
    ceiling: MAX_STORE_BUDGET,
    fallback: 20 * GIB,
};

/// Twice the store's share: target directories hold the linked outputs of every
/// live checkout, and they are what fills a disk in practice.
const TARGET_BUDGET: ScaledBudget = ScaledBudget {
    percent: 10,
    floor: 10 * GIB,
    ceiling: MAX_TARGET_BUDGET,
    fallback: 30 * GIB,
};

/// Private incremental state is valuable to active edit loops but is not
/// shared, so it gets the action store's disk share with a larger floor.
const INCREMENTAL_BUDGET: ScaledBudget = ScaledBudget {
    percent: 5,
    floor: 10 * GIB,
    ceiling: MAX_INCREMENTAL_BUDGET,
    fallback: 20 * GIB,
};

/// How much free space a sweep keeps on the disks it collects, unless
/// configured: a tenth of a small disk, but never so much of a large one that
/// hundreds of gigabytes of free space would still count as running out.
const MIN_FREE: ScaledBudget = ScaledBudget {
    percent: 10,
    floor: 5 * GIB,
    ceiling: 50 * GIB,
    // Never consulted: the threshold is only resolved against a disk that was
    // just measured, and a disk that cannot be measured cannot be short either.
    fallback: 5 * GIB,
};

impl ScaledBudget {
    fn resolve(self, disk_total_bytes: Option<u64>) -> u64 {
        let Some(total) = disk_total_bytes.filter(|total| *total > 0) else {
            return self.fallback;
        };
        let share = (total / 100).saturating_mul(self.percent);
        // Floors and the ceiling are whole increments themselves, so clamping
        // cannot reintroduce a ragged number.
        let whole = share - (share % BUDGET_INCREMENT);
        whole.clamp(self.floor, self.ceiling)
    }
}

/// Share of physical memory the compile scheduler budgets by default.
///
/// Deliberately less than the whole machine: the editor, the browser, and the
/// page cache are spending memory the budget cannot see, and a budget equal to
/// physical RAM would schedule compilations into exactly the pressure the
/// scheduler exists to avoid.
const SCHEDULER_MEMORY_PERCENT: u64 = 85;

/// Memory budget used when physical memory cannot be measured.
const SCHEDULER_MEMORY_FALLBACK: u64 = 16 * GIB;

/// The single declaration used to resolve and document tuist_cargo_cache configuration.
#[derive(Debug, usage_rs::Config)]
#[usage(file(
    path = "<config directory>/tuist_cargo_cache/config.toml",
    scope = "global",
    format = "toml"
))]
pub(crate) struct RawConfig {
    /// Cache directory, which holds the store and private incremental state.
    ///
    /// Managed targets (`target.root`) and compiler shims (`shims_dir`) live
    /// inside it unless configured elsewhere. NFS is unsupported for local
    /// build storage.
    #[usage(
        env = "TUIST_CARGO_CACHE_DIR",
        default_note = "an `tuist_cargo_cache` directory in the platform cache directory, such as `~/.cache/tuist_cargo_cache`"
    )]
    cache_dir: Option<PathBuf>,
    /// Directory for the persistent compiler shims.
    ///
    /// Containers that share a cache directory should each use a private,
    /// dedicated local directory that survives builds and contains no real
    /// compilers. A relative path resolves under `cache_dir` and cannot climb
    /// above it with `..` or normalize to an empty path.
    #[usage(
        env = "TUIST_CARGO_CACHE_SHIMS_DIR",
        default_note = "`<cache_dir>/shims`"
    )]
    shims_dir: Option<PathBuf>,
    /// Write a JSON build report to this path.
    #[usage(env = "TUIST_CARGO_CACHE_STATS_REPORT")]
    stats_report: Option<PathBuf>,
    /// Detail of the build summary printed after a build.
    ///
    /// `auto` prints the explanatory `ci` report in CI and the one-line `short`
    /// summary locally; `short`, `ci`, `full`, and `off` select a fixed style.
    #[usage(
        env = "TUIST_CARGO_CACHE_SUMMARY",
        default = "auto",
        choices("auto", "off", "short", "ci", "full")
    )]
    summary: String,
    /// Open the terminal warning browser after a successful Cargo build.
    ///
    /// Has no effect when `display` is `plain`.
    #[usage(env = "TUIST_CARGO_CACHE_PRETTY_INSPECT", default = false)]
    pretty_inspect: bool,
    /// How tuist_cargo_cache displays Cargo's output.
    ///
    /// `auto` allows animated output in a terminal. `plain` disables it even
    /// there, including the inline build view and its warning browser, so
    /// `pretty_inspect` has no effect.
    #[usage(
        env = "TUIST_CARGO_CACHE_DISPLAY",
        default = "auto",
        choices("auto", "plain")
    )]
    display: String,
    /// Compile and consult the cache, then compare outputs.
    #[usage(env = "TUIST_CARGO_CACHE_VERIFY", default = false, scope = "env")]
    verify: bool,
    /// Percentage of compilation identities to verify (0–100), selected deterministically.
    #[usage(env = "TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE", default = 0)]
    verify_sample_rate: i64,
    /// Let Cargo compile local workspace members incrementally.
    ///
    /// tuist_cargo_cache stops forcing `CARGO_INCREMENTAL=0`, so Cargo's profiles decide: by
    /// default, dev builds compile incrementally and release builds do not.
    /// Those compilations bypass the shared cache, crates that depend on them
    /// may miss, and learned incremental reuse turns off. Ignored when `CI` is
    /// `1`, `true`, or `yes`, and while `eager_incremental` is in effect. When
    /// it applies, Cargo still honors a `CARGO_INCREMENTAL` already set in the
    /// environment. This may also be set in workspace `.tuist_cargo_cache.toml`; the
    /// environment variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_INCREMENTAL", default = false)]
    incremental: bool,
    /// Keep private workspace incremental state from the first compilation.
    ///
    /// It applies in CI too, and it overrides `incremental` and learned
    /// incremental reuse. Workspace crates then compile with that state
    /// instead of restoring or publishing shared results, and crates that link
    /// them stay private as well. The first build can be slower. Ignored for
    /// compilations selected for verification by `TUIST_CARGO_CACHE_VERIFY` or
    /// `verify_sample_rate`. This may also be set in workspace `.tuist_cargo_cache.toml`; the
    /// environment variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_EAGER_INCREMENTAL", default = false)]
    eager_incremental: bool,
    /// Use private incremental state for crates whose sources keep changing.
    ///
    /// A workspace crate qualifies on its first source edit; any other crate
    /// after three consecutive misses with changed sources. A qualifying
    /// crate's outputs, and those of crates that link them, stay out of the
    /// shared cache. Off in CI (`CI` set to `1`, `true`, or `yes`), while
    /// `incremental` or `eager_incremental` is in effect, and for compilations
    /// selected for verification by `TUIST_CARGO_CACHE_VERIFY` or `verify_sample_rate`.
    #[usage(
        key = "learned_incremental",
        env = "TUIST_CARGO_CACHE_LEARNED_INCREMENTAL",
        default = true
    )]
    _learned_incremental: bool,
    /// How much learned incremental state one crate may keep, or `"none"`.
    ///
    /// State past this is discarded before the crate compiles again.
    #[usage(
        key = "learned_incremental_max_size",
        env = "TUIST_CARGO_CACHE_LEARNED_INCREMENTAL_MAX_SIZE",
        default_note = "8 GiB, or `gc.max_total_size` when set"
    )]
    learned_incremental_max_size: Option<String>,
    /// Cap on the per-compilation history one build records, or `"none"`.
    ///
    /// Past the cap, the totals the build reports stay complete but its
    /// per-compilation rows stop, and `tuist_cargo_cache explain` says so.
    #[usage(
        key = "events_max_size",
        env = "TUIST_CARGO_CACHE_EVENTS_MAX_SIZE",
        default = "16MiB"
    )]
    events_max_size: String,
    /// Reuse Rust compilations across checkouts with matching build-script output.
    ///
    /// tuist_cargo_cache gives rustc a shared, content-addressed `OUT_DIR` in the cache
    /// directory and remaps generated source paths in Rust and C/C++ debug
    /// information. Disable to preserve Cargo's original `OUT_DIR` and paths.
    /// This may also be set in workspace `.tuist_cargo_cache.toml`; the environment
    /// variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_SHARE_OUT_DIR", default = true)]
    share_out_dir: bool,
    /// Remap the workspace root so compilations do not record their checkout.
    ///
    /// A crate rebuilt in a second checkout then comes out byte-identical, so
    /// its dependents still share. Source paths in debug information and panic
    /// messages name a placeholder instead. This may also be set in workspace
    /// `.tuist_cargo_cache.toml`; the environment variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT", default = false)]
    share_workspace_root: bool,
    /// Restore cached outputs by hard link when the filesystem cannot clone them.
    ///
    /// Filesystems with clone support (APFS, Btrfs, XFS with reflink, ZFS) are
    /// unaffected: they clone either way. On other Unix filesystems, ext4 above
    /// all, this is the difference between a restore that writes nothing and
    /// one that copies every cached byte. On Windows, tuist_cargo_cache copies whatever it
    /// cannot clone. A hard-linked output is the store's object, so it is
    /// read-only. tuist_cargo_cache unlinks it before a compiler rewrites it, but Cargo run
    /// without tuist_cargo_cache in the same target directory can fail with
    /// `output file ... is not writeable`. Disable to give every restored
    /// output a file of its own.
    #[usage(env = "TUIST_CARGO_CACHE_RESTORE_HARDLINK", default = true)]
    restore_hardlink: bool,
    /// Cache executions of build scripts using Cargo's freshness inputs.
    ///
    /// This may also be set in workspace `.tuist_cargo_cache.toml`; the environment
    /// variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", default = true)]
    build_script_execution: bool,
    /// Record a per-compilation event stream for `tuist_cargo_cache tui` to watch.
    ///
    /// `tuist_cargo_cache explain --last` and `tuist_cargo_cache analyze` also read it back. A build run
    /// with this off is not recorded, so those commands report the newest build
    /// that was, or find none. Cache entries and other build state are
    /// still stored.
    #[usage(env = "TUIST_CARGO_CACHE_EVENTS", default = true)]
    events: bool,
    /// Cache C and C++ compilations run by build scripts and by `tuist_cargo_cache exec`.
    ///
    /// With this off, `tuist_cargo_cache exec` runs its command uncached. This may also be
    /// set in workspace `.tuist_cargo_cache.toml`; the environment variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_CC", default = true)]
    cc: bool,
    /// Store C objects that embed absolute paths under checkout-specific keys.
    ///
    /// Disable for disposable worktrees to avoid storing objects that cannot be
    /// reused at another path. Existing entries may still be restored.
    #[usage(env = "TUIST_CARGO_CACHE_CC_STORE_PATH_SPECIFIC", default = true)]
    cc_store_path_specific: bool,
    /// Set `ZERO_AR_DATE` for build scripts so native archives omit a timestamp.
    ///
    /// Apple's `ar` and `ranlib` read the variable; other archivers ignore it.
    /// Without it, those tools stamp the time into every archive they write,
    /// such as the ones CMake-based dependencies build with `/usr/bin/ar` on
    /// macOS. An archive rebuilt from unchanged objects then gets a new digest,
    /// and every cached action downstream of it misses.
    ///
    /// `auto` normalizes every build whose Cargo `PROFILE` is not `release`.
    /// Cargo reports `release` for `--release` builds and for every profile
    /// that inherits from `release`, such as `bench`, so `auto` leaves their
    /// archives byte-for-byte as the host toolchain made them.
    /// `always` covers those too, and `off` leaves the toolchain alone. A
    /// `ZERO_AR_DATE` you set yourself always wins.
    ///
    /// tuist_cargo_cache sets the variable through the build-script wrapper that
    /// `build_script_execution` installs, so this has no effect on build
    /// scripts compiled while that setting is off.
    #[usage(
        env = "TUIST_CARGO_CACHE_AR_DETERMINISM",
        default = "auto",
        choices("auto", "always", "off")
    )]
    ar_determinism: String,
    /// Forward rustc's diagnostics and artifact notifications to Cargo as they arrive.
    ///
    /// Cargo can then start a dependent against a crate's metadata while that
    /// crate's code generation continues. Disable to hold the compiler's output
    /// until tuist_cargo_cache has stored the result, which is useful when diagnosing the
    /// compiler shim itself.
    #[usage(
        env = "TUIST_CARGO_CACHE_FORWARD_COMPILER_NOTIFICATIONS",
        default = true
    )]
    forward_compiler_notifications: bool,
    /// Style of the savings line printed after a build.
    ///
    /// `quips` draws the line from a pool of dry one-liners, `plain` reports
    /// the same figures without a quip, and `off` prints nothing but keeps
    /// the totals.
    #[usage(
        env = "TUIST_CARGO_CACHE_SAVINGS",
        default = "quips",
        choices("quips", "plain", "off")
    )]
    savings: String,
    /// Cache natively linked test binaries, executables, and proc macros.
    ///
    /// On Linux, `cdylib`s are cached too. Only links for the host qualify: a
    /// binary, test, or `cdylib` built with an explicit `--target`, including
    /// one set by `build.target`, still links normally even when it names the
    /// host triple. The built-in WebAssembly targets are cached regardless of
    /// this setting. On macOS this also passes ld64 `-oso_prefix` so a
    /// debug-info link's debug map stops naming this checkout, which is what
    /// lets the link cache. Supported on Linux, macOS, and Windows; a link tuist_cargo_cache
    /// cannot describe exactly still links normally.
    #[usage(
        key = "cache_links",
        env = "TUIST_CARGO_CACHE_CACHE_LINKS",
        default = true,
        scope = "env"
    )]
    cache_links: bool,
    /// Append the full reason for every bypassed compilation to this path.
    #[usage(
        key = "bypass_log",
        env = "TUIST_CARGO_CACHE_BYPASS_LOG",
        scope = "env"
    )]
    _bypass_log: Option<PathBuf>,
    /// Log filter, such as `debug` or `tuist_cargo_cache=trace`.
    ///
    /// It covers every log the tuist_cargo_cache process emits: its own and those of the
    /// libraries it builds on. The default keeps the pty library behind the
    /// inline build view quiet, because tuist_cargo_cache falls back to plain Cargo when that
    /// view cannot start.
    #[usage(
        key = "log",
        env = "TUIST_CARGO_CACHE_LOG",
        default = "info,portable_pty=off",
        scope = "env"
    )]
    _log: String,
    #[usage(flatten)]
    remote: RawRemote,
    #[usage(flatten)]
    http: RawHttp,
    #[usage(flatten)]
    gc: RawGc,
    #[usage(flatten)]
    target: RawTarget,
    #[usage(flatten)]
    scheduler: RawScheduler,
    #[usage(flatten)]
    linker: RawLinker,
}

#[derive(Debug, usage_rs::Config)]
#[usage(prefix = "linker")]
struct RawLinker {
    /// Linker used when the active Cargo profile has no matching selection.
    ///
    /// This may also be set in workspace `.tuist_cargo_cache.toml`, but not to a `path:`
    /// selector; `TUIST_CARGO_CACHE_LINKER` wins.
    #[usage(default = "system")]
    default: String,
    /// Linkers selected by Cargo profile and target triple.
    ///
    /// This may also be set in workspace `.tuist_cargo_cache.toml`, where no entry may be a
    /// `path:` selector. Workspace entries replace the global file's entries
    /// for the same profile and target, and `TUIST_CARGO_CACHE_LINKER` wins over both.
    profiles: Option<BTreeMap<String, BTreeMap<String, String>>>,
    /// Override the configured linker for this invocation.
    #[usage(key = "selection", env = "TUIST_CARGO_CACHE_LINKER", scope = "env")]
    _selection: Option<String>,
}

#[derive(Debug, usage_rs::Config)]
#[usage(prefix = "scheduler")]
struct RawScheduler {
    /// Coordinate real compilations machine-wide through a permit pool.
    ///
    /// Cache hits never take a permit. A compilation that runs the compiler
    /// takes one first, so concurrent tuist_cargo_cache builds on one machine share one pool.
    /// This may also be set in workspace `.tuist_cargo_cache.toml`; the environment
    /// variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_SCHEDULER", default = true)]
    enabled: bool,
    /// Number of compile permits in the machine-wide pool.
    ///
    /// A typical compilation takes one permit; links and memory-heavy crates
    /// can take more. This may also be set in workspace `.tuist_cargo_cache.toml`; the
    /// environment variable wins.
    #[usage(
        env = "TUIST_CARGO_CACHE_SCHEDULER_CPUS",
        default_note = "logical CPUs"
    )]
    cpus: Option<i64>,
    /// Permits withheld from `scheduler.cpus` to leave CPUs for other work.
    ///
    /// At least one permit always remains. This may also be set in workspace
    /// `.tuist_cargo_cache.toml`; the environment variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_SCHEDULER_RESERVE_CPUS", default = 0)]
    reserve_cpus: i64,
    /// Memory budget the permits divide, such as `24GiB`, or `"none"`.
    ///
    /// Each permit stands for an equal share of it. `"none"` leaves plain CPU
    /// permits and also turns off `scheduler.pressure` and `scheduler.suspend`.
    /// This may also be set in workspace `.tuist_cargo_cache.toml`; the environment
    /// variable wins.
    #[usage(
        env = "TUIST_CARGO_CACHE_SCHEDULER_MEMORY",
        default_note = "85% of physical memory, or of the Linux cgroup memory limit if lower"
    )]
    memory: Option<String>,
    /// Priority of this build's compilations in the machine-wide permit pool.
    ///
    /// While a normal-priority build is waiting, a `low` build leaves about a
    /// quarter of the pool free for it. This may also be set in workspace
    /// `.tuist_cargo_cache.toml`; the environment variable wins.
    #[usage(
        env = "TUIST_CARGO_CACHE_SCHEDULER_PRIORITY",
        default = "normal",
        choices("normal", "low")
    )]
    priority: String,
    /// Delay additional compilations while memory is under pressure.
    ///
    /// Works on Linux and macOS. Has no effect when `scheduler.memory` is
    /// `"none"`. This may also be set in workspace `.tuist_cargo_cache.toml`; the environment
    /// variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_SCHEDULER_PRESSURE", default = true)]
    pressure: bool,
    /// Experimentally suspend Linux compiler process trees under memory pressure.
    ///
    /// Takes effect only with `scheduler.cgroup_root` set, `scheduler.pressure`
    /// on, and `scheduler.memory` not `"none"`. When suspension cannot start,
    /// tuist_cargo_cache warns once per build and only delays new compilations.
    #[usage(env = "TUIST_CARGO_CACHE_SCHEDULER_SUSPEND", default = false)]
    suspend: bool,
    /// Absolute path to a delegated cgroup v2 directory for `scheduler.suspend`.
    ///
    /// tuist_cargo_cache must be able to write to it. tuist_cargo_cache uses it only on Linux, and only
    /// while `scheduler.suspend` is in effect.
    #[usage(env = "TUIST_CARGO_CACHE_SCHEDULER_CGROUP_ROOT")]
    cgroup_root: Option<PathBuf>,
    /// Run `cargo test` binaries under the same permit pool.
    ///
    /// This may also be set in workspace `.tuist_cargo_cache.toml`; the environment
    /// variable wins.
    #[usage(env = "TUIST_CARGO_CACHE_SCHEDULER_TESTS", default = false)]
    tests: bool,
}

#[derive(Debug, usage_rs::Config)]
#[usage(prefix = "remote")]
struct RawRemote {
    /// Remote cache URL; its scheme selects the backend.
    ///
    /// Use `https://` for an tuist_cargo_cache cache server or `s3://bucket[/prefix]` for an
    /// S3-compatible bucket. tuist_cargo_cache refuses the `remote.s3_*` settings with any
    /// other scheme.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_URL", ty = "url")]
    url: Option<String>,
    /// Namespace that isolates one project's cache, such as `acme/backend`.
    ///
    /// Required when `remote.url` is set.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_NAMESPACE")]
    namespace: Option<String>,
    /// Bearer token for a cache server.
    ///
    /// An `s3://` remote refuses it. Takes precedence over `remote.token_file`
    /// and `remote.oidc_audience`.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_TOKEN")]
    token: Option<String>,
    /// File containing a bearer token for a cache server.
    ///
    /// An `s3://` remote refuses it. `remote.token` takes precedence over it,
    /// and it takes precedence over `remote.oidc_audience`.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_TOKEN_FILE")]
    token_file: Option<PathBuf>,
    /// GitHub Actions OIDC token audience for authenticating to a cache server.
    ///
    /// GitHub Actions only; the job needs `id-token: write`. An `s3://` remote
    /// refuses it.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_OIDC_AUDIENCE")]
    oidc_audience: Option<String>,
    /// Remote access mode.
    ///
    /// Only trusted CI (a push to a protected branch on GitHub Actions or GitLab
    /// CI) may write. Everywhere else, including a local shell, `read-write`
    /// acts as `read-only` and `write-only` disables the remote.
    #[usage(
        env = "TUIST_CARGO_CACHE_REMOTE_MODE",
        default = "read-write",
        choices("read-write", "read-only", "write-only")
    )]
    mode: String,
    /// S3 endpoint for a service other than AWS, such as MinIO or R2.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_S3_ENDPOINT", ty = "url")]
    s3_endpoint: Option<String>,
    /// S3 region; Cloudflare R2 uses `auto`.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_S3_REGION")]
    s3_region: Option<String>,
    /// Address S3 buckets in the path rather than the host.
    #[usage(env = "TUIST_CARGO_CACHE_REMOTE_S3_FORCE_PATH_STYLE")]
    s3_force_path_style: Option<bool>,
    /// How to handle a bucket that does not implement S3 conditional writes.
    ///
    /// Conditional writes keep concurrent updates to the action manifest, which
    /// prefetch reads, from overwriting each other. `auto` uses them until the
    /// bucket rejects them and then writes without them; `required` fails
    /// against such a bucket; and `off` never sends conditional headers.
    #[usage(
        env = "TUIST_CARGO_CACHE_REMOTE_S3_CONDITIONAL_WRITES",
        default = "auto",
        choices("auto", "required", "off")
    )]
    s3_conditional_writes: String,
}

#[derive(Debug, usage_rs::Config)]
#[usage(prefix = "target")]
struct RawTarget {
    /// Let tuist_cargo_cache place eligible target directories under the managed target root.
    #[usage(env = "TUIST_CARGO_CACHE_TARGET_VIEWS", default = true)]
    views: bool,
    /// Give `cargo check` and `cargo clippy` their own directory in the
    /// managed target.
    ///
    /// They then run beside a build instead of waiting for Cargo's target lock.
    #[usage(env = "TUIST_CARGO_CACHE_TARGET_LANES", default = true)]
    lanes: bool,
    /// Copy registry build units from another checkout's managed target into
    /// a profile this checkout has not built yet (Cargo 1.100 or later).
    #[usage(env = "TUIST_CARGO_CACHE_TARGET_SEED", default = true)]
    seed: bool,
    /// Managed target root: the directory that holds managed targets.
    ///
    /// A relative path resolves under `cache_dir`. Changing it moves each
    /// checkout's managed target on its next build; across filesystems, tuist_cargo_cache
    /// removes the old outputs rather than copying them. NFS is unsupported for
    /// build outputs.
    #[usage(
        env = "TUIST_CARGO_CACHE_TARGET_ROOT",
        default_note = "`<cache_dir>/targets`"
    )]
    root: Option<PathBuf>,
    /// Size budget for managed targets, or `"none"`.
    ///
    /// Over budget, tuist_cargo_cache collects managed targets least recently used first and
    /// keeps the most recently used one.
    #[usage(
        env = "TUIST_CARGO_CACHE_TARGET_MAX_SIZE",
        default_note = "10% of the target disk, from 10 GiB to 100 GiB; shared budget when `gc.max_total_size` is set"
    )]
    max_size: Option<String>,
    /// Collect managed targets, and build units inside them, unused this long,
    /// or `"none"`.
    #[usage(
        env = "TUIST_CARGO_CACHE_TARGET_MAX_AGE",
        default = "30d",
        ty = "duration"
    )]
    max_age: String,
    /// Checkouts whose managed targets are never collected for age or size.
    ///
    /// An absolute path covers the checkouts under it; a relative one matches
    /// wherever it appears in a checkout's path. A leading `~` is your home
    /// directory. When `target.evict_first` also matches a checkout, the entry
    /// that reaches deeper into its path wins, and a tie keeps it. A kept
    /// target is still collected once its checkout is deleted.
    #[usage(env = "TUIST_CARGO_CACHE_TARGET_KEEP", parse = "list_by_comma")]
    keep: Option<Vec<String>>,
    /// Checkouts whose managed targets are collected first when over budget.
    ///
    /// Entries, such as `.claude/worktrees`, are matched like `target.keep`.
    #[usage(env = "TUIST_CARGO_CACHE_TARGET_EVICT_FIRST", parse = "list_by_comma")]
    evict_first: Option<Vec<String>>,
}

#[derive(Debug, usage_rs::Config)]
#[usage(prefix = "gc")]
struct RawGc {
    /// Sweep after a build when collection is due.
    #[usage(env = "TUIST_CARGO_CACHE_GC_AUTO", default = true)]
    auto: bool,
    /// Size budget for the action store.
    ///
    /// It also caps how much one build downloads from the remote cache. Unlike
    /// the other size budgets, it cannot be `"none"`.
    #[usage(
        env = "TUIST_CARGO_CACHE_GC_MAX_SIZE",
        default_note = "5% of the cache disk, from 5 GiB to 500 GiB; `gc.max_total_size` when set"
    )]
    max_size: Option<String>,
    /// Combined size target for the action store, managed targets, and
    /// incremental state, or `"none"`.
    ///
    /// A size such as `50GiB` counts logical bytes across the action store,
    /// managed targets, learned incremental state, and generated source trees.
    /// When set, it replaces the disk-scaled defaults of the component budgets;
    /// explicit component limits still apply. Active and protected state may
    /// exceed this target.
    #[usage(env = "TUIST_CARGO_CACHE_GC_MAX_TOTAL_SIZE")]
    max_total_size: Option<String>,
    /// Shared budget for learned incremental state and generated source trees,
    /// or `"none"`.
    ///
    /// Over budget, tuist_cargo_cache collects the incremental state of inactive checkouts
    /// least recently used first and keeps the most recently used checkout's.
    /// Generated source trees get whatever budget incremental state leaves.
    #[usage(
        env = "TUIST_CARGO_CACHE_GC_INCREMENTAL_MAX_SIZE",
        default_note = "5% of the cache disk, from 10 GiB to 100 GiB; shared budget when `gc.max_total_size` is set"
    )]
    incremental_max_size: Option<String>,
    /// Collect learned incremental state unused this long, or `"none"`.
    #[usage(
        env = "TUIST_CARGO_CACHE_GC_INCREMENTAL_MAX_AGE",
        default = "30d",
        ty = "duration"
    )]
    incremental_max_age: String,
    /// Free space to keep on the disks that hold the cache directory and
    /// managed targets, or `"none"`.
    ///
    /// Below it, sweeps run more often and collect private state, generated
    /// source trees, managed targets, and shared store objects past their
    /// budgets to free the shortfall. Active and most recently used state
    /// stays, so the disk can remain short.
    #[usage(
        env = "TUIST_CARGO_CACHE_GC_MIN_FREE_SIZE",
        default_note = "10% of each disk, from 5 GiB to 50 GiB"
    )]
    min_free_size: Option<String>,
    /// Minimum interval between automatic sweeps while the disks have room.
    ///
    /// While a disk is short of `gc.min_free_size`, the interval is capped at
    /// five minutes, so sweeps can run that often even when this is longer.
    #[usage(env = "TUIST_CARGO_CACHE_GC_INTERVAL", default = "1h", ty = "duration")]
    interval: String,
}

#[derive(Debug, usage_rs::Config)]
#[usage(prefix = "http")]
struct RawHttp {
    /// Connect timeout, and how long a remote cache request may wait for data.
    ///
    /// A response must begin within this time of its request starting, so an
    /// upload's whole body has to be sent within it. After that, the clock
    /// restarts whenever response bytes arrive: a long download keeps going
    /// while data flows and fails only after this long with none.
    /// `http.download_timeout` caps a whole blob download, retries included.
    /// Managed linker downloads use this setting only as their connect timeout.
    #[usage(
        env = "TUIST_CARGO_CACHE_HTTP_TIMEOUT",
        default = "30s",
        ty = "duration"
    )]
    timeout: String,
    /// Deadline for one blob download, retries and backoff included.
    ///
    /// It also caps each whole request tuist_cargo_cache makes to download a managed linker.
    #[usage(
        env = "TUIST_CARGO_CACHE_HTTP_DOWNLOAD_TIMEOUT",
        default = "10m",
        ty = "duration"
    )]
    download_timeout: String,
    /// Wall-clock time a build may lose to failed reads from a cache server.
    ///
    /// Once it is spent, the build stops reading from the remote and compiles
    /// instead. `0` keeps reading however long it takes. Has no effect on an
    /// `s3://` remote.
    #[usage(
        env = "TUIST_CARGO_CACHE_HTTP_READ_STALL_BUDGET",
        default = "90s",
        ty = "duration"
    )]
    read_stall_budget: String,
    /// How many times to retry a remote cache request after a transient failure.
    #[usage(env = "TUIST_CARGO_CACHE_HTTP_RETRIES", default = 3)]
    retries: i64,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub cache_dir: PathBuf,
    /// Persistent executable wrappers, separate from shared build artifacts.
    pub shims_dir: PathBuf,
    pub stats_report: Option<PathBuf>,
    pub verify: bool,
    pub verify_sample_rate: u8,
    /// Let Cargo compile workspace members incrementally, rather than forcing
    /// `CARGO_INCREMENTAL=0` for the whole build.
    pub incremental: bool,
    /// Seed private workspace incremental state from the first compilation; disabled by default.
    pub eager_incremental: bool,
    /// Share compilations that read `OUT_DIR` between checkouts.
    ///
    /// Enabled by default. When the source scan finds `OUT_DIR`, rustc receives
    /// a copy of the build-script output under the cache, in a directory named
    /// for its contents. Matching output trees give rustc the same path across
    /// checkouts, allowing a cache hit when the other inputs also match.
    /// Different output trees use different paths and cache keys. If the scan
    /// misses the reference or the output cannot be copied, rustc keeps Cargo's
    /// original `OUT_DIR`.
    ///
    /// Also remap generated source paths in Rust and C/C++ debug information.
    /// Disabling this preserves Cargo's original `OUT_DIR` and literal paths,
    /// so Rust compilations that read `OUT_DIR` remain checkout-specific.
    pub share_out_dir: bool,
    /// Restore cached outputs by hard link where the filesystem cannot clone
    /// them.
    ///
    /// Reflinks are always preferred: a cloned output is its own inode and
    /// behaves like a copy that happened to be cheap. A hard link is the store
    /// object itself, so it is read-only and every checkout holding one shares
    /// its modification time. That is a narrower guarantee, and on a
    /// filesystem without clone support it is the only alternative to writing
    /// every restored byte.
    pub restore_hardlink: bool,
    /// Remap the workspace root so rustc does not record the checkout a
    /// compilation ran in.
    ///
    /// Off by default. Cargo gives rustc the crate's own directory to work in,
    /// and rustc records it, so a workspace member rebuilt in a second checkout
    /// produces a different artifact even when everything it read was the same,
    /// and every crate above it rebuilds with it. Remapping the root removes
    /// that difference, at the cost of naming a placeholder wherever a source
    /// path is recorded: debug information, `file!()`, and panic locations.
    pub share_workspace_root: bool,
    /// Cache build-script execution when the script declares rerun inputs.
    pub build_script_execution: bool,
    /// Append a per-compilation event stream to the store, for `tuist_cargo_cache tui`,
    /// `tuist_cargo_cache explain --last`, and `tuist_cargo_cache analyze`.
    ///
    /// On by default: one small unbuffered append per accounted compilation,
    /// against a compilation or restore measured in milliseconds. Turn it off
    /// to keep the store free of build history.
    pub events: bool,
    /// Point build scripts at a caching `CC` and `CXX`.
    ///
    /// On by default: the shim never changes the compilation, and anything it
    /// cannot model exactly bypasses to the real compiler.
    pub cc: bool,
    /// Store path-specific C outputs for reuse at the same checkout path.
    pub cc_store_path_specific: bool,
    /// When to normalize native archive timestamps for build scripts.
    pub ar_determinism: String,
    /// Forward the compiler's diagnostics and artifact notifications as they
    /// arrive instead of after the result is stored.
    ///
    /// On by default. Cargo reads the metadata notification from rustc's
    /// standard error and starts dependents against the `.rmeta` right away,
    /// which the shim would otherwise delay until publication finished. The
    /// bytes are still captured for the cache entry and for verification.
    pub forward_compiler_notifications: bool,
    pub remote: RemoteSettings,
    pub http: HttpSettings,
    pub gc: GcSettings,
    pub target: TargetSettings,
    pub scheduler: SchedulerSettings,
    pub linker: LinkerSettings,
}

/// Linker selectors keyed first by Cargo profile, then by target triple.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkerSettings {
    pub default: String,
    pub profiles: BTreeMap<String, BTreeMap<String, String>>,
}

impl Default for LinkerSettings {
    fn default() -> Self {
        Self {
            default: "system".into(),
            profiles: BTreeMap::new(),
        }
    }
}

impl LinkerSettings {
    pub(crate) fn for_build(&self, profile: &str, target: Option<&str>) -> Option<String> {
        let selections = self.selections(profile)?;
        target
            .and_then(|target| selections.get(target))
            .or_else(|| selections.get("default"))
            .cloned()
    }

    /// The profile's selector table. Cargo 1.99's built-in `debug` profile
    /// inherits `dev`, so it uses the `dev` table unless it has its own.
    pub(crate) fn selections(&self, profile: &str) -> Option<&BTreeMap<String, String>> {
        self.profiles.get(profile).or_else(|| {
            (profile == "debug")
                .then(|| self.profiles.get("dev"))
                .flatten()
        })
    }
}

impl Config {
    /// A configuration with everything defaulted, for tests that care about one
    /// setting and should not have to spell out the rest.
    #[cfg(test)]
    pub fn for_test(cache_dir: &std::path::Path) -> Self {
        Self {
            cache_dir: cache_dir.to_path_buf(),
            shims_dir: cache_dir.join("shims"),
            stats_report: None,
            verify: false,
            verify_sample_rate: 0,
            incremental: false,
            eager_incremental: false,
            share_out_dir: false,
            restore_hardlink: true,
            share_workspace_root: false,
            build_script_execution: false,
            events: false,
            // Off like the rest: a test that says nothing about C compilation
            // should not have compiler shims installed underneath it.
            cc: false,
            cc_store_path_specific: true,
            ar_determinism: "auto".into(),
            forward_compiler_notifications: true,
            remote: Default::default(),
            http: Default::default(),
            gc: Default::default(),
            target: TargetSettings {
                views: true,
                lanes: true,
                seed: false,
                root: cache_dir.join("targets"),
            },
            scheduler: Default::default(),
            linker: Default::default(),
        }
    }
}

/// How real compilations draw from the machine-wide permit pool.
#[derive(Debug, Clone)]
pub struct SchedulerSettings {
    /// Whether compilations take permits at all.
    pub enabled: bool,
    /// Machine-wide concurrent compile permits.
    pub cpus: u64,
    /// Permits withheld from the configured CPU count.
    pub reserve_cpus: u64,
    /// Memory the permits divide; `None` leaves plain CPU permits.
    pub memory_bytes: Option<u64>,
    /// Priority of this build's compilations against other builds.
    pub priority: SchedulerPriority,
    /// Whether `cargo test` binaries take permits too.
    pub tests: bool,
    /// Gate new compilations on live memory pressure.
    pub pressure: bool,
    /// Opt in to Linux compiler supervision and suspension.
    pub suspend: bool,
    /// An explicitly delegated cgroup v2 directory.
    pub cgroup_root: Option<PathBuf>,
}

impl SchedulerSettings {
    /// Compile permits left after preserving capacity for interactive work.
    pub(crate) fn permits(&self) -> u64 {
        self.cpus.saturating_sub(self.reserve_cpus).max(1)
    }
}

/// The scheduling a hand-built `Config` gets: none.
///
/// Deliberately not the declared configuration default, which is enabled. A
/// `Config` assembled in code rather than resolved from the environment has
/// not been told where a machine-wide pool should live or how large the
/// machine is, and guessing would have tests and embedders contending over a
/// real pool they never asked for. Resolution always states every field.
impl Default for SchedulerSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            cpus: 1,
            reserve_cpus: 0,
            memory_bytes: None,
            priority: SchedulerPriority::Normal,
            tests: false,
            pressure: false,
            suspend: false,
            cgroup_root: None,
        }
    }
}

/// Whose compilations wait when the machine is contended.
///
/// `Low` is for builds nobody is sitting at, such as CI on a shared box or an
/// editor's background check. They leave a share of the permit pool free
/// whenever a normal-priority build is waiting for it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SchedulerPriority {
    #[default]
    Normal,
    Low,
}

impl SchedulerPriority {
    /// The spelling the configuration and the session environment use.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Low => "low",
        }
    }
}

impl std::str::FromStr for SchedulerPriority {
    type Err = eyre::Report;

    fn from_str(value: &str) -> Result<Self> {
        match value {
            "normal" => Ok(Self::Normal),
            "low" => Ok(Self::Low),
            other => Err(eyre::eyre!("priority must be normal or low, not {other:?}")),
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct RemoteSettings {
    pub url: Option<String>,
    pub namespace: Option<String>,
    pub token: Option<String>,
    pub token_file: Option<PathBuf>,
    pub oidc_audience: Option<String>,
    pub mode: RemoteCacheMode,
    pub s3_endpoint: Option<String>,
    pub s3_region: Option<String>,
    pub s3_force_path_style: Option<bool>,
    pub s3_conditional_writes: S3ConditionalWrites,
}

#[derive(Debug, Clone)]
pub struct HttpSettings {
    pub timeout: Duration,
    pub download_timeout: Duration,
    pub read_stall_budget: Duration,
    pub retries: i64,
}

/// Where build outputs are written, and whether tuist_cargo_cache places them.
#[derive(Debug, Clone)]
pub struct TargetSettings {
    pub views: bool,
    pub lanes: bool,
    pub seed: bool,
    pub root: PathBuf,
}

/// How the store is kept inside its budget.
#[derive(Debug, Clone)]
pub struct GcSettings {
    pub auto: bool,
    pub max_bytes: u64,
    pub interval: Duration,
}

#[derive(Debug, Clone)]
pub(crate) struct RetentionSettings {
    pub target_max_bytes: Option<u64>,
    pub target_max_age: Option<Duration>,
    pub incremental_max_bytes: Option<u64>,
    pub incremental_max_age: Option<Duration>,
    pub max_total_bytes: Option<u64>,
    /// Checkouts whose targets `target.keep` and `target.evict_first` set apart.
    pub target_precedence: crate::target::Precedence,
    /// Free space below which a sweep collects past the budgets above;
    /// `None` never does.
    pub min_free: Option<MinFree>,
}

/// The free space `gc.min_free_size` asks a sweep to keep.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MinFree {
    /// A share of whichever disk is being measured. The cache and managed
    /// targets can be on different disks, so this is resolved per disk.
    ShareOfDisk,
    Bytes(u64),
}

impl MinFree {
    pub(crate) fn bytes(self, disk_total_bytes: u64) -> u64 {
        match self {
            Self::ShareOfDisk => MIN_FREE.resolve(Some(disk_total_bytes)),
            Self::Bytes(bytes) => bytes,
        }
    }
}

/// The declared default of `learned_incremental_max_size`.
///
/// A crate's incremental state is roughly proportional to the crate, not to
/// how often it is edited, because rustc discards superseded sessions itself.
/// A large workspace binary with line tables keeps a few GiB, so the budget is
/// generous enough that ordinary crates never hit it; discarding state on
/// every edit would silently turn the edit loop back into full recompilation.
pub(crate) const DEFAULT_LEARNED_INCREMENTAL_MAX_SIZE: u64 = 8 * 1024 * 1024 * 1024;

/// The declared default of `events_max_size`.
///
/// The cap exists so the TUI can read a session's tail without reading a
/// build-sized file first. A row carrying key details runs to several KiB, so a
/// large workspace reaches this partway through a build and keeps only the part
/// that fit: enough for the TUI, and raisable for anyone diagnosing a miss
/// with `tuist_cargo_cache explain`.
pub(crate) const DEFAULT_EVENTS_MAX_SIZE: u64 = 16 * 1024 * 1024;

/// Settings only the command line consumes.
///
/// `Config` is a public struct callers can construct, so a knob the binary
/// alone reads does not belong on it: adding a field there changes an API this
/// crate does not mean to offer. release-plz no longer runs cargo-semver-checks
/// over `tuist_cargo_cache` (see `release-plz.toml`), so nothing enforces this; keep the
/// knob off `Config` anyway.
#[derive(Debug, Clone)]
pub(crate) struct CliSettings {
    pub retention: RetentionSettings,
    pub savings: SavingsStyle,
    pub summary: SummaryStyle,
    pub pretty_inspect: bool,
    pub plain_output: bool,
    /// Whether a churning crate may compile with its own incremental state.
    pub learned_incremental: bool,
    /// How much of that state one crate may keep, in bytes; `None` is no limit.
    pub learned_incremental_max_size: Option<u64>,
    /// Whether natively linked programs may be cached.
    pub cache_links: bool,
    /// How many bytes of per-compilation rows one build may record; `None` is
    /// no limit.
    pub events_max_size: Option<u64>,
}

/// Matches the declared defaults: a derived `Default` would silence the savings
/// line, which is the opposite of what an unconfigured machine should get.
impl Default for CliSettings {
    fn default() -> Self {
        Self {
            retention: RetentionSettings::default(),
            savings: SavingsStyle::default(),
            summary: SummaryStyle::default(),
            pretty_inspect: false,
            plain_output: false,
            learned_incremental: true,
            learned_incremental_max_size: Some(DEFAULT_LEARNED_INCREMENTAL_MAX_SIZE),
            cache_links: true,
            events_max_size: Some(DEFAULT_EVENTS_MAX_SIZE),
        }
    }
}

/// How much of the per-build cache summary is printed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum SummaryStyle {
    #[default]
    Auto,
    Off,
    Short,
    Ci,
    Full,
}

impl SummaryStyle {
    /// Select the environment's default report while preserving explicit styles.
    pub(crate) fn resolve(self, ci: bool) -> Self {
        match self {
            Self::Auto if ci => Self::Ci,
            Self::Auto => Self::Short,
            style => style,
        }
    }
}

impl std::str::FromStr for SummaryStyle {
    type Err = eyre::Report;

    fn from_str(value: &str) -> Result<Self> {
        match value {
            "auto" => Ok(Self::Auto),
            "off" => Ok(Self::Off),
            "short" => Ok(Self::Short),
            "ci" => Ok(Self::Ci),
            "full" => Ok(Self::Full),
            other => Err(eyre::eyre!(
                "summary must be auto, off, short, ci, or full, not {other:?}"
            )),
        }
    }
}

/// How the line about accumulated savings reads.
///
/// The quips are the product's voice and the default; `plain` is the same
/// facts in the register of the `tuist_cargo_cache[cache]:` and `tuist_cargo_cache[gc]:` lines beside them, for
/// people who want their build logs to keep a straight face; `off` keeps the
/// totals without printing anything.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum SavingsStyle {
    #[default]
    Quips,
    Plain,
    Off,
}

impl std::str::FromStr for SavingsStyle {
    type Err = eyre::Report;

    fn from_str(value: &str) -> Result<Self> {
        match value {
            "quips" => Ok(Self::Quips),
            "plain" => Ok(Self::Plain),
            "off" => Ok(Self::Off),
            other => Err(eyre::eyre!(
                "savings must be quips, plain, or off, not {other:?}"
            )),
        }
    }
}

/// The retention a run gets when nobody resolved configuration for it.
///
/// These are the unmeasured fallbacks rather than the disk-scaled budgets: a
/// `Default` cannot probe a disk it has not been told about. Collection still
/// happens, which is the property that matters: a default that pruned nothing
/// would make every unconfigured path a leak.
impl Default for RetentionSettings {
    fn default() -> Self {
        Self {
            target_max_bytes: Some(TARGET_BUDGET.fallback),
            target_max_age: Some(DEFAULT_TARGET_MAX_AGE),
            incremental_max_bytes: Some(INCREMENTAL_BUDGET.fallback),
            incremental_max_age: Some(DEFAULT_TARGET_MAX_AGE),
            max_total_bytes: None,
            target_precedence: crate::target::Precedence::default(),
            // Off, unlike the configured default: whether a disk is short
            // depends on the machine a test happens to run on.
            min_free: None,
        }
    }
}

impl Default for GcSettings {
    fn default() -> Self {
        Self {
            auto: true,
            max_bytes: STORE_BUDGET.fallback,
            interval: DEFAULT_GC_INTERVAL,
        }
    }
}

impl Default for HttpSettings {
    fn default() -> Self {
        Self {
            timeout: DEFAULT_HTTP_TIMEOUT,
            download_timeout: DEFAULT_HTTP_DOWNLOAD_TIMEOUT,
            read_stall_budget: DEFAULT_HTTP_READ_STALL_BUDGET,
            retries: DEFAULT_HTTP_RETRIES,
        }
    }
}

impl Config {
    /// Load configuration for this machine.
    pub fn load() -> Result<Self> {
        Self::load_for_cli().map(|(config, _)| config)
    }

    pub(crate) fn load_for_tuist() -> Result<(Self, CliSettings)> {
        Self::from_layers_for_cli(&EnvLayer::from_process(), None)
    }

    pub(crate) fn load_for_cli() -> Result<(Self, CliSettings)> {
        let env = EnvLayer::from_process();
        let file = config_file_path().map(|path| FileLayer::at(path, FileScope::Global));
        Self::from_layers_for_cli(&env, file.as_ref())
            .map_err(|error| with_repair_hints(error, &env, file.as_ref()))
    }

    fn from_layers_for_cli(
        env: &EnvLayer,
        file: Option<&FileLayer>,
    ) -> Result<(Self, CliSettings)> {
        Self::from_layers_measuring(
            env,
            file,
            crate::util::disk_total_bytes,
            crate::util::memory_total_bytes,
        )
    }

    fn from_layers_measuring(
        env: &EnvLayer,
        file: Option<&FileLayer>,
        measure_disk: impl Fn(&Path) -> Option<u64>,
        measure_memory: impl Fn() -> Option<u64>,
    ) -> Result<(Self, CliSettings)> {
        let mut layers = Layers::new().then(env);
        if let Some(file) = file {
            layers = layers.then(file);
        }
        let resolved = usage_config::resolve(RawConfig::SETTINGS_REGISTRY, layers)?;
        if !resolved.warnings.is_empty() {
            let problems = resolved
                .warnings
                .iter()
                .map(|warning| match &warning.origin {
                    Some(origin) => format!("{} ({})", warning.message, origin.describe()),
                    None => warning.message.clone(),
                })
                .collect::<Vec<_>>()
                .join("\n");
            bail!("invalid configuration:\n{problems}");
        }
        let raw = RawConfig::read(&resolved)?;
        Self::from_raw_measuring(raw, measure_disk, measure_memory)
    }

    /// Resolve settings, measuring the machine with the given probes.
    ///
    /// The probes are parameters so tests can state a disk or memory size
    /// rather than asserting against whatever machine happens to run them.
    fn from_raw_measuring(
        raw: RawConfig,
        measure_disk: impl Fn(&Path) -> Option<u64>,
        measure_memory: impl Fn() -> Option<u64>,
    ) -> Result<(Self, CliSettings)> {
        let cache_dir = raw.cache_dir.or_else(default_cache_dir).ok_or_else(|| {
            eyre::eyre!(
                "could not determine a cache directory; set TUIST_CARGO_CACHE_DIR or `tuist_cargo_cache settings set cache_dir <path>`"
            )
        })?;
        let shims_dir = match raw.shims_dir {
            Some(directory) if directory.is_absolute() => directory,
            Some(directory) => {
                let mut relative = PathBuf::new();
                for component in directory.components() {
                    match component {
                        Component::Normal(part) => relative.push(part),
                        Component::CurDir => (),
                        Component::ParentDir if relative.pop() => (),
                        _ => {
                            return Err(eyre::eyre!(
                                "relative paths must stay beneath cache_dir; \
                                 use an absolute path for a directory outside the cache"
                            )
                            .wrap_err(Invalid("shims_dir")));
                        }
                    }
                }
                if relative.as_os_str().is_empty() {
                    return Err(eyre::eyre!(
                        "relative paths must name a directory beneath cache_dir"
                    )
                    .wrap_err(Invalid("shims_dir")));
                }
                cache_dir.join(relative)
            }
            None => cache_dir.join("shims"),
        };
        let target_root = match raw.target.root {
            Some(root) if root.is_absolute() => root,
            Some(root) => cache_dir.join(root),
            None => cache_dir.join("targets"),
        };
        let store_budget = raw
            .gc
            .max_size
            .as_deref()
            .map(parse_store_budget)
            .transpose()
            .wrap_err(Invalid("gc.max_size"))?;
        let target_budget = raw
            .target
            .max_size
            .as_deref()
            .map(parse_optional_byte_size)
            .transpose()
            .wrap_err(Invalid("target.max_size"))?;
        let incremental_budget = raw
            .gc
            .incremental_max_size
            .as_deref()
            .map(parse_optional_byte_size)
            .transpose()
            .wrap_err(Invalid("gc.incremental_max_size"))?;
        let total_budget = raw
            .gc
            .max_total_size
            .as_deref()
            .map(parse_optional_byte_size)
            .transpose()
            .wrap_err(Invalid("gc.max_total_size"))?
            .flatten();
        // A combined budget replaces only implicit component caps. Explicit
        // limits (including "none") still win; no disk scaling is needed in
        // this mode, even when targets live on another volume.
        let store_disk = (total_budget.is_none()
            && (store_budget.is_none() || incremental_budget.is_none()))
        .then(|| measure_disk(&cache_dir))
        .flatten();
        let target_disk = (total_budget.is_none() && target_budget.is_none())
            .then(|| measure_disk(&target_root))
            .flatten();
        let retention = RetentionSettings {
            target_max_bytes: target_budget.unwrap_or_else(|| {
                total_budget
                    .is_none()
                    .then(|| TARGET_BUDGET.resolve(target_disk))
            }),
            target_max_age: parse_optional_duration(&raw.target.max_age)
                .wrap_err(Invalid("target.max_age"))?,
            incremental_max_bytes: incremental_budget.unwrap_or_else(|| {
                total_budget
                    .is_none()
                    .then(|| INCREMENTAL_BUDGET.resolve(store_disk))
            }),
            incremental_max_age: parse_optional_duration(&raw.gc.incremental_max_age)
                .wrap_err(Invalid("gc.incremental_max_age"))?,
            max_total_bytes: total_budget,
            target_precedence: crate::target::Precedence {
                keep: checkout_patterns(raw.target.keep.as_deref(), dirs::home_dir())
                    .wrap_err(Invalid("target.keep"))?,
                evict_first: checkout_patterns(raw.target.evict_first.as_deref(), dirs::home_dir())
                    .wrap_err(Invalid("target.evict_first"))?,
            },
            min_free: match raw.gc.min_free_size.as_deref() {
                None => Some(MinFree::ShareOfDisk),
                Some(value) => parse_optional_byte_size(value)
                    .wrap_err(Invalid("gc.min_free_size"))?
                    .map(MinFree::Bytes),
            },
        };
        let mode = raw.remote.mode.parse().wrap_err(Invalid("remote.mode"))?;
        let s3_conditional_writes = raw
            .remote
            .s3_conditional_writes
            .parse()
            .wrap_err(Invalid("remote.s3_conditional_writes"))?;
        let http = HttpSettings {
            timeout: parse_duration(&raw.http.timeout).wrap_err(Invalid("http.timeout"))?,
            download_timeout: parse_duration(&raw.http.download_timeout)
                .wrap_err(Invalid("http.download_timeout"))?,
            read_stall_budget: parse_duration(&raw.http.read_stall_budget)
                .wrap_err(Invalid("http.read_stall_budget"))?,
            retries: raw.http.retries,
        };
        let gc = GcSettings {
            auto: raw.gc.auto,
            max_bytes: store_budget
                .or(total_budget)
                .unwrap_or_else(|| STORE_BUDGET.resolve(store_disk)),
            interval: parse_duration(&raw.gc.interval).wrap_err(Invalid("gc.interval"))?,
        };
        let target = TargetSettings {
            views: raw.target.views,
            lanes: raw.target.lanes,
            seed: raw.target.seed,
            root: target_root,
        };
        let scheduler_cpus = match raw.scheduler.cpus {
            Some(cpus) => u64::try_from(cpus)
                .ok()
                .filter(|cpus| *cpus > 0)
                .ok_or_else(|| {
                    eyre::eyre!("must be a positive count").wrap_err(Invalid("scheduler.cpus"))
                })?,
            None => std::thread::available_parallelism().map_or(1, |cpus| cpus.get() as u64),
        };
        let scheduler_reserve_cpus = u64::try_from(raw.scheduler.reserve_cpus).map_err(|_| {
            eyre::eyre!("must be a non-negative count").wrap_err(Invalid("scheduler.reserve_cpus"))
        })?;
        let scheduler_memory = match raw.scheduler.memory.as_deref() {
            Some(value) => parse_optional_byte_size(value).wrap_err(Invalid("scheduler.memory"))?,
            // Measured only when the scheduler would use the answer, like the
            // disk budgets above.
            None => Some(
                raw.scheduler
                    .enabled
                    .then(&measure_memory)
                    .flatten()
                    .map_or(SCHEDULER_MEMORY_FALLBACK, |total| {
                        total / 100 * SCHEDULER_MEMORY_PERCENT
                    }),
            ),
        };
        let scheduler = SchedulerSettings {
            enabled: raw.scheduler.enabled,
            cpus: scheduler_cpus,
            reserve_cpus: scheduler_reserve_cpus,
            memory_bytes: scheduler_memory,
            priority: raw
                .scheduler
                .priority
                .parse()
                .wrap_err(Invalid("scheduler.priority"))?,
            tests: raw.scheduler.tests,
            pressure: raw.scheduler.pressure,
            suspend: raw.scheduler.suspend,
            cgroup_root: raw.scheduler.cgroup_root,
        };
        let config = Self {
            cache_dir,
            shims_dir,
            gc,
            target,
            scheduler,
            linker: LinkerSettings {
                default: raw.linker.default,
                profiles: raw.linker.profiles.unwrap_or_default(),
            },
            stats_report: raw.stats_report,
            verify: raw.verify,
            verify_sample_rate: u8::try_from(raw.verify_sample_rate)
                .ok()
                .filter(|rate| *rate <= 100)
                .ok_or_else(|| {
                    eyre::eyre!("expected 0–100").wrap_err(Invalid("verify_sample_rate"))
                })?,
            incremental: raw.incremental,
            eager_incremental: raw.eager_incremental,
            share_out_dir: raw.share_out_dir,
            restore_hardlink: raw.restore_hardlink,
            share_workspace_root: raw.share_workspace_root,
            build_script_execution: raw.build_script_execution,
            events: raw.events,
            cc: raw.cc,
            cc_store_path_specific: raw.cc_store_path_specific,
            ar_determinism: raw.ar_determinism,
            forward_compiler_notifications: raw.forward_compiler_notifications,
            remote: RemoteSettings {
                url: raw.remote.url,
                namespace: raw.remote.namespace,
                token: raw.remote.token,
                token_file: raw.remote.token_file,
                oidc_audience: raw.remote.oidc_audience,
                mode,
                s3_endpoint: raw.remote.s3_endpoint,
                s3_region: raw.remote.s3_region,
                s3_force_path_style: raw.remote.s3_force_path_style,
                s3_conditional_writes,
            },
            http,
        };
        Ok((
            config,
            CliSettings {
                retention,
                savings: raw.savings.parse().wrap_err(Invalid("savings"))?,
                summary: raw.summary.parse().wrap_err(Invalid("summary"))?,
                pretty_inspect: raw.pretty_inspect,
                plain_output: raw.display == "plain",
                learned_incremental: raw._learned_incremental,
                learned_incremental_max_size: raw
                    .learned_incremental_max_size
                    .as_deref()
                    .map(parse_optional_byte_size)
                    .transpose()
                    .wrap_err(Invalid("learned_incremental_max_size"))?
                    .unwrap_or(Some(
                        total_budget.unwrap_or(DEFAULT_LEARNED_INCREMENTAL_MAX_SIZE),
                    )),
                cache_links: raw.cache_links,
                events_max_size: parse_optional_byte_size(&raw.events_max_size)
                    .wrap_err(Invalid("events_max_size"))?,
            },
        ))
    }

    /// Apply the deliberately small, safe policy surface from `.tuist_cargo_cache.toml` at
    /// the resolved Cargo workspace root.
    pub fn apply_workspace_policy(&mut self, workspace_root: &Path) -> Result<()> {
        if std::env::var_os("TUIST_CARGO_NATIVE").is_some() {
            return Ok(());
        }
        self.apply_workspace_policy_with(workspace_root, |name| std::env::var_os(name).is_some())
    }

    fn apply_workspace_policy_with(
        &mut self,
        workspace_root: &Path,
        environment_contains: impl Fn(&str) -> bool,
    ) -> Result<()> {
        let path = workspace_root.join(".tuist_cargo_cache.toml");
        let contents = match std::fs::read_to_string(&path) {
            Ok(contents) => contents,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => {
                return Err(error).wrap_err_with(|| format!("failed to read {}", path.display()));
            }
        };
        let document = contents
            .parse::<toml_edit::DocumentMut>()
            .wrap_err_with(|| format!("failed to parse {}", path.display()))?;

        for (key, value) in document.iter() {
            if key == "linker" {
                if environment_contains("TUIST_CARGO_CACHE_LINKER") {
                    continue;
                }
                let table = value
                    .as_table()
                    .ok_or_else(|| eyre::eyre!("{}.linker must be a table", path.display()))?;
                for (linker_key, value) in table.iter() {
                    match linker_key {
                        "default" => {
                            let selection = value.as_str().ok_or_else(|| {
                                eyre::eyre!("{}.linker.default must be a string", path.display())
                            })?;
                            crate::managed_linker::validate_workspace_selector(selection)
                                .wrap_err_with(|| {
                                    format!("invalid {}.linker.default", path.display())
                                })?;
                            self.linker.default = selection.to_owned();
                        }
                        "profiles" => {
                            for (profile, selections) in workspace_linker_profiles(&path, value)? {
                                self.linker
                                    .profiles
                                    .entry(profile)
                                    .or_default()
                                    .extend(selections);
                            }
                        }
                        _ => bail!(
                            "{} contains unsupported workspace setting \"linker.{linker_key}\"; only linker.default and linker.profiles are allowed",
                            path.display()
                        ),
                    }
                }
                continue;
            }
            if key == "scheduler" {
                let table = value
                    .as_table()
                    .ok_or_else(|| eyre::eyre!("{}.scheduler must be a table", path.display()))?;
                for (scheduler_key, value) in table.iter() {
                    let setting = format!("scheduler.{scheduler_key}");
                    match scheduler_key {
                        "enabled" if !environment_contains("TUIST_CARGO_CACHE_SCHEDULER") => {
                            self.scheduler.enabled = workspace_bool(&path, &setting, value)?;
                        }
                        "cpus" if !environment_contains("TUIST_CARGO_CACHE_SCHEDULER_CPUS") => {
                            self.scheduler.cpus = workspace_count(&path, &setting, value, false)?;
                        }
                        "reserve_cpus"
                            if !environment_contains(
                                "TUIST_CARGO_CACHE_SCHEDULER_RESERVE_CPUS",
                            ) =>
                        {
                            self.scheduler.reserve_cpus =
                                workspace_count(&path, &setting, value, true)?;
                        }
                        "memory" if !environment_contains("TUIST_CARGO_CACHE_SCHEDULER_MEMORY") => {
                            let memory = value.as_str().ok_or_else(|| {
                                eyre::eyre!("{}.{} must be a string", path.display(), setting)
                            })?;
                            self.scheduler.memory_bytes = parse_optional_byte_size(memory)
                                .wrap_err_with(|| {
                                    format!("invalid {}.{setting}", path.display())
                                })?;
                        }
                        "priority"
                            if !environment_contains("TUIST_CARGO_CACHE_SCHEDULER_PRIORITY") =>
                        {
                            let priority = value.as_str().ok_or_else(|| {
                                eyre::eyre!("{}.{} must be a string", path.display(), setting)
                            })?;
                            self.scheduler.priority = priority.parse().wrap_err_with(|| {
                                format!("invalid {}.{setting}", path.display())
                            })?;
                        }
                        "pressure"
                            if !environment_contains("TUIST_CARGO_CACHE_SCHEDULER_PRESSURE") =>
                        {
                            self.scheduler.pressure = workspace_bool(&path, &setting, value)?;
                        }
                        "tests" if !environment_contains("TUIST_CARGO_CACHE_SCHEDULER_TESTS") => {
                            self.scheduler.tests = workspace_bool(&path, &setting, value)?;
                        }
                        "enabled" | "cpus" | "reserve_cpus" | "memory" | "priority" | "tests"
                        | "pressure" => {}
                        _ => bail!(
                            "{} contains unsupported workspace setting {setting:?}; only scheduler.enabled, scheduler.cpus, scheduler.reserve_cpus, scheduler.memory, scheduler.priority, scheduler.pressure, and scheduler.tests are allowed",
                            path.display()
                        ),
                    }
                }
                continue;
            }
            if !matches!(
                key,
                "incremental"
                    | "eager_incremental"
                    | "share_out_dir"
                    | "share_workspace_root"
                    | "build_script_execution"
                    | "cc"
            ) {
                bail!(
                    "{} contains unsupported workspace setting {key:?}; only incremental, eager_incremental, share_out_dir, share_workspace_root, build_script_execution, cc, linker, and scheduler are allowed",
                    path.display()
                );
            }
            let value = value
                .as_bool()
                .ok_or_else(|| eyre::eyre!("{}.{} must be a boolean", path.display(), key))?;
            match key {
                "incremental" if !environment_contains("TUIST_CARGO_CACHE_INCREMENTAL") => {
                    self.incremental = value;
                }
                "eager_incremental"
                    if !environment_contains("TUIST_CARGO_CACHE_EAGER_INCREMENTAL") =>
                {
                    self.eager_incremental = value;
                }
                "share_out_dir" if !environment_contains("TUIST_CARGO_CACHE_SHARE_OUT_DIR") => {
                    self.share_out_dir = value;
                }
                "share_workspace_root"
                    if !environment_contains("TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT") =>
                {
                    self.share_workspace_root = value;
                }
                "build_script_execution"
                    if !environment_contains("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION") =>
                {
                    self.build_script_execution = value;
                }
                "cc" if !environment_contains("TUIST_CARGO_CACHE_CC") => {
                    self.cc = value;
                }
                "incremental"
                | "eager_incremental"
                | "share_out_dir"
                | "share_workspace_root"
                | "build_script_execution"
                | "cc" => {}
                _ => unreachable!("workspace policy keys were validated above"),
            }
        }
        Ok(())
    }

    /// Where cached actions and blobs live.
    pub fn store_dir(&self) -> PathBuf {
        self.cache_dir.join("actions")
    }
}

fn workspace_bool(path: &Path, setting: &str, value: &toml_edit::Item) -> Result<bool> {
    value
        .as_bool()
        .ok_or_else(|| eyre::eyre!("{}.{} must be a boolean", path.display(), setting))
}

fn workspace_linker_profiles(
    path: &Path,
    value: &toml_edit::Item,
) -> Result<BTreeMap<String, BTreeMap<String, String>>> {
    let profiles = value
        .as_table()
        .ok_or_else(|| eyre::eyre!("{}.linker.profiles must be a table", path.display()))?;
    let mut resolved = BTreeMap::new();
    for (profile, targets) in profiles {
        let targets = targets.as_table().ok_or_else(|| {
            eyre::eyre!(
                "{}.linker.profiles.{profile} must be a table of target selectors",
                path.display()
            )
        })?;
        let mut selections = BTreeMap::new();
        for (target, selection) in targets {
            let selection = selection.as_str().ok_or_else(|| {
                eyre::eyre!(
                    "{}.linker.profiles.{profile}.{target} must be a string",
                    path.display()
                )
            })?;
            crate::managed_linker::validate_workspace_selector(selection).wrap_err_with(|| {
                format!(
                    "invalid {}.linker.profiles.{profile}.{target}",
                    path.display()
                )
            })?;
            selections.insert(target.to_owned(), selection.to_owned());
        }
        resolved.insert(profile.to_owned(), selections);
    }
    Ok(resolved)
}

fn workspace_count(
    path: &Path,
    setting: &str,
    value: &toml_edit::Item,
    zero_allowed: bool,
) -> Result<u64> {
    let count = value
        .as_integer()
        .and_then(|count| u64::try_from(count).ok())
        .filter(|count| zero_allowed || *count > 0);
    count.ok_or_else(|| {
        let requirement = if zero_allowed {
            "non-negative"
        } else {
            "positive"
        };
        eyre::eyre!(
            "{}.{} must be a {requirement} count",
            path.display(),
            setting
        )
    })
}

/// Resolve a byte size, written either plainly or with a unit.
///
/// Both IEC and SI spellings parse. `20GiB` and `20GB` are different numbers,
/// and sizes are reported back in IEC, so the two are not interchangeable.
fn parse_byte_size(value: &str) -> Result<u64> {
    // `ByteSize`'s parse error is a bare `String`, so it cannot be a source.
    value
        .trim()
        .parse::<ByteSize>()
        .map(|size| size.as_u64())
        .map_err(|error| eyre::eyre!(error))
}

/// The spelling that turns a limit off outright.
///
/// A limit needs an off switch that is not "unset", because unset now means the
/// scaled default. Only this exact word does it: anything else that fails to
/// parse is still an error, so a typo cannot quietly disable collection.
const NO_LIMIT: &str = "none";

fn is_no_limit(value: &str) -> bool {
    value.trim().eq_ignore_ascii_case(NO_LIMIT)
}

/// Parse the store budget, which alone has no off switch.
///
/// An unbounded action store is the problem collection exists to prevent, so
/// `"none"` is refused. It has to be refused in words, since the sibling size
/// settings accept it and `bytesize` would otherwise blame a float.
fn parse_store_budget(value: &str) -> Result<u64> {
    if is_no_limit(value) {
        eyre::bail!("the action store budget cannot be disabled; set a size such as 20GiB");
    }
    parse_byte_size(value)
}

pub(crate) fn parse_optional_byte_size(value: &str) -> Result<Option<u64>> {
    if is_no_limit(value) {
        return Ok(None);
    }
    parse_byte_size(value).map(Some)
}

/// `target.keep` or `target.evict_first` as paths to match checkouts against.
///
/// A leading `~` is the home directory, and an absolute entry that exists is
/// resolved the way checkout paths are recorded, so a symlinked home still
/// matches. Relative entries stay relative: they match anywhere.
///
/// A `~` entry with no home directory to expand it is an error: read as a
/// relative path it would match nothing, and a `target.keep` that silently
/// protects nothing is worse than a configuration that fails to load.
fn checkout_patterns(entries: Option<&[String]>, home: Option<PathBuf>) -> Result<Vec<PathBuf>> {
    entries
        .unwrap_or_default()
        .iter()
        .map(|entry| entry.trim())
        .filter(|entry| !entry.is_empty())
        .map(|entry| {
            let path = match entry.strip_prefix('~') {
                Some(rest) if rest.is_empty() || rest.starts_with(['/', '\\']) => {
                    let Some(home) = home.clone() else {
                        eyre::bail!("{entry:?} starts with ~, but there is no home directory");
                    };
                    std::fs::canonicalize(&home)
                        .unwrap_or(home)
                        .join(rest.trim_start_matches(['/', '\\']))
                }
                _ => PathBuf::from(entry),
            };
            Ok(if path.is_absolute() {
                std::fs::canonicalize(&path).unwrap_or(path)
            } else {
                path
            })
        })
        .collect()
}

fn parse_optional_duration(value: &str) -> Result<Option<Duration>> {
    if is_no_limit(value) {
        return Ok(None);
    }
    parse_duration(value).map(Some)
}

/// The setting a value was refused for, as the context of the error, so a
/// report can say where the value came from and how to change it.
#[derive(Debug)]
struct Invalid(&'static str);

impl std::fmt::Display for Invalid {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "invalid {}", self.0)
    }
}

/// `error` followed by how to fix each setting it names.
///
/// Resolved a second time rather than threaded through, because only a
/// failing load pays for it and the resolution itself has no side effects.
fn with_repair_hints(
    error: eyre::Report,
    env: &EnvLayer,
    file: Option<&FileLayer>,
) -> eyre::Report {
    let mut layers = Layers::new().then(env);
    if let Some(file) = file {
        layers = layers.then(file);
    }
    let Ok(resolved) = usage_config::resolve(RawConfig::SETTINGS_REGISTRY, layers) else {
        return error;
    };
    let hints = if resolved.warnings.is_empty() {
        error
            .downcast_ref::<Invalid>()
            .and_then(|invalid| {
                resolved
                    .origin_key(invalid.0)
                    .and_then(|origin| repair_hint(origin, invalid.0, false))
            })
            .into_iter()
            .collect::<Vec<_>>()
    } else {
        resolved
            .warnings
            .iter()
            .filter_map(|warning| {
                let origin = warning.origin.as_ref()?;
                let key = match origin.kind {
                    usage_config::SourceKind::FILE => origin.identifier.rsplit_once('#')?.1,
                    _ => "",
                };
                let unknown = warning.kind == usage_config::WarningKind::UnknownSetting;
                repair_hint(origin, key, unknown)
            })
            .collect()
    };
    if hints.is_empty() {
        return error;
    }
    eyre::eyre!("{error:#}\n{}", hints.join("\n"))
}

/// How to change a value that came from `origin`, for the setting `key`.
fn repair_hint(origin: &usage_config::Origin, key: &str, unknown: bool) -> Option<String> {
    match origin.kind {
        usage_config::SourceKind::ENV => Some(format!(
            "{} sets it; change or unset that variable",
            origin.identifier
        )),
        usage_config::SourceKind::FILE if unknown => Some(format!(
            "`tuist_cargo_cache settings unset {key}` removes it"
        )),
        usage_config::SourceKind::FILE => Some(format!(
            "`tuist_cargo_cache settings set {key} <value>` replaces it, or `tuist_cargo_cache settings unset {key}` restores the default"
        )),
        _ => None,
    }
}

/// The global configuration file, which `tuist_cargo_cache settings` edits.
pub(crate) fn config_file_path() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("TUIST_CARGO_CACHE_CONFIG") {
        return Some(PathBuf::from(path));
    }
    dirs::config_dir().map(|dir| dir.join("tuist_cargo_cache").join("config.toml"))
}

/// Every setting tuist_cargo_cache declares.
pub(crate) fn settings_registry() -> usage_config::Registry {
    RawConfig::SETTINGS_REGISTRY
}

/// Resolve the settings from the environment and the global file, without
/// the workspace policy.
pub(crate) fn resolve_settings() -> Result<usage_config::Resolved> {
    resolve_settings_from(Some(&EnvLayer::from_process()))
}

/// Resolve the settings from the global file alone: what would apply once the
/// environment stopped overriding it.
pub(crate) fn resolve_file_settings() -> Result<usage_config::Resolved> {
    resolve_settings_from(None)
}

fn resolve_settings_from(env: Option<&EnvLayer>) -> Result<usage_config::Resolved> {
    let mut layers = Layers::new();
    if let Some(env) = env {
        layers = layers.then(env);
    }
    let file = config_file_path().map(|path| FileLayer::at(path, FileScope::Global));
    if let Some(file) = &file {
        layers = layers.then(file);
    }
    Ok(usage_config::resolve(settings_registry(), layers)?)
}

/// Check that `contents` would be a valid global configuration file at `path`,
/// ignoring the environment so a variable cannot hide a bad value.
///
/// `path` must exist, because the file layer treats a missing file as empty
/// before it ever reaches the text it is handed here.
pub(crate) fn check_global_file(path: &Path, contents: String) -> Result<()> {
    let file = FileLayer::at(path, FileScope::Global).preprocess(move |_| Ok(contents.clone()));
    Config::from_layers_for_cli(&EnvLayer::new(Vec::<(String, String)>::new()), Some(&file))
        .map(|_| ())
}

fn default_cache_dir() -> Option<PathBuf> {
    dirs::cache_dir().map(|dir| dir.join("tuist_cargo_cache"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The disk size the tests below resolve scaled budgets against, so an
    /// assertion describes the scaling rule rather than the disk running it.
    const TEST_DISK: u64 = 400 * GIB;

    fn configured(file: Option<&str>, values: &[(&str, &str)]) -> Result<Config> {
        configured_for_cli(file, values).map(|(config, _)| config)
    }

    fn configured_for_cli(
        file: Option<&str>,
        values: &[(&str, &str)],
    ) -> Result<(Config, CliSettings)> {
        configured_on_disk(file, values, Some(TEST_DISK))
    }

    fn configured_retention(
        file: Option<&str>,
        values: &[(&str, &str)],
    ) -> Result<(Config, RetentionSettings)> {
        configured_for_cli(file, values).map(|(config, settings)| (config, settings.retention))
    }

    fn configured_on_disk(
        file: Option<&str>,
        values: &[(&str, &str)],
        disk_total_bytes: Option<u64>,
    ) -> Result<(Config, CliSettings)> {
        configured_measuring(file, values, move |_| disk_total_bytes)
    }

    /// Resolve with a stated size per path, for the budgets that are measured
    /// against different disks.
    fn configured_measuring(
        file: Option<&str>,
        values: &[(&str, &str)],
        measure_disk: impl Fn(&Path) -> Option<u64>,
    ) -> Result<(Config, CliSettings)> {
        let env = EnvLayer::new(
            values
                .iter()
                .map(|(name, value)| ((*name).to_string(), (*value).to_string())),
        );
        let directory = tempfile::tempdir().unwrap();
        let file = file.map(|contents| {
            let path = directory.path().join("config.toml");
            std::fs::write(&path, contents).unwrap();
            FileLayer::at(path, FileScope::Global)
        });
        Config::from_layers_measuring(&env, file.as_ref(), measure_disk, || Some(32 * GIB))
    }

    #[test]
    fn repository_policy_cannot_opt_into_process_supervision() {
        let directory = tempfile::tempdir().unwrap();
        for policy in ["suspend = true", "cgroup_root = '/delegated'"] {
            std::fs::write(
                directory.path().join(".tuist_cargo_cache.toml"),
                format!("[scheduler]\n{policy}\n"),
            )
            .unwrap();
            let mut config = configured(None, &[]).unwrap();
            assert!(
                config
                    .apply_workspace_policy_with(directory.path(), |_| false)
                    .is_err()
            );
        }
    }

    #[test]
    fn suspension_requires_explicit_opt_in() {
        let config = configured(None, &[]).unwrap();
        assert!(!config.scheduler.suspend);
        assert!(config.scheduler.cgroup_root.is_none());
        let config = configured(
            None,
            &[
                ("TUIST_CARGO_CACHE_SCHEDULER_SUSPEND", "1"),
                ("TUIST_CARGO_CACHE_SCHEDULER_CGROUP_ROOT", "/delegated"),
            ],
        )
        .unwrap();
        assert!(config.scheduler.suspend);
        assert_eq!(
            config.scheduler.cgroup_root,
            Some(PathBuf::from("/delegated"))
        );
    }

    #[test]
    fn pressure_setting_defaults_and_overrides() {
        assert!(configured(None, &[]).unwrap().scheduler.pressure);
        assert!(
            !configured(Some("[scheduler]\npressure = false"), &[])
                .unwrap()
                .scheduler
                .pressure
        );
        assert!(
            !configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER_PRESSURE", "0")])
                .unwrap()
                .scheduler
                .pressure
        );
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "[scheduler]\npressure = false",
        )
        .unwrap();
        let mut config = configured(None, &[]).unwrap();
        config
            .apply_workspace_policy_with(directory.path(), |_| false)
            .unwrap();
        assert!(!config.scheduler.pressure);
    }

    #[test]
    fn environment_overrides_the_file() {
        let file = r#"
            cache_dir = "/from/file"
            [remote]
            url = "https://file.example"
            namespace = "file"
            mode = "read-only"
            s3_conditional_writes = "required"
            [http]
            timeout = "5s"
            retries = 9
            [gc]
            auto = false
            max_size = "1GiB"
            interval = "6h"
            [target]
            views = true
            root = "/from/file/targets"
            "#;
        let config = configured(
            Some(file),
            &[
                ("TUIST_CARGO_CACHE_DIR", "/from/env"),
                ("TUIST_CARGO_CACHE_REMOTE_URL", "https://env.example"),
                ("TUIST_CARGO_CACHE_REMOTE_MODE", "write-only"),
                ("TUIST_CARGO_CACHE_HTTP_TIMEOUT", "250ms"),
                ("TUIST_CARGO_CACHE_GC_MAX_SIZE", "2GiB"),
                ("TUIST_CARGO_CACHE_TARGET_ROOT", "/from/env/targets"),
            ],
        )
        .unwrap();

        assert_eq!(config.cache_dir, PathBuf::from("/from/env"));
        assert_eq!(config.remote.url.unwrap(), "https://env.example");
        assert_eq!(config.remote.mode, RemoteCacheMode::WriteOnly);
        assert_eq!(config.http.timeout, Duration::from_millis(250));
        assert_eq!(config.gc.max_bytes, 2 * 1024 * 1024 * 1024);
        // Values absent from the environment still come from the file.
        assert_eq!(config.remote.namespace.unwrap(), "file");
        assert_eq!(
            config.remote.s3_conditional_writes,
            S3ConditionalWrites::Required
        );
        assert_eq!(config.http.retries, 9);
        assert!(!config.gc.auto);
        assert_eq!(config.gc.interval, Duration::from_secs(6 * 60 * 60));
        assert_eq!(config.target.root, PathBuf::from("/from/env/targets"));
        assert!(config.target.views);
    }

    #[test]
    fn private_shims_resolve_relative_to_the_cache_and_environment_overrides_the_file() {
        let directory = tempfile::tempdir().unwrap();
        let cache = directory.path().join("cache");
        let private = directory.path().join("private shims");
        let cache_text = cache.to_str().unwrap();
        let from_file = configured(
            Some("shims_dir = 'worker/shims'"),
            &[("TUIST_CARGO_CACHE_DIR", cache_text)],
        )
        .unwrap();
        assert_eq!(from_file.shims_dir, cache.join("worker/shims"));
        let from_environment = configured(
            Some("shims_dir = 'worker/shims'"),
            &[
                ("TUIST_CARGO_CACHE_DIR", cache_text),
                ("TUIST_CARGO_CACHE_SHIMS_DIR", private.to_str().unwrap()),
            ],
        )
        .unwrap();
        assert_eq!(from_environment.shims_dir, private);
        assert_eq!(from_environment.store_dir(), cache.join("actions"));
        let relative = configured(
            None,
            &[
                ("TUIST_CARGO_CACHE_DIR", cache_text),
                ("TUIST_CARGO_CACHE_SHIMS_DIR", "local"),
            ],
        )
        .unwrap();
        assert_eq!(relative.shims_dir, cache.join("local"));
    }

    #[test]
    fn relative_shims_cannot_traverse_above_the_cache_root() {
        for path in ["../private", "worker/../../private", "../cache/private"] {
            let error = configured(None, &[("TUIST_CARGO_CACHE_SHIMS_DIR", path)]).unwrap_err();
            assert!(error.to_string().contains("invalid shims_dir"), "{error}");
            let file = format!("shims_dir = '{path}'");
            assert!(configured(Some(&file), &[]).is_err());
        }
    }

    #[test]
    fn shims_reject_empty_and_empty_normalizing_paths() {
        for path in ["", ".", "./", "a/.."] {
            let file = format!("shims_dir = '{path}'");
            for result in [
                configured(None, &[("TUIST_CARGO_CACHE_SHIMS_DIR", path)]),
                configured(Some(&file), &[]),
            ] {
                let error = result.unwrap_err();
                assert!(error.to_string().contains("invalid shims_dir"), "{error}");
            }
        }
    }

    #[test]
    fn relative_shims_normalize_parent_components_within_the_cache_root() {
        let config = configured(
            None,
            &[("TUIST_CARGO_CACHE_SHIMS_DIR", "worker/../private/./shims")],
        )
        .unwrap();
        assert_eq!(config.shims_dir, config.cache_dir.join("private/shims"));
    }

    #[test]
    fn defaults_apply_without_configuration() {
        let (config, retention) = configured_retention(None, &[]).unwrap();
        assert_eq!(
            config.remote.s3_conditional_writes,
            S3ConditionalWrites::Auto
        );
        assert_eq!(config.http.timeout, DEFAULT_HTTP_TIMEOUT);
        assert_eq!(config.http.download_timeout, DEFAULT_HTTP_DOWNLOAD_TIMEOUT);
        assert_eq!(config.http.retries, DEFAULT_HTTP_RETRIES);
        assert_eq!(config.remote.mode, RemoteCacheMode::ReadWrite);
        assert!(config.remote.url.is_none());
        assert!(!config.verify);
        assert!(!config.incremental);
        assert!(config.share_out_dir);
        assert!(config.build_script_execution);
        assert!(config.store_dir().ends_with("actions"));
        assert_eq!(config.shims_dir, config.cache_dir.join("shims"));
        assert!(config.gc.auto, "collection runs until it is turned off");
        assert_eq!(config.gc.max_bytes, 20 * GIB, "5% of a 400GiB disk");
        assert_eq!(config.gc.interval, DEFAULT_GC_INTERVAL);
        assert!(
            config.target.views,
            "eligible target directories are managed"
        );
        assert_eq!(config.target.root, config.cache_dir.join("targets"));
        // Collection of live target directories is on by default; leaving these
        // unset is what used to let a disk fill up indefinitely.
        assert_eq!(
            retention.target_max_bytes,
            Some(40 * GIB),
            "10% of a 400GiB disk"
        );
        assert_eq!(retention.target_max_age, Some(DEFAULT_TARGET_MAX_AGE));
        assert_eq!(retention.incremental_max_bytes, Some(20 * GIB));
        assert_eq!(retention.incremental_max_age, Some(DEFAULT_TARGET_MAX_AGE));
        assert_eq!(
            retention.max_total_bytes, None,
            "a combined budget stays opt-in"
        );
        assert_eq!(retention.min_free, Some(MinFree::ShareOfDisk));
    }

    #[test]
    fn the_free_space_minimum_scales_with_each_disk() {
        let share = MinFree::ShareOfDisk;
        assert_eq!(share.bytes(32 * GIB), 5 * GIB, "the floor on a small disk");
        assert_eq!(share.bytes(256 * GIB), 25 * GIB);
        assert_eq!(share.bytes(4_096 * GIB), 50 * GIB, "the ceiling");
        assert_eq!(MinFree::Bytes(GIB).bytes(4_096 * GIB), GIB);
    }

    #[test]
    fn the_free_space_minimum_can_be_set_or_turned_off() {
        let (_, retention) =
            configured_retention(None, &[("TUIST_CARGO_CACHE_GC_MIN_FREE_SIZE", "8GiB")]).unwrap();
        assert_eq!(retention.min_free, Some(MinFree::Bytes(8 * GIB)));
        let (_, retention) =
            configured_retention(Some("[gc]\nmin_free_size = \"none\""), &[]).unwrap();
        assert_eq!(retention.min_free, None);
        let error = configured_retention(None, &[("TUIST_CARGO_CACHE_GC_MIN_FREE_SIZE", "lots")])
            .unwrap_err();
        assert!(
            format!("{error:#}").contains("gc.min_free_size"),
            "{error:#}"
        );
    }

    #[test]
    fn target_precedence_reads_lists_from_the_file_and_environment() {
        let (_, retention) = configured_retention(None, &[]).unwrap();
        assert_eq!(
            retention.target_precedence,
            crate::target::Precedence::default()
        );

        let (_, retention) = configured_retention(
            Some("[target]\nkeep = [\"~/src/app\"]\nevict_first = [\".claude/worktrees\"]"),
            &[],
        )
        .unwrap();
        let home = dirs::home_dir().unwrap();
        let home = std::fs::canonicalize(&home).unwrap_or(home);
        assert_eq!(retention.target_precedence.keep, [home.join("src/app")]);
        assert_eq!(
            retention.target_precedence.evict_first,
            [PathBuf::from(".claude/worktrees")]
        );

        let (_, retention) = configured_retention(
            None,
            &[(
                "TUIST_CARGO_CACHE_TARGET_EVICT_FIRST",
                ".claude/worktrees, scratch",
            )],
        )
        .unwrap();
        assert_eq!(
            retention.target_precedence.evict_first,
            [PathBuf::from(".claude/worktrees"), PathBuf::from("scratch")]
        );
    }

    #[test]
    fn a_home_relative_pattern_without_a_home_is_an_error() {
        let entries = ["~/src/app".to_string(), "scratch".to_string()];

        let error = checkout_patterns(Some(&entries), None).unwrap_err();
        assert!(format!("{error:#}").contains("~/src/app"), "{error:#}");
        assert_eq!(
            checkout_patterns(Some(&entries[1..]), None).unwrap(),
            [PathBuf::from("scratch")],
            "entries that need no home still load"
        );
        assert_eq!(
            checkout_patterns(
                Some(&entries[..1]),
                Some(PathBuf::from("/nonexistent-home"))
            )
            .unwrap(),
            [PathBuf::from("/nonexistent-home/src/app")]
        );
    }

    #[test]
    fn path_specific_storage_defaults_on_and_environment_overrides_file() {
        let (config, _) = configured_retention(None, &[]).unwrap();
        assert!(config.cc_store_path_specific);
        let (config, _) =
            configured_retention(Some("cc_store_path_specific = false"), &[]).unwrap();
        assert!(!config.cc_store_path_specific);
        let (config, _) = configured_retention(
            Some("cc_store_path_specific = false"),
            &[("TUIST_CARGO_CACHE_CC_STORE_PATH_SPECIFIC", "1")],
        )
        .unwrap();
        assert!(config.cc_store_path_specific);
    }

    #[test]
    fn budgets_scale_with_the_disk_within_bounds() {
        let cases = [
            // A small disk lands on the floors rather than a cache too small
            // to ever hit in.
            (Some(32 * GIB), STORE_BUDGET.floor, TARGET_BUDGET.floor),
            (Some(400 * GIB), 20 * GIB, 40 * GIB),
            // 5% and 10% of 1TiB are 51.2 and 102.4 GiB: the first rounds down
            // to a whole increment, the second meets its ceiling.
            (Some(1_024 * GIB), 50 * GIB, MAX_TARGET_BUDGET),
            // A large shared disk can give the store more than the old 100GiB
            // ceiling while managed targets remain capped there.
            (Some(8_000 * GIB), 400 * GIB, MAX_TARGET_BUDGET),
            // The store still has a ceiling on exceptionally large disks.
            (Some(20_000 * GIB), MAX_STORE_BUDGET, MAX_TARGET_BUDGET),
            // An unmeasurable disk uses the fixed fallbacks.
            (None, STORE_BUDGET.fallback, TARGET_BUDGET.fallback),
        ];
        for (disk, store, target) in cases {
            let (config, settings) = configured_on_disk(None, &[], disk).unwrap();
            let retention = settings.retention;
            assert_eq!(config.gc.max_bytes, store, "store budget for {disk:?}");
            assert_eq!(
                retention.target_max_bytes,
                Some(target),
                "target budget for {disk:?}"
            );
        }
    }

    #[test]
    fn a_scaled_budget_is_always_a_whole_increment() {
        // Awkward disk sizes are the point: 5% of 333GiB is 16.65GiB, which
        // should be reported as a number somebody could have chosen.
        for disk_gib in [17_u64, 63, 333, 500, 999, 1_500, 4_000] {
            for budget in [STORE_BUDGET, TARGET_BUDGET, INCREMENTAL_BUDGET] {
                let resolved = budget.resolve(Some(disk_gib * GIB));
                assert_eq!(
                    resolved % BUDGET_INCREMENT,
                    0,
                    "{resolved} is not a whole increment for a {disk_gib}GiB disk"
                );
                assert!(resolved >= budget.floor);
                assert!(resolved <= budget.ceiling);
            }
        }
    }

    #[test]
    fn rounding_never_hands_out_more_than_the_share() {
        // Rounded down, never to nearest: a budget must not exceed the share of
        // the disk it was allowed, floors aside.
        for disk_gib in [200_u64, 333, 617, 1_000] {
            let total = disk_gib * GIB;
            let resolved = STORE_BUDGET.resolve(Some(total));
            let share = (total / 100) * STORE_BUDGET.percent;
            assert!(
                resolved <= share.max(STORE_BUDGET.floor),
                "{resolved} exceeds the {share} share of a {disk_gib}GiB disk"
            );
        }
    }

    #[test]
    fn configured_budgets_outrank_the_disk() {
        let (config, settings) = configured_on_disk(
            None,
            &[
                ("TUIST_CARGO_CACHE_GC_MAX_SIZE", "3GiB"),
                ("TUIST_CARGO_CACHE_TARGET_MAX_SIZE", "7GiB"),
            ],
            Some(8_000 * GIB),
        )
        .unwrap();
        let retention = settings.retention;

        assert_eq!(config.gc.max_bytes, 3 * GIB);
        assert_eq!(retention.target_max_bytes, Some(7 * GIB));
        assert_eq!(
            retention.incremental_max_bytes,
            Some(MAX_INCREMENTAL_BUDGET)
        );
    }

    #[test]
    fn each_budget_is_sized_from_the_disk_that_holds_it() {
        // A scratch volume for targets is exactly why these are measured apart:
        // sizing a 4TiB disk from a 64GiB home directory would prune it to the
        // floor.
        let (config, settings) = configured_measuring(
            None,
            &[
                ("TUIST_CARGO_CACHE_DIR", "/cache"),
                ("TUIST_CARGO_CACHE_TARGET_ROOT", "/scratch"),
            ],
            |path| {
                Some(if path.starts_with("/scratch") {
                    4_000 * GIB
                } else {
                    64 * GIB
                })
            },
        )
        .unwrap();

        assert_eq!(config.gc.max_bytes, STORE_BUDGET.floor, "5% of 64GiB");
        assert_eq!(
            settings.retention.incremental_max_bytes,
            Some(INCREMENTAL_BUDGET.floor),
            "5% of 64GiB, at the floor"
        );
        assert_eq!(
            settings.retention.target_max_bytes,
            Some(MAX_TARGET_BUDGET),
            "10% of 4TiB, at the ceiling"
        );
    }

    #[test]
    fn the_store_budget_cannot_be_disabled() {
        let error = configured(None, &[("TUIST_CARGO_CACHE_GC_MAX_SIZE", "none")])
            .expect_err("an unbounded store is what collection exists to prevent");
        let message = format!("{error:#}");
        assert!(
            message.contains("cannot be disabled"),
            "the error should say why rather than blame a float: {message}"
        );
    }

    #[test]
    fn none_turns_a_retention_limit_off() {
        let (_, retention) = configured_retention(
            None,
            &[
                ("TUIST_CARGO_CACHE_TARGET_MAX_SIZE", "none"),
                ("TUIST_CARGO_CACHE_TARGET_MAX_AGE", "NONE"),
                ("TUIST_CARGO_CACHE_GC_INCREMENTAL_MAX_SIZE", "none"),
                ("TUIST_CARGO_CACHE_GC_INCREMENTAL_MAX_AGE", "none"),
                ("TUIST_CARGO_CACHE_GC_MAX_TOTAL_SIZE", "None"),
            ],
        )
        .unwrap();

        assert_eq!(retention.target_max_bytes, None);
        assert_eq!(retention.target_max_age, None);
        assert_eq!(retention.incremental_max_bytes, None);
        assert_eq!(retention.incremental_max_age, None);
        assert_eq!(retention.max_total_bytes, None);
    }

    #[test]
    fn the_unconfigured_retention_default_still_collects() {
        // Paths that resolve no configuration must not silently stop pruning.
        let retention = RetentionSettings::default();
        assert_eq!(retention.target_max_bytes, Some(TARGET_BUDGET.fallback));
        assert_eq!(retention.target_max_age, Some(DEFAULT_TARGET_MAX_AGE));
        assert_eq!(
            retention.incremental_max_bytes,
            Some(INCREMENTAL_BUDGET.fallback)
        );
        assert_eq!(retention.incremental_max_age, Some(DEFAULT_TARGET_MAX_AGE));
    }

    #[test]
    fn a_total_budget_replaces_only_implicit_size_limits() {
        for total in [1, 100] {
            let value = format!("{total}GiB");
            let (config, settings) = configured_measuring(
                None,
                &[("TUIST_CARGO_CACHE_GC_MAX_TOTAL_SIZE", &value)],
                |_| panic!("a total budget needs no disk-scaled defaults"),
            )
            .unwrap();
            assert_eq!(config.gc.max_bytes, total * GIB);
            assert_eq!(settings.retention.max_total_bytes, Some(total * GIB));
            assert_eq!(settings.retention.target_max_bytes, None);
            assert_eq!(settings.retention.incremental_max_bytes, None);
            assert_eq!(settings.learned_incremental_max_size, Some(total * GIB));
            assert_eq!(settings.retention.min_free, Some(MinFree::ShareOfDisk));
            assert_eq!(
                settings.retention.target_max_age,
                Some(DEFAULT_TARGET_MAX_AGE)
            );
        }

        let (config, settings) = configured_for_cli(
            Some(
                r#"
learned_incremental_max_size = "2GiB"
[target]
max_size = "3GiB"
[gc]
max_total_size = "10GiB"
max_size = "4GiB"
incremental_max_size = "5GiB"
"#,
            ),
            &[],
        )
        .unwrap();
        assert_eq!(config.gc.max_bytes, 4 * GIB);
        assert_eq!(settings.retention.target_max_bytes, Some(3 * GIB));
        assert_eq!(settings.retention.incremental_max_bytes, Some(5 * GIB));
        assert_eq!(settings.learned_incremental_max_size, Some(2 * GIB));

        let (_, settings) = configured_for_cli(
            Some(
                r#"
learned_incremental_max_size = "none"
[target]
max_size = "none"
[gc]
max_total_size = "10GiB"
incremental_max_size = "none"
"#,
            ),
            &[],
        )
        .unwrap();
        assert_eq!(settings.retention.target_max_bytes, None);
        assert_eq!(settings.retention.incremental_max_bytes, None);
        assert_eq!(settings.learned_incremental_max_size, None);
    }

    #[test]
    fn disabling_the_total_budget_restores_component_defaults() {
        let (expected_config, expected) = configured_for_cli(None, &[]).unwrap();
        let (config, settings) = configured_for_cli(
            Some("[gc]\nmax_total_size = \"1GiB\""),
            &[("TUIST_CARGO_CACHE_GC_MAX_TOTAL_SIZE", "none")],
        )
        .unwrap();
        assert_eq!(config.gc.max_bytes, expected_config.gc.max_bytes);
        assert_eq!(settings.retention.max_total_bytes, None);
        assert_eq!(
            settings.retention.target_max_bytes,
            expected.retention.target_max_bytes
        );
        assert_eq!(
            settings.retention.incremental_max_bytes,
            expected.retention.incremental_max_bytes
        );
        assert_eq!(
            settings.learned_incremental_max_size,
            expected.learned_incremental_max_size
        );
    }

    #[test]
    fn reads_target_and_whole_cache_retention_limits() {
        let (_, retention) = configured_retention(
            None,
            &[
                ("TUIST_CARGO_CACHE_TARGET_MAX_SIZE", "8GiB"),
                ("TUIST_CARGO_CACHE_TARGET_MAX_AGE", "14d"),
                ("TUIST_CARGO_CACHE_GC_INCREMENTAL_MAX_SIZE", "9GiB"),
                ("TUIST_CARGO_CACHE_GC_INCREMENTAL_MAX_AGE", "21d"),
                ("TUIST_CARGO_CACHE_GC_MAX_TOTAL_SIZE", "12GiB"),
            ],
        )
        .unwrap();

        assert_eq!(retention.target_max_bytes, Some(8 * 1024 * 1024 * 1024));
        assert_eq!(
            retention.target_max_age,
            Some(Duration::from_secs(14 * 86_400))
        );
        assert_eq!(retention.incremental_max_bytes, Some(9 * GIB));
        assert_eq!(
            retention.incremental_max_age,
            Some(Duration::from_secs(21 * 86_400))
        );
        assert_eq!(retention.max_total_bytes, Some(12 * 1024 * 1024 * 1024));
    }

    #[test]
    fn managed_targets_can_be_turned_off() {
        for value in ["0", "false", "no", "off", ""] {
            let config = configured(None, &[("TUIST_CARGO_CACHE_TARGET_VIEWS", value)]).unwrap();
            assert!(
                !config.target.views,
                "TUIST_CARGO_CACHE_TARGET_VIEWS={value:?} should disable managed targets"
            );
        }
    }

    #[test]
    fn relative_target_roots_are_anchored_to_the_cache_directory() {
        let config = configured(
            None,
            &[
                ("TUIST_CARGO_CACHE_DIR", "/cache"),
                ("TUIST_CARGO_CACHE_TARGET_ROOT", "target-views"),
            ],
        )
        .unwrap();

        assert_eq!(config.target.root, PathBuf::from("/cache/target-views"));
    }

    #[test]
    fn rejects_unparseable_values() {
        assert!(configured(None, &[("TUIST_CARGO_CACHE_REMOTE_MODE", "sideways")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_HTTP_TIMEOUT", "later")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_HTTP_RETRIES", "many")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_GC_MAX_SIZE", "lots")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_GC_MAX_TOTAL_SIZE", "lots")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_GC_INTERVAL", "later")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_TARGET_MAX_SIZE", "lots")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_TARGET_MAX_AGE", "later")]).is_err());
        // A budget that cannot be read must not be guessed at, and neither must
        // a switch: silently collecting to the wrong number, or not at all, is
        // worse than saying so.
        assert!(configured(None, &[("TUIST_CARGO_CACHE_GC_AUTO", "maybe")]).is_err());
        assert!(configured(None, &[("TUIST_CARGO_CACHE_TARGET_VIEWS", "sometimes")]).is_err());
    }

    #[test]
    fn collection_runs_until_it_is_turned_off() {
        for value in ["0", "false", "no", "off", ""] {
            let config = configured(None, &[("TUIST_CARGO_CACHE_GC_AUTO", value)]).unwrap();
            assert!(
                !config.gc.auto,
                "TUIST_CARGO_CACHE_GC_AUTO={value:?} should disable"
            );
        }
        for value in ["1", "true", "yes", "on", "ON"] {
            let config = configured(None, &[("TUIST_CARGO_CACHE_GC_AUTO", value)]).unwrap();
            assert!(
                config.gc.auto,
                "TUIST_CARGO_CACHE_GC_AUTO={value:?} should enable"
            );
        }
    }

    #[test]
    fn reads_a_budget_in_either_unit_convention() {
        // `20GB` and `20GiB` are different numbers and sizes are reported back
        // in IEC, so both spellings have to mean exactly what they say.
        for (value, expected) in [
            ("20GiB", 20 * 1024 * 1024 * 1024),
            ("20GB", 20_000_000_000),
            ("1024", 1024),
        ] {
            let config = configured(None, &[("TUIST_CARGO_CACHE_GC_MAX_SIZE", value)]).unwrap();
            assert_eq!(config.gc.max_bytes, expected, "{value} should parse");
        }
    }

    #[test]
    fn the_environment_can_turn_off_what_the_file_turned_on() {
        let file = "incremental = true";
        let config = configured(Some(file), &[]).unwrap();
        assert!(config.incremental);
        let config = configured(Some(file), &[("TUIST_CARGO_CACHE_INCREMENTAL", "0")]).unwrap();
        assert!(!config.incremental);
    }

    #[test]
    fn eager_incremental_is_opt_in_and_workspace_policy_respects_environment() {
        assert!(!configured(None, &[]).unwrap().eager_incremental);
        assert!(
            configured(None, &[("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "1")])
                .unwrap()
                .eager_incremental
        );
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "eager_incremental = true",
        )
        .unwrap();
        let mut config = configured(Some("eager_incremental = false"), &[]).unwrap();
        config
            .apply_workspace_policy_with(directory.path(), |_| false)
            .unwrap();
        assert!(config.eager_incremental);
        let mut config = configured(
            Some("eager_incremental = true"),
            &[("TUIST_CARGO_CACHE_EAGER_INCREMENTAL", "0")],
        )
        .unwrap();
        config
            .apply_workspace_policy_with(directory.path(), |name| {
                name == "TUIST_CARGO_CACHE_EAGER_INCREMENTAL"
            })
            .unwrap();
        assert!(!config.eager_incremental);
    }

    /// On by default: a crate nobody is editing never reaches the threshold, so
    /// the setting only matters to the one the developer is working in.
    #[test]
    fn learned_incremental_is_on_until_it_is_turned_off() {
        let (_, settings) = configured_for_cli(None, &[]).unwrap();
        assert!(settings.learned_incremental);

        let (_, settings) =
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0")]).unwrap();
        assert!(!settings.learned_incremental);
    }

    /// The budget has to hold a real crate's state: rustc keeps one session's
    /// worth per crate, and a large binary's session is a few GiB.
    #[test]
    fn learned_incremental_state_budget_is_generous_and_can_be_lifted() {
        let (_, settings) = configured_for_cli(None, &[]).unwrap();
        assert_eq!(
            settings.learned_incremental_max_size,
            Some(DEFAULT_LEARNED_INCREMENTAL_MAX_SIZE)
        );

        let (_, settings) = configured_for_cli(
            None,
            &[("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL_MAX_SIZE", "2GiB")],
        )
        .unwrap();
        assert_eq!(
            settings.learned_incremental_max_size,
            Some(2 * 1024 * 1024 * 1024)
        );

        let (_, settings) = configured_for_cli(
            None,
            &[("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL_MAX_SIZE", "none")],
        )
        .unwrap();
        assert_eq!(settings.learned_incremental_max_size, None);

        let error = configured_for_cli(
            None,
            &[("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL_MAX_SIZE", "lots")],
        )
        .unwrap_err();
        assert!(error.to_string().contains("learned_incremental_max_size"));
    }

    /// The default keeps the TUI's read cheap; diagnosing a miss on a large
    /// workspace needs more history than it allows.
    #[test]
    fn recorded_history_is_capped_by_default_and_can_be_lifted() {
        let (_, settings) = configured_for_cli(None, &[]).unwrap();
        assert_eq!(settings.events_max_size, Some(DEFAULT_EVENTS_MAX_SIZE));

        let (_, settings) =
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_EVENTS_MAX_SIZE", "256MiB")]).unwrap();
        assert_eq!(settings.events_max_size, Some(256 * 1024 * 1024));

        let (_, settings) =
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_EVENTS_MAX_SIZE", "none")]).unwrap();
        assert_eq!(settings.events_max_size, None);

        let error =
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_EVENTS_MAX_SIZE", "lots")]).unwrap_err();
        assert!(error.to_string().contains("events_max_size"));
    }

    #[test]
    fn workspace_policy_overrides_global_safe_settings() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "incremental = true\nshare_out_dir = true\nbuild_script_execution = true\n",
        )
        .unwrap();
        let mut config = configured(
            Some("incremental = false\nshare_out_dir = false\nbuild_script_execution = false"),
            &[],
        )
        .unwrap();

        config
            .apply_workspace_policy_with(directory.path(), |_| false)
            .unwrap();

        assert!(config.incremental);
        assert!(config.share_out_dir);
        assert!(config.build_script_execution);
    }

    #[test]
    fn linkers_are_selected_by_profile_and_target() {
        let file = r#"
[linker]
default = "system"

[linker.profiles.dev]
default = "wild@0.10.0"
aarch64-apple-darwin = "rust-lld"

[linker.profiles.release]
default = "rust-lld"
"#;
        let config = configured(Some(file), &[]).unwrap();

        assert_eq!(
            config.linker.for_build("dev", Some("aarch64-apple-darwin")),
            Some("rust-lld".into())
        );
        assert_eq!(
            config
                .linker
                .for_build("dev", Some("x86_64-unknown-linux-gnu")),
            Some("wild@0.10.0".into())
        );
        assert_eq!(
            config.linker.for_build("release", None),
            Some("rust-lld".into())
        );
        assert_eq!(config.linker.for_build("bench", None), None);
        assert_eq!(
            config
                .linker
                .for_build("debug", Some("x86_64-unknown-linux-gnu")),
            Some("wild@0.10.0".into()),
            "Cargo's debug profile inherits dev"
        );
    }

    #[test]
    fn workspace_linker_policy_overrides_the_global_selection() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "[linker.profiles.dev]\ndefault = \"mold@2.42.0\"\n",
        )
        .unwrap();
        let mut config = configured(
            Some(
                "[linker.profiles.dev]\ndefault = \"system\"\naarch64-apple-darwin = \"rust-lld\"",
            ),
            &[],
        )
        .unwrap();

        config
            .apply_workspace_policy_with(directory.path(), |_| false)
            .unwrap();

        assert_eq!(
            config
                .linker
                .for_build("dev", Some("x86_64-unknown-linux-gnu")),
            Some("mold@2.42.0".into())
        );
        assert_eq!(
            config.linker.for_build("dev", Some("aarch64-apple-darwin")),
            Some("rust-lld".into())
        );
    }

    #[test]
    fn workspace_linker_policy_preserves_unrelated_global_profiles() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "[linker.profiles.dev]\ndefault = \"mold@2.42.0\"\n",
        )
        .unwrap();
        let mut config = configured(
            Some("[linker.profiles.release]\ndefault = \"rust-lld\""),
            &[],
        )
        .unwrap();

        config
            .apply_workspace_policy_with(directory.path(), |_| false)
            .unwrap();

        assert_eq!(
            config.linker.for_build("release", None),
            Some("rust-lld".into())
        );
        assert_eq!(
            config.linker.for_build("dev", None),
            Some("mold@2.42.0".into())
        );
    }

    #[test]
    fn workspace_linker_policy_rejects_executable_paths() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "[linker.profiles.dev]\ndefault = \"path:./linker\"\n",
        )
        .unwrap();
        let mut config = configured(None, &[]).unwrap();

        let error = config
            .apply_workspace_policy_with(directory.path(), |_| false)
            .unwrap_err();

        assert!(
            format!("{error:?}")
                .contains("workspace linker policy may not select an executable path")
        );
    }

    #[test]
    fn workspace_policy_accepts_scheduler_settings() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "[scheduler]\nenabled = true\ncpus = 8\nreserve_cpus = 2\nmemory = \"6GiB\"\npriority = \"low\"\ntests = true\n",
        )
        .unwrap();
        let mut config = configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER", "false")]).unwrap();

        config
            .apply_workspace_policy_with(directory.path(), |name| {
                name == "TUIST_CARGO_CACHE_SCHEDULER"
            })
            .unwrap();

        assert!(!config.scheduler.enabled, "the environment still wins");
        assert_eq!(config.scheduler.cpus, 8);
        assert_eq!(config.scheduler.reserve_cpus, 2);
        assert_eq!(config.scheduler.permits(), 6);
        assert_eq!(config.scheduler.memory_bytes, Some(6 * GIB));
        assert_eq!(config.scheduler.priority, SchedulerPriority::Low);
        assert!(config.scheduler.tests);
    }

    #[test]
    fn environment_overrides_workspace_scheduler_policy() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "[scheduler]\ncpus = 8\nreserve_cpus = 2\nmemory = \"6GiB\"\npriority = \"low\"\n",
        )
        .unwrap();
        let environment = [
            ("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "5"),
            ("TUIST_CARGO_CACHE_SCHEDULER_RESERVE_CPUS", "1"),
            ("TUIST_CARGO_CACHE_SCHEDULER_MEMORY", "4GiB"),
            ("TUIST_CARGO_CACHE_SCHEDULER_PRIORITY", "normal"),
        ];
        let mut config = configured(None, &environment).unwrap();

        config
            .apply_workspace_policy_with(directory.path(), |name| {
                environment.iter().any(|(key, _)| *key == name)
            })
            .unwrap();

        assert_eq!(config.scheduler.cpus, 5);
        assert_eq!(config.scheduler.reserve_cpus, 1);
        assert_eq!(config.scheduler.memory_bytes, Some(4 * GIB));
        assert_eq!(config.scheduler.priority, SchedulerPriority::Normal);
    }

    #[test]
    fn workspace_policy_validates_scheduler_settings() {
        for setting in [
            "[scheduler]\ncpus = 0",
            "[scheduler]\nreserve_cpus = -1",
            "[scheduler]\nmemory = \"plenty\"",
            "[scheduler]\npriority = \"urgent\"",
            "[scheduler]\nunknown = true",
        ] {
            let directory = tempfile::tempdir().unwrap();
            std::fs::write(directory.path().join(".tuist_cargo_cache.toml"), setting).unwrap();
            let mut config = configured(None, &[]).unwrap();
            assert!(
                config
                    .apply_workspace_policy_with(directory.path(), |_| false)
                    .is_err(),
                "{setting:?} should be rejected"
            );
        }
    }

    #[test]
    fn environment_overrides_workspace_policy() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join(".tuist_cargo_cache.toml"),
            "incremental = true\nshare_out_dir = true\nbuild_script_execution = true\n",
        )
        .unwrap();
        let mut config = configured(
            None,
            &[
                ("TUIST_CARGO_CACHE_SHARE_OUT_DIR", "0"),
                ("TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION", "0"),
            ],
        )
        .unwrap();

        config
            .apply_workspace_policy_with(directory.path(), |_| true)
            .unwrap();

        assert!(!config.incremental);
        assert!(!config.share_out_dir);
        assert!(!config.build_script_execution);
    }

    #[test]
    fn workspace_policy_rejects_every_setting_outside_the_allowlist() {
        for setting in [
            "cache_dir = \"elsewhere\"",
            "verify = true",
            "[remote]\nurl = \"https://example.com\"",
            // Credentials and the store they authenticate to are a machine's
            // business, never a repository's.
            "[remote]\ns3_endpoint = \"https://store.example.com\"",
            "[remote]\ns3_region = \"us-west-2\"",
            "[gc]\nauto = false",
            "[target]\nviews = false",
        ] {
            let directory = tempfile::tempdir().unwrap();
            std::fs::write(directory.path().join(".tuist_cargo_cache.toml"), setting).unwrap();
            let mut config = configured(None, &[]).unwrap();
            let error = config
                .apply_workspace_policy_with(directory.path(), |_| false)
                .unwrap_err();
            assert!(
                error.to_string().contains("unsupported workspace setting"),
                "{error}"
            );
        }
    }

    #[test]
    fn missing_workspace_policy_is_ignored() {
        let directory = tempfile::tempdir().unwrap();
        let mut config = configured(None, &[]).unwrap();
        config
            .apply_workspace_policy_with(directory.path(), |_| false)
            .unwrap();
    }

    #[test]
    fn a_refused_value_names_its_setting_for_the_repair_hint() {
        let error = configured(Some("[gc]\ninterval = \"soon\"\n"), &[]).unwrap_err();
        assert_eq!(
            error.downcast_ref::<Invalid>().map(|invalid| invalid.0),
            Some("gc.interval")
        );
        let error = configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "0")]).unwrap_err();
        assert_eq!(
            format!("{error:#}"),
            "invalid scheduler.cpus: must be a positive count"
        );
        let env = EnvLayer::new([(
            "TUIST_CARGO_CACHE_SCHEDULER_CPUS".to_string(),
            "0".to_string(),
        )]);
        assert_eq!(
            format!("{:#}", with_repair_hints(error, &env, None)),
            "invalid scheduler.cpus: must be a positive count\n\
             TUIST_CARGO_CACHE_SCHEDULER_CPUS sets it; change or unset that variable"
        );
    }

    #[test]
    fn unknown_file_keys_are_rejected() {
        let error = configured(Some("not_a_setting = true"), &[]).unwrap_err();
        assert!(error.to_string().contains("not_a_setting"), "{error}");
    }

    #[test]
    fn verification_sample_rate_is_a_percentage() {
        assert_eq!(configured(None, &[]).unwrap().verify_sample_rate, 0);
        for rate in ["0", "1", "25", "100"] {
            let config =
                configured(None, &[("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE", rate)]).unwrap();
            assert_eq!(config.verify_sample_rate.to_string(), rate);
        }
        assert_eq!(
            configured(Some("verify_sample_rate = 5"), &[])
                .unwrap()
                .verify_sample_rate,
            5
        );
        for rate in ["-1", "101", "256", "bad"] {
            assert!(configured(None, &[("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE", rate)]).is_err());
        }
    }

    #[test]
    fn verify_is_off_for_empty_and_zero() {
        for value in ["", "0"] {
            let config = configured(None, &[("TUIST_CARGO_CACHE_VERIFY", value)]).unwrap();
            assert!(
                !config.verify,
                "TUIST_CARGO_CACHE_VERIFY={value:?} should not enable"
            );
        }
        let config = configured(None, &[("TUIST_CARGO_CACHE_VERIFY", "1")]).unwrap();
        assert!(config.verify);
    }

    #[test]
    fn savings_default_to_quips_with_plain_and_off_as_choices() {
        let (_, settings) = configured_for_cli(None, &[]).unwrap();
        assert_eq!(
            settings.savings,
            SavingsStyle::Quips,
            "an unconfigured machine gets the voice"
        );
        let (_, settings) =
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_SAVINGS", "plain")]).unwrap();
        assert_eq!(settings.savings, SavingsStyle::Plain);
        let (_, settings) =
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_SAVINGS", "off")]).unwrap();
        assert_eq!(settings.savings, SavingsStyle::Off);
        assert!(
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_SAVINGS", "sarcastic")]).is_err(),
            "an unknown style is an error, not a silent default"
        );
    }

    #[test]
    fn summaries_default_to_auto_and_allow_fixed_styles() {
        let (_, settings) = configured_for_cli(None, &[]).unwrap();
        assert_eq!(settings.summary, SummaryStyle::Auto);
        assert_eq!(settings.summary.resolve(false), SummaryStyle::Short);
        assert_eq!(settings.summary.resolve(true), SummaryStyle::Ci);
        for (value, style) in [
            ("off", SummaryStyle::Off),
            ("short", SummaryStyle::Short),
            ("ci", SummaryStyle::Ci),
            ("full", SummaryStyle::Full),
        ] {
            let (_, settings) =
                configured_for_cli(None, &[("TUIST_CARGO_CACHE_SUMMARY", value)]).unwrap();
            assert_eq!(settings.summary.resolve(false), style);
            assert_eq!(settings.summary.resolve(true), style);
            let (_, settings) =
                configured_for_cli(Some(&format!("summary = {value:?}")), &[]).unwrap();
            assert_eq!(settings.summary.resolve(true), style);
        }
        assert!(
            configured_for_cli(None, &[("TUIST_CARGO_CACHE_SUMMARY", "verbose")]).is_err(),
            "an unknown style is an error, not a silent default"
        );
    }

    #[test]
    fn the_scheduler_defaults_on_with_most_of_the_measured_memory() {
        let config = configured(None, &[]).unwrap();
        assert!(config.scheduler.enabled);
        assert_eq!(
            config.scheduler.cpus,
            std::thread::available_parallelism().unwrap().get() as u64
        );
        // 85% of the 32GiB the test harness reports.
        assert_eq!(
            config.scheduler.memory_bytes,
            Some(32 * GIB / 100 * 85),
            "the budget leaves headroom for what it cannot see"
        );
        assert_eq!(config.scheduler.priority, SchedulerPriority::Normal);
        assert_eq!(config.scheduler.reserve_cpus, 0);
    }

    #[test]
    fn the_scheduler_is_configurable_and_refuses_nonsense() {
        let config = configured(
            None,
            &[
                ("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "3"),
                ("TUIST_CARGO_CACHE_SCHEDULER_RESERVE_CPUS", "1"),
                ("TUIST_CARGO_CACHE_SCHEDULER_MEMORY", "4GiB"),
                ("TUIST_CARGO_CACHE_SCHEDULER_PRIORITY", "low"),
            ],
        )
        .unwrap();
        assert_eq!(config.scheduler.cpus, 3);
        assert_eq!(config.scheduler.reserve_cpus, 1);
        assert_eq!(config.scheduler.permits(), 2);
        assert_eq!(config.scheduler.memory_bytes, Some(4 * GIB));
        assert_eq!(config.scheduler.priority, SchedulerPriority::Low);

        let config = configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER", "false")]).unwrap();
        assert!(!config.scheduler.enabled);

        let config = configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER_MEMORY", "none")]).unwrap();
        assert_eq!(
            config.scheduler.memory_bytes, None,
            "\"none\" keeps plain CPU permits"
        );

        let config = configured(
            None,
            &[
                ("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "3"),
                ("TUIST_CARGO_CACHE_SCHEDULER_RESERVE_CPUS", "9"),
            ],
        )
        .unwrap();
        assert_eq!(config.scheduler.permits(), 1, "one permit always remains");

        let error = configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER_CPUS", "0")]).unwrap_err();
        assert!(error.to_string().contains("scheduler.cpus"), "{error}");
        let error =
            configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER_RESERVE_CPUS", "-1")]).unwrap_err();
        assert!(
            error.to_string().contains("scheduler.reserve_cpus"),
            "{error}"
        );
        let error =
            configured(None, &[("TUIST_CARGO_CACHE_SCHEDULER_PRIORITY", "loud")]).unwrap_err();
        assert!(error.to_string().contains("scheduler.priority"), "{error}");
    }

    #[test]
    fn a_disabled_scheduler_needs_no_memory_measurement() {
        let env = EnvLayer::new([(
            "TUIST_CARGO_CACHE_SCHEDULER".to_string(),
            "false".to_string(),
        )]);
        let (config, _) = Config::from_layers_measuring(
            &env,
            None,
            |_| None,
            || panic!("a disabled scheduler must not probe memory"),
        )
        .unwrap();
        assert!(!config.scheduler.enabled);
    }

    #[test]
    fn the_usage_spec_declares_files_environment_and_defaults() {
        let spec = RawConfig::spec_kdl();
        assert!(spec.contains(r#"file "<config directory>/tuist_cargo_cache/config.toml""#));
        assert!(spec.contains(r#"env "TUIST_CARGO_CACHE_GC_MAX_SIZE""#));
        assert!(spec.contains(r#"prop "gc.max_size""#));
        assert!(spec.contains(r#"prop "target.max_size""#));
        assert!(spec.contains(r#"env "TUIST_CARGO_CACHE_TARGET_MAX_AGE""#));
        assert!(spec.contains(r#"default="30d""#));
        // The scaled budgets have no literal default to declare, so the
        // generated reference has to describe them instead.
        assert!(spec.contains("5% of the cache disk"));
        assert!(spec.contains("10% of the target disk"));
        assert!(spec.contains(r#"env "TUIST_CARGO_CACHE_SAVINGS""#));
        assert!(spec.contains(r#"default="quips""#));
        // The declared log default is the filter the logger actually installs.
        assert!(spec.contains(&format!(r#"default="{}""#, crate::logging::DEFAULT_FILTER)));
    }
}
