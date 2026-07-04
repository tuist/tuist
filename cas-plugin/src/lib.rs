//! Tuist CAS plugin: an LLVM CAS plugin (llcas ABI v0.1) that wraps Xcode's
//! libToolchainCASPlugin for local storage and hashing, and adds kura-backed
//! remoteness as read-through on miss + write-through on store.
//!
//! The build system runs in its fast "plugin-local" mode (no
//! COMPILATION_CACHE_REMOTE_SERVICE_PATH); this plugin owns all remote
//! traffic. Interception is deliberately not keyed on the `globally` flag,
//! which is never set on this path.

mod prefetch;
mod remote;
mod types;
mod upstream;

use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};

use prefetch::Prefetcher;
use remote::{Remote, RemoteConfig};
use types::*;
use upstream::Upstream;

// --- Global upstream table ---------------------------------------------------

static UPSTREAM: OnceLock<Result<&'static Upstream, String>> = OnceLock::new();

fn upstream_path() -> String {
    if let Ok(path) = std::env::var("TUIST_CAS_UPSTREAM_PLUGIN") {
        return path;
    }
    let developer_dir =
        std::env::var("DEVELOPER_DIR").unwrap_or_else(|_| "/Applications/Xcode.app/Contents/Developer".into());
    format!("{developer_dir}/usr/lib/libToolchainCASPlugin.dylib")
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

struct CasState {
    up: &'static Upstream,
    cas: llcas_cas_t,
    remote: Option<Arc<Remote>>,
    prefetcher: Prefetcher,
    // Uploads value-object graphs on actioncache_put. Deliberately NOT hooked
    // on store_object: the compiler stores input ingests and scan trees every
    // build (warm included), and mirroring those re-uploads the world.
    uploader: Prefetcher,
    stats_remote_entry_hits: AtomicU64,
    stats_remote_node_hits: AtomicU64,
    stats_remote_misses: AtomicU64,
    // Time spent resolving demand-driven remote work (entry read-through and
    // object-load materialization). This bounds how far warm-remote can sit
    // above the local-replay floor due to fetching, as opposed to overheads.
    stats_demand_wait_ms: AtomicU64,
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

unsafe fn wrap_upstream_cancel_token(
    up: &'static Upstream,
    slot: *mut llcas_cancellable_t,
    inner_slot: llcas_cancellable_t,
) {
    if !slot.is_null() {
        *slot = Box::into_raw(Box::new(CancelToken::Upstream(up, inner_slot))) as llcas_cancellable_t;
    }
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

    let remote = RemoteConfig::from_env().map(Remote::new);
    let has_remote = remote.is_some();
    let state_ptr = Box::into_raw(Box::new(CasState {
        up,
        cas: upstream_cas,
        remote,
        prefetcher: Prefetcher::new(),
        uploader: Prefetcher::new(),
        stats_remote_entry_hits: AtomicU64::new(0),
        stats_remote_node_hits: AtomicU64::new(0),
        stats_remote_misses: AtomicU64::new(0),
        stats_demand_wait_ms: AtomicU64::new(0),
    }));
    if has_remote {
        let cas_addr = state_ptr as usize;
        (*state_ptr).prefetcher.configure(Prefetcher::worker_count(), move |digest| {
            prefetch_process(cas_addr, digest);
        });
        (*state_ptr).uploader.configure(Prefetcher::worker_count(), move |digest| {
            upload_process(cas_addr, digest);
        });
    }
    state_ptr as llcas_cas_t
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
        state.prefetcher.stop();
        state.uploader.drain_stop();
        if let Some(remote) = &state.remote {
            remote.drain();
            log_line(&format!(
                "dispose: remote entry hits={} node hits={} misses={} prefetched={} demand_wait={}ms | gets {} | posts {}",
                state.stats_remote_entry_hits.load(Ordering::Relaxed),
                state.stats_remote_node_hits.load(Ordering::Relaxed),
                state.stats_remote_misses.load(Ordering::Relaxed),
                state.prefetcher.fetched.load(Ordering::Relaxed),
                state.stats_demand_wait_ms.load(Ordering::Relaxed),
                remote.get_stats.summary(),
                remote.post_stats.summary(),
            ));
        }
        (state.up.llcas_cas_dispose)(state.cas);
    }
    drop(Box::from_raw(state_ptr));
}

fn log_line(message: &str) {
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

/// Fetches a node from the remote and stores it into the upstream local CAS.
/// Returns the node's ref digests on success, or None when the node is not
/// available remotely, so callers can hand the children to the prefetcher.
unsafe fn materialize_node(state: &CasState, digest: &[u8]) -> Result<Option<Vec<Vec<u8>>>, String> {
    let Some(remote) = &state.remote else { return Ok(None) };
    let Some(node) = remote.get_node(digest) else {
        state.stats_remote_misses.fetch_add(1, Ordering::Relaxed);
        return Ok(None);
    };
    state.stats_remote_node_hits.fetch_add(1, Ordering::Relaxed);

    let mut ref_ids = Vec::with_capacity(node.refs.len());
    for reference in &node.refs {
        let digest = llcas_digest_t { data: reference.as_ptr(), size: reference.len() };
        let mut id = llcas_objectid_t { opaque: 0 };
        let mut error: *mut c_char = std::ptr::null_mut();
        if (state.up.llcas_cas_get_objectid)(state.cas, digest, &mut id, &mut error) {
            let message = adopt_upstream_string(state.up, error);
            let text = if message.is_null() { "get_objectid failed".into() } else {
                let s = CStr::from_ptr(message).to_string_lossy().into_owned();
                llcas_string_dispose(message);
                s
            };
            return Err(text);
        }
        ref_ids.push(id);
    }

    let data = llcas_data_t { data: node.data.as_ptr() as *const c_void, size: node.data.len() };
    let mut stored_id = llcas_objectid_t { opaque: 0 };
    let mut error: *mut c_char = std::ptr::null_mut();
    if (state.up.llcas_cas_store_object)(
        state.cas,
        data,
        ref_ids.as_ptr(),
        ref_ids.len(),
        &mut stored_id,
        &mut error,
    ) {
        let message = adopt_upstream_string(state.up, error);
        let text = if message.is_null() { "store_object failed".into() } else {
            let s = CStr::from_ptr(message).to_string_lossy().into_owned();
            llcas_string_dispose(message);
            s
        };
        return Err(text);
    }
    Ok(Some(node.refs))
}

/// Prefetch worker: materializes one node if missing locally, then walks its
/// refs. Locally present nodes are still traversed because shallow
/// materialization leaves dangling children behind.
fn prefetch_process(cas_addr: usize, digest: Vec<u8>) {
    unsafe {
        let state = cas_state(cas_addr as llcas_cas_t);
        let digest_t = llcas_digest_t { data: digest.as_ptr(), size: digest.len() };
        let mut id = llcas_objectid_t { opaque: 0 };
        let mut id_error: *mut c_char = std::ptr::null_mut();
        if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut id_error) {
            if !id_error.is_null() {
                (state.up.llcas_string_dispose)(id_error);
            }
            return;
        }

        let mut loaded = llcas_loaded_object_t { opaque: 0 };
        let mut load_error: *mut c_char = std::ptr::null_mut();
        let result = (state.up.llcas_cas_load_object)(state.cas, id, &mut loaded, &mut load_error);
        if !load_error.is_null() {
            (state.up.llcas_string_dispose)(load_error);
        }
        match result {
            LLCAS_LOOKUP_RESULT_SUCCESS => {
                let refs = (state.up.llcas_loaded_object_get_refs)(state.cas, loaded);
                let count = (state.up.llcas_object_refs_get_count)(state.cas, refs);
                for index in 0..count {
                    let child = (state.up.llcas_object_refs_get_id)(state.cas, refs, index);
                    state.prefetcher.enqueue(digest_bytes(state, child));
                }
            }
            LLCAS_LOOKUP_RESULT_NOTFOUND => {
                if let Ok(Some(child_digests)) = materialize_node(state, &digest) {
                    state.prefetcher.fetched.fetch_add(1, Ordering::Relaxed);
                    for child in child_digests {
                        state.prefetcher.enqueue(child);
                    }
                }
            }
            _ => {}
        }
    }
}

unsafe fn load_object_impl(
    state: &CasState,
    id: llcas_objectid_t,
    loaded: *mut llcas_loaded_object_t,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_load_object)(state.cas, id, loaded, &mut upstream_error);
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND || state.remote.is_none() {
        adopt_error(state.up, upstream_error, error);
        return result;
    }
    if !upstream_error.is_null() {
        (state.up.llcas_string_dispose)(upstream_error);
    }

    let started = std::time::Instant::now();
    let digest = digest_bytes(state, id);
    let outcome = match materialize_node(state, &digest) {
        Ok(Some(child_digests)) => {
            for child in child_digests {
                state.prefetcher.enqueue(child);
            }
            let mut retry_error: *mut c_char = std::ptr::null_mut();
            let result = (state.up.llcas_cas_load_object)(state.cas, id, loaded, &mut retry_error);
            adopt_error(state.up, retry_error, error);
            result
        }
        Ok(None) => LLCAS_LOOKUP_RESULT_NOTFOUND,
        Err(message) => {
            set_error(error, &message);
            LLCAS_LOOKUP_RESULT_ERROR
        }
    };
    state
        .stats_demand_wait_ms
        .fetch_add(started.elapsed().as_millis() as u64, Ordering::Relaxed);
    outcome
}

