//! Build-session lifecycle: the cache agent, its transport, and the rustc shim
//! that cargo invokes through `RUSTC_WRAPPER`.

use crate::config::{Config, MinFree};
use crate::events::{ActionDetail, ActionOutcome, EventWriter};
use crate::util::duration_ns;
use eyre::Result;
use log::{debug, warn};
use serde::Serialize;
use std::collections::{BTreeMap, VecDeque};
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
#[cfg(unix)]
use std::sync::atomic::AtomicU64;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;
use tuist_cargo_cache_cc::CcLanguage;
#[cfg(test)]
use tuist_cargo_cache_core::AGENT_PROTOCOL_VERSION;
use tuist_cargo_cache_core::{
    ActionDiagnostic, AgentEvent, AgentEventObserver, AgentRemoteCache, AgentRequest,
    AgentResponse, AgentStats, CacheAgent, CacheDigest, FileDigestCache, FileDigestScope,
    FileIdentity, NoFileDigestCache, RecordedFileDigest, canonical_json,
};

mod client;
pub mod cmake;
mod diagnostics;
mod server;
mod shims;
mod stats;
pub(crate) use stats::{cache_misses, unexpected_bypasses};
pub(crate) mod verification;

#[cfg(test)]
use client::validate_handshake_response;
use client::{request_agent_at, request_standalone_agent};
pub(crate) use diagnostics::{
    note, report_shim_error, report_shim_warning, reserve_stderr_for_compiler,
};
#[cfg(unix)]
pub(crate) use server::create_fifo;
pub(crate) use server::listener_unavailable;
use server::spawn_server;
pub(crate) use shims::CC_CRATE_ENV;
#[cfg(all(test, windows))]
use shims::link_path_shim;
use shims::{CcShims, install_cc_shims, install_session_shims, is_shim_directory};
pub use shims::{
    PathShims, ShimLink, install_path_shims, install_shim, install_shim_named, shim_file_name,
};
#[cfg(test)]
use shims::{
    TargetedCompiler, resolve_in_path, resolve_named_compiler, resolve_on_path, symlink_shim,
    targeted_compiler_language,
};
use stats::StatsReport;
pub(crate) use stats::display_stats;
pub(crate) use stats::session_was_active;
#[cfg(test)]
use stats::{
    ci_summary, short_summary, should_display_short_stats, should_display_stats,
    stale_manifest_note,
};

pub const RUSTC_SHIM_STEM: &str = "tuist_cargo_cache-rustc";
pub const RUSTDOC_SHIM_STEM: &str = "tuist_cargo_cache-rustdoc";
/// File stem of the C shim, which build scripts inherit as an absolute path.
///
/// It deliberately does not end in `-cc` or `-gcc`. Those suffixes name a
/// cross-compiler prefix by convention -- `aarch64-linux-gnu-gcc` compiles for
/// `aarch64-linux-gnu` -- and tooling reads them back off whatever `CC` holds.
/// The `autotools` crate strips one from the compiler path and passes the rest
/// to `configure` as `--host`, so a shim named `tuist_cargo_cache-cc` turned
/// `/var/cache/tuist_cargo_cache/shims/tuist_cargo_cache-cc` into `--host=/var/cache/tuist_cargo_cache/shims/tuist_cargo_cache`, which
/// `config.sub` rejects as a machine triple. Anything installed under a name a
/// `CC` variable can carry has to stay clear of those two suffixes.
pub const CC_SHIM_STEM: &str = "tuist_cargo_cache-c";
pub const CXX_SHIM_STEM: &str = "tuist_cargo_cache-cxx";
/// What the C shim was installed under before [`CC_SHIM_STEM`] changed.
///
/// The shim directory outlives the session that wrote it because a configure
/// step records its compiler by absolute path -- into `CMakeCache.txt`, into a
/// generated makefile -- so a tree configured by an older tuist_cargo_cache still invokes
/// this name. Nothing is installed under it any more; it is only recognized.
const LEGACY_CC_SHIM_STEM: &str = "tuist_cargo_cache-cc";
pub(crate) const PATH_SHIMS_ENV: &str = "TUIST_CARGO_CACHE_CC_SHIM_COMPILERS";
pub(crate) const SOCKET_ENV: &str = "TUIST_CARGO_CACHE_SOCKET";
pub(crate) const REAL_CC_ENV: &str = "TUIST_CARGO_CACHE_REAL_CC";
pub(crate) const REAL_CXX_ENV: &str = "TUIST_CARGO_CACHE_REAL_CXX";
pub(crate) const STAGING_ENV: &str = "TUIST_CARGO_CACHE_STAGING_DIR";
pub(crate) const BUILD_ENV: &str = "TUIST_CARGO_CACHE_BUILD";
pub(crate) const VERIFY_ENV: &str = "TUIST_CARGO_CACHE_VERIFY";
pub(crate) const SHARE_OUT_DIR_ENV: &str = "TUIST_CARGO_CACHE_SHARE_OUT_DIR";
pub(crate) const RESTORE_HARDLINK_ENV: &str = "TUIST_CARGO_CACHE_RESTORE_HARDLINK";
pub(crate) const SHARE_WORKSPACE_ROOT_ENV: &str = "TUIST_CARGO_CACHE_SHARE_WORKSPACE_ROOT";
pub(crate) const BUILD_SCRIPT_EXECUTION_ENV: &str = "TUIST_CARGO_CACHE_BUILD_SCRIPT_EXECUTION";
pub(crate) const FORWARD_COMPILER_NOTIFICATIONS_ENV: &str =
    "TUIST_CARGO_CACHE_FORWARD_COMPILER_NOTIFICATIONS";
pub(crate) const BUILD_SCRIPT_SHIM_PATH_ENV: &str = "TUIST_CARGO_CACHE_BUILD_SCRIPT_SHIM_PATH";
pub(crate) const AR_DETERMINISM_ENV: &str = "TUIST_CARGO_CACHE_AR_DETERMINISM";
pub(crate) const EAGER_INCREMENTAL_ENV: &str = "TUIST_CARGO_CACHE_SESSION_EAGER_INCREMENTAL";
pub(crate) const GC_AUTO_ENV: &str = "TUIST_CARGO_CACHE_SESSION_GC_AUTO";
pub(crate) const GC_MIN_FREE_ENV: &str = "TUIST_CARGO_CACHE_SESSION_GC_MIN_FREE";
pub(crate) const GC_CACHE_DIR_ENV: &str = "TUIST_CARGO_CACHE_SESSION_GC_CACHE_DIR";
pub(crate) const GC_TARGET_ROOT_ENV: &str = "TUIST_CARGO_CACHE_SESSION_GC_TARGET_ROOT";
pub(crate) const GC_EXECUTABLE_ENV: &str = "TUIST_CARGO_CACHE_SESSION_GC_EXECUTABLE";
pub(crate) const LEARNED_INCREMENTAL_ENV: &str = "TUIST_CARGO_CACHE_LEARNED_INCREMENTAL";
pub(crate) const LEARNED_INCREMENTAL_MAX_SIZE_ENV: &str =
    "TUIST_CARGO_CACHE_LEARNED_INCREMENTAL_MAX_SIZE";
pub(crate) const INCREMENTAL_ROOT_ENV: &str = "TUIST_CARGO_CACHE_INCREMENTAL_ROOT";
pub(crate) const MANAGED_TARGET_LINKERS_ENV: &str = "TUIST_CARGO_CACHE_MANAGED_TARGET_LINKERS";
pub(crate) const MANAGED_LINKER_ENV: &str = "TUIST_CARGO_CACHE_MANAGED_LINKER";
pub const CACHE_LINKS_ENV: &str = "TUIST_CARGO_CACHE_CACHE_LINKS";
/// Group completed builds for one later cache export, used by CI actions.
pub const CACHE_EXPORT_GROUP_ENV: &str = "TUIST_CARGO_CACHE_CACHE_EXPORT_GROUP";
pub(crate) const WORKSPACE_ROOT_ENV: &str = "TUIST_CARGO_CACHE_WORKSPACE_ROOT";
pub(crate) const TARGET_DIR_ENV: &str = "TUIST_CARGO_CACHE_TARGET_DIR";
pub(crate) const BUILD_SCRIPT_REAL_SUFFIX: &str = ".tuist_cargo_cache-real";
const PREVIOUS_RUSTC_WRAPPER_ENV: &str = "TUIST_CARGO_CACHE_PREVIOUS_RUSTC_WRAPPER";
const PREVIOUS_RUSTC_WORKSPACE_WRAPPER_ENV: &str =
    "TUIST_CARGO_CACHE_PREVIOUS_RUSTC_WORKSPACE_WRAPPER";
const REAL_RUSTDOC_ENV: &str = "TUIST_CARGO_CACHE_REAL_RUSTDOC";
pub(crate) const BYPASS_LOG_ENV: &str = "TUIST_CARGO_CACHE_BYPASS_LOG";
const VERSION: &str = env!("CARGO_PKG_VERSION");
#[cfg(unix)]
static SHIM_STAGING_NONCE: AtomicU64 = AtomicU64::new(0);

/// Encode only the resolved retention input the compiler shim needs. The
/// share form is resolved against the disk being checked, so it cannot be
/// turned into one byte value while the Cargo session is starting.
fn session_gc_environment(config: &Config, min_free: Option<MinFree>) -> Vec<(String, String)> {
    let min_free = min_free.map_or_else(String::new, |min_free| match min_free {
        MinFree::ShareOfDisk => "share".into(),
        MinFree::Bytes(bytes) => bytes.to_string(),
    });
    // The shim runs from the crate it is compiling, so a relative cache path
    // would probe that crate's disk and could start a collector for a stray
    // cache there. Keep this session-only path separate from TUIST_CARGO_CACHE_DIR so
    // nested tools retain the environment they were given.
    let absolute = |path: &Path| {
        std::path::absolute(path)
            .ok()
            .map_or_else(String::new, |path| path.to_string_lossy().into_owned())
    };
    // Inside a shim, `current_exe()` names the shim, and a process started
    // from it would run as that shim instead of as `tuist_cargo_cache gc`. The session's
    // own binary is the one the collector must be started from.
    let executable = std::env::current_exe()
        .ok()
        .map_or_else(String::new, |path| absolute(&path));
    vec![
        (GC_AUTO_ENV.into(), u8::from(config.gc.auto).to_string()),
        (GC_MIN_FREE_ENV.into(), min_free),
        (GC_CACHE_DIR_ENV.into(), absolute(&config.cache_dir)),
        (GC_TARGET_ROOT_ENV.into(), absolute(&config.target.root)),
        (GC_EXECUTABLE_ENV.into(), executable),
    ]
}

/// Resolve the session-only low-disk setting without consulting configuration.
/// A missing or malformed value deliberately disables the shim hook.
pub(crate) fn low_disk_min_free() -> Option<MinFree> {
    low_disk_min_free_from_environment(
        std::env::var(GC_AUTO_ENV).ok().as_deref(),
        std::env::var(GC_MIN_FREE_ENV).ok().as_deref(),
    )
}

/// Check the session's resolved cache disk after a real compiler invocation.
///
/// Persistent wrappers leave the session-only settings absent or empty, so
/// they never load configuration just to decide whether to probe the disk.
pub(crate) fn check_low_disk_after_compile() {
    let Some(min_free) = low_disk_min_free() else {
        return;
    };
    let session_path = |name: &str| std::env::var_os(name).filter(|path| !path.is_empty());
    let (Some(cache_dir), Some(target_root), Some(executable)) = (
        session_path(GC_CACHE_DIR_ENV),
        session_path(GC_TARGET_ROOT_ENV),
        session_path(GC_EXECUTABLE_ENV),
    ) else {
        return;
    };
    let loaded = if std::env::var_os("TUIST_CARGO_NATIVE").is_some() {
        Config::load_for_tuist().map(|(config, _)| config)
    } else {
        Config::load()
    };
    let mut config = match loaded {
        Ok(config) => config,
        Err(error) => {
            log::debug!("the low-disk sweep check could not load configuration: {error:#}");
            return;
        }
    };
    // The shim runs from the crate it is compiling, so a relative path loaded
    // here would name that crate's disk instead of the session's.
    config.cache_dir = cache_dir.into();
    config.target.root = target_root.into();
    crate::cli::schedule_low_disk_sweep(&config, min_free, &crate::util::disk_space, &|config| {
        crate::cli::spawn_collector_from(Path::new(&executable), config)
    });
}

fn low_disk_min_free_from_environment(
    auto: Option<&str>,
    min_free: Option<&str>,
) -> Option<MinFree> {
    (auto == Some("1")).then_some(())?;
    match min_free? {
        "share" => Some(MinFree::ShareOfDisk),
        value if !value.is_empty() => value.parse().ok().map(MinFree::Bytes),
        _ => None,
    }
}

