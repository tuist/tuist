//! Tuist CAS plugin: an LLVM CAS plugin (llcas ABI v0.1) that wraps Xcode's
//! libToolchainCASPlugin for local storage and hashing, and adds kura-backed
//! remoteness over the Bazel Remote Execution API (see reapi.rs).
//!
//! This plugin owns all remote traffic. `COMPILATION_CACHE_REMOTE_SERVICE_PATH`
//! points at our proxy's socket, but Xcode's own remote client never sees it: we
//! consume the matching `remote-service-path` option below rather than forwarding
//! it to the wrapped plugin. The setting is still required, because it is what
//! turns on the build system's clang caching lane, which routes C, Objective-C,
//! precompiled modules and headers through whichever CAS plugin is configured.
//! Without it, only Swift compilations are shared.
//!
//! Interception is therefore not keyed on the `globally` flag: the clang lane
//! sets it and the Swift path does not, and both are ours to serve.

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
use reapi::OpStats;
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
    // All remote work is delegated to the per-machine proxy over a unix
    // socket; this process runs no gRPC client at all. Always present: an
    // unconfigured socket resolves to the well-known path, and a proxy that is
    // not listening degrades per op rather than up front.
    proxy: ProxyClient,
    // The account/project this build's cache belongs to, declared to the proxy
    // so it routes to the right instance. Empty for an Xcode ⌘B build (no CLI
    // env); the proxy then falls back to its primed cas_path mapping.
    proxy_instance: String,
    // Upload policy from `xcodeCache(upload:)`. When false, read hits still work
    // but no value graphs are published (the read path is unchanged). Carried by
    // the `tuist-upload` plugin option (so it reaches every frontend, including a
    // ⌘B build) with the `TUIST_CAS_UPLOAD` env as a fallback; see resolve_upload.
    upload: bool,
    // (key -> value digest) associations served FROM the remote by this
    // process, so the client's end-of-job re-puts of replayed results skip
    // the publish path entirely (see actioncache_put_remote).
    remote_hits: Mutex<std::collections::HashMap<Vec<u8>, Vec<u8>>>,
    created_at: std::time::Instant,
    cas_dir: Option<std::path::PathBuf>,
    // Uploads value-object graphs on actioncache_put. Deliberately NOT hooked
    // on store_object: the compiler stores input ingests and scan trees every
    // build (warm included), and mirroring those re-uploads the world.
    // The client puts the same (key, value) many times per build; only the
    // first becomes a publication. Publish items carry unique spool paths, so
    // the queue's content dedup cannot do this.
    published: Mutex<std::collections::HashSet<(Vec<u8>, Vec<u8>)>>,
    // Value graphs share children heavily across keys; without these caches a
    // warm build re-fetches (read side) and re-compresses/re-hashes (publish
    // side) the same nodes once per referencing key.
    known_local: Mutex<std::collections::HashSet<Vec<u8>>>,
    stats_remote_entry_hits: AtomicU64,
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
        let name_str = name.to_string_lossy();
        // Tuist-specific options are consumed here; everything else is
        // forwarded to the wrapped plugin. `remote-service-path` is also
        // consumed, never forwarded: in the remote-cache configuration the
        // build system passes it to the plugin, but this plugin serves remote
        // reads itself (kura read/write-through) and must not let the wrapped
        // Apple plugin run its own remote choreography against that socket.
        if name_str.starts_with("tuist-") || name_str == "remote-service-path" {
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

    // All remote work goes through the proxy, so there is always one to address:
    // an unset socket falls back to the well-known path rather than disabling
    // remote caching, because the Xcode ⌘B case carries no CLI environment and
    // would otherwise silently build local-only. If nothing is listening there
    // the connect fails per op and we degrade to the local CAS.
    let socket_path = std::env::var("TUIST_CAS_PROXY_SOCKET")
        .ok()
        .filter(|socket| !socket.is_empty())
        .unwrap_or_else(default_proxy_socket);
    let proxy = ProxyClient { socket_path };
    // Logged once per CAS create: a build that degrades to local-only (proxy
    // unreachable) is otherwise indistinguishable from a cold cache, since both
    // just emit misses.
    log_line(&format!(
        "cas create: proxy={:?} cas_dir={:?}",
        proxy.socket_path, state.ondisk_path,
    ));
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
    let cas_dir = state
        .ondisk_path
        .as_ref()
        .and_then(|p| p.to_str().ok())
        .map(std::path::PathBuf::from);
    let state_ptr = Box::into_raw(Box::new(CasState {
        up,
        cas: upstream_cas,
        proxy,
        proxy_instance,
        upload: resolve_upload(state),
        created_at: std::time::Instant::now(),
        cas_dir,
        published: Mutex::new(std::collections::HashSet::new()),
        remote_hits: Mutex::new(std::collections::HashMap::new()),
        known_local: Mutex::new(std::collections::HashSet::new()),
        stats_remote_entry_hits: AtomicU64::new(0),
        stats_remote_misses: AtomicU64::new(0),
        stats_demand_wait_ms: AtomicU64::new(0),
        stats_client_store: OpStats::default(),
        stats_client_store_bytes: AtomicU64::new(0),
        stats_mat_store: OpStats::default(),
        stats_mat_store_bytes: AtomicU64::new(0),
        stats_local_put_ms: AtomicU64::new(0),
    }));
    state_ptr as llcas_cas_t
}