#[no_mangle]
pub unsafe extern "C" fn llcas_cas_load_object(
    cas: llcas_cas_t,
    id: llcas_objectid_t,
    loaded: *mut llcas_loaded_object_t,
    error: *mut *mut c_char,
) -> llcas_lookup_result_t {
    load_object_impl(cas_state(cas), id, loaded, error)
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
    let cas_addr = cas as usize;
    let ctx_addr = ctx_cb as usize;
    std::thread::spawn(move || {
        let state = cas_state(cas_addr as llcas_cas_t);
        let mut loaded = llcas_loaded_object_t { opaque: 0 };
        let mut error: *mut c_char = std::ptr::null_mut();
        // The callback must fire exactly once even if the impl panics, or the
        // build system waits forever.
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            load_object_impl(state, id, &mut loaded, &mut error)
        }))
        .unwrap_or_else(|_| {
            set_error(&mut error, "tuist-cas-plugin: panic during load");
            LLCAS_LOOKUP_RESULT_ERROR
        });
        callback(ctx_addr as *mut c_void, result, loaded, error);
    });
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
    let mut upstream_error: *mut c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_cas_store_object)(state.cas, data, refs, refs_count, p_id, &mut upstream_error);
    adopt_error(state.up, upstream_error, error);
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
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND || state.remote.is_none() {
        adopt_error(state.up, upstream_error, error);
        return result;
    }
    if !upstream_error.is_null() {
        (state.up.llcas_string_dispose)(upstream_error);
    }

    let _demand_guard = DemandWaitGuard { state, started: std::time::Instant::now() };
    let remote = state.remote.as_ref().unwrap();
    let Some(value_digest) = remote.get_entry(key) else {
        state.stats_remote_misses.fetch_add(1, Ordering::Relaxed);
        return LLCAS_LOOKUP_RESULT_NOTFOUND;
    };
    state.stats_remote_entry_hits.fetch_add(1, Ordering::Relaxed);

    // Materialize the value object, then let the prefetcher walk the ref
    // graph in the background so frontend demand loads land locally.
    match materialize_node(state, &value_digest) {
        Ok(Some(child_digests)) => {
            for child in child_digests {
                state.prefetcher.enqueue(child);
            }
        }
        Ok(None) => return LLCAS_LOOKUP_RESULT_NOTFOUND,
        Err(message) => {
            set_error(error, &message);
            return LLCAS_LOOKUP_RESULT_ERROR;
        }
    }

    let value_digest_t = llcas_digest_t { data: value_digest.as_ptr(), size: value_digest.len() };
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
    actioncache_get_impl(state, &key, globally, p_value, error)
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
    if result != LLCAS_LOOKUP_RESULT_NOTFOUND || state.remote.is_none() {
        let _ = ours_cancel_token(cancel_tok);
        let error = adopt_upstream_string(state.up, probe_error);
        callback(ctx_cb, result, value, error);
        return;
    }
    if !probe_error.is_null() {
        (state.up.llcas_string_dispose)(probe_error);
    }

    let _ = ours_cancel_token(cancel_tok);
    let cas_addr = cas as usize;
    let ctx_addr = ctx_cb as usize;
    std::thread::spawn(move || {
        let state = cas_state(cas_addr as llcas_cas_t);
        let mut value = llcas_objectid_t { opaque: 0 };
        let mut error: *mut c_char = std::ptr::null_mut();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            actioncache_get_impl(state, &key_bytes, globally, &mut value, &mut error)
        }))
        .unwrap_or_else(|_| {
            set_error(&mut error, "tuist-cas-plugin: panic during cache query");
            LLCAS_LOOKUP_RESULT_ERROR
        });
        callback(ctx_addr as *mut c_void, result, value, error);
    });
}