/// A cache session: the agent, its listener, and the shim cargo will invoke.
pub struct CacheSession {
    socket: String,
    rustc_shim: PathBuf,
    /// Held for the session's lifetime so collection keeps `rustc_shim`.
    _rustc_shim_lease: shims::ShimLease,
    rustdoc_shim: PathBuf,
    cc_shims: Option<CcShims>,
    cmake_shims_dir: PathBuf,
    staging: PathBuf,
    verify: bool,
    verify_sample_rate: u8,
    incremental: bool,
    share_out_dir: bool,
    restore_hardlink: bool,
    share_workspace_root: bool,
    cc_store_path_specific: bool,
    build_script_execution: bool,
    forward_compiler_notifications: bool,
    agent: CacheAgent,
    /// The stream `tuist_cargo_cache tui` watches, when event recording is on.
    events: Option<EventStream>,
    /// What the shims need to draw compile permits from the machine-wide pool.
    scheduler_env: Vec<(String, String)>,
    /// The resolved automatic-collection policy for this session.
    gc_env: Vec<(String, String)>,
    store: PathBuf,
    incremental_root: PathBuf,
    /// Where the shim keeps content-addressed copies of build-script output.
    out_dir_root: PathBuf,
    /// Active leases keep collection from deleting checkout-private state
    /// while this session's compiler processes may still be using it.
    incremental_leases: Mutex<Vec<crate::incremental::ActiveLease>>,
    /// The checkout's private state directory once `begin` has claimed it,
    /// where the file-digest ledger is saved when the session finishes.
    ledger_dir: Mutex<Option<PathBuf>>,
    /// What the ledger file looked like when this session read it, so a
    /// session that was alone in the checkout can write without merging.
    ledger_stamp: Arc<Mutex<Option<crate::digest_ledger::Stamp>>>,
    started: Instant,
    shutdown: Mutex<Option<oneshot::Sender<()>>>,
    server: Mutex<Option<JoinHandle<Result<()>>>>,
    task: Arc<SessionTask>,
}

/// The Cargo task is loaded only if a compiler shim connects.
pub(super) struct SessionTask {
    identity: std::sync::OnceLock<String>,
    initialized: tokio::sync::OnceCell<bool>,
    /// Whether any shim connected, which is what makes a run worth committing.
    connected: std::sync::atomic::AtomicBool,
}

impl CacheSession {
    /// Live counters for the inline Cargo display, scoped to this session.
    pub(crate) fn progress_stats(&self) -> AgentStats {
        self.agent.stats()
    }

    /// Install the shim, start the agent, and begin serving the shim's requests.
    ///
    /// `session_dir` holds the shim, socket, and staging directory, and is
    /// expected to be a temporary directory owned by the caller.
    pub async fn start(session_dir: &Path, config: &Config) -> Result<Self> {
        Self::start_with_events_limit(
            session_dir,
            config,
            Some(crate::config::DEFAULT_EVENTS_MAX_SIZE),
        )
        .await
    }

    /// Start a session recording at most `events_max_size` bytes of rows.
    ///
    /// Every command that builds under tuist_cargo_cache passes the configured value.
    /// `start` keeps the declared default for callers outside this crate,
    /// which have no settings to pass.
    pub(crate) async fn start_with_events_limit(
        session_dir: &Path,
        config: &Config,
        events_max_size: Option<u64>,
    ) -> Result<Self> {
        Self::start_with_jobs(session_dir, config, None, events_max_size, None).await
    }

    /// Start a session with the resolved automatic-collection policy.
    pub(crate) async fn start_with_events_limit_and_gc(
        session_dir: &Path,
        config: &Config,
        events_max_size: Option<u64>,
        min_free: Option<MinFree>,
    ) -> Result<Self> {
        Self::start_with_jobs(session_dir, config, None, events_max_size, min_free).await
    }

    /// Start a session whose Cargo jobserver limits compiler concurrency.
    ///
    /// `events_max_size` bounds the row-level history the build records;
    /// `None` records all of it. The counters it reports are unaffected.
    pub(crate) async fn start_with_jobs(
        session_dir: &Path,
        config: &Config,
        cargo_jobs: Option<u64>,
        events_max_size: Option<u64>,
        min_free: Option<MinFree>,
    ) -> Result<Self> {
        let session_shims = install_session_shims(session_dir, &config.shims_dir)?;
        let (shim, rustdoc_shim) = (session_shims.rustc, session_shims.rustdoc);
        let rustc_shim_lease = session_shims.lease;
        let cc_shims = if config.cc {
            // Build systems such as CMake persist HOST_CC as an absolute
            // compiler path. Keep the C/C++ shims outside the temporary
            // session so that path remains executable on the next tuist_cargo_cache run,
            // and private to this binary so another installation sharing the
            // shim directory cannot repoint or strand them.
            install_cc_shims(&session_shims.native)?
        } else {
            None
        };
        let staging = session_dir.join("staging");
        std::fs::create_dir(&staging)?;
        let store = config.store_dir();
        let task = Arc::new(SessionTask {
            identity: std::sync::OnceLock::new(),
            initialized: tokio::sync::OnceCell::new(),
            connected: std::sync::atomic::AtomicBool::new(false),
        });
        let agent = if let Some(remote) = action_remote_cache(config, &store).await? {
            CacheAgent::new_remote_with_download_limit(
                store.clone(),
                VERSION,
                remote,
                config.gc.max_bytes,
            )
        } else {
            CacheAgent::new(store.clone(), VERSION)
        };
        let events = config
            .events
            .then(|| Arc::new(EventWriter::with_limit(&store, events_max_size)))
            .map(EventStream::new);
        let agent = match &events {
            Some(events) => agent.with_observer(Arc::new(events.clone())),
            None => agent,
        };
        // A shim that needs the build's predictions is the one that waits for
        // the manifest; the probes cargo runs first only report bypasses.
        let agent = agent.with_task_loader({
            let task = Arc::clone(&task);
            Arc::new(move |agent: &CacheAgent, identity: &str| {
                let task = Arc::clone(&task);
                let identity = identity.to_string();
                Box::pin(async move {
                    if task.identity.get().is_some_and(|known| *known == identity) {
                        server::initialize_task(agent, &task).await;
                    }
                })
                    as std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send + '_>>
            })
        });
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let (socket, server) =
            spawn_server(session_dir, agent.clone(), Arc::clone(&task), shutdown_rx).await?;
        Ok(Self {
            socket,
            rustc_shim: shim,
            _rustc_shim_lease: rustc_shim_lease,
            rustdoc_shim,
            cc_shims,
            cmake_shims_dir: session_shims.native,
            staging,
            verify: config.verify,
            verify_sample_rate: config.verify_sample_rate,
            incremental: config.incremental,
            share_out_dir: config.share_out_dir,
            restore_hardlink: config.restore_hardlink,
            share_workspace_root: config.share_workspace_root,
            cc_store_path_specific: config.cc_store_path_specific,
            build_script_execution: config.build_script_execution,
            forward_compiler_notifications: config.forward_compiler_notifications,
            agent,
            events,
            scheduler_env: crate::scheduler::session_environment_with_jobs(config, cargo_jobs),
            gc_env: session_gc_environment(config, min_free),
            store,
            incremental_root: config.cache_dir.join("incremental"),
            out_dir_root: config.cache_dir.join(crate::out_dir::ROOT),
            incremental_leases: Mutex::new(Vec::new()),
            ledger_dir: Mutex::new(None),
            ledger_stamp: Arc::new(Mutex::new(None)),
            started: Instant::now(),
            shutdown: Mutex::new(Some(shutdown_tx)),
            server: Mutex::new(Some(server)),
            task,
        })
    }

    /// Begin the build's action run and return the environment cargo needs.
    ///
    /// `environment` is amended in place so a caller can pass the environment it
    /// already intends to hand to cargo. Any `RUSTC_WRAPPER` already present is
    /// preserved for the shim to chain to. The manifest identity is derived from
    /// `workspace_root` and `command` here so that callers cannot supply one the
    /// protocol would reject.
    pub async fn begin(
        &self,
        workspace_root: &Path,
        target_dir: &Path,
        command: &[String],
        environment: &mut BTreeMap<String, String>,
    ) -> Option<ActionRun> {
        let identity = build_identity(workspace_root, command);
        // Named before the first compilation, so a TUI that attaches mid-build
        // can say whose build it is watching rather than showing bare rows.
        if let Some(events) = &self.events {
            events
                .writer
                .started(workspace_root, command, Some(&identity));
        }
        // Recorded before the build rather than after it: a build that fails
        // still means this checkout is here and using the store, and the record
        // is what stops the collector treating its artifacts as abandoned.
        if let Err(error) =
            crate::store::record_checkout(&self.store, &identity, workspace_root, target_dir)
        {
            warn!("this checkout was not recorded as a cache root: {error}");
        }
        self.offer_earlier_lockfiles(&identity, workspace_root);
        let _ = self.task.identity.set(identity.clone());
        // Read now, in the background, rather than when the first shim
        // connects: cargo spends its own startup planning the build, and that
        // is time the manifest can be parsed in instead of stalling the first
        // compilation on it.
        {
            let agent = self.agent.clone();
            let task = Arc::clone(&self.task);
            tokio::spawn(async move {
                server::initialize_task(&agent, &task).await;
            });
        }
        let action_run = Some(ActionRun {
            run: identity.clone(),
            receipt: build_receipt_run(&identity),
            identity: identity.clone(),
            workspace_root: workspace_root.to_path_buf(),
            export_group: std::env::var(CACHE_EXPORT_GROUP_ENV).ok(),
            store: self.store.clone(),
            agent: self.agent.clone(),
            initialized: Some(Arc::clone(&self.task)),
        });
        let shim = self.rustc_shim.to_string_lossy().into_owned();
        // The shim maps these roots out of its cache keys; a dependency compiles
        // with its working directory in the registry, so it cannot find them.
        environment.insert(
            WORKSPACE_ROOT_ENV.into(),
            workspace_root.to_string_lossy().into_owned(),
        );
        environment.insert(
            TARGET_DIR_ENV.into(),
            target_dir.to_string_lossy().into_owned(),
        );
        // A compilation that reads build-script output is handed a copy of it
        // under the cache, named for its contents, so checkouts whose
        // generated sources match hand rustc the same path.
        environment.insert(
            crate::out_dir::ROOT_ENV.into(),
            self.out_dir_root.to_string_lossy().into_owned(),
        );
        // Always replace an inherited value. If recording this checkout fails,
        // the shim must use its target-local fallback rather than another
        // checkout's persistent state.
        environment.insert(
            INCREMENTAL_ROOT_ENV.into(),
            target_dir
                .join("tuist_cargo_cache-incremental")
                .to_string_lossy()
                .into_owned(),
        );
        match crate::incremental::touch(&self.incremental_root, workspace_root) {
            Ok(checkout) => {
                let root = checkout.directory;
                self.incremental_leases.lock().unwrap().push(checkout.lease);
                environment.insert(
                    INCREMENTAL_ROOT_ENV.into(),
                    root.to_string_lossy().into_owned(),
                );
                // Seeded under the ledger's own lock on a blocking thread, so
                // cargo's startup overlaps the read, and a shim that asks
                // before it is done waits for the answer instead of hashing
                // every unchanged dependency again.
                let agent = self.agent.clone();
                let ledger_root = root.clone();
                let stamp = Arc::clone(&self.ledger_stamp);
                tokio::task::spawn_blocking(move || {
                    let seeded = agent.seed_file_digests_with(|| {
                        *stamp.lock().unwrap() = crate::digest_ledger::stamp(&ledger_root);
                        crate::digest_ledger::load(&ledger_root)
                    });
                    debug!("file-digest ledger seeded with {seeded} entries");
                });
                *self.ledger_dir.lock().unwrap() = Some(root);
            }
            Err(error) => warn!("incremental state was not recorded: {error:#}"),
        }
        environment.insert(SOCKET_ENV.into(), self.socket.clone());
        environment.insert(
            STAGING_ENV.into(),
            self.staging.to_string_lossy().into_owned(),
        );
        environment.insert(BUILD_ENV.into(), identity);
        // Always state this explicitly: removing the key would leave the shim
        // inheriting whatever the parent environment had.
        environment.insert(
            VERIFY_ENV.into(),
            if self.verify { "1" } else { "0" }.into(),
        );
        environment.insert(
            verification::SAMPLE_RATE_ENV.into(),
            self.verify_sample_rate.to_string(),
        );
        environment.insert(
            "TUIST_CARGO_CACHE_CC_STORE_PATH_SPECIFIC".into(),
            if self.cc_store_path_specific {
                "1"
            } else {
                "0"
            }
            .into(),
        );
        environment.insert(
            SHARE_OUT_DIR_ENV.into(),
            if self.share_out_dir { "1" } else { "0" }.into(),
        );
        environment.insert(
            RESTORE_HARDLINK_ENV.into(),
            if self.restore_hardlink { "1" } else { "0" }.into(),
        );
        environment.insert(
            SHARE_WORKSPACE_ROOT_ENV.into(),
            if self.share_workspace_root { "1" } else { "0" }.into(),
        );
        environment.insert(
            BUILD_SCRIPT_EXECUTION_ENV.into(),
            if self.build_script_execution {
                "1"
            } else {
                "0"
            }
            .into(),
        );
        environment.insert(
            FORWARD_COMPILER_NOTIFICATIONS_ENV.into(),
            if self.forward_compiler_notifications {
                "1"
            } else {
                "0"
            }
            .into(),
        );
        for (name, value) in &self.scheduler_env {
            environment.insert(name.clone(), value.clone());
        }
        for (name, value) in &self.gc_env {
            environment.insert(name.clone(), value.clone());
        }
        if let Some(previous) = environment.insert("RUSTC_WRAPPER".into(), shim.clone())
            && previous != shim
        {
            // The shim defers to a wrapper that was already configured rather
            // than compiling around it, since that wrapper may do more than
            // cache. Say so, because the alternative is a silent no-op.
            warn!(
                "RUSTC_WRAPPER is already set to {previous}; deferring to it, so this build is not cached"
            );
            environment.insert(PREVIOUS_RUSTC_WRAPPER_ENV.into(), previous);
        }
        if let Some(previous) = environment.get("RUSTC_WORKSPACE_WRAPPER") {
            // Cargo nests this inside RUSTC_WRAPPER, so the shim receives the
            // workspace wrapper where it ordinarily receives rustc. Remember
            // that path to recognize the nested invocation. Clippy has a
            // modeled identity and configuration inputs; other workspace
            // wrappers remain transparent because tuist_cargo_cache cannot key their work.
            if executable_stem(OsStr::new(previous)) != Some("clippy-driver") {
                warn!(
                    "RUSTC_WORKSPACE_WRAPPER is already set to {previous}; deferring to it for workspace crates, so those compilations are not cached"
                );
            }
            environment.insert(
                PREVIOUS_RUSTC_WORKSPACE_WRAPPER_ENV.into(),
                previous.clone(),
            );
        }
        // Tuist does not cache documentation. Let Cargo honor explicit rustdoc
        // settings and otherwise perform its own lookup, without interception.
        if std::env::var_os("TUIST_CARGO_NATIVE").is_none() {
            let rustdoc = configured_rustdoc(environment);
            environment.insert(REAL_RUSTDOC_ENV.into(), rustdoc);
            environment.insert(
                "RUSTDOC".into(),
                self.rustdoc_shim.to_string_lossy().into_owned(),
            );
        }
        if let Some(shims) = &self.cc_shims {
            // Select CMake from the final per-build environment, just as we
            // do for compilers. Do this before injecting compiler shims: if
            // installing the CMake adapter fails, leave native builds plain
            // rather than exposing an unstable compiler identity to CMake.
            match cmake::environment(&self.cmake_shims_dir, shims, environment) {
                Ok(cmake_environment) => {
                    self.begin_cc(environment);
                    environment.extend(cmake_environment);
                }
                Err(error) => warn!("native compiler caching is unavailable: {error:#}"),
            }
        }
        if self.incremental {
            // Hand the decision back to cargo, which compiles local packages
            // incrementally in dev profiles and never in release. Not
            // overriding is the whole of the feature: the actions themselves
            // still bypass, they are just faster to recompile.
            environment.remove("CARGO_INCREMENTAL");
        } else {
            // Incremental compilation is never cacheable, so it is disabled
            // rather than left to bypass every action.
            environment.insert("CARGO_INCREMENTAL".into(), "0".into());
        }
        action_run
    }