fn spool_dir(state: &CasState) -> Option<std::path::PathBuf> {
    state.cas_dir.as_ref().map(|dir| dir.join("tuist-spool"))
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
        // Ingestion counters, logged whether or not this build reached the
        // proxy, so a floor build produces the same accounting as a warm one.
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
    if let Some(cas_dir) = &state.cas_dir {
        let _ = state.proxy.invalidate(&cas_dir.to_string_lossy());
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


unsafe fn load_object_impl(
    state: &CasState,
    id: llcas_objectid_t,
    loaded: *mut llcas_loaded_object_t,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_load_object)(state.cas, id, loaded, &mut upstream_error);
    // Proxy mode answers action-cache gets BEFORE the value graph finishes
    // materializing (the caller of a get is swift-build's serial task-setup
    // path, which must never wait on a graph fetch). The load path — which
    // runs on parallel compiler worker threads — is where a not-yet-stored
    // node is produced: FETCH_OBJECT blocks until the proxy has it (present,
    // mid-materialization, or fetched on demand), then the local load retries.
    if result == LLCAS_LOOKUP_RESULT_NOTFOUND {
        let digest = (state.up.llcas_objectid_get_digest)(state.cas, id);
        let digest = std::slice::from_raw_parts(digest.data, digest.size);
        let cas_path = state
            .cas_dir
            .as_ref()
            .map(|dir| dir.to_string_lossy().into_owned())
            .unwrap_or_default();
        match state.proxy.fetch_object(&cas_path, &state.proxy_instance, digest) {
            Ok(true) => {
                if !upstream_error.is_null() {
                    (state.up.llcas_string_dispose)(upstream_error);
                }
                upstream_error = std::ptr::null_mut();
                let retried =
                    (state.up.llcas_cas_load_object)(state.cas, id, loaded, &mut upstream_error);
                adopt_error(state.up, upstream_error, error);
                return retried;
            }
            Ok(false) => {}
            Err(message) => {
                log_line(&format!("proxy fetch_object error: {message}"));
            }
        }
    }
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
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND {
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
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND {
        adopt_error(state.up, upstream_error, error);
        return result;
    }
    if !upstream_error.is_null() {
        (state.up.llcas_string_dispose)(upstream_error);
    }

    let _demand_guard = DemandWaitGuard { state, started: std::time::Instant::now() };
    let client = &state.proxy;
    let cas_path = state
        .cas_dir
        .as_ref()
        .map(|dir| dir.to_string_lossy().into_owned())
        .unwrap_or_default();
    match client.resolve(&cas_path, &state.proxy_instance, key) {
        Ok(Resolution::Hit(value_digest)) => {
            state.stats_remote_entry_hits.fetch_add(1, Ordering::Relaxed);
            // Remember the association: the client re-puts replayed results
            // at the end of its job, and re-publishing a (key, value) that
            // just came FROM the remote is pure churn — a spool write on
            // the compile path plus a proxy publish check per key
            // (thousands per warm build). actioncache_put_remote skips
            // puts that match this map.
            state
                .remote_hits
                .lock()
                .unwrap()
                .insert(key.to_vec(), value_digest.clone());
            let value_digest_t =
                llcas_digest_t { data: value_digest.as_ptr(), size: value_digest.len() };
            let mut value_id = llcas_objectid_t { opaque: 0 };
            let mut id_error: *mut c_char = std::ptr::null_mut();
            if (state.up.llcas_cas_get_objectid)(state.cas, value_digest_t, &mut value_id, &mut id_error) {
                adopt_error(state.up, id_error, error);
                return LLCAS_LOOKUP_RESULT_ERROR;
            }
            // The local association outlives the value graph (the build
            // system prunes the store several times per build), so a later
            // get can hit it locally with the objects gone. That is safe
            // ONLY because the load path self-heals: a local load miss
            // consults the proxy (FETCH_OBJECT), whose fetch instructions
            // are retained after materialization and also cover locally
            // published nodes — clang fails the build outright on a
            // missing object, it does not recompile.
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
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND {
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
    if state.upload {
        let value_digest = digest_bytes(state, value);
        // This exact association was served FROM the remote earlier in this
        // process (see actioncache_get_impl): publishing it back is pure churn.
        // A put with a DIFFERENT value for the same key still goes through.
        if state.remote_hits.lock().unwrap().get(key) == Some(&value_digest) {
            return;
        }
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
            // Failure is fine: the record survives for the proxy sweep.
            let _ =
                state.proxy.publish(&cas_path, &state.proxy_instance, &path.to_string_lossy());
        }
        return;
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