unsafe fn actioncache_put_remote(state: &CasState, key: &[u8], value: llcas_objectid_t) {
    if let Some(remote) = &state.remote {
        let value_digest = digest_bytes(state, value);
        // Upload the value's object graph, then publish the entry. Ordering
        // is per-process best effort: a reader seeing the entry before the
        // graph lands degrades to a cache miss.
        state.uploader.enqueue(value_digest.clone());
        remote.enqueue_entry(key, &value_digest);
    }
}

/// Uploader worker: pushes one locally stored node to the remote and queues
/// its children, walking the value graph produced by an actioncache_put.
fn upload_process(cas_addr: usize, digest: Vec<u8>) {
    unsafe {
        let state = cas_state(cas_addr as llcas_cas_t);
        let Some(remote) = &state.remote else { return };
        let digest_t = llcas_digest_t { data: digest.as_ptr(), size: digest.len() };
        let mut id = llcas_objectid_t { opaque: 0 };
        let mut id_error: *mut c_char = std::ptr::null_mut();
        if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut id_error) {
            if !id_error.is_null() {
                (state.up.llcas_string_dispose)(id_error);
            }
            return;
        }
        let mut loaded = llcas_loaded_object_t { opaque: 0 };
        let mut load_error: *mut c_char = std::ptr::null_mut();
        let result = (state.up.llcas_cas_load_object)(state.cas, id, &mut loaded, &mut load_error);
        if !load_error.is_null() {
            (state.up.llcas_string_dispose)(load_error);
        }
        if result != LLCAS_LOOKUP_RESULT_SUCCESS {
            return;
        }
        let data = (state.up.llcas_loaded_object_get_data)(state.cas, loaded);
        let payload = std::slice::from_raw_parts(data.data as *const u8, data.size);
        let refs = (state.up.llcas_loaded_object_get_refs)(state.cas, loaded);
        let count = (state.up.llcas_object_refs_get_count)(state.cas, refs);
        let mut ref_digests = Vec::with_capacity(count);
        for index in 0..count {
            let child = (state.up.llcas_object_refs_get_id)(state.cas, refs, index);
            ref_digests.push(digest_bytes(state, child));
        }
        remote.upload_node(&digest, &ref_digests, payload);
        for child in ref_digests {
            state.uploader.enqueue(child);
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
        actioncache_put_remote(state, &key, value);
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
        actioncache_put_remote(state, &key, value);
    }
    callback(ctx_cb, failed, error);
}