    /// Point build scripts at the C and C++ shims.
    ///
    /// A build that already chose its compiler keeps it. Unlike `RUSTC_WRAPPER`,
    /// `CC` is commonly exported machine-wide for reasons that have nothing to
    /// do with this build, so standing aside is unremarkable and is logged
    /// rather than warned about; the session summary already reports how much
    /// of the build the cache covered.
    fn begin_cc(&self, environment: &mut BTreeMap<String, String>) {
        let Some(shims) = &self.cc_shims else {
            return;
        };
        // A build that named its own host compiler keeps it. This does not
        // stand in the way of the targeted shims below: those wrap a compiler
        // the build named rather than replacing one it chose, and the `cc`
        // crate reads the host and target variables in different builds.
        let host_chosen = CC_CRATE_ENV
            .iter()
            .find(|name| environment.contains_key(**name) || std::env::var_os(name).is_some());
        match host_chosen {
            Some(name) => {
                debug!("{name} is already set; host C and C++ compilations are not cached");
                let value = environment
                    .get(*name)
                    .cloned()
                    .or_else(|| std::env::var(name).ok())
                    .unwrap_or_else(|| "<non-UTF-8 value>".into());
                append_cacheability_observation(
                    environment,
                    "cc-compiler-override",
                    &format!(
                        "{name} is already set to `{value}`, so host C and C++ compilations do not pass through tuist_cargo_cache; unset it for this build to make them visible to the cache"
                    ),
                );
            }
            // `HOST_CC` rather than `CC`, because of where each sits in the
            // `cc` crate's lookup order: it reads `CC_<target>`, then
            // `HOST_CC` or `TARGET_CC` depending on whether it is
            // cross-compiling, and only then plain `CC`. Setting `CC` would
            // capture cross compiles too, and these shims wrap the *host*
            // compiler -- a `cargo build --target` would silently build target
            // objects with the host driver.
            None => shims.apply_host(environment),
        }
        shims.apply_targeted(environment);
        // Each targeted shim finds the compiler it stands in for through this
        // map, keyed by the name it is invoked under -- the same mechanism the
        // standalone shims use.
        let pins = shims.pins();
        if !pins.is_empty()
            && let Ok(encoded) = serde_json::to_string(&pins)
        {
            environment.insert(PATH_SHIMS_ENV.into(), encoded);
        }
    }

    /// Begin a standalone build's action run and return the environment it
    /// needs.
    ///
    /// The cargo-specific keys -- `RUSTC_WRAPPER`, `HOST_CC`,
    /// `CARGO_INCREMENTAL` -- stay untouched: the build finds its compilers
    /// through the shim directory placed first on `PATH` instead.
    pub async fn begin_exec(
        &self,
        project_root: &Path,
        command: &[String],
        shims: Option<&PathShims>,
        environment: &mut BTreeMap<String, String>,
    ) -> Option<ActionRun> {
        let identity = exec_identity(project_root, command);
        if let Some(events) = &self.events {
            events
                .writer
                .started(project_root, command, Some(&identity));
        }
        // The project root stands in for the target directory: a standalone
        // build owns its output directory, so there is nothing managed to
        // record, but the checkout itself must be known for its objects to
        // count as reachable.
        if let Err(error) =
            crate::store::record_checkout(&self.store, &identity, project_root, project_root)
        {
            warn!("this checkout was not recorded as a cache root: {error}");
        }
        let (protocol_build, action_run) =
            match self.agent.begin_task_on_prediction(&identity).await {
                Ok(run) => (
                    run.clone(),
                    Some(ActionRun {
                        receipt: run.clone(),
                        run,
                        identity: identity.clone(),
                        workspace_root: project_root.to_path_buf(),
                        export_group: std::env::var(CACHE_EXPORT_GROUP_ENV).ok(),
                        store: self.store.clone(),
                        agent: self.agent.clone(),
                        initialized: None,
                    }),
                ),
                Err(error) => {
                    warn!("build action manifest was not loaded: {error}");
                    (identity, None)
                }
            };
        environment.insert(
            WORKSPACE_ROOT_ENV.into(),
            project_root.to_string_lossy().into_owned(),
        );
        environment.insert(SOCKET_ENV.into(), self.socket.clone());
        environment.insert(
            STAGING_ENV.into(),
            self.staging.to_string_lossy().into_owned(),
        );
        environment.insert(BUILD_ENV.into(), protocol_build);
        environment.insert(
            VERIFY_ENV.into(),
            if self.verify { "1" } else { "0" }.into(),
        );
        environment.insert(
            verification::SAMPLE_RATE_ENV.into(),
            self.verify_sample_rate.to_string(),
        );
        environment.insert(
            "TUIST_CARGO_CACHE_CC_STORE_PATH_SPECIFIC".into(),
            if self.cc_store_path_specific {
                "1"
            } else {
                "0"
            }
            .into(),
        );
        for (name, value) in &self.scheduler_env {
            environment.insert(name.clone(), value.clone());
        }
        for (name, value) in &self.gc_env {
            environment.insert(name.clone(), value.clone());
        }
        let Some(shims) = shims else {
            return action_run;
        };
        if let Ok(pins) = serde_json::to_string(&shims.compilers) {
            environment.insert(PATH_SHIMS_ENV.into(), pins);
        }
        // First on PATH, so `make`'s default `cc` and an explicit `CC=gcc`
        // both resolve to a shim, which chains to the compiler pinned above.
        let path = std::env::var_os("PATH").unwrap_or_default();
        let paths = std::iter::once(shims.directory.clone()).chain(std::env::split_paths(&path));
        if let Ok(joined) = std::env::join_paths(paths) {
            environment.insert("PATH".into(), joined.to_string_lossy().into_owned());
        }
        action_run
    }

    /// Add the compiler launchers to a CMake configure `tuist_cargo_cache exec` runs.
    ///
    /// They live beside this binary's own native shims, which a CMake cache
    /// may record, rather than in the shared `PATH` shim directory.
    pub fn prepare_exec_cmake(
        &self,
        program: &OsStr,
        arguments: &mut Vec<OsString>,
        environment: &mut BTreeMap<String, String>,
    ) {
        if let Err(error) =
            cmake::exec_arguments(&self.cmake_shims_dir, program, arguments, environment)
        {
            warn!("CMake compiler launchers are unavailable: {error:#}");
        }
    }

    /// Warm the recorded actions for a Cargo command without running Cargo.
    pub async fn prefetch(&self, workspace_root: &Path, command: &[String]) -> Result<()> {
        let identity = build_identity(workspace_root, command);
        self.offer_earlier_lockfiles(&identity, workspace_root);
        self.agent.prefetch_task(&identity).await?;
        Ok(())
    }

    /// Let a lockfile nobody has built yet inherit the predictions recorded
    /// for the lockfiles before it, found through the file's Git history.
    fn offer_earlier_lockfiles(&self, identity: &str, workspace_root: &Path) {
        let workspace_root = workspace_root.to_path_buf();
        if let Err(error) = self.agent.register_task_fallbacks(identity, move || {
            tuist_cargo_cache_cargo::previous_build_identities(&workspace_root)
        }) {
            debug!("earlier lockfile states were not offered: {error}");
        }
    }

    /// Stop the agent and collect this session's statistics.
    pub async fn finish(&self) -> Result<AgentStats> {
        if let Some(shutdown) = self.shutdown.lock().unwrap().take() {
            let _ = shutdown.send(());
        }
        let server = self.server.lock().unwrap().take();
        // Held rather than raised: the shims have already been told their objects
        // were stored, so a listener that failed is no reason to abandon the
        // uploads that promise implies.
        let served = match server {
            Some(server) => server
                .await
                .map_err(eyre::Report::from)
                .and_then(|served| served),
            None => Ok(()),
        };
        self.agent.cancel_prefetches().await;
        // Cancelling first hands the queue the transfer budget the abandoned
        // downloads were holding.
        self.agent.wait_for_uploads().await;
        served?;
        // Saved after the shims are done and before the summary, so the next
        // session in this checkout starts from everything this one hashed.
        // Best-effort like the ledger itself.
        if let Some(ledger_dir) = self.ledger_dir.lock().unwrap().take() {
            let stamp = self.ledger_stamp.lock().unwrap().take();
            match crate::digest_ledger::save(&ledger_dir, self.agent.file_digests(), stamp) {
                Ok(count) => debug!("file-digest ledger saved with {count} entries"),
                Err(error) => warn!("the file-digest ledger was not saved: {error:#}"),
            }
        }
        self.incremental_leases.lock().unwrap().clear();
        let mut stats = self.agent.stats();
        stats.session_duration_ns = duration_ns(self.started.elapsed());
        // The same totals the summary reports, so a reader of a finished stream
        // does not have to re-derive them from the rows -- and so a stream that
        // hit its row cap still ends with the whole truth.
        if let Some(events) = &self.events
            && let Ok(totals) = serde_json::to_value(StatsReport::from(&stats))
        {
            events.writer.finished(totals);
        }
        Ok(stats)
    }
}

