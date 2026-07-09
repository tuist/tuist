//! Tuist CAS plugin: an LLVM CAS plugin (llcas ABI v0.1) that wraps Xcode's
//! libToolchainCASPlugin for local storage and hashing, and adds kura-backed
//! remoteness over the Bazel Remote Execution API (see reapi.rs).
//!
//! The build system runs in its fast "plugin-local" mode (no
//! COMPILATION_CACHE_REMOTE_SERVICE_PATH); this plugin owns all remote
//! traffic. Interception is deliberately not keyed on the `globally` flag,
//! which is never set on this path.

pub mod analytics;
pub mod proxy;
pub mod proxy_proto;
pub mod prefetch;
pub mod reapi;
pub mod token;
pub mod types;
pub mod upstream;

use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use proxy_proto::{ProxyClient, Resolution};
use prefetch::Prefetcher;
use reapi::{ManifestEntry, OpStats, Remote, RemoteConfig};
use token::TokenProvider;
use types::*;
use upstream::Upstream;

// --- Global upstream table ---------------------------------------------------

static UPSTREAM: OnceLock<Result<&'static Upstream, String>> = OnceLock::new();

/// Resolves the path to Apple's `libToolchainCASPlugin.dylib`. Shared with the
/// `tuist-cas-proxy` binary so the plugin and the proxy agree on how to find the
/// upstream (including the `xcode-select` fallback for versioned Xcode installs).
pub fn upstream_path() -> String {
    if let Ok(path) = std::env::var("TUIST_CAS_UPSTREAM_PLUGIN") {
        return path;
    }
    // Resolve the active developer dir: explicit DEVELOPER_DIR, then
    // `xcode-select -p` (the system's active Xcode, which handles versioned
    // install paths like /Applications/Xcode-26.5.0.app), then the default
    // location as a last resort. Without the xcode-select fallback a launchd or
    // CI context that sets neither env would silently degrade every resolve to a
    // local miss on any non-default Xcode install.
    let developer_dir = std::env::var("DEVELOPER_DIR")
        .ok()
        .filter(|dir| !dir.is_empty())
        .or_else(xcode_select_developer_dir)
        .unwrap_or_else(|| "/Applications/Xcode.app/Contents/Developer".into());
    format!("{developer_dir}/usr/lib/libToolchainCASPlugin.dylib")
}

/// The active developer directory reported by `xcode-select -p`, or `None` when
/// the tool is missing or fails.
fn xcode_select_developer_dir() -> Option<String> {
    let output = std::process::Command::new("xcode-select")
        .arg("-p")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (!path.is_empty()).then_some(path)
}

fn upstream() -> Result<&'static Upstream, String> {
    UPSTREAM
        .get_or_init(|| unsafe {
            Upstream::load(&upstream_path()).map(|up| &*Box::leak(Box::new(up)))
        })
        .clone()
        .map_err(|e| e)
}

// --- String ownership ----------------------------------------------------------
// Every string handed to the client is allocated by us (CString), because the
// client releases all strings through our llcas_string_dispose. Strings coming
// back from the upstream plugin are copied and immediately released upstream.

fn own_string(s: &str) -> *mut c_char {
    CString::new(s.replace('\0', "?"))
        .unwrap_or_default()
        .into_raw()
}

unsafe fn adopt_upstream_string(up: &Upstream, s: *mut c_char) -> *mut c_char {
    if s.is_null() {
        return std::ptr::null_mut();
    }
    let copy = own_string(&CStr::from_ptr(s).to_string_lossy());
    (up.llcas_string_dispose)(s);
    copy
}

unsafe fn set_error(error: *mut *mut c_char, message: &str) {
    if !error.is_null() {
        *error = own_string(message);
    }
}

/// Runs `body`, catching any panic so it can never unwind across an
/// `extern "C"` boundary. A panic escaping a `#[no_mangle] extern "C"` function
/// aborts the whole process (the compiler / build service) instead of degrading
/// to a local miss, which is the invariant this plugin promises. On a panic,
/// writes `message` into `error` (when non-null) and returns `sentinel`. The
/// async llcas paths already guard their impl calls this way; this brings the
/// synchronous entry points that run our own logic (remote resolves, mutex
/// locks) to parity.
unsafe fn ffi_guard<R>(
    error: *mut *mut c_char,
    sentinel: R,
    message: &str,
    body: impl FnOnce() -> R,
) -> R {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(body)).unwrap_or_else(|_| {
        set_error(error, message);
        sentinel
    })
}

unsafe fn adopt_error(up: &Upstream, error_in: *mut c_char, error_out: *mut *mut c_char) {
    if error_out.is_null() {
        if !error_in.is_null() {
            (up.llcas_string_dispose)(error_in);
        }
        return;
    }
    *error_out = adopt_upstream_string(up, error_in);
}

// --- Handles -------------------------------------------------------------------

struct OptionsState {
    ondisk_path: Option<CString>,
    client_version: Option<(u32, u32)>,
    options: Vec<(CString, CString)>,
}

// Uploader items are "publish records": key digest, value digest, and the
// path of the write-ahead spool file backing them. Publication is durable
// against process death: most compiler processes exit WITHOUT calling
// llcas_cas_dispose (measured: 874 of 877 putters in one build), so anything
// held only in memory is lost. The record file is written before the enqueue
// and deleted only after the value graph and the entry have been uploaded;
// leftover records are swept by later plugin instances.
pub struct PublishRecord {
    pub key: Vec<u8>,
    pub value_digest: Vec<u8>,
    pub spool_path: Option<std::path::PathBuf>,
}

impl PublishRecord {
    fn encode_body(&self) -> Vec<u8> {
        let mut body = Vec::with_capacity(2 + self.key.len() + self.value_digest.len());
        body.extend_from_slice(&(self.key.len() as u16).to_be_bytes());
        body.extend_from_slice(&self.key);
        body.extend_from_slice(&self.value_digest);
        body
    }

    pub fn decode_body(body: &[u8], spool_path: Option<std::path::PathBuf>) -> Option<Self> {
        if body.len() < 2 {
            return None;
        }
        let key_len = u16::from_be_bytes([body[0], body[1]]) as usize;
        if body.len() < 2 + key_len {
            return None;
        }
        Some(Self {
            key: body[2..2 + key_len].to_vec(),
            value_digest: body[2 + key_len..].to_vec(),
            spool_path,
        })
    }

    fn encode_item(&self) -> Vec<u8> {
        let body = self.encode_body();
        let mut item = Vec::with_capacity(2 + body.len() + 128);
        item.extend_from_slice(&(body.len() as u16).to_be_bytes());
        item.extend_from_slice(&body);
        if let Some(path) = &self.spool_path {
            item.extend_from_slice(path.to_string_lossy().as_bytes());
        }
        item
    }

    fn decode_item(item: &[u8]) -> Option<Self> {
        if item.len() < 2 {
            return None;
        }
        let body_len = u16::from_be_bytes([item[0], item[1]]) as usize;
        if item.len() < 2 + body_len {
            return None;
        }
        let path_bytes = &item[2 + body_len..];
        let spool_path = if path_bytes.is_empty() {
            None
        } else {
            Some(std::path::PathBuf::from(String::from_utf8_lossy(path_bytes).into_owned()))
        };
        Self::decode_body(&item[2..2 + body_len], spool_path)
    }
}