/// Select the rustdoc behind any session shim already present in the caller.
///
/// Integration tests (and nested `tuist_cargo_cache` commands in general) can begin a cache
/// session from inside another one. Chaining the outer rustdoc shim would make
/// it name itself as the real rustdoc and recurse; unwrap it just as the rustc
/// path preserves and explicitly models an existing wrapper.
fn configured_rustdoc(environment: &BTreeMap<String, String>) -> String {
    let configured = environment
        .get("RUSTDOC")
        .cloned()
        .or_else(|| std::env::var("RUSTDOC").ok())
        .unwrap_or_else(|| "rustdoc".into());
    if Path::new(&configured).file_stem() == Some(OsStr::new(RUSTDOC_SHIM_STEM)) {
        environment
            .get(REAL_RUSTDOC_ENV)
            .cloned()
            .or_else(|| std::env::var(REAL_RUSTDOC_ENV).ok())
            .unwrap_or_else(|| "rustdoc".into())
    } else {
        configured
    }
}

impl Drop for CacheSession {
    fn drop(&mut self) {
        if let Some(shutdown) = self.shutdown.get_mut().unwrap().take() {
            let _ = shutdown.send(());
        }
        if let Some(server) = self.server.get_mut().unwrap().take() {
            server.abort();
        }
    }
}

/// Writes the agent's decisions to this session's event stream.
///
/// The translation lives here rather than in the agent because the agent
/// accounts for compilations and has no opinion about who is watching. What it
/// reports as a compiler invocation becomes a miss, an unconsulted compilation,
/// or a verification row, since that is the distinction a reader wants. A
/// bypass the agent paired with its compile becomes one bypass row carrying
/// the crate and compiler time; a bare bypass compile is dropped, because the
/// bypass row already said so.
#[derive(Clone)]
struct EventStream {
    writer: Arc<EventWriter>,
    diagnostics: Arc<Mutex<VecDeque<PendingDiagnostic>>>,
}

struct PendingDiagnostic {
    outcome: String,
    crate_name: Option<String>,
    diagnostic: ActionDiagnostic,
}

impl EventStream {
    fn new(writer: Arc<EventWriter>) -> Self {
        Self {
            writer,
            diagnostics: Arc::new(Mutex::new(VecDeque::new())),
        }
    }

    fn take_diagnostic(&self, outcome: &str, crate_name: Option<&str>) -> Option<ActionDiagnostic> {
        let mut diagnostics = self.diagnostics.lock().unwrap();
        let position = diagnostics.iter().position(|pending| {
            pending.outcome == outcome && pending.crate_name.as_deref() == crate_name
        })?;
        diagnostics
            .remove(position)
            .map(|pending| pending.diagnostic)
    }
}

impl AgentEventObserver for EventStream {
    fn event(&self, event: AgentEvent) {
        match event {
            AgentEvent::WrapperTiming { timing } => self.writer.wrapper_timing(timing),
            AgentEvent::ActionHit {
                crate_name,
                restore,
            } => {
                let diagnostic = self.take_diagnostic("hit", crate_name.as_deref());
                self.writer.action_with_diagnostic(
                    ActionOutcome::Hit,
                    crate_name,
                    restore.duration_ns,
                    ActionDetail {
                        avoided_compiler_ns: restore.avoided_compiler_duration_ns,
                        output_files: restore.output_files,
                        output_bytes: restore.output_bytes,
                        reflinked_output_bytes: restore.reflinked_output_bytes,
                        hardlinked_output_bytes: restore.hardlinked_output_bytes,
                        copied_output_bytes: restore.copied_output_bytes,
                    },
                    diagnostic,
                );
            }
            AgentEvent::Bypass { kind } => self.writer.action(
                ActionOutcome::Bypass { reason: kind },
                None,
                0,
                ActionDetail::default(),
            ),
            AgentEvent::BypassedCompilation {
                kind,
                crate_name,
                duration_ns,
            } => self.writer.action(
                ActionOutcome::Bypass { reason: kind },
                crate_name,
                duration_ns,
                ActionDetail::default(),
            ),
            // Nothing is emitted for the counter itself: the compiler
            // invocation that follows carries the same fact with a crate name
            // and a duration attached, and two rows would double-count it.
            AgentEvent::Unconsulted => {}
            AgentEvent::CompilerInvocation {
                outcome,
                crate_name,
                duration_ns,
            } => {
                let recorded_outcome = match outcome.as_str() {
                    // An incremental compilation reaches the ledger under what
                    // its lookup did. It had no row at all while its outcome
                    // said only that its result was withheld, which is how the
                    // summary and `tuist_cargo_cache explain` came to disagree.
                    "miss" | "incremental-miss" => ActionOutcome::Miss,
                    "unconsulted" | "incremental-unconsulted" => ActionOutcome::Unconsulted,
                    // A verification's own row comes from the verification
                    // event, which knows whether it matched; a bypass already
                    // has one.
                    _ => return,
                };
                let diagnostic = self.take_diagnostic(&outcome, crate_name.as_deref());
                self.writer.action_with_diagnostic(
                    recorded_outcome,
                    crate_name,
                    duration_ns,
                    ActionDetail::default(),
                    diagnostic,
                );
            }
            AgentEvent::Verification { matched, restore } => self.writer.action(
                ActionOutcome::Verification { matched },
                None,
                restore.duration_ns,
                ActionDetail::default(),
            ),
            AgentEvent::ActionDiagnostic {
                outcome,
                crate_name,
                diagnostic,
            } => self
                .diagnostics
                .lock()
                .unwrap()
                .push_back(PendingDiagnostic {
                    outcome,
                    crate_name,
                    diagnostic,
                }),
            // A decision this build does not know how to describe is left out
            // rather than guessed at; the totals still count it.
            _ => {}
        }
    }
}

/// An in-flight build's completed action manifest.
pub struct ActionRun {
    run: String,
    receipt: String,
    identity: String,
    workspace_root: PathBuf,
    export_group: Option<String>,
    store: PathBuf,
    agent: CacheAgent,
    initialized: Option<Arc<SessionTask>>,
}

impl ActionRun {
    pub async fn commit(self) -> Result<()> {
        if self.initialized.as_ref().is_some_and(|task| {
            !task.connected.load(std::sync::atomic::Ordering::Relaxed)
                || task.initialized.get() != Some(&true)
        }) {
            return Ok(());
        }
        let predictions = self.agent.commit_task_actions(&self.run).await?;
        // A build that predicted nothing new has nothing to export that the
        // receipt before it did not already name, so that receipt stands. A
        // grouped export still gets its receipt: the group is the record of
        // which runs took part.
        if predictions.is_empty() && self.export_group.is_none() {
            return Ok(());
        }
        crate::store::record_build_receipt(
            &self.store,
            &self.receipt,
            &self.identity,
            &self.workspace_root,
            self.export_group.as_deref(),
            predictions,
        )
    }
}

/// A unique receipt name for one invocation of a stable Cargo task.
fn build_receipt_run(identity: &str) -> String {
    CacheDigest::blake3(
        format!(
            "{identity}\0{}\0{}",
            std::process::id(),
            crate::util::random_string(12)
        )
        .as_bytes(),
    )
    .hash
}

/// Identity for this build's prefetch manifest.
///
/// Manifests are namespaced by identity, so this only affects how well one
/// build can predict another's actions; action keys themselves are independent
/// of it.
pub fn build_identity(workspace_root: &Path, command: &[String]) -> String {
    tuist_cargo_cache_cargo::build_identity(workspace_root, command)
}

/// Identity material for a standalone build's prediction manifest.
///
/// Its own record rather than a reuse of the Cargo one: the two identity
/// spaces must not collide, and the Cargo crate keeps its material private
/// precisely so its scheme can evolve for Cargo's own reasons.
#[derive(Serialize)]
struct ExecIdentity<'a> {
    version: u8,
    project: &'a str,
    command: &'a [String],
    os: &'static str,
    arch: &'static str,
}

/// Identity of a standalone build: the project and the command it runs.
///
/// Worktrees of one project must share a manifest for predictions to travel --
/// the cc adapter has no second way to build a key -- so the marker prefers
/// content and origin over location: a `Cargo.lock` digest where one exists,
/// then the Git or Jujutsu origin URL, and only then the directory name.
pub fn exec_identity(project_root: &Path, command: &[String]) -> String {
    let project = exec_marker(project_root);
    let material = ExecIdentity {
        version: 2,
        project: &project,
        command,
        os: std::env::consts::OS,
        arch: std::env::consts::ARCH,
    };
    let bytes = canonical_json(&material).expect("exec identity must serialize");
    CacheDigest::blake3(&bytes).hash
}

fn exec_marker(project_root: &Path) -> String {
    if let Ok(lock) = std::fs::read(project_root.join("Cargo.lock")) {
        return CacheDigest::blake3(&lock).hash;
    }
    if let Some(origin) = project_origin_marker(project_root) {
        return origin;
    }
    project_root
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned()
}

/// The origin URL names a project the same way in every worktree and clone,
/// which a checkout's directory name does not. Try Git first for colocated
/// repositories so they keep exactly the identity they had before.
fn project_origin_marker(project_root: &Path) -> Option<String> {
    if !project_root.join(".git").exists() {
        if project_root.join(".jj").exists() {
            return jj_origin_marker(project_root);
        }
        if project_root.join(".sl").exists() {
            return sapling_origin_marker(project_root);
        }
        if project_root.join(".hg").exists() {
            return mercurial_origin_marker(project_root);
        }
    }
    git_origin_marker(project_root)
        .or_else(|| jj_origin_marker(project_root))
        .or_else(|| sapling_origin_marker(project_root))
        .or_else(|| mercurial_origin_marker(project_root))
}

/// Read Git's origin without imposing a repository layout on explicit roots.
fn git_origin_marker(project_root: &Path) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(project_root)
        .args(["config", "--get", "remote.origin.url"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    origin_marker_from_output(&output.stdout)
}

/// Read Jujutsu's origin only from a root that is itself a Jujutsu checkout.
fn jj_origin_marker(project_root: &Path) -> Option<String> {
    // Without this gate `jj -R` may discover an unrelated enclosing checkout.
    if !project_root.join(".jj").exists() {
        return None;
    }
    let output = Command::new("jj")
        .arg("-R")
        .arg(project_root)
        .arg("--ignore-working-copy")
        .args(["git", "remote", "list"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let remotes = String::from_utf8_lossy(&output.stdout);
    let url = jj_origin_url(&remotes)?;
    Some(format!("origin\0{url}"))
}

/// Extract the fetch URL for the conventionally named origin remote.
fn jj_origin_url(remotes: &str) -> Option<&str> {
    remotes.lines().find_map(|line| {
        let mut fields = line.split_whitespace();
        if fields.next()? == "origin" {
            fields.next()
        } else {
            None
        }
    })
}

/// Read the default source from a native Sapling checkout.
fn sapling_origin_marker(project_root: &Path) -> Option<String> {
    default_path_origin_marker("sl", project_root, &["config", "paths.default"], ".sl")
}

/// Read the default source from a Mercurial checkout.
fn mercurial_origin_marker(project_root: &Path) -> Option<String> {
    default_path_origin_marker("hg", project_root, &["paths", "default"], ".hg")
}

fn default_path_origin_marker(
    program: &str,
    project_root: &Path,
    arguments: &[&str],
    marker: &str,
) -> Option<String> {
    // Without this gate the command may discover an unrelated enclosing
    // checkout, just as Jujutsu would.
    if !project_root.join(marker).exists() {
        return None;
    }
    let output = Command::new(program)
        .arg("-R")
        .arg(project_root)
        .args(arguments)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    origin_marker_from_output(&output.stdout)
}

fn origin_marker_from_output(output: &[u8]) -> Option<String> {
    let url = String::from_utf8_lossy(output).trim().to_string();
    (!url.is_empty()).then(|| format!("origin\0{url}"))
}

async fn action_remote_cache(config: &Config, store: &Path) -> Result<Option<AgentRemoteCache>> {
    let Some(client) = crate::remote::remote_client(config).await? else {
        return Ok(None);
    };
    let Some(mode) = crate::policy::effective_remote_cache_mode(config.remote.mode) else {
        return Ok(None);
    };
    Ok(Some(AgentRemoteCache {
        client,
        mode,
        staging_dir: store.join("remote"),
    }))
}

/// Whether this process was invoked as the rustc shim.
pub fn is_rustc_shim() -> bool {
    std::env::args_os()
        .next()
        .as_deref()
        .map(Path::new)
        .and_then(Path::file_stem)
        .is_some_and(|stem| stem == OsStr::new(RUSTC_SHIM_STEM))
}

/// Whether this process was invoked as the rustdoc shim.
pub fn is_rustdoc_shim() -> bool {
    std::env::args_os()
        .next()
        .as_deref()
        .map(Path::new)
        .and_then(Path::file_stem)
        .is_some_and(|stem| stem == OsStr::new(RUSTDOC_SHIM_STEM))
}

/// Ultra-early argv0 path used by Cargo's `RUSTDOC` integration.
pub fn run_rustdoc_shim() -> ExitCode {
    let rustdoc = std::env::var_os(REAL_RUSTDOC_ENV).unwrap_or_else(|| "rustdoc".into());
    let arguments = std::env::args_os().skip(1).collect::<Vec<_>>();
    match crate::rustdoc::document(&rustdoc, &arguments) {
        Ok(code) => code,
        Err(_error) => {
            let _ = request_agent(&[AgentRequest::RecordBypass {
                kind: "rustdoc".into(),
            }]);
            #[cfg(debug_assertions)]
            eprintln!("tuist_cargo_cache[warning]: rustdoc cache bypassed: {_error:#}");
            run_transparent_rustdoc(rustdoc, arguments)
        }
    }
}

fn run_transparent_rustdoc(rustdoc: OsString, arguments: Vec<OsString>) -> ExitCode {
    let status = Command::new(&rustdoc).args(arguments).status();
    match status {
        Ok(status) => ExitCode::from(u8::try_from(status.code().unwrap_or(1)).unwrap_or(1)),
        Err(error) => {
            eprintln!(
                "tuist_cargo_cache[error]: the rustdoc shim failed to execute rustdoc: {error}"
            );
            ExitCode::FAILURE
        }
    }
}

/// Whether this process replaced a Cargo build-script executable.
pub fn is_build_script_shim() -> bool {
    let Some(invoked) = build_script_invocation_path() else {
        return false;
    };
    is_build_script_executable(&invoked) && find_build_script_real_path(&invoked).is_some()
}

/// Cargo runs a build script as `build-script-<stem>`, where `<stem>` names
/// its source file: `build-script-build` for `build.rs`.
fn is_build_script_executable(path: &Path) -> bool {
    build_script_crate_name(path).is_some()
}

/// The crate name rustc compiled a build-script executable under.
fn build_script_crate_name(path: &Path) -> Option<String> {
    let stem = path.file_stem()?.to_str()?;
    let target = stem
        .strip_prefix("build-script-")
        .or_else(|| stem.strip_prefix("build_script_"))
        .filter(|target| !target.is_empty())?;
    Some(format!("build_script_{}", target.replace('-', "_")))
}

pub(crate) fn build_script_invocation_path() -> Option<PathBuf> {
    std::env::var_os(BUILD_SCRIPT_SHIM_PATH_ENV)
        .map(PathBuf::from)
        .or_else(|| std::env::args_os().next().map(PathBuf::from))
}

pub(crate) fn build_script_real_path(executable: &Path) -> PathBuf {
    let mut name = executable.as_os_str().to_os_string();
    name.push(BUILD_SCRIPT_REAL_SUFFIX);
    PathBuf::from(name)
}

pub(crate) fn build_script_execution_requested() -> bool {
    std::env::var_os(BUILD_SCRIPT_EXECUTION_ENV)
        .is_some_and(|value| !value.is_empty() && value != "0")
}

/// Locate the preserved binary. Cargo runs an un-hashed hard link named
/// `build-script-build`, while rustc produced and tuist_cargo_cache wrapped the hashed
/// `build_script_build-<unit>` sibling.
pub(crate) fn find_build_script_real_path(executable: &Path) -> Option<PathBuf> {
    let direct = build_script_real_path(executable);
    if direct.is_file() {
        return Some(direct);
    }
    let prefix = format!("{}-", build_script_crate_name(executable)?);
    let parent = executable.parent()?;
    let mut matches = std::fs::read_dir(parent)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_file()
                && path
                    .file_name()
                    .and_then(OsStr::to_str)
                    .is_some_and(|name| {
                        name.starts_with(&prefix) && name.ends_with(BUILD_SCRIPT_REAL_SUFFIX)
                    })
        });
    let found = matches.next()?;
    matches.next().is_none().then_some(found)
}

/// Run Cargo's build script through the execution cache.
pub fn run_build_script_shim() -> ExitCode {
    // The wrapper lives in Cargo's target directory, so it can outlive the tuist_cargo_cache
    // session that installed it. A later plain `cargo` invocation must remain
    // a transparent build-script call.
    if session_socket().is_none() || !build_script_execution_requested() {
        return crate::build_script::run_real();
    }
    let _timing = crate::build_script::start_timing();
    match crate::build_script::run() {
        Ok(code) => code,
        Err(error) => {
            report_shim_warning(&format!("build-script cache bypassed: {error:#}"));
            crate::build_script::run_real()
        }
    }
}

/// Compiler names the standalone shim directory stands in for, and the
/// language each name selects.
///
/// Only the plain platform drivers: a versioned name such as `gcc-13` was
/// chosen deliberately by the build, and a compiler chosen that specifically
/// is one this table should not silently intercept.
const PATH_SHIM_NAMES: &[(&str, CcLanguage)] = &[
    ("cc", CcLanguage::C),
    ("gcc", CcLanguage::C),
    ("clang", CcLanguage::C),
    ("c++", CcLanguage::Cxx),
    ("g++", CcLanguage::Cxx),
    ("clang++", CcLanguage::Cxx),
    ("cl.exe", CcLanguage::Cxx),
];

/// The language a standalone shim name selects, if the name is one.
fn path_shim_language(name: &str) -> Option<CcLanguage> {
    PATH_SHIM_NAMES
        .iter()
        .find(|(shim, _)| *shim == name)
        .map(|(_, language)| *language)
}

/// Which compiler this process was invoked as a shim for, if any.
pub fn is_cc_shim() -> Option<CcLanguage> {
    let stem = std::env::args_os()
        .next()
        .as_deref()
        .map(Path::new)
        .and_then(Path::file_stem)?
        .to_str()?
        .to_string();
    cc_shim_language(&stem)
}

/// The language a shim file stem selects, if it is one tuist_cargo_cache installs.
fn cc_shim_language(stem: &str) -> Option<CcLanguage> {
    match stem {
        CC_SHIM_STEM | LEGACY_CC_SHIM_STEM => Some(CcLanguage::C),
        CXX_SHIM_STEM => Some(CcLanguage::Cxx),
        "cl" if cfg!(windows) => Some(CcLanguage::Cxx),
        // `tuist_cargo_cache-cxx-...` is tested first: neither `tuist_cargo_cache-c-` nor `tuist_cargo_cache-cc-` is a
        // prefix of it, but reading it the other way round invites the mistake.
        other if other.starts_with(&format!("{CXX_SHIM_STEM}-")) => Some(CcLanguage::Cxx),
        other
            if other.starts_with(&format!("{CC_SHIM_STEM}-"))
                || other.starts_with(&format!("{LEGACY_CC_SHIM_STEM}-")) =>
        {
            Some(CcLanguage::C)
        }
        other => path_shim_language(other),
    }
}

/// How a targeted C shim's name was spelled before [`CC_SHIM_STEM`] changed.
///
/// A targeted shim finds the cross compiler it stands in for by looking its own
/// invocation name up in the pin map, so a build still invoking the old name
/// has to reach the same entry. A miss would not fail that build: it would fall
/// through to `TUIST_CARGO_CACHE_REAL_CC` and compile the cross target's objects with the
/// host compiler.
///
/// The trailing hyphen is what makes the prefix safe to strip. `tuist_cargo_cache-c` on its
/// own is a prefix of `tuist_cargo_cache-cxx`; `tuist_cargo_cache-c-` is a prefix of no C++ shim name.
fn legacy_cc_shim_name(name: &str) -> Option<String> {
    let rest = name.strip_prefix(&format!("{CC_SHIM_STEM}-"))?;
    Some(format!("{LEGACY_CC_SHIM_STEM}-{rest}"))
}

/// The file name this process was invoked under.
fn shim_invocation_name() -> Option<String> {
    std::env::args_os()
        .next()
        .as_deref()
        .map(Path::new)
        .and_then(Path::file_name)?
        .to_str()
        .map(ToOwned::to_owned)
}

/// Ultra-early argv0 path used by the `CC` and `CXX` build scripts inherit.
///
/// Unlike `RUSTC_WRAPPER`, there is no convention that hands the shim the real
/// compiler: the build script calls `$CC` and every argument is the
/// compilation's own. The compiler to run therefore arrives out of band, and a
/// shim that cannot find one falls back to the platform default rather than
/// failing a build it was only meant to observe.
pub fn run_cc_shim(language: CcLanguage) -> ExitCode {
    // From here on, stderr carries only what the real compiler would have
    // written: build scripts probe compilers by running them and reading that
    // stream, and a diagnostic mixed into it changes what they decide.
    reserve_stderr_for_compiler();
    let arguments = std::env::args_os().skip(1).collect::<Vec<_>>();
    let compiler = match real_compiler(language) {
        Ok(compiler) => compiler,
        Err(error) => {
            eprintln!(
                "tuist_cargo_cache[error]: the {} shim found no compiler to run: {error:#}",
                language.shim_stem()
            );
            return ExitCode::from(1);
        }
    };
    // A shim reached outside a session has no agent to ask, and this is the
    // ordinary way a persisted compiler path is invoked: a build configured
    // under `tuist_cargo_cache exec` and then built without it. Stand aside before probing
    // anything, so that costs one exec rather than a compiler query first.
    if session_socket().is_none() {
        return run_transparent_cc(compiler, arguments);
    }
    match crate::cc::compile(&compiler, &arguments, language) {
        Ok(exit_code) => return exit_code,
        Err(error) => {
            record_cc_bypass(&error);
        }
    }
    run_transparent_cc(compiler, arguments)
}

/// The compiler a cc shim stands in for.
///
/// The session pins this when it installs the shims: `tuist_cargo_cache exec` pins every
/// name it placed on `PATH`, and a cargo session pins the pair build scripts
/// inherit. A shim invoked with no pin searches `PATH` for the name it was
/// invoked under, skipping any candidate that is this binary, so an inherited
/// `CC` or a stale shim directory cannot make the shim call itself.
fn real_compiler(language: CcLanguage) -> Result<OsString> {
    let invoked = shim_invocation_name();
    if let Some(name) = invoked.as_deref()
        && let Some(compiler) = pinned_path_shim(name)
    {
        return Ok(compiler.into_os_string());
    }
    let pinned = match language {
        CcLanguage::C => REAL_CC_ENV,
        CcLanguage::Cxx => REAL_CXX_ENV,
    };
    if let Some(compiler) = std::env::var_os(pinned).filter(|value| !value.is_empty()) {
        return Ok(compiler);
    }
    // A shim named after a real driver stands in for exactly that driver; the
    // session shim names have no driver of their own and fall back to the
    // platform default.
    let name = invoked
        .as_deref()
        .filter(|name| path_shim_language(name).is_some())
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| language.default_driver().to_string());
    let current = std::env::current_exe().ok();
    let path = std::env::var_os("PATH").unwrap_or_default();
    for directory in std::env::split_paths(&path) {
        // `tuist_cargo_cache exec` puts its own shim directory first on `PATH`, so identity
        // alone leaves two installations picking each other's shims and
        // handing the compilation back and forth until the box runs out of
        // processes. A marked directory holds shims whoever wrote it.
        if is_shim_directory(&directory) {
            continue;
        }
        let candidate = directory.join(&name);
        if !candidate.is_file() || is_same_binary(&candidate, current.as_deref()) {
            continue;
        }
        return Ok(candidate.into_os_string());
    }
    eyre::bail!("no {name} was found on PATH")
}

/// The compiler an exec session pinned for this shim name, if any.
fn pinned_path_shim(name: &str) -> Option<PathBuf> {
    let pins = std::env::var(PATH_SHIMS_ENV).ok()?;
    let pins: BTreeMap<String, PathBuf> = serde_json::from_str(&pins).ok()?;
    let compiler = pins.get(name)?;
    pin_names_a_compiler(compiler, std::env::current_exe().ok().as_deref())
        .then(|| compiler.clone())
}

/// Whether a recorded pin names something other than a shim.
///
/// An older tuist_cargo_cache recorded these pins, or this one did before shim directories
/// were marked. A pin naming a shim would make this shim stand in for itself,
/// so the caller falls through to the `PATH` search rather than running it.
fn pin_names_a_compiler(compiler: &Path, current: Option<&Path>) -> bool {
    !is_same_binary(compiler, current) && !compiler.parent().is_some_and(is_shim_directory)
}