/// Reads a boolean env var, treating unset as `default` and `0`/`false`/`no`/`off`
/// (case-insensitive) as false; any other value is true.
fn env_bool(name: &str, default: bool) -> bool {
    match std::env::var(name) {
        Ok(value) => !matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "0" | "false" | "no" | "off"
        ),
        Err(_) => default,
    }
}

/// The well-known per-machine proxy socket. Both the plugin (as its ⌘B
/// fallback) and the proxy binary (as its default bind path) resolve it, so
/// an Xcode ⌘B build with no CLI environment still finds a running proxy. A
/// per-user path keeps the socket off the world-readable `/tmp`.
///
/// This is the *default* state location (`~/.local/state/tuist`), matching where
/// the CLI keeps `cas_analytics.db` and where the old daemon's socket lived.
/// Deliberately anchored to `HOME` and NOT honoring `XDG_STATE_HOME`, unlike the
/// CLI's `Environment.stateDirectory`: the plugin resolves this itself inside
/// compiler frontends (an Xcode ⌘B build carries no CLI environment), so it must
/// agree with the launchd proxy from `HOME` alone.
pub fn default_proxy_socket() -> String {
    match std::env::var("HOME") {
        Ok(home) if !home.is_empty() => format!("{home}/.local/state/tuist/cas-proxy.sock"),
        _ => "/tmp/tuist-cas-proxy.sock".to_string(),
    }
}

/// The value of a plugin option the build system passed to `set_option`
/// (e.g. `tuist-instance`), or `None` when absent or empty.
fn option_value(state: &OptionsState, name: &str) -> Option<String> {
    state
        .options
        .iter()
        .find(|(option_name, _)| option_name.to_string_lossy() == name)
        .map(|(_, value)| value.to_string_lossy().into_owned())
        .filter(|value| !value.is_empty())
}

/// Whether this build publishes value graphs (`xcodeCache(upload:)`). Prefers
/// the `tuist-upload` plugin option (baked into build settings by `tuist
/// generate`, so it reaches every frontend including a ⌘B build with no CLI
/// env), then the `TUIST_CAS_UPLOAD` env, then defaults to on. An explicit
/// `false` on either channel disables publishing; read hits are unaffected.
fn resolve_upload(state: &OptionsState) -> bool {
    match option_value(state, "tuist-upload") {
        Some(value) => !value.eq_ignore_ascii_case("false"),
        None => env_bool("TUIST_CAS_UPLOAD", true),
    }
}

struct CasState {
    up: &'static Upstream,
    cas: llcas_cas_t,
    remote: Option<Arc<Remote>>,
    // Proxy mode: all remote work is delegated to the per-machine proxy
    // over a unix socket; this process runs no gRPC client at all.
    proxy: Option<ProxyClient>,
    // The account/project this build's cache belongs to, declared to the proxy
    // so it routes to the right instance. Empty for an Xcode ⌘B build (no CLI
    // env); the proxy then falls back to its primed cas_path mapping.
    proxy_instance: String,
    // Upload policy from `xcodeCache(upload:)`. When false, read hits still work
    // but no value graphs are published (the read path is unchanged). Carried by
    // the `tuist-upload` plugin option (so it reaches every frontend, including a
    // ⌘B build) with the `TUIST_CAS_UPLOAD` env as a fallback; see resolve_upload.
    upload: bool,
    created_at: std::time::Instant,
    cas_dir: Option<std::path::PathBuf>,
    sweeper: Mutex<Option<std::thread::JoinHandle<()>>>,
    // Uploads value-object graphs on actioncache_put. Deliberately NOT hooked
    // on store_object: the compiler stores input ingests and scan trees every
    // build (warm included), and mirroring those re-uploads the world.
    uploader: Prefetcher,
    // The client puts the same (key, value) many times per build; only the
    // first becomes a publication. Publish items carry unique spool paths, so
    // the queue's content dedup cannot do this.
    published: Mutex<std::collections::HashSet<(Vec<u8>, Vec<u8>)>>,
    // Value graphs share children heavily across keys; without these caches a
    // warm build re-fetches (read side) and re-compresses/re-hashes (publish
    // side) the same nodes once per referencing key.
    known_local: Mutex<std::collections::HashSet<Vec<u8>>>,
    publish_cache: Mutex<std::collections::HashMap<Vec<u8>, (reapi::Digest, Vec<Vec<u8>>)>>,
    stats_remote_entry_hits: AtomicU64,
    stats_remote_node_hits: AtomicU64,
    stats_remote_misses: AtomicU64,
    // Time spent resolving demand-driven remote work (entry read-through and
    // object-load materialization). This bounds how far warm-remote can sit
    // above the local-replay floor due to fetching, as opposed to overheads.
    stats_demand_wait_ms: AtomicU64,
    // Local CAS ingestion, split by writer: the client's own store_object
    // calls (input ingests, scan trees, computed outputs) vs stores performed
    // by this plugin while materializing fetched nodes. Comparing these
    // between a warm-remote build and a kept-CAS floor build attributes the
    // gap between them.
    stats_client_store: OpStats,
    stats_client_store_bytes: AtomicU64,
    stats_mat_store: OpStats,
    stats_mat_store_bytes: AtomicU64,
    stats_local_put_ms: AtomicU64,
    stats_upload_walk_loads: AtomicU64,
    stats_manifest_entries: AtomicU64,
}

/// Process CPU (user+system) in milliseconds, for attributing wall-time gaps
/// to actual compute per process class.
fn process_cpu_ms() -> u64 {
    unsafe {
        let mut usage: libc::rusage = std::mem::zeroed();
        if libc::getrusage(libc::RUSAGE_SELF, &mut usage) != 0 {
            return 0;
        }
        let user = usage.ru_utime.tv_sec as u64 * 1000 + usage.ru_utime.tv_usec as u64 / 1000;
        let system = usage.ru_stime.tv_sec as u64 * 1000 + usage.ru_stime.tv_usec as u64 / 1000;
        user + system
    }
}

unsafe fn cas_state<'a>(cas: llcas_cas_t) -> &'a CasState {
    &*(cas as *const CasState)
}

/// Records elapsed demand wait on drop so every early return is counted.
struct DemandWaitGuard<'a> {
    state: &'a CasState,
    started: std::time::Instant,
}

impl Drop for DemandWaitGuard<'_> {
    fn drop(&mut self) {
        self.state
            .stats_demand_wait_ms
            .fetch_add(self.started.elapsed().as_millis() as u64, Ordering::Relaxed);
    }
}