/// Whether `candidate` is the running tuist_cargo_cache binary under another name.
///
/// Shims are hard links, so a path comparison alone cannot recognize one that
/// lives in a different directory -- a stale shim directory an outer session
/// left on `PATH`, say. Device and inode identify the file itself.
fn is_same_binary(candidate: &Path, current: Option<&Path>) -> bool {
    let Some(current) = current else {
        return false;
    };
    let resolved = std::fs::canonicalize(candidate).unwrap_or_else(|_| candidate.to_path_buf());
    let current_resolved = std::fs::canonicalize(current)
        .ok()
        .unwrap_or_else(|| current.to_path_buf());
    if resolved == current_resolved {
        return true;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt as _;
        if let (Ok(a), Ok(b)) = (std::fs::metadata(&resolved), std::fs::metadata(current)) {
            return a.dev() == b.dev() && a.ino() == b.ino();
        }
    }
    false
}

fn run_transparent_cc(compiler: OsString, arguments: Vec<OsString>) -> ExitCode {
    let mut command = Command::new(&compiler);
    command.args(&arguments);

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt as _;

        let error = command.exec();
        eprintln!("tuist_cargo_cache[error]: the cc shim failed to execute {compiler:?}: {error}");
        ExitCode::from(1)
    }
    #[cfg(not(unix))]
    {
        match command.status() {
            Ok(status) => ExitCode::from(u8::try_from(status.code().unwrap_or(1)).unwrap_or(1)),
            Err(error) => {
                eprintln!(
                    "tuist_cargo_cache[error]: the cc shim failed to execute {compiler:?}: {error}"
                );
                ExitCode::from(1)
            }
        }
    }
}

/// Ultra-early argv0 path used by cargo's `RUSTC_WRAPPER` integration.
///
/// Cargo invokes this thousands of times per build, so it runs before any
/// runtime, logging, or configuration is set up. Cacheable invocations restore
/// from or publish through the cache; anything else is a transparent compiler
/// call.
pub fn run_rustc_shim() -> ExitCode {
    // Cargo captures the wrapper's stderr as compiler output. Keep tuist_cargo_cache's own
    // diagnostics out of that stream; the session agent owns their display.
    reserve_stderr_for_compiler();
    let mut arguments = std::env::args_os().skip(1);
    let Some(rustc) = arguments.next() else {
        report_shim_error("the rustc shim expected the rustc executable as its first argument");
        return ExitCode::from(1);
    };
    let mut arguments = arguments.collect::<Vec<_>>();
    if let Ok(selections) = std::env::var(MANAGED_TARGET_LINKERS_ENV)
        && let Ok(selections) = serde_json::from_str::<BTreeMap<String, PathBuf>>(&selections)
        && let Some(linker) = target_linker(&arguments, &selections)
    {
        use_managed_linker(&mut arguments, linker.as_os_str());
    }
    if let Some(linker) = std::env::var_os(MANAGED_LINKER_ENV).filter(|path| !path.is_empty()) {
        use_managed_linker(&mut arguments, &linker);
    }
    let is_workspace_wrapper = std::env::var_os(PREVIOUS_RUSTC_WORKSPACE_WRAPPER_ENV)
        .is_some_and(|wrapper| wrapper == rustc);
    let (wrapper_argument, compiler_arguments) = workspace_wrapper_arguments(&rustc, &arguments);
    let cacheable_workspace_wrapper = is_workspace_wrapper && wrapper_argument.is_some();
    // Cargo moves long argument lists into `@argfile`s; the flags that name
    // and describe the compilation are inside them then. rustc still receives
    // the arguments as they were given.
    let described = tuist_cargo_cache_rustc::RustcInvocation::expand_arguments(&arguments)
        .unwrap_or_else(|_| arguments.clone());
    // Held here rather than inside the cache attempt so that a compilation
    // that bypasses is timed through its compiler run as well.
    let _timing = crate::phase_timing::start("rustc", crate_name_argument(&described));
    let out_dir = std::env::var_os("OUT_DIR").map(PathBuf::from);
    let (unit_id, dependencies) = crate::unit_graph::rustc_unit(&described, out_dir.as_deref());
    crate::phase_timing::identify(unit_id, dependencies);
    if std::env::var_os(PREVIOUS_RUSTC_WRAPPER_ENV).is_none()
        && (!is_workspace_wrapper || cacheable_workspace_wrapper)
    {
        // Cargo composes RUSTC_WRAPPER outside RUSTC_WORKSPACE_WRAPPER. Clippy
        // occupies the latter, so its wrapper protocol arrives here as
        // `clippy-driver <real-rustc> <rustc arguments>`. The real rustc path
        // must still be passed to the driver when it executes, but it is not a
        // source input and must not be handed to the rustc argument parser.
        match crate::rustc::compile(&rustc, compiler_arguments, wrapper_argument) {
            Ok(exit_code) => return exit_code,
            Err(error) => {
                record_bypass(&error);
            }
        }
    }

    run_transparent_rustc(rustc, arguments, &described)
}

/// Explicit Cargo targets must not affect host build scripts or proc macros.
fn target_linker<'a>(
    arguments: &[OsString],
    selections: &'a BTreeMap<String, PathBuf>,
) -> Option<&'a PathBuf> {
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        let target = if argument == "--target" {
            arguments.next().and_then(|value| value.to_str())
        } else {
            argument
                .to_str()
                .and_then(|value| value.strip_prefix("--target="))
        };
        if let Some(target) = target {
            return selections.get(target).or_else(|| {
                // Cargo versions can pass JSON paths without Windows' verbatim
                // prefix. Canonicalize both spellings to the stored routing key.
                if !target.ends_with(".json") {
                    return None;
                }
                let canonical = std::fs::canonicalize(target).ok()?;
                selections.get(canonical.to_str()?)
            });
        }
    }
    None
}

/// Route native links through the selected executable while leaving metadata
/// queries and `cargo check` byte-for-byte unchanged.
fn use_managed_linker(arguments: &mut Vec<OsString>, linker: &OsStr) {
    if links_natively(arguments) {
        arguments.push("-Clinker=clang".into());
        arguments.push(format!("-Clink-arg=-fuse-ld={}", Path::new(linker).display()).into());
    }
}

fn workspace_wrapper_arguments<'a>(
    compiler: &OsStr,
    arguments: &'a [OsString],
) -> (Option<&'a OsStr>, &'a [OsString]) {
    let wrapper_argument = arguments.first().filter(|argument| {
        executable_stem(compiler) == Some("clippy-driver")
            && executable_stem(argument) == Some("rustc")
    });
    match wrapper_argument {
        Some(argument) => (Some(argument.as_os_str()), &arguments[1..]),
        None => (None, arguments),
    }
}

fn executable_stem(executable: &OsStr) -> Option<&str> {
    Path::new(executable).file_stem()?.to_str()
}

/// Run the compiler without caching. `described` is `arguments` with any
/// `@argfile` expanded, which is where to look for what is being compiled;
/// rustc itself is given `arguments` unchanged.
fn run_transparent_rustc(
    rustc: OsString,
    arguments: Vec<OsString>,
    described: &[OsString],
) -> ExitCode {
    // The compiler below may replace this process, and with it any lease on
    // a stable `OUT_DIR`; it compiles against Cargo's own tree instead.
    crate::out_dir::restore();
    let crate_name = crate_name_argument(described);
    // A bypassed compilation is still a real compiler process the machine has
    // to pay for. Probe invocations pass through unscheduled: cargo runs them
    // to learn about the compiler before it plans anything, so making one wait
    // for a permit would stall a build's startup behind its siblings' permits.
    // Most probes carry no --crate-name; the target-info queries carry the
    // placeholder name `___` alongside `--print`, and compile nothing.
    let is_query = described.iter().any(|argument| {
        argument == "-"
            || argument
                .to_str()
                .is_some_and(|argument| argument.starts_with("--print"))
    });
    let demand = crate_name.as_deref().filter(|_| !is_query).map(|name| {
        crate::scheduler::Demand::new(name, links_natively(described)).with_link_profile(described)
    });
    let permit = demand
        .as_ref()
        .and_then(|demand| crate::scheduler::pool().and_then(|pool| pool.admit(demand)));
    // Started after admission, matching the cached paths: waiting for the
    // machine is not time this compilation cost, and reporting it as compiler
    // time would make the jobs that wait longest -- bypassed links -- look
    // like the slowest crates in the build.
    let started = Instant::now();
    let mut command = if let Some(wrapper) = std::env::var_os(PREVIOUS_RUSTC_WRAPPER_ENV) {
        let mut command = Command::new(wrapper);
        command.arg(&rustc);
        command
    } else {
        Command::new(&rustc)
    };
    command.args(&arguments);
    command.env_remove(PREVIOUS_RUSTC_WRAPPER_ENV);
    command.env_remove(PREVIOUS_RUSTC_WORKSPACE_WRAPPER_ENV);
    #[cfg(unix)]
    let eligible = permit.is_some()
        && std::env::var_os(PREVIOUS_RUSTC_WRAPPER_ENV).is_none()
        && std::env::var_os(PREVIOUS_RUSTC_WORKSPACE_WRAPPER_ENV).is_none()
        && crate_name
            .as_deref()
            .is_some_and(|name| !name.starts_with("build_script_"));
    #[cfg(unix)]
    let mut action = crate::supervision::prepare(&mut command, eligible);

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt as _;

        // A probe compiles nothing worth timing, so this process can become
        // the compiler. A real compilation is waited for even without a
        // permit, so that its time is recorded.
        if demand.is_none() {
            crate::phase_timing::finish();
            let error = command.exec();
            report_shim_error(&format!("the rustc shim failed to execute rustc: {error}"));
            return ExitCode::from(1);
        }
        if std::env::var_os("TUIST_CARGO_SESSION").is_some() {
            let compiler = crate::phase_timing::phase("compiler");
            let output = crate::tuist_observer::bypass_output(&mut command, action);
            drop(compiler);
            return match output {
                Ok(output) => {
                    let elapsed = started.elapsed();
                    let epoch = std::time::SystemTime::now()
                        .checked_sub(elapsed)
                        .unwrap_or(std::time::SystemTime::now());
                    crate::tuist_observer::record_command(
                        &command,
                        epoch,
                        elapsed,
                        output.status.success(),
                        &output.stderr,
                    );
                    drop(permit);
                    if let Some(demand) = &demand {
                        crate::scheduler::record_compiler_memory(demand, &output.status);
                    }
                    record_compiler_invocation(
                        "bypass",
                        crate_name.as_deref(),
                        duration_ns(elapsed),
                    );
                    crate::materialize::exit_code(output.status)
                }
                Err(error) => {
                    report_shim_error(&format!("the rustc shim failed to execute rustc: {error}"));
                    ExitCode::from(1)
                }
            };
        }
        // A held permit must be released when the compiler finishes, and its
        // lease lock is close-on-exec, so this process has to outlive the
        // compiler rather than become it.
        let compiler = crate::phase_timing::phase("compiler");
        let waited = command.spawn().and_then(|mut child| {
            if let Some(action) = &mut action {
                action.started();
            }
            child.wait()
        });
        drop(compiler);
        match waited {
            Ok(status) => {
                let elapsed = started.elapsed();
                let epoch = std::time::SystemTime::now()
                    .checked_sub(elapsed)
                    .unwrap_or(std::time::SystemTime::now());
                crate::tuist_observer::record(described, epoch, elapsed, status.success(), &[]);
                drop(permit);
                if let Some(demand) = &demand {
                    crate::scheduler::record_compiler_memory(demand, &status);
                }
                record_compiler_invocation(
                    "bypass",
                    crate_name.as_deref(),
                    duration_ns(started.elapsed()),
                );
                crate::materialize::exit_code(status)
            }
            Err(error) => {
                report_shim_error(&format!("the rustc shim failed to execute rustc: {error}"));
                ExitCode::from(1)
            }
        }
    }
    #[cfg(windows)]
    {
        use std::os::windows::io::AsRawHandle as _;
        use windows_sys::Win32::System::Threading::GetExitCodeProcess;

        let compiler = crate::phase_timing::phase("compiler");
        let waited = command.spawn().and_then(|mut child| {
            let status = child.wait()?;
            let mut exit_code = 1;
            // SAFETY: the child owns a valid process handle until it is
            // dropped, and `exit_code` is a valid out pointer.
            if unsafe { GetExitCodeProcess(child.as_raw_handle().cast(), &raw mut exit_code) } == 0
            {
                Err(std::io::Error::last_os_error())
            } else {
                Ok((exit_code, status))
            }
        });
        drop(compiler);
        match waited {
            Ok((exit_code, status)) => {
                drop(permit);
                if let Some(demand) = &demand {
                    crate::scheduler::record_compiler_memory(demand, &status);
                }
                record_compiler_invocation(
                    "bypass",
                    crate_name.as_deref(),
                    duration_ns(started.elapsed()),
                );
                // ExitProcess skips Rust destructors, including the timer.
                crate::phase_timing::finish();
                // SAFETY: This process is only a transparent compiler wrapper.
                // ExitProcess is required to preserve Windows exception codes,
                // which cannot be represented by stable Rust's ExitCode API.
                unsafe { windows_sys::Win32::System::Threading::ExitProcess(exit_code) }
            }
            Err(error) => {
                report_shim_error(&format!("the rustc shim failed to execute rustc: {error}"));
                ExitCode::from(1)
            }
        }
    }
}

/// Whether a bypassed invocation will run a linker.
///
/// Read off the raw arguments because there is no parsed invocation here:
/// this is the path a compilation takes when the cache could not model it,
/// and a link tuist_cargo_cache cannot describe exactly -- an unidentifiable linker, a
/// native library, a flag that would embed this checkout -- still lands here.
/// They are also the compilations that run a machine out of memory, so the
/// scheduler has to recognize one without the parser's help.
///
/// A test harness links a program whatever its crate type says, which is why
/// `--test` counts on its own -- but only once the emit says a linker runs at
/// all. `cargo check` and `clippy --all-targets` compile those very same
/// binary and test targets with `--emit=metadata`, and charging a check the
/// link weight would make the cheapest stage the heaviest thing queued.
fn links_natively(arguments: &[OsString]) -> bool {
    let mut produces_program = false;
    // No `--emit` at all is rustc's default, which is `link`. Cargo always
    // passes one; something driving rustc by hand may not.
    let mut emits_link = true;
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        let Some(argument) = argument.to_str() else {
            continue;
        };
        if argument == "--test" {
            produces_program = true;
        }
        let kinds = if argument == "--crate-type" {
            arguments.next().and_then(|kinds| kinds.to_str())
        } else {
            argument.strip_prefix("--crate-type=")
        };
        // rustc accepts them comma-separated, and any one of them links.
        if kinds.is_some_and(|kinds| {
            kinds.split(',').any(|kind| {
                matches!(
                    kind,
                    "bin" | "cdylib" | "dylib" | "proc-macro" | "staticlib"
                )
            })
        }) {
            produces_program = true;
        }
        let emits = if argument == "--emit" {
            arguments.next().and_then(|emits| emits.to_str())
        } else {
            argument.strip_prefix("--emit=")
        };
        if let Some(emits) = emits {
            // Each kind may carry a path of its own, as `link=/some/where`.
            emits_link = emits
                .split(',')
                .any(|emit| emit.split('=').next() == Some("link"));
        }
    }
    produces_program && emits_link
}

pub(crate) fn crate_name_argument(arguments: &[OsString]) -> Option<String> {
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        if argument == "--crate-name" {
            return arguments
                .next()
                .and_then(|name| name.to_str())
                .map(str::to_string);
        }
        if let Some(argument) = argument.to_str()
            && let Some(name) = argument.strip_prefix("--crate-name=")
        {
            return Some(name.to_string());
        }
    }
    None
}

/// Whether this rustc invocation compiles a Cargo build script named
/// `crate_name`.
///
/// A `[[bin]]` target can share a build script's crate name, but Cargo sets
/// `CARGO_BIN_NAME` for every binary target and never for a build script.
pub(crate) fn is_cargo_build_script(crate_name: &str) -> bool {
    tuist_cargo_cache_rustc::is_build_script_crate_name(crate_name)
        && std::env::var_os("CARGO_BIN_NAME").is_none()
}

/// Whether every `--crate-type` rustc was given is `bin`, as Cargo gives a
/// build script. A library can share a build script's crate name, but never
/// its crate type.
pub(crate) fn compiles_only_a_binary(arguments: &[OsString]) -> bool {
    let mut types = Vec::new();
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        let value = if argument == "--crate-type" {
            arguments.next().and_then(|value| value.to_str())
        } else {
            argument
                .to_str()
                .and_then(|argument| argument.strip_prefix("--crate-type="))
        };
        if let Some(value) = value {
            types.extend(value.split(','));
        }
    }
    !types.is_empty() && types.iter().all(|kind| *kind == "bin")
}

/// Whether the shim should verify cached results against a real compilation.
///
/// An empty value or `0` is off, matching how the configuration reads it, so
/// that an explicit disable cannot be mistaken for an enable.
pub(crate) fn verify_requested() -> bool {
    verification::requested()
}

/// The session file-digest ledger, answered by the cache agent.
///
/// Both directions are best-effort: a lookup that cannot reach the agent
/// reports misses and the caller hashes as it always did, and a record that
/// fails is dropped -- the ledger is a shortcut, never a dependency.
struct AgentFileDigestCache;

impl FileDigestCache for AgentFileDigestCache {
    fn resolve(
        &self,
        scope: FileDigestScope,
        files: &[FileIdentity],
    ) -> Vec<tuist_cargo_cache_core::FileDigestResolution> {
        if files.is_empty() {
            return Vec::new();
        }
        let response = request_agent(&[AgentRequest::ResolveFileDigests {
            scope,
            files: files.to_vec(),
        }]);
        match response.map(|responses| responses.into_iter().next()) {
            Ok(Some(AgentResponse::FileDigestsResolved { resolutions }))
                if resolutions.len() == files.len() =>
            {
                resolutions
            }
            _ => vec![tuist_cargo_cache_core::FileDigestResolution::Unresolved; files.len()],
        }
    }

    fn find(&self, scope: FileDigestScope, files: &[FileIdentity]) -> Vec<Option<CacheDigest>> {
        if files.is_empty() {
            return Vec::new();
        }
        let response = request_agent(&[AgentRequest::FindFileDigests {
            scope,
            files: files.to_vec(),
        }]);
        match response.map(|responses| responses.into_iter().next()) {
            Ok(Some(AgentResponse::FileDigests { digests })) if digests.len() == files.len() => {
                digests
            }
            _ => vec![None; files.len()],
        }
    }

    fn record(&self, scope: FileDigestScope, entries: Vec<RecordedFileDigest>) {
        if entries.is_empty() {
            return;
        }
        let _ = request_agent(&[AgentRequest::RecordFileDigests { scope, entries }]);
    }
}

/// The file-digest ledger this shim may consult, or none under verification.
///
/// Verification exists to qualify the whole cached path end to end, so it
/// rehashes every input the way a first encounter would rather than trusting
/// what this same session recorded.
pub(crate) fn file_digest_cache() -> &'static dyn FileDigestCache {
    if verify_requested() {
        &NoFileDigestCache
    } else {
        &AgentFileDigestCache
    }
}

/// Record file digests in the session ledger, best-effort.
pub(crate) fn record_file_digests(scope: FileDigestScope, entries: Vec<RecordedFileDigest>) {
    if !verify_requested() {
        AgentFileDigestCache.record(scope, entries);
    }
}

/// Whether this build may cache natively linked programs.
///
/// Restricted to platforms whose linker tuist_cargo_cache knows how to identify: a host it
/// cannot describe would otherwise key a link as though the linker did not
/// matter.
pub fn cache_links_supported() -> bool {
    cfg!(any(target_os = "linux", target_os = "macos", windows))
}

/// Whether the shim may cache a natively linked program.
///
/// Unset means on, which is the one place this differs from verify mode: a
/// shim installed by `tuist_cargo_cache setup` is driven by plain cargo, with no session to
/// have written the variable, and reading absence as "off" there would leave
/// the persistent wrapper on a default nobody chose. A session always states
/// the answer explicitly, so `TUIST_CARGO_CACHE_CACHE_LINKS=0` still turns it off for both.
///
/// The platform is checked here rather than trusted from whoever set the
/// variable, for the same reason: the standalone shim has no session to have
/// applied the gate.
pub(crate) fn cache_links_requested() -> bool {
    cache_links_supported()
        && std::env::var_os(CACHE_LINKS_ENV).is_none_or(|value| !value.is_empty() && value != "0")
}

/// Whether a restore may hard link the store's object into the target
/// directory when the filesystem cannot clone it. Read the same way as verify
/// mode, except that an absent value means yes: a shim started outside a
/// session still restores, and a copy is the slower answer, not the safer one.
pub(crate) fn restore_hardlink_requested() -> bool {
    std::env::var_os(RESTORE_HARDLINK_ENV).is_none_or(|value| !value.is_empty() && value != "0")
}

/// Whether the shim may make a compilation independent of its `OUT_DIR` so two
/// checkouts can share it. Read the same way as verify mode.
pub(crate) fn share_out_dir_requested() -> bool {
    std::env::var_os(SHARE_OUT_DIR_ENV).is_some_and(|value| !value.is_empty() && value != "0")
}

/// Whether the shim may keep the checkout out of what rustc records, so a
/// crate rebuilt in a second checkout matches the first. Read the same way as
/// verify mode.
pub(crate) fn share_workspace_root_requested() -> bool {
    std::env::var_os(SHARE_WORKSPACE_ROOT_ENV)
        .is_some_and(|value| !value.is_empty() && value != "0")
}

/// Whether the shim forwards the compiler's output as it arrives. Unlike the
/// other switches this is on when unset: a shim running outside a session
/// should behave like a released build, not like a diagnosis of one.
pub(crate) fn forward_compiler_notifications_requested() -> bool {
    std::env::var_os(FORWARD_COMPILER_NOTIFICATIONS_ENV)
        .is_none_or(|value| value.is_empty() || value != "0")
}

/// Whether the shim may compile a churning crate with its own incremental
/// state instead of publishing it. Read the same way as verify mode.
pub(crate) fn learned_incremental_requested() -> bool {
    std::env::var_os(LEARNED_INCREMENTAL_ENV).is_some_and(|value| !value.is_empty() && value != "0")
}

/// Whether the session opted into private workspace state from the first compilation.
pub(crate) fn eager_incremental_requested() -> bool {
    std::env::var_os(EAGER_INCREMENTAL_ENV).is_some_and(|value| value == "1")
}

/// How much incremental state one crate may keep before the shim discards it;
/// `None` is no limit. The session writes the resolved setting, but a shim
/// running without one may inherit the user's own spelling, so both a byte
/// count and a size with a unit are accepted. Anything unreadable falls back
/// to the declared default rather than to no limit or to zero.
pub(crate) fn learned_incremental_max_size() -> Option<u64> {
    let default = Some(crate::config::DEFAULT_LEARNED_INCREMENTAL_MAX_SIZE);
    match std::env::var(LEARNED_INCREMENTAL_MAX_SIZE_ENV) {
        Ok(value) if !value.trim().is_empty() => {
            crate::config::parse_optional_byte_size(&value).unwrap_or(default)
        }
        _ => default,
    }
}

/// Tell the session that this compilation was not cacheable.
///
/// Bypasses never reach the agent otherwise, so without this they are invisible
/// outside a debug build. Reported by reason kind rather than message, since
/// several reasons carry a path or a flag.
fn record_bypass(error: &eyre::Report) {
    let reason = error.downcast_ref::<tuist_cargo_cache_rustc::BypassReason>();
    let kind = reason.map_or("other", tuist_cargo_cache_rustc::BypassReason::kind);
    append_bypass_log(
        None,
        kind,
        error,
        reason.and_then(tuist_cargo_cache_rustc::BypassReason::remediation),
    );
    // A shim running outside a session has nowhere to report, which is fine.
    // Sent before the compiler runs, so an interrupted compilation is still
    // reported. The shim's connection to the agent lasts as long as the shim,
    // so the compile time recorded afterwards arrives on the same connection,
    // where the agent pairs it with this reason.
    let diagnostic = bypass_diagnostic(
        expected_rustc_bypass(reason),
        &format!("rustc cache bypassed: {error:#}"),
    );
    let _ = request_agent(&[AgentRequest::RecordBypass { kind: kind.into() }, diagnostic]);
}

/// Tell the session that a C or C++ compilation was not cacheable.
///
/// Kinds are prefixed so that a reason the two adapters share by name, such as
/// an unmodeled flag, does not merge into one statistic covering both.
fn record_cc_bypass(error: &eyre::Report) {
    let reason = error.downcast_ref::<tuist_cargo_cache_cc::CcBypassReason>();
    let kind = reason.map_or_else(
        || "cc-other".to_string(),
        |reason| format!("cc-{}", reason.kind()),
    );
    append_bypass_log(
        None,
        &kind,
        error,
        reason.and_then(tuist_cargo_cache_cc::CcBypassReason::remediation),
    );
    // A shim running outside a session has nowhere to report, which is fine.
    let diagnostic = bypass_diagnostic(
        expected_cc_bypass(reason),
        &format!("cc cache bypassed: {error:#}"),
    );
    let _ = request_agent(&[AgentRequest::RecordBypass { kind }, diagnostic]);
}

/// A compiler succeeded but its result could not be cached. Do not count a
/// second outcome: this invocation already recorded its compilation outcome.
pub(crate) fn report_cc_publication_failure(unit: &str, error: &eyre::Report) {
    let reason = error.downcast_ref::<tuist_cargo_cache_cc::CcBypassReason>();
    let kind = reason.map_or_else(
        || "cc-other".to_string(),
        |reason| format!("cc-{}", reason.kind()),
    );
    append_bypass_log(
        Some(unit),
        &kind,
        error,
        reason.and_then(tuist_cargo_cache_cc::CcBypassReason::remediation),
    );
    let diagnostic = bypass_diagnostic(
        expected_cc_bypass(reason),
        &format!(
            "cc result was not published for {}: {error:#}",
            unit.escape_default()
        ),
    );
    let _ = request_agent(&[diagnostic]);
}