enum CancelToken {
    Ours(#[allow(dead_code)] Arc<AtomicBool>),
    // Constructed only when an upstream async path hands us its token; the
    // current sync-answering paths use Ours, but dispose/cancel must handle it.
    #[allow(dead_code)]
    Upstream(&'static Upstream, llcas_cancellable_t),
}

// --- Version -------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn llcas_get_plugin_version(major: *mut u32, minor: *mut u32) {
    unsafe {
        if !major.is_null() {
            *major = LLCAS_VERSION_MAJOR;
        }
        if !minor.is_null() {
            *minor = LLCAS_VERSION_MINOR;
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn llcas_string_dispose(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cancellable_cancel(token: llcas_cancellable_t) {
    if token.is_null() {
        return;
    }
    match &*(token as *const CancelToken) {
        CancelToken::Ours(flag) => flag.store(true, Ordering::Relaxed),
        CancelToken::Upstream(up, inner) => {
            if let Some(cancel) = up.llcas_cancellable_cancel {
                cancel(*inner);
            }
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cancellable_dispose(token: llcas_cancellable_t) {
    if token.is_null() {
        return;
    }
    let boxed = Box::from_raw(token as *mut CancelToken);
    if let CancelToken::Upstream(up, inner) = *boxed {
        if let Some(dispose) = up.llcas_cancellable_dispose {
            dispose(inner);
        }
    }
}

fn ours_cancel_token(slot: *mut llcas_cancellable_t) -> Arc<AtomicBool> {
    let flag = Arc::new(AtomicBool::new(false));
    if !slot.is_null() {
        unsafe {
            *slot = Box::into_raw(Box::new(CancelToken::Ours(Arc::clone(&flag)))) as llcas_cancellable_t;
        }
    }
    flag
}

// --- Options -------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn llcas_cas_options_create() -> llcas_cas_options_t {
    Box::into_raw(Box::new(OptionsState {
        ondisk_path: None,
        client_version: None,
        options: Vec::new(),
    })) as llcas_cas_options_t
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_options_dispose(options: llcas_cas_options_t) {
    if !options.is_null() {
        drop(Box::from_raw(options as *mut OptionsState));
    }
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_options_set_client_version(
    options: llcas_cas_options_t,
    major: u32,
    minor: u32,
) {
    (*(options as *mut OptionsState)).client_version = Some((major, minor));
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_options_set_ondisk_path(
    options: llcas_cas_options_t,
    path: *const c_char,
) {
    (*(options as *mut OptionsState)).ondisk_path = Some(CStr::from_ptr(path).to_owned());
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_options_set_option(
    options: llcas_cas_options_t,
    name: *const c_char,
    value: *const c_char,
    _error: *mut *mut c_char,
) -> bool {
    (*(options as *mut OptionsState))
        .options
        .push((CStr::from_ptr(name).to_owned(), CStr::from_ptr(value).to_owned()));
    false
}

// --- CAS lifecycle ---------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_create(
    options: llcas_cas_options_t,
    error: *mut *mut c_char,
) -> llcas_cas_t {
    let up = match upstream() {
        Ok(up) => up,
        Err(message) => {
            set_error(error, &message);
            return std::ptr::null_mut();
        }
    };
    let state = &*(options as *const OptionsState);

    let upstream_options = (up.llcas_cas_options_create)();
    if let Some((major, minor)) = state.client_version {
        (up.llcas_cas_options_set_client_version)(upstream_options, major, minor);
    }
    if let Some(path) = &state.ondisk_path {
        (up.llcas_cas_options_set_ondisk_path)(upstream_options, path.as_ptr());
    }
    for (name, value) in &state.options {
        // Tuist-specific options are consumed here; everything else is
        // forwarded to the wrapped plugin.
        if name.to_string_lossy().starts_with("tuist-") {
            continue;
        }
        let mut option_error: *mut c_char = std::ptr::null_mut();
        if (up.llcas_cas_options_set_option)(upstream_options, name.as_ptr(), value.as_ptr(), &mut option_error) {
            adopt_error(up, option_error, error);
            (up.llcas_cas_options_dispose)(upstream_options);
            return std::ptr::null_mut();
        }
    }

    let mut create_error: *mut c_char = std::ptr::null_mut();
    let upstream_cas = (up.llcas_cas_create)(upstream_options, &mut create_error);
    (up.llcas_cas_options_dispose)(upstream_options);
    if upstream_cas.is_null() {
        adopt_error(up, create_error, error);
        return std::ptr::null_mut();
    }

    let explicit_socket = std::env::var("TUIST_CAS_PROXY_SOCKET")
        .ok()
        .filter(|socket| !socket.is_empty());
    let has_direct_endpoint = std::env::var("TUIST_CAS_REMOTE_GRPC_URL").is_ok();
    // Proxy mode when a socket is given, or (the Xcode ⌘B case, which carries
    // no CLI environment) when no direct endpoint is configured: fall back to
    // the well-known proxy socket so a running proxy is used, else the
    // connect fails and we degrade to the local CAS. Direct mode is bench-only.
    let proxy = explicit_socket
        .or_else(|| (!has_direct_endpoint).then(default_proxy_socket))
        .map(|socket_path| ProxyClient { socket_path });
    // The account/project this build's cache belongs to, routed to the proxy.
    // Prefer the `tuist-instance` plugin option (baked into build settings by
    // `tuist generate`, so it reaches every compiler frontend including an Xcode
    // ⌘B build that carries no CLI environment); fall back to the CLI env, then
    // empty (the proxy resolves the instance from its registry).
    let proxy_instance = option_value(state, "tuist-instance").unwrap_or_else(|| {
        match (
            std::env::var("TUIST_CAS_ACCOUNT"),
            std::env::var("TUIST_CAS_PROJECT"),
        ) {
            (Ok(account), Ok(project)) => format!("{account}/{project}"),
            _ => String::new(),
        }
    });
    let remote = if proxy.is_some() {
        None
    } else {
        RemoteConfig::from_env().map(|config| Remote::new(config, TokenProvider::from_env()))
    };
    let has_remote = remote.is_some();
    let cas_dir = state
        .ondisk_path
        .as_ref()
        .and_then(|p| p.to_str().ok())
        .map(std::path::PathBuf::from);
    let state_ptr = Box::into_raw(Box::new(CasState {
        up,
        cas: upstream_cas,
        remote,
        proxy,
        proxy_instance,
        upload: resolve_upload(state),
        created_at: std::time::Instant::now(),
        cas_dir,
        sweeper: Mutex::new(None),
        uploader: Prefetcher::new(),
        published: Mutex::new(std::collections::HashSet::new()),
        known_local: Mutex::new(std::collections::HashSet::new()),
        publish_cache: Mutex::new(std::collections::HashMap::new()),
        stats_remote_entry_hits: AtomicU64::new(0),
        stats_remote_node_hits: AtomicU64::new(0),
        stats_remote_misses: AtomicU64::new(0),
        stats_demand_wait_ms: AtomicU64::new(0),
        stats_client_store: OpStats::default(),
        stats_client_store_bytes: AtomicU64::new(0),
        stats_mat_store: OpStats::default(),
        stats_mat_store_bytes: AtomicU64::new(0),
        stats_local_put_ms: AtomicU64::new(0),
        stats_upload_walk_loads: AtomicU64::new(0),
        stats_manifest_entries: AtomicU64::new(0),
    }));
    if has_remote {
        let cas_addr = state_ptr as usize;
        (*state_ptr).uploader.configure(Prefetcher::worker_count(), move |item| {
            upload_process(cas_addr, item);
        });
        // Spawn a sweeper only when there is something to sweep: most
        // processes find an empty spool, and a per-process thread plus its
        // dispose-join costs real wall time multiplied by thousands of
        // short-lived compiler processes.
        let has_spool_entries = spool_dir(&*state_ptr)
            .and_then(|dir| std::fs::read_dir(dir).ok())
            .map(|mut entries| entries.next().is_some())
            .unwrap_or(false);
        if has_spool_entries {
            *(*state_ptr).sweeper.lock().unwrap() = Some(std::thread::spawn(move || {
                // Only processes that live a while sweep: a short-lived
                // frontend claiming records it cannot finish just bounces
                // them back to the spool.
                for _ in 0..75 {
                    std::thread::sleep(std::time::Duration::from_millis(10));
                    let state = cas_state(cas_addr as llcas_cas_t);
                    if state.uploader.is_shutdown() {
                        return;
                    }
                }
                sweep_spool(cas_addr);
            }));
        }
    }
    state_ptr as llcas_cas_t
}

fn spool_dir(state: &CasState) -> Option<std::path::PathBuf> {
    state.cas_dir.as_ref().map(|dir| dir.join("tuist-spool"))
}

/// Requeues publications left behind by processes that died before their
/// uploader finished (most compiler processes exit without disposing the
/// CAS). Every plugin instance with a remote sweeps once at creation; files
/// are claimed by rename so concurrent sweepers do not duplicate work, and
/// claims from dead pids are re-claimable.
fn sweep_spool(cas_addr: usize) {
    let state = unsafe { cas_state(cas_addr as llcas_cas_t) };
    let Some(dir) = spool_dir(state) else { return };
    let Ok(entries) = std::fs::read_dir(&dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        let base = if let Some((base, claim_pid)) = name.split_once(".claim-") {
            // A claim from a live process is in flight; a dead claimant's
            // record is fair game again.
            let alive = claim_pid
                .parse::<i32>()
                .map(|pid| unsafe { libc::kill(pid, 0) } == 0)
                .unwrap_or(false);
            if alive {
                continue;
            }
            base.to_string()
        } else {
            name.to_string()
        };
        let claimed = dir.join(format!("{base}.claim-{}", std::process::id()));
        if std::fs::rename(&path, &claimed).is_err() {
            continue;
        }
        if let Ok(bytes) = std::fs::read(&claimed) {
            if let Some(record) = PublishRecord::decode_body(&bytes, Some(claimed.clone())) {
                state.uploader.enqueue(record.encode_item());
            } else {
                let _ = std::fs::remove_file(&claimed);
            }
        }
    }
}

/// Writes the publication's write-ahead record. Returns the path the worker
/// deletes after a successful publish.
fn write_publish_record(state: &CasState, record: &PublishRecord) -> Option<std::path::PathBuf> {
    let dir = spool_dir(state)?;
    std::fs::create_dir_all(&dir).ok()?;
    static SPOOL_SEQ: AtomicU64 = AtomicU64::new(0);
    let path = dir.join(format!(
        "{}-{}",
        std::process::id(),
        SPOOL_SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(&path, record.encode_body()).ok()?;
    Some(path)
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_dispose(cas: llcas_cas_t) {
    if cas.is_null() {
        return;
    }
    let state_ptr = cas as *mut CasState;
    {
        // Workers reference this state; join them before freeing anything.
        // Prefetches are droppable; queued uploads must flush.
        let state = &*state_ptr;
        // Drain FIRST: it sets the uploader's shutdown flag, which is what
        // tells a still-waiting sweeper to abort. Joining the sweeper before
        // the flag is set would serialize its startup delay onto every
        // process exit. Post-shutdown sweeper enqueues are dropped harmlessly
        // (the records persist for a later sweep).
        // Bounded drain keeps process exit off the build's critical path;
        // whatever is still queued is spooled for later processes to upload.
        let drain_budget = std::env::var("TUIST_CAS_DRAIN_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(50);
        let drain_started = std::time::Instant::now();
        // Leftovers are simply dropped: each publication's write-ahead record
        // survives on disk and a later sweep completes it.
        let leftovers = state
            .uploader
            .drain_stop_timeout(std::time::Duration::from_millis(drain_budget));
        let spooled = leftovers.len();
        if let Some(sweeper) = state.sweeper.lock().unwrap().take() {
            let _ = sweeper.join();
        }
        if let Some(remote) = &state.remote {
            let drain_ms = drain_started.elapsed().as_millis();
            log_line(&format!(
                "dispose: drain={drain_ms}ms spooled={spooled} cpu={}ms life={}ms walks up={} remote entry hits={} manifest entries={} blobs fetched={} misses={} demand_wait={}ms | gets {} | posts {}",
                process_cpu_ms(),
                state.created_at.elapsed().as_millis(),
                state.stats_upload_walk_loads.load(Ordering::Relaxed),
                state.stats_remote_entry_hits.load(Ordering::Relaxed),
                state.stats_manifest_entries.load(Ordering::Relaxed),
                state.stats_remote_node_hits.load(Ordering::Relaxed),
                state.stats_remote_misses.load(Ordering::Relaxed),
                state.stats_demand_wait_ms.load(Ordering::Relaxed),
                remote.get_stats.summary(),
                remote.post_stats.summary(),
            ));
        }
        // Ingestion counters are logged with or without a remote so a floor
        // build produces the same accounting as a warm-remote build.
        if state.stats_client_store.count.load(Ordering::Relaxed) > 0
            || state.stats_mat_store.count.load(Ordering::Relaxed) > 0
        {
            log_line(&format!(
                "ingest: cpu={}ms life={}ms client_store {} bytes={} | mat_store {} bytes={} | local_put={}ms",
                process_cpu_ms(),
                state.created_at.elapsed().as_millis(),
                state.stats_client_store.summary(),
                state.stats_client_store_bytes.load(Ordering::Relaxed),
                state.stats_mat_store.summary(),
                state.stats_mat_store_bytes.load(Ordering::Relaxed),
                state.stats_local_put_ms.load(Ordering::Relaxed),
            ));
        }
        (state.up.llcas_cas_dispose)(state.cas);
    }
    drop(Box::from_raw(state_ptr));
}

/// Diagnostic: records which executable missed which key remotely, so miss
/// populations can be attributed to task classes and compared across builds.
fn log_miss(key: &[u8]) {
    static EXE: OnceLock<String> = OnceLock::new();
    let exe = EXE.get_or_init(|| {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
            .unwrap_or_else(|| "unknown".into())
    });
    let mut hex = String::with_capacity(key.len() * 2);
    for byte in key {
        hex.push_str(&format!("{byte:02x}"));
    }
    log_line(&format!("miss exe={exe} key={hex}"));
}

pub fn log_line(message: &str) {
    if let Ok(path) = std::env::var("TUIST_CAS_LOG") {
        use std::io::Write;
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis())
                .unwrap_or(0);
            let _ = writeln!(file, "[tuist-cas-plugin t={now} pid={}] {message}", std::process::id());
        }
    }
}

// --- Simple forwards -------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_get_ondisk_size(cas: llcas_cas_t, error: *mut *mut c_char) -> i64 {
    let state = cas_state(cas);
    let Some(get_size) = state.up.llcas_cas_get_ondisk_size else { return -1 };
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = get_size(state.cas, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    result
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_set_ondisk_size_limit(
    cas: llcas_cas_t,
    size_limit: i64,
    error: *mut *mut c_char,
) -> bool {
    let state = cas_state(cas);
    let Some(set_limit) = state.up.llcas_cas_set_ondisk_size_limit else { return false };
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = set_limit(state.cas, size_limit, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    result
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_prune_ondisk_data(cas: llcas_cas_t, error: *mut *mut c_char) -> bool {
    let state = cas_state(cas);
    let Some(prune) = state.up.llcas_cas_prune_ondisk_data else { return false };
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = prune(state.cas, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    // Pruning removed objects from the shared on-disk CAS in place (and a partial
    // prune that then errored may have removed some too). Drop this process's own
    // known-local marks, and tell the per-machine proxy to drop its marks for
    // this path: neither store recreation nor a cached-hit presence check would
    // otherwise notice the removed blobs, so a later resolve could skip
    // re-fetching them and hand back a broken graph. Prune is infrequent, so the
    // occasional re-warm from an over-broad invalidation is cheap.
    state.known_local.lock().unwrap().clear();
    if let (Some(client), Some(cas_dir)) = (&state.proxy, &state.cas_dir) {
        let _ = client.invalidate(&cas_dir.to_string_lossy());
    }
    result
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_get_hash_schema_name(cas: llcas_cas_t) -> *mut c_char {
    let state = cas_state(cas);
    adopt_upstream_string(state.up, (state.up.llcas_cas_get_hash_schema_name)(state.cas))
}

#[no_mangle]
pub unsafe extern "C" fn llcas_digest_parse(
    cas: llcas_cas_t,
    printed_digest: *const c_char,
    bytes: *mut u8,
    bytes_size: usize,
    error: *mut *mut c_char,
) -> u32 {
    let state = cas_state(cas);
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = (state.up.llcas_digest_parse)(state.cas, printed_digest, bytes, bytes_size, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    result
}

#[no_mangle]
pub unsafe extern "C" fn llcas_digest_print(
    cas: llcas_cas_t,
    digest: llcas_digest_t,
    printed_id: *mut *mut c_char,
    error: *mut *mut c_char,
) -> bool {
    let state = cas_state(cas);
    let mut upstream_printed: *mut c_char = std::ptr::null_mut();
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_digest_print)(state.cas, digest, &mut upstream_printed, &mut upstream_error);
    if !printed_id.is_null() {
        *printed_id = adopt_upstream_string(state.up, upstream_printed);
    } else if !upstream_printed.is_null() {
        (state.up.llcas_string_dispose)(upstream_printed);
    }
    adopt_error(state.up, upstream_error, error);
    failed
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_get_objectid(
    cas: llcas_cas_t,
    digest: llcas_digest_t,
    p_id: *mut llcas_objectid_t,
    error: *mut *mut c_char,
) -> bool {
    let state = cas_state(cas);
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_cas_get_objectid)(state.cas, digest, p_id, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    failed
}

#[no_mangle]
pub unsafe extern "C" fn llcas_objectid_get_digest(cas: llcas_cas_t, id: llcas_objectid_t) -> llcas_digest_t {
    let state = cas_state(cas);
    (state.up.llcas_objectid_get_digest)(state.cas, id)
}

#[no_mangle]
pub unsafe extern "C" fn llcas_loaded_object_get_data(
    cas: llcas_cas_t,
    object: llcas_loaded_object_t,
) -> llcas_data_t {
    let state = cas_state(cas);
    (state.up.llcas_loaded_object_get_data)(state.cas, object)
}

#[no_mangle]
pub unsafe extern "C" fn llcas_loaded_object_get_refs(
    cas: llcas_cas_t,
    object: llcas_loaded_object_t,
) -> llcas_object_refs_t {
    let state = cas_state(cas);
    (state.up.llcas_loaded_object_get_refs)(state.cas, object)
}

#[no_mangle]
pub unsafe extern "C" fn llcas_object_refs_get_count(cas: llcas_cas_t, refs: llcas_object_refs_t) -> usize {
    let state = cas_state(cas);
    (state.up.llcas_object_refs_get_count)(state.cas, refs)
}

#[no_mangle]
pub unsafe extern "C" fn llcas_object_refs_get_id(
    cas: llcas_cas_t,
    refs: llcas_object_refs_t,
    index: usize,
) -> llcas_objectid_t {
    let state = cas_state(cas);
    (state.up.llcas_object_refs_get_id)(state.cas, refs, index)
}

#[no_mangle]
pub unsafe extern "C" fn llcas_loaded_object_export_data_to_filepath(
    cas: llcas_cas_t,
    object: llcas_loaded_object_t,
    filepath: *const c_char,
    error: *mut *mut c_char,
) -> bool {
    let state = cas_state(cas);
    if let Some(export) = state.up.llcas_loaded_object_export_data_to_filepath {
        let mut upstream_error: *mut c_char = std::ptr::null_mut();
        let failed = export(state.cas, object, filepath, &mut upstream_error);
        adopt_error(state.up, upstream_error, error);
        return failed;
    }
    let data = (state.up.llcas_loaded_object_get_data)(state.cas, object);
    let payload = std::slice::from_raw_parts(data.data as *const u8, data.size);
    let path = CStr::from_ptr(filepath).to_string_lossy().into_owned();
    match std::fs::write(&path, payload) {
        Ok(()) => false,
        Err(write_error) => {
            set_error(error, &format!("tuist-cas-plugin: failed to write {path}: {write_error}"));
            true
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_contains_object(
    cas: llcas_cas_t,
    id: llcas_objectid_t,
    globally: bool,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    let state = cas_state(cas);
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_contains_object)(state.cas, id, globally, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    result
}

// --- Read-through: object loads -----------------------------------------------

unsafe fn digest_bytes(state: &CasState, id: llcas_objectid_t) -> Vec<u8> {
    let digest = (state.up.llcas_objectid_get_digest)(state.cas, id);
    if digest.data.is_null() || digest.size == 0 {
        return Vec::new();
    }
    std::slice::from_raw_parts(digest.data, digest.size).to_vec()
}

/// Stores one fetched node into the upstream local CAS.
unsafe fn store_node(state: &CasState, node: &reapi::Node) -> bool {
    let mut ref_ids = Vec::with_capacity(node.refs.len());
    for reference in &node.refs {
        let digest = llcas_digest_t { data: reference.as_ptr(), size: reference.len() };
        let mut id = llcas_objectid_t { opaque: 0 };
        let mut id_error: *mut c_char = std::ptr::null_mut();
        if (state.up.llcas_cas_get_objectid)(state.cas, digest, &mut id, &mut id_error) {
            if !id_error.is_null() {
                (state.up.llcas_string_dispose)(id_error);
            }
            return false;
        }
        ref_ids.push(id);
    }
    let data = llcas_data_t { data: node.data.as_ptr() as *const c_void, size: node.data.len() };
    let mut stored = llcas_objectid_t { opaque: 0 };
    let mut store_error: *mut c_char = std::ptr::null_mut();
    let started = std::time::Instant::now();
    let failed = (state.up.llcas_cas_store_object)(
        state.cas,
        data,
        ref_ids.as_ptr(),
        ref_ids.len(),
        &mut stored,
        &mut store_error,
    );
    state.stats_mat_store.record(started.elapsed());
    state
        .stats_mat_store_bytes
        .fetch_add(node.data.len() as u64, Ordering::Relaxed);
    if failed {
        if !store_error.is_null() {
            (state.up.llcas_string_dispose)(store_error);
        }
        return false;
    }
    true
}

unsafe fn load_object_impl(
    state: &CasState,
    id: llcas_objectid_t,
    loaded: *mut llcas_loaded_object_t,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    // Local-only: the manifest-driven action-cache read-through materializes
    // the entire value graph before answering, so demand loads always find
    // their bytes locally.
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_load_object)(state.cas, id, loaded, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    result
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_load_object(
    cas: llcas_cas_t,
    id: llcas_objectid_t,
    loaded: *mut llcas_loaded_object_t,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    let state = cas_state(cas);
    ffi_guard(error, LLCAS_LOOKUP_RESULT_ERROR, "tuist-cas-plugin: panic during load", || {
        load_object_impl(state, id, loaded, error)
    })
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_load_object_async(
    cas: llcas_cas_t,
    id: llcas_objectid_t,
    ctx_cb: *mut c_void,
    callback: llcas_cas_load_object_cb,
    cancel_tok: *mut llcas_cancellable_t,
) {
    let state = cas_state(cas);

    // Fast path: local hit answers synchronously without a thread hop.
    let mut loaded = llcas_loaded_object_t { opaque: 0 };
    let mut probe_error: *mut c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_load_object)(state.cas, id, &mut loaded, &mut probe_error);
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND || state.remote.is_none() {
        let _ = ours_cancel_token(cancel_tok);
        let error = adopt_upstream_string(state.up, probe_error);
        callback(ctx_cb, result, loaded, error);
        return;
    }
    if !probe_error.is_null() {
        (state.up.llcas_string_dispose)(probe_error);
    }

    let _ = ours_cancel_token(cancel_tok);
    // Answered on the caller's thread: the demand fetch is a few ms against a
    // near cache, and a thread hop only adds scheduling latency to a build
    // pipeline that measures as mostly serial. The callback must fire exactly
    // once even if the impl panics, or the build system waits forever.
    let mut loaded = llcas_loaded_object_t { opaque: 0 };
    let mut error: *mut c_char = std::ptr::null_mut();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        load_object_impl(state, id, &mut loaded, &mut error)
    }))
    .unwrap_or_else(|_| {
        set_error(&mut error, "tuist-cas-plugin: panic during load");
        LLCAS_LOOKUP_RESULT_ERROR
    });
    callback(ctx_cb, result, loaded, error);
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_store_object(
    cas: llcas_cas_t,
    data: llcas_data_t,
    refs: *const llcas_objectid_t,
    refs_count: usize,
    p_id: *mut llcas_objectid_t,
    error: *mut *mut c_char,
) -> bool {
    let state = cas_state(cas);
    let started = std::time::Instant::now();
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_cas_store_object)(state.cas, data, refs, refs_count, p_id, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    state.stats_client_store.record(started.elapsed());
    state.stats_client_store_bytes.fetch_add(data.size as u64, Ordering::Relaxed);
    failed
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_store_from_filepath(
    cas: llcas_cas_t,
    filepath: *const c_char,
    p_id: *mut llcas_objectid_t,
    error: *mut *mut c_char,
) -> bool {
    let state = cas_state(cas);
    let failed = if let Some(store_from_filepath) = state.up.llcas_cas_store_from_filepath {
        let mut upstream_error: *mut c_char = std::ptr::null_mut();
        let failed = store_from_filepath(state.cas, filepath, p_id, &mut upstream_error);
        adopt_error(state.up, upstream_error, error);
        failed
    } else {
        let path = CStr::from_ptr(filepath).to_string_lossy().into_owned();
        match std::fs::read(&path) {
            Ok(contents) => {
                let data = llcas_data_t { data: contents.as_ptr() as *const c_void, size: contents.len() };
                let mut upstream_error: *mut c_char = std::ptr::null_mut();
                let failed =
                    (state.up.llcas_cas_store_object)(state.cas, data, std::ptr::null(), 0, p_id, &mut upstream_error);
                adopt_error(state.up, upstream_error, error);
                failed
            }
            Err(read_error) => {
                set_error(error, &format!("tuist-cas-plugin: failed to read {path}: {read_error}"));
                true
            }
        }
    };
    failed
}

// --- Read/write-through: action cache -------------------------------------------

unsafe fn actioncache_get_impl(
    state: &CasState,
    key: &[u8],
    globally: bool,
    p_value: *mut llcas_objectid_t,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    let key_digest = llcas_digest_t { data: key.as_ptr(), size: key.len() };
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result =
        (state.up.llcas_actioncache_get_for_digest)(state.cas, key_digest, p_value, globally, &mut upstream_error);
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND
        || (state.remote.is_none() && state.proxy.is_none())
    {
        adopt_error(state.up, upstream_error, error);
        return result;
    }
    if !upstream_error.is_null() {
        (state.up.llcas_string_dispose)(upstream_error);
    }

    let _demand_guard = DemandWaitGuard { state, started: std::time::Instant::now() };
    if let Some(client) = &state.proxy {
        let cas_path = state
            .cas_dir
            .as_ref()
            .map(|dir| dir.to_string_lossy().into_owned())
            .unwrap_or_default();
        match client.resolve(&cas_path, &state.proxy_instance, key) {
            Ok(Resolution::Hit(value_digest)) => {
                state.stats_remote_entry_hits.fetch_add(1, Ordering::Relaxed);
                let value_digest_t =
                    llcas_digest_t { data: value_digest.as_ptr(), size: value_digest.len() };
                let mut value_id = llcas_objectid_t { opaque: 0 };
                let mut id_error: *mut c_char = std::ptr::null_mut();
                if (state.up.llcas_cas_get_objectid)(state.cas, value_digest_t, &mut value_id, &mut id_error) {
                    adopt_error(state.up, id_error, error);
                    return LLCAS_LOOKUP_RESULT_ERROR;
                }
                let mut put_error: *mut c_char = std::ptr::null_mut();
                if (state.up.llcas_actioncache_put_for_digest)(state.cas, key_digest, value_id, false, &mut put_error) {
                    adopt_error(state.up, put_error, error);
                    return LLCAS_LOOKUP_RESULT_ERROR;
                }
                if !p_value.is_null() {
                    *p_value = value_id;
                }
                return LLCAS_LOOKUP_RESULT_SUCCESS;
            }
            Ok(Resolution::Miss) => {
                state.stats_remote_misses.fetch_add(1, Ordering::Relaxed);
                return LLCAS_LOOKUP_RESULT_NOTFOUND;
            }
            Err(message) => {
                state.stats_remote_misses.fetch_add(1, Ordering::Relaxed);
                log_line(&format!("proxy resolve error: {message}"));
                return LLCAS_LOOKUP_RESULT_NOTFOUND;
            }
        }
    }
    let remote = state.remote.as_ref().unwrap();
    let manifest = match remote.get_action(key) {
        Ok(Some(manifest)) if !manifest.is_empty() => manifest,
        Ok(_) => {
            state.stats_remote_misses.fetch_add(1, Ordering::Relaxed);
            log_miss(key);
            return LLCAS_LOOKUP_RESULT_NOTFOUND;
        }
        Err(message) => {
            state.stats_remote_misses.fetch_add(1, Ordering::Relaxed);
            log_line(&format!("get_action failed: {message}"));
            return LLCAS_LOOKUP_RESULT_NOTFOUND;
        }
    };
    state.stats_remote_entry_hits.fetch_add(1, Ordering::Relaxed);
    state
        .stats_manifest_entries
        .fetch_add(manifest.len() as u64, Ordering::Relaxed);

    // The manifest names every blob in the value graph up front; fetch only
    // what the local CAS lacks, in one batched round trip.
    let missing: Vec<&ManifestEntry> = manifest
        .iter()
        .filter(|entry| {
            if state
                .known_local
                .lock()
                .unwrap()
                .contains(&entry.llcas_digest)
            {
                return false;
            }
            let digest_t =
                llcas_digest_t { data: entry.llcas_digest.as_ptr(), size: entry.llcas_digest.len() };
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut id_error: *mut c_char = std::ptr::null_mut();
            if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut id_error) {
                if !id_error.is_null() {
                    (state.up.llcas_string_dispose)(id_error);
                }
                return true;
            }
            // Authoritative presence check: an actual load, the same call the
            // consumer will make.
            let mut loaded = llcas_loaded_object_t { opaque: 0 };
            let mut check_error: *mut c_char = std::ptr::null_mut();
            let present = (state.up.llcas_cas_load_object)(state.cas, id, &mut loaded, &mut check_error);
            if !check_error.is_null() {
                (state.up.llcas_string_dispose)(check_error);
            }
            if present == LLCAS_LOOKUP_RESULT_SUCCESS {
                state
                    .known_local
                    .lock()
                    .unwrap()
                    .insert(entry.llcas_digest.clone());
                return false;
            }
            true
        })
        .collect();
    if !missing.is_empty() {
        let digests: Vec<_> = missing.iter().map(|entry| entry.blob.clone()).collect();
        let contents = match remote.batch_read(&digests) {
            Ok(contents) => contents,
            Err(message) => {
                log_line(&format!("batch_read failed: {message}"));
                return LLCAS_LOOKUP_RESULT_NOTFOUND;
            }
        };
        for entry in &missing {
            // An unreadable or absent blob means the published graph is
            // incomplete; degrade to a miss and let the client recompute.
            let Some(blob) = contents.get(&entry.blob.hash) else {
                return LLCAS_LOOKUP_RESULT_NOTFOUND;
            };
            let Some(frame) = reapi::decompress_frame(blob) else {
                return LLCAS_LOOKUP_RESULT_NOTFOUND;
            };
            let Some(node) = reapi::decode_frame(&frame) else {
                return LLCAS_LOOKUP_RESULT_NOTFOUND;
            };
            if !store_node(state, &node) {
                return LLCAS_LOOKUP_RESULT_NOTFOUND;
            }
            state
                .known_local
                .lock()
                .unwrap()
                .insert(entry.llcas_digest.clone());
            state.stats_remote_node_hits.fetch_add(1, Ordering::Relaxed);
        }
    }
    let value_digest = manifest[0].llcas_digest.clone();

    let value_digest_t = llcas_digest_t { data: value_digest.as_ptr(), size: value_digest.len() };
    let mut value_id = llcas_objectid_t { opaque: 0 };
    let mut id_error: *mut c_char = std::ptr::null_mut();
    if (state.up.llcas_cas_get_objectid)(state.cas, value_digest_t, &mut value_id, &mut id_error) {
        adopt_error(state.up, id_error, error);
        return LLCAS_LOOKUP_RESULT_ERROR;
    }

    let mut put_error: *mut c_char = std::ptr::null_mut();
    let put_started = std::time::Instant::now();
    let put_failed =
        (state.up.llcas_actioncache_put_for_digest)(state.cas, key_digest, value_id, false, &mut put_error);
    state
        .stats_local_put_ms
        .fetch_add(put_started.elapsed().as_millis() as u64, Ordering::Relaxed);
    if put_failed {
        adopt_error(state.up, put_error, error);
        return LLCAS_LOOKUP_RESULT_ERROR;
    }

    if !p_value.is_null() {
        *p_value = value_id;
    }
    LLCAS_LOOKUP_RESULT_SUCCESS
}

#[no_mangle]
pub unsafe extern "C" fn llcas_actioncache_get_for_digest(
    cas: llcas_cas_t,
    key: llcas_digest_t,
    p_value: *mut llcas_objectid_t,
    globally: bool,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    let state = cas_state(cas);
    let key = std::slice::from_raw_parts(key.data, key.size).to_vec();
    ffi_guard(error, LLCAS_LOOKUP_RESULT_ERROR, "tuist-cas-plugin: panic during cache query", || {
        actioncache_get_impl(state, &key, globally, p_value, error)
    })
}

#[no_mangle]
pub unsafe extern "C" fn llcas_actioncache_get_for_digest_async(
    cas: llcas_cas_t,
    key: llcas_digest_t,
    globally: bool,
    ctx_cb: *mut c_void,
    callback: llcas_actioncache_get_cb,
    cancel_tok: *mut llcas_cancellable_t,
) {
    let state = cas_state(cas);
    let key_bytes = std::slice::from_raw_parts(key.data, key.size).to_vec();

    // Fast path: answer local hits synchronously.
    let mut value = llcas_objectid_t { opaque: 0 };
    let key_digest = llcas_digest_t { data: key_bytes.as_ptr(), size: key_bytes.len() };
    let mut probe_error: *mut c_char = std::ptr::null_mut();
    let result =
        (state.up.llcas_actioncache_get_for_digest)(state.cas, key_digest, &mut value, globally, &mut probe_error);
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND
        || (state.remote.is_none() && state.proxy.is_none())
    {
        let _ = ours_cancel_token(cancel_tok);
        let error = adopt_upstream_string(state.up, probe_error);
        callback(ctx_cb, result, value, error);
        return;
    }
    if !probe_error.is_null() {
        (state.up.llcas_string_dispose)(probe_error);
    }

    let _ = ours_cancel_token(cancel_tok);
    // Answered on the caller's thread; see llcas_cas_load_object_async.
    let mut value = llcas_objectid_t { opaque: 0 };
    let mut error: *mut c_char = std::ptr::null_mut();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        actioncache_get_impl(state, &key_bytes, globally, &mut value, &mut error)
    }))
    .unwrap_or_else(|_| {
        set_error(&mut error, "tuist-cas-plugin: panic during cache query");
        LLCAS_LOOKUP_RESULT_ERROR
    });
    callback(ctx_cb, result, value, error);
}

unsafe fn actioncache_put_remote(state: &CasState, key: &[u8], value: llcas_objectid_t) {
    if state.proxy.is_some() && state.upload {
        let value_digest = digest_bytes(state, value);
        if !state
            .published
            .lock()
            .unwrap()
            .insert((key.to_vec(), value_digest.clone()))
        {
            return;
        }
        let record = PublishRecord { key: key.to_vec(), value_digest, spool_path: None };
        if let Some(path) = write_publish_record(state, &record) {
            let cas_path = state
                .cas_dir
                .as_ref()
                .map(|dir| dir.to_string_lossy().into_owned())
                .unwrap_or_default();
            if let Some(client) = &state.proxy {
                // Failure is fine: the record survives for the proxy sweep.
                let _ = client.publish(&cas_path, &state.proxy_instance, &path.to_string_lossy());
            }
        }
        return;
    }
    if state.remote.is_some() && state.upload {
        if std::env::var("TUIST_CAS_LOG_PUTS").is_ok() {
            let mut hex = String::with_capacity(key.len() * 2);
            for byte in key {
                hex.push_str(&format!("{byte:02x}"));
            }
            log_line(&format!("put key={hex}"));
        }
        let value_digest = digest_bytes(state, value);
        if !state
            .published
            .lock()
            .unwrap()
            .insert((key.to_vec(), value_digest.clone()))
        {
            return;
        }
        let mut record = PublishRecord {
            key: key.to_vec(),
            value_digest,
            spool_path: None,
        };
        record.spool_path = write_publish_record(state, &record);
        state.uploader.enqueue(record.encode_item());
    }
}

/// Loads a node from the local CAS and encodes its transport blob. Returns
/// the compressed frame and the node's child digests.
unsafe fn encode_node_blob(
    state: &CasState,
    digest: &[u8],
) -> Result<(Vec<u8>, Vec<Vec<u8>>), String> {
    state.stats_upload_walk_loads.fetch_add(1, Ordering::Relaxed);
    let digest_t = llcas_digest_t { data: digest.as_ptr(), size: digest.len() };
    let mut id = llcas_objectid_t { opaque: 0 };
    let mut id_error: *mut c_char = std::ptr::null_mut();
    if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut id_error) {
        if !id_error.is_null() {
            (state.up.llcas_string_dispose)(id_error);
        }
        return Err("objectid".into());
    }
    let mut loaded = llcas_loaded_object_t { opaque: 0 };
    let mut load_error: *mut c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_load_object)(state.cas, id, &mut loaded, &mut load_error);
    if !load_error.is_null() {
        (state.up.llcas_string_dispose)(load_error);
    }
    if result != LLCAS_LOOKUP_RESULT_SUCCESS {
        return Err("local load".into());
    }
    let data = (state.up.llcas_loaded_object_get_data)(state.cas, loaded);
    let node_data = std::slice::from_raw_parts(data.data as *const u8, data.size);
    let refs = (state.up.llcas_loaded_object_get_refs)(state.cas, loaded);
    let count = (state.up.llcas_object_refs_get_count)(state.cas, refs);
    let mut ref_digests = Vec::with_capacity(count);
    for index in 0..count {
        let child = (state.up.llcas_object_refs_get_id)(state.cas, refs, index);
        ref_digests.push(digest_bytes(state, child));
    }
    let blob = reapi::compress_frame(&reapi::encode_frame(&ref_digests, node_data));
    Ok((blob, ref_digests))
}

/// Uploader worker: completes one publication over REAPI. Fast-skips when
/// this exact result is already published; otherwise walks the closure from
/// the local CAS, uploads only the blobs the server reports missing, and
/// publishes the ActionResult manifest LAST, so a reader can never observe
/// an entry whose graph is incomplete. On failure the write-ahead record
/// survives for a later sweep.
fn upload_process(cas_addr: usize, item: Vec<u8>) {
    unsafe {
        let state = cas_state(cas_addr as llcas_cas_t);
        let Some(remote) = &state.remote else { return };
        let Some(record) = PublishRecord::decode_item(&item) else { return };

        let outcome = (|| -> Result<(), String> {
            if let Ok(Some(manifest)) = remote.get_action(&record.key) {
                if manifest.first().map(|entry| entry.llcas_digest.as_slice())
                    == Some(record.value_digest.as_slice())
                {
                    return Ok(());
                }
            }

            // Walk the closure from the shared local CAS, root first. Shared
            // subtrees appear in many closures; the publish cache makes each
            // unique node's load + compress + hash happen once per process.
            let mut entries: Vec<ManifestEntry> = Vec::new();
            let mut blobs: Vec<Option<Vec<u8>>> = Vec::new();
            let mut visited = std::collections::HashSet::new();
            let mut pending = std::collections::VecDeque::from([record.value_digest.clone()]);
            while let Some(digest) = pending.pop_front() {
                if !visited.insert(digest.clone()) {
                    continue;
                }
                if let Some((blob_digest, children)) =
                    state.publish_cache.lock().unwrap().get(&digest).cloned()
                {
                    entries.push(ManifestEntry { llcas_digest: digest, blob: blob_digest });
                    blobs.push(None);
                    pending.extend(children);
                    continue;
                }
                let (blob, children) = encode_node_blob(state, &digest)?;
                let blob_digest = reapi::blob_digest(&blob);
                state
                    .publish_cache
                    .lock()
                    .unwrap()
                    .insert(digest.clone(), (blob_digest.clone(), children.clone()));
                entries.push(ManifestEntry { llcas_digest: digest, blob: blob_digest });
                blobs.push(Some(blob));
                pending.extend(children);
            }

            // Server-side dedup: upload only what the server lacks. Bytes
            // dropped by the cache are re-encoded only if actually needed.
            let missing =
                remote.find_missing(entries.iter().map(|entry| entry.blob.clone()).collect())?;
            let missing_set: std::collections::HashSet<(String, i64)> = missing
                .into_iter()
                .map(|digest| (digest.hash, digest.size_bytes))
                .collect();
            let mut uploads: Vec<(reapi::Digest, Vec<u8>)> = Vec::new();
            for (entry, blob) in entries.iter().zip(blobs) {
                if !missing_set.contains(&(entry.blob.hash.clone(), entry.blob.size_bytes)) {
                    continue;
                }
                let bytes = match blob {
                    Some(bytes) => bytes,
                    None => encode_node_blob(state, &entry.llcas_digest)?.0,
                };
                uploads.push((entry.blob.clone(), bytes));
            }
            if !uploads.is_empty() {
                remote.batch_update(uploads)?;
            }
            remote.update_action(&record.key, &entries)
        })();

        match outcome {
            Ok(()) => {
                if let Some(path) = &record.spool_path {
                    let _ = std::fs::remove_file(path);
                }
            }
            Err(reason) => {
                log_line(&format!("publish failed ({reason}); record kept for sweep"));
            }
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn llcas_actioncache_put_for_digest(
    cas: llcas_cas_t,
    key: llcas_digest_t,
    value: llcas_objectid_t,
    globally: bool,
    error: *mut *mut c_char,
) -> bool {
    let state = cas_state(cas);
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_actioncache_put_for_digest)(state.cas, key, value, globally, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
    if !failed {
        let key = std::slice::from_raw_parts(key.data, key.size).to_vec();
        // Best-effort remote publish: a panic here must neither fail the
        // already-succeeded local put nor unwind across the extern "C" boundary.
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            actioncache_put_remote(state, &key, value)
        }));
    }
    failed
}

#[no_mangle]
pub unsafe extern "C" fn llcas_actioncache_put_for_digest_async(
    cas: llcas_cas_t,
    key: llcas_digest_t,
    value: llcas_objectid_t,
    globally: bool,
    ctx_cb: *mut c_void,
    callback: llcas_actioncache_put_cb,
    cancel_tok: *mut llcas_cancellable_t,
) {
    let state = cas_state(cas);
    let _ = ours_cancel_token(cancel_tok);
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_actioncache_put_for_digest)(state.cas, key, value, globally, &mut upstream_error);
    let error = adopt_upstream_string(state.up, upstream_error);
    if !failed {
        let key = std::slice::from_raw_parts(key.data, key.size).to_vec();
        // Best-effort remote publish: swallow panics so they cannot fail the
        // local put or unwind across the extern "C" boundary.
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            actioncache_put_remote(state, &key, value)
        }));
    }
    callback(ctx_cb, failed, error);
}