/// Only known routine decisions are downgraded: adapter errors also include
/// failed reads and invalid state, which must retain warning severity.
fn expected_rustc_bypass(reason: Option<&tuist_cargo_cache_rustc::BypassReason>) -> bool {
    use tuist_cargo_cache_rustc::BypassReason::*;
    matches!(
        reason,
        Some(
            CompilerQuery
                | UnknownFlag(_)
                | UnknownCodegenOption(_)
                | StandardInput
                | Incremental
                | UnsupportedCrateType(_)
                | UnsupportedEmit(_)
                | NoCacheableOutput
                | NoDepInfo
                | NativeLibrary(_)
                | MissingNativeLibrary(_)
                | CustomTargetNativeLibrary(_)
                | UnportableNativeLink(_)
                | UnmodeledLinkArgument(_)
                | UnsupportedSearchPath(_)
                | UnmappedAbsolutePath(_)
                | NonUtf8Argument { .. }
                | NonUtf8Path(_)
                | SplitOutputDirectories
                | ImplicitEmitWithOutputFile(_)
                | AmbiguousOutputName(_)
                | BuildScriptInputOverlapsOutputs(_)
        )
    )
}

fn expected_cc_bypass(reason: Option<&tuist_cargo_cache_cc::CcBypassReason>) -> bool {
    use tuist_cargo_cache_cc::CcBypassReason::*;
    matches!(
        reason,
        Some(
            CompilerQuery
                | NotACompile
                | UnknownFlag(_)
                | ResponseFile(_)
                | NonObjectOutput(_)
                | StandardInput
                | UnsupportedLanguage(_)
                | CallerDependencyFlags(_)
                | PrecompiledHeader(_)
                | CoverageInstrumentation(_)
                | SplitDebugOutput(_)
                | SaveTemps(_)
                | ToolPassthrough(_)
                | Plugin(_)
                | UnportableOutput(_)
                | PathSpecificStorageDisabled
                | SearchPathModifiedDuringCompilation(_)
                | LocalCpuTarget(_)
                | UnsupportedCompilerDriver(_)
                | UnsupportedEnvironment(_)
                | EmbeddedTimestampMacro(_)
                | AssemblerInputDirective(_)
                | TooManyInputs
                | UnmappedAbsolutePath(_)
                | NonUtf8Argument { .. }
                | NonUtf8Path(_)
        )
    )
}

/// Known routine bypass reasons describe conservative decisions. Other
/// errors represent failed cache paths even when the compiler can recover.
fn bypass_diagnostic(expected: bool, message: &str) -> AgentRequest {
    let message = diagnostics::diagnostic_message(message);
    if expected {
        AgentRequest::RecordDebug {
            target: module_path!().into(),
            message,
        }
    } else {
        AgentRequest::RecordWarning { message }
    }
}

/// Record a compilation the cache had no key to look up with.
pub(crate) fn record_unconsulted() {
    // A shim running outside a session has nowhere to report, which is fine.
    let _ = request_agent(&[AgentRequest::RecordUnconsulted]);
}

pub(crate) fn record_compiler_invocation(
    outcome: &str,
    crate_name: Option<&str>,
    duration_ns: u64,
) {
    record_compiler_invocation_with_diagnostic(outcome, crate_name, duration_ns, None);
}

pub(crate) fn record_compiler_invocation_with_diagnostic(
    outcome: &str,
    crate_name: Option<&str>,
    duration_ns: u64,
    diagnostic: Option<tuist_cargo_cache_core::ActionDiagnostic>,
) {
    let mut requests = Vec::new();
    if let Some(diagnostic) = diagnostic
        && let Some(request) = action_diagnostic_request(outcome, crate_name, diagnostic)
    {
        requests.push(request);
    }
    requests.extend(unit_outcome_requests(outcome, crate_name));
    requests.push(AgentRequest::RecordCompilerInvocation {
        outcome: outcome.into(),
        crate_name: crate_name.map(str::to_string),
        duration_ns,
    });
    let _ = request_agent(&requests);
}

/// Use Cargo's output fingerprint, not a crate name shared by package versions.
/// The reserved debug envelope keeps the public v6 request enum unchanged.
pub(crate) fn unit_outcome_requests(outcome: &str, crate_name: Option<&str>) -> Vec<AgentRequest> {
    let Some(crate_name) = crate_name else {
        return Vec::new();
    };
    let arguments: Vec<_> = std::env::args_os()
        .filter_map(|arg| arg.into_string().ok())
        .collect();
    let fingerprint = compiler_unit_key(crate_name, arguments.iter().cloned());
    let uplifted = std::env::var_os("CARGO_MANIFEST_PATH").and_then(|manifest| {
        compiler_uplifted_unit_key(crate_name, Path::new(&manifest), &arguments)
    });
    fingerprint
        .into_iter()
        .chain(uplifted)
        .filter_map(|unit| {
            Some(AgentRequest::RecordDebug {
                target: "tuist_cargo_cache::unit-outcome".into(),
                message: serde_json::to_string(&(unit, outcome)).ok()?,
            })
        })
        .collect()
}

/// Cargo can report only an uplifted executable/library, without its hash.
/// Scope this fallback to the package manifest, target and output directory;
/// never infer an outcome from a crate name alone. If Cargo reuses an uplifted
/// path for multiple configurations, the collected outcomes remain mixed.
pub(crate) fn uplifted_unit_key(
    manifest: &Path,
    directory: &Path,
    crate_name: &str,
    mut crate_types: Vec<String>,
) -> Option<String> {
    let directory = if directory.file_name()? == "deps" {
        directory.parent()?
    } else {
        directory
    };
    crate_types.sort();
    crate_types.dedup();
    if crate_types.is_empty() {
        return None;
    }
    let identity = serde_json::to_vec(&(
        manifest
            .canonicalize()
            .unwrap_or_else(|_| manifest.to_path_buf()),
        directory
            .canonicalize()
            .unwrap_or_else(|_| directory.to_path_buf()),
        crate_name.replace('-', "_"),
        crate_types,
    ))
    .ok()?;
    Some(format!("uplifted:{}", CacheDigest::blake3(&identity).hash))
}

pub(crate) fn compiler_uplifted_unit_key(
    crate_name: &str,
    manifest: &Path,
    arguments: &[String],
) -> Option<String> {
    // Test artifacts retain hashes and can share a target name with a normal
    // build. Do not add them to the normal target's uplifted alias.
    if arguments.iter().any(|argument| argument == "--test") {
        return None;
    }
    let mut directory = None;
    let mut crate_types = Vec::new();
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        let (flag, inline) = argument
            .split_once('=')
            .map_or((argument.as_str(), None), |(flag, value)| {
                (flag, Some(value))
            });
        if matches!(flag, "--out-dir" | "--crate-type") {
            let value = inline.or_else(|| arguments.next().map(String::as_str))?;
            if flag == "--out-dir" {
                directory = Some(PathBuf::from(value));
            } else {
                crate_types.extend(value.split(',').map(str::to_string));
            }
        }
    }
    uplifted_unit_key(manifest, &directory?, crate_name, crate_types)
}

pub(crate) fn compiler_unit_key(
    crate_name: &str,
    arguments: impl IntoIterator<Item = String>,
) -> Option<String> {
    let mut arguments = arguments.into_iter();
    while let Some(argument) = arguments.next() {
        let option = if argument == "-C" {
            arguments.next()?
        } else if let Some(option) = argument.strip_prefix("-C") {
            option.to_string()
        } else {
            continue;
        };
        if let Some(hash) = option.strip_prefix("extra-filename=-")
            && (8..=64).contains(&hash.len())
            && hash.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Some(format!("{crate_name}:{hash}"));
        }
    }
    None
}

const ACTION_DIAGNOSTIC_PREFIX: &str = "@tuist_cargo_cache-action-diagnostic\t";

#[derive(Serialize)]
struct ActionDiagnosticEnvelope<'a> {
    outcome: &'a str,
    crate_name: Option<&'a str>,
    diagnostic: ActionDiagnostic,
}

pub(crate) fn action_diagnostic_request(
    outcome: &str,
    crate_name: Option<&str>,
    diagnostic: ActionDiagnostic,
) -> Option<AgentRequest> {
    // Keep diagnostics on the v6 wire without adding fields to the public,
    // exhaustively matchable AgentRequest variants. The agent recognizes this
    // reserved warning envelope and does not surface it as a user warning.
    let payload = serde_json::to_string(&ActionDiagnosticEnvelope {
        outcome,
        crate_name,
        diagnostic,
    })
    .ok()?;
    Some(AgentRequest::RecordWarning {
        message: format!("{ACTION_DIAGNOSTIC_PREFIX}{payload}"),
    })
}

/// Append the full reason to `TUIST_CARGO_CACHE_BYPASS_LOG`, when one is configured.
///
/// The aggregate counts say which kinds dominate; this says exactly which flag
/// or path caused each one. It exists because stderr cannot be relied on:
/// cargo swallows the output of its own probe invocations, so some bypasses are
/// invisible there.
fn append_bypass_log(
    unit: Option<&str>,
    kind: &str,
    error: &eyre::Report,
    remediation: Option<&str>,
) {
    let Some(path) = std::env::var_os(BYPASS_LOG_ENV).filter(|path| !path.is_empty()) else {
        return;
    };
    // O_APPEND places each write at the end of the file, so one write per
    // record is what keeps parallel shims from splicing their lines together.
    // Records are a single short line for that reason: a write the kernel had
    // to break up could still interleave, and nothing here can prevent it.
    let suffix = remediation.map_or_else(String::new, |text| format!("\t{text}"));
    let unit = unit.map_or_else(String::new, |unit| {
        format!("\tunit={}", unit.escape_default())
    });
    let line = format!("{kind}\t{error:#}{suffix}{unit}\n");
    if let Err(problem) = append_line(&path, &line) {
        // Say so once. This runs per compilation and a destination that cannot
        // be written now will fail for every later record too, so warning each
        // time would bury the build in identical lines. Without this the
        // requested log is simply absent, with nothing explaining why.
        static WARNED: std::sync::Once = std::sync::Once::new();
        WARNED.call_once(|| {
            eprintln!(
                "tuist_cargo_cache[warning]: {BYPASS_LOG_ENV} was not written ({}): {problem}",
                Path::new(&path).display()
            );
        });
    }
}

/// Record a cacheability problem that prevents compiler invocations from ever
/// reaching a shim. It is separate from bypasses because there is no observed
/// compilation to count.
fn append_cacheability_observation(
    environment: &BTreeMap<String, String>,
    kind: &str,
    detail: &str,
) {
    let Some(path) = environment
        .get(BYPASS_LOG_ENV)
        .filter(|path| !path.is_empty())
    else {
        return;
    };
    let line = format!("@observation\t{kind}\t{detail}\n");
    if let Err(problem) = append_line(OsStr::new(path), &line) {
        debug!("cacheability observation was not recorded: {problem}");
    }
}

fn append_line(path: &OsStr, line: &str) -> std::io::Result<()> {
    use std::io::Write as _;
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    file.write_all(line.as_bytes())
}

pub(crate) fn request_agent(requests: &[AgentRequest]) -> Result<Vec<AgentResponse>> {
    let _phase = requests
        .first()
        .and_then(|request| match request {
            AgentRequest::FindActionResult { .. } | AgentRequest::FindActionPrediction { .. } => {
                Some("lookup")
            }
            AgentRequest::FindBlobs { .. } => Some("blob_transfer"),
            AgentRequest::JoinActionPromise { .. } => Some("flight_wait"),
            AgentRequest::ResolveFileDigests { .. } | AgentRequest::FindFileDigests { .. } => {
                Some("key")
            }
            _ => None,
        })
        .map(crate::phase_timing::phase);

    match session_socket() {
        Some(socket) => request_agent_at(&socket, requests),
        None => request_standalone_agent(requests),
    }
}

/// The session socket a shim should ask, if a session named one.
///
/// An empty value means the same as an absent one: there is no session to
/// reach. Everything that asks whether this process has a session has to
/// agree on that, because the alternatives are not equivalent for a cc shim
/// -- a standalone agent runs in the shim itself and writes to the stderr the
/// compiler owns, which is what [`report_shim_warning`] exists to avoid.
fn session_socket() -> Option<OsString> {
    std::env::var_os(SOCKET_ENV).filter(|socket| !socket.is_empty())
}

#[cfg(test)]
#[path = "session_tests.rs"]
mod tests;
