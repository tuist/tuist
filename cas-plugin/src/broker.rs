//! The per-machine broker: one long-lived process owns the REAPI channel,
//! the resolved-key map, the global known-local set, and all publications.
//! Compiler processes stay thin (one unix-socket round trip per cache miss),
//! which is what keeps warm builds near the local-CAS floor: any fixed
//! per-process cost is multiplied by thousands of short-lived frontends.
//!
//! The broker opens the same on-disk local CAS the compilers use (the store
//! is multi-process by design) and materializes fetched graphs into it
//! before answering a resolve, so consumers' demand loads are local hits.

use std::collections::{HashMap, HashSet, VecDeque};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::Instant;

use crate::broker_proto::{
    read_request, write_response, Request, OP_PUBLISH, OP_RESOLVE, STATUS_ERROR, STATUS_HIT,
    STATUS_MISS,
};
use crate::prefetch::Prefetcher;
use crate::reapi::{self, ManifestEntry, Remote};
use crate::types::*;
use crate::upstream::Upstream;
use crate::PublishRecord;

/// Per-local-CAS-path state. Leaked for 'static lifetime: the broker runs
/// until killed.
pub struct PathState {
    up: &'static Upstream,
    cas: llcas_cas_t,
    // key digest -> Some(value digest) for published/fetched results, None
    // for definitive misses. A publish updates its entry, so a miss cached
    // during planning turns into a hit once the local build publishes it.
    resolved: Mutex<HashMap<Vec<u8>, Option<Vec<u8>>>>,
    // Single-flight: concurrent resolves of the same key (the build system
    // plans while the compiler asks) wait for the first instead of
    // duplicating manifest + fetch work.
    inflight: Mutex<HashSet<Vec<u8>>>,
    inflight_cvar: Condvar,
    // Sharded: this set is checked once per manifest entry (~1.9M times per
    // warm build) from every connection thread.
    known_local: [Mutex<HashSet<Vec<u8>>>; 32],
    publish_cache: Mutex<HashMap<Vec<u8>, (reapi::Digest, Vec<Vec<u8>>)>>,
    pub stats_resolves: AtomicU64,
    pub stats_remote_hits: AtomicU64,
    pub stats_misses: AtomicU64,
    pub stats_blobs_fetched: AtomicU64,
    pub stats_published: AtomicU64,
    pub ms_action: AtomicU64,
    pub ms_filter: AtomicU64,
    pub ms_fetch: AtomicU64,
    pub ms_decode: AtomicU64,
    pub ms_store: AtomicU64,
}

impl PathState {
    fn shard(&self, digest: &[u8]) -> &Mutex<HashSet<Vec<u8>>> {
        &self.known_local[digest.first().copied().unwrap_or(0) as usize % 32]
    }
}

// The broker is single-process and owns these raw handles for its lifetime;
// the llcas API is thread-safe (the same handles are shared across worker
// threads inside compiler processes too).
unsafe impl Send for PathState {}
unsafe impl Sync for PathState {}

pub struct Broker {
    remote: std::sync::Arc<Remote>,
    upstream_plugin: String,
    paths: Mutex<HashMap<String, &'static PathState>>,
    publisher: Prefetcher,
}

impl Broker {
    pub fn new(remote: std::sync::Arc<Remote>, upstream_plugin: String) -> &'static Broker {
        let broker: &'static Broker = Box::leak(Box::new(Broker {
            remote,
            upstream_plugin,
            paths: Mutex::new(HashMap::new()),
            publisher: Prefetcher::new(),
        }));
        let broker_addr = broker as *const Broker as usize;
        broker.publisher.configure(8, move |item| {
            let broker = unsafe { &*(broker_addr as *const Broker) };
            broker.publish_item(&item);
        });
        broker
    }

    fn path_state(&self, cas_path: &str) -> Result<&'static PathState, String> {
        if let Some(state) = self.paths.lock().unwrap().get(cas_path) {
            return Ok(state);
        }
        let up = unsafe { Upstream::load(&self.upstream_plugin)? };
        let up: &'static Upstream = Box::leak(Box::new(up));
        let cas = unsafe { open_cas(up, cas_path)? };
        let state: &'static PathState = Box::leak(Box::new(PathState {
            up,
            cas,
            resolved: Mutex::new(HashMap::new()),
            inflight: Mutex::new(HashSet::new()),
            inflight_cvar: Condvar::new(),
            known_local: std::array::from_fn(|_| Mutex::new(HashSet::new())),
            publish_cache: Mutex::new(HashMap::new()),
            stats_resolves: AtomicU64::new(0),
            stats_remote_hits: AtomicU64::new(0),
            stats_misses: AtomicU64::new(0),
            stats_blobs_fetched: AtomicU64::new(0),
            stats_published: AtomicU64::new(0),
            ms_action: AtomicU64::new(0),
            ms_filter: AtomicU64::new(0),
            ms_fetch: AtomicU64::new(0),
            ms_decode: AtomicU64::new(0),
            ms_store: AtomicU64::new(0),
        }));
        self.paths
            .lock()
            .unwrap()
            .insert(cas_path.to_string(), state);
        Ok(state)
    }

    /// Serves one RESOLVE: answer from the resolved map, else read-through
    /// (manifest + batched fetch of globally-missing blobs + local store).
    fn resolve(&self, state: &'static PathState, key: &[u8]) -> Result<Option<Vec<u8>>, String> {
        state.stats_resolves.fetch_add(1, Ordering::Relaxed);
        // Single-flight: wait out a concurrent resolve of the same key.
        {
            let mut inflight = state.inflight.lock().unwrap();
            loop {
                if let Some(resolution) = state.resolved.lock().unwrap().get(key) {
                    return Ok(resolution.clone());
                }
                if !inflight.contains(key) {
                    inflight.insert(key.to_vec());
                    break;
                }
                inflight = state.inflight_cvar.wait(inflight).unwrap();
            }
        }
        let outcome = self.resolve_uncached(state, key);
        {
            let mut inflight = state.inflight.lock().unwrap();
            inflight.remove(key);
            state.inflight_cvar.notify_all();
        }
        outcome
    }

    fn resolve_uncached(
        &self,
        state: &'static PathState,
        key: &[u8],
    ) -> Result<Option<Vec<u8>>, String> {
        let phase = Instant::now();
        let manifest = match self.remote.get_action(key)? {
            Some(manifest) if !manifest.is_empty() => manifest,
            _ => {
                state.stats_misses.fetch_add(1, Ordering::Relaxed);
                state.resolved.lock().unwrap().insert(key.to_vec(), None);
                return Ok(None);
            }
        };
        state.stats_remote_hits.fetch_add(1, Ordering::Relaxed);
        state
            .ms_action
            .fetch_add(phase.elapsed().as_millis() as u64, Ordering::Relaxed);

        let phase = Instant::now();
        let missing: Vec<&ManifestEntry> = manifest
            .iter()
            .filter(|entry| !self.is_local(state, &entry.llcas_digest))
            .collect();
        state
            .ms_filter
            .fetch_add(phase.elapsed().as_millis() as u64, Ordering::Relaxed);
        if !missing.is_empty() {
            // One batch per resolve: the server parallelizes blob reads
            // internally, so client-side fragmentation only multiplies
            // per-RPC overhead (measured: 6-way splitting of ~23-blob sets
            // pinned per-resolve latency at per-RPC cost times groups).
            let phase = Instant::now();
            let digests: Vec<_> = missing.iter().map(|entry| entry.blob.clone()).collect();
            let contents = self.remote.batch_read(&digests)?;
            state
                .ms_fetch
                .fetch_add(phase.elapsed().as_millis() as u64, Ordering::Relaxed);
            for entry in &missing {
                let Some(blob) = contents.get(&entry.blob.hash) else {
                    // Incomplete graph on the server: degrade to a miss (do
                    // not negative-cache; the writer may still be uploading).
                    return Ok(None);
                };
                let phase = Instant::now();
                let Some(frame) = reapi::decompress_frame(blob) else {
                    return Ok(None);
                };
                let Some(node) = reapi::decode_frame(&frame) else {
                    return Ok(None);
                };
                state
                    .ms_decode
                    .fetch_add(phase.elapsed().as_millis() as u64, Ordering::Relaxed);
                let phase = Instant::now();
                unsafe { store_node(state, &node)? };
                state
                    .ms_store
                    .fetch_add(phase.elapsed().as_millis() as u64, Ordering::Relaxed);
                state
                    .shard(&entry.llcas_digest)
                    .lock()
                    .unwrap()
                    .insert(entry.llcas_digest.clone());
                state.stats_blobs_fetched.fetch_add(1, Ordering::Relaxed);
            }
        }
        let value = manifest[0].llcas_digest.clone();
        state
            .resolved
            .lock()
            .unwrap()
            .insert(key.to_vec(), Some(value.clone()));
        Ok(Some(value))
    }

    fn is_local(&self, state: &PathState, digest: &[u8]) -> bool {
        if state.shard(digest).lock().unwrap().contains(digest) {
            return true;
        }
        unsafe {
            let digest_t = llcas_digest_t { data: digest.as_ptr(), size: digest.len() };
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
            if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut error) {
                if !error.is_null() {
                    (state.up.llcas_string_dispose)(error);
                }
                return false;
            }
            let mut loaded = llcas_loaded_object_t { opaque: 0 };
            let mut load_error: *mut std::ffi::c_char = std::ptr::null_mut();
            let result = (state.up.llcas_cas_load_object)(state.cas, id, &mut loaded, &mut load_error);
            if !load_error.is_null() {
                (state.up.llcas_string_dispose)(load_error);
            }
            if result == LLCAS_LOOKUP_RESULT_SUCCESS {
                state.shard(digest).lock().unwrap().insert(digest.to_vec());
                true
            } else {
                false
            }
        }
    }

    /// PUBLISH notify: queue the record for the publisher pool. Items encode
    /// cas_path + record path.
    fn enqueue_publish(&self, cas_path: &str, record_path: &str) {
        let mut item = Vec::with_capacity(2 + cas_path.len() + record_path.len());
        item.extend_from_slice(&(cas_path.len() as u16).to_be_bytes());
        item.extend_from_slice(cas_path.as_bytes());
        item.extend_from_slice(record_path.as_bytes());
        self.publisher.enqueue(item);
    }

    fn publish_item(&self, item: &[u8]) {
        if item.len() < 2 {
            return;
        }
        let path_len = u16::from_be_bytes([item[0], item[1]]) as usize;
        if item.len() < 2 + path_len {
            return;
        }
        let cas_path = String::from_utf8_lossy(&item[2..2 + path_len]).into_owned();
        let record_path = String::from_utf8_lossy(&item[2 + path_len..]).into_owned();
        let Ok(state) = self.path_state(&cas_path) else { return };
        let Ok(bytes) = std::fs::read(&record_path) else { return };
        let Some(record) =
            PublishRecord::decode_body(&bytes, Some(std::path::PathBuf::from(&record_path)))
        else {
            let _ = std::fs::remove_file(&record_path);
            return;
        };
        match self.publish(state, &record) {
            Ok(()) => {
                let _ = std::fs::remove_file(&record_path);
                state.stats_published.fetch_add(1, Ordering::Relaxed);
                state
                    .resolved
                    .lock()
                    .unwrap()
                    .insert(record.key.clone(), Some(record.value_digest.clone()));
            }
            Err(reason) => {
                crate::log_line(&format!("broker publish failed ({reason}); record kept"));
            }
        }
    }

    fn publish(&self, state: &'static PathState, record: &PublishRecord) -> Result<(), String> {
        if let Ok(Some(manifest)) = self.remote.get_action(&record.key) {
            if manifest.first().map(|entry| entry.llcas_digest.as_slice())
                == Some(record.value_digest.as_slice())
            {
                return Ok(());
            }
        }
        let mut entries: Vec<ManifestEntry> = Vec::new();
        let mut blobs: Vec<Option<Vec<u8>>> = Vec::new();
        let mut visited = HashSet::new();
        let mut pending = VecDeque::from([record.value_digest.clone()]);
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
            let (blob, children) = unsafe { encode_node_blob(state, &digest)? };
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
        let missing = self
            .remote
            .find_missing(entries.iter().map(|entry| entry.blob.clone()).collect())?;
        let missing_set: HashSet<(String, i64)> = missing
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
                None => unsafe { encode_node_blob(state, &entry.llcas_digest)?.0 },
            };
            uploads.push((entry.blob.clone(), bytes));
        }
        if !uploads.is_empty() {
            self.remote.batch_update(uploads)?;
        }
        self.remote.update_action(&record.key, &entries)
    }

    /// Sweeps orphaned publication records for every known CAS path.
    pub fn sweep(&self) {
        let paths: Vec<String> = self.paths.lock().unwrap().keys().cloned().collect();
        for cas_path in paths {
            let spool = std::path::Path::new(&cas_path).join("tuist-spool");
            let Ok(entries) = std::fs::read_dir(&spool) else { continue };
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    // Claims are ours alone now; reclaim anything.
                    let base = name.split_once(".claim-").map(|(b, _)| b.to_string());
                    let path = match base {
                        Some(base) => {
                            let claimed = spool.join(format!("{base}.claim-{}", std::process::id()));
                            if std::fs::rename(entry.path(), &claimed).is_err() {
                                continue;
                            }
                            claimed
                        }
                        None => entry.path(),
                    };
                    self.enqueue_publish(&cas_path, &path.to_string_lossy());
                }
            }
        }
    }

    pub fn stats_line(&self) -> String {
        let paths = self.paths.lock().unwrap();
        let mut parts = Vec::new();
        for (path, state) in paths.iter() {
            parts.push(format!(
                "{}: resolves={} remote_hits={} misses={} blobs={} published={} | ms action={} filter={} fetch={} decode={} store={}",
                path,
                state.stats_resolves.load(Ordering::Relaxed),
                state.stats_remote_hits.load(Ordering::Relaxed),
                state.stats_misses.load(Ordering::Relaxed),
                state.stats_blobs_fetched.load(Ordering::Relaxed),
                state.stats_published.load(Ordering::Relaxed),
                state.ms_action.load(Ordering::Relaxed),
                state.ms_filter.load(Ordering::Relaxed),
                state.ms_fetch.load(Ordering::Relaxed),
                state.ms_decode.load(Ordering::Relaxed),
                state.ms_store.load(Ordering::Relaxed),
            ));
        }
        parts.join(" | ")
    }

    pub fn serve(&'static self, listener: UnixListener) {
        for stream in listener.incoming() {
            let Ok(stream) = stream else { continue };
            std::thread::spawn(move || {
                let _ = self.handle(stream);
            });
        }
    }

    fn handle(&self, mut stream: UnixStream) -> std::io::Result<()> {
        let request: Request = read_request(&mut stream)?;
        match request.op {
            OP_RESOLVE => {
                let outcome = self
                    .path_state(&request.cas_path)
                    .and_then(|state| self.resolve(state, &request.payload));
                match outcome {
                    Ok(Some(value)) => write_response(&mut stream, STATUS_HIT, &value),
                    Ok(None) => write_response(&mut stream, STATUS_MISS, &[]),
                    Err(message) => {
                        crate::log_line(&format!("broker resolve failed: {message}"));
                        write_response(&mut stream, STATUS_ERROR, message.as_bytes())
                    }
                }
            }
            OP_PUBLISH => {
                let record_path = String::from_utf8_lossy(&request.payload).into_owned();
                self.enqueue_publish(&request.cas_path, &record_path);
                write_response(&mut stream, STATUS_HIT, &[])
            }
            _ => write_response(&mut stream, STATUS_ERROR, b"bad op"),
        }
    }
}

unsafe fn open_cas(up: &'static Upstream, path: &str) -> Result<llcas_cas_t, String> {
    let options = (up.llcas_cas_options_create)();
    let c_path =
        std::ffi::CString::new(path).map_err(|_| "bad cas path".to_string())?;
    (up.llcas_cas_options_set_client_version)(options, 0, 1);
    (up.llcas_cas_options_set_ondisk_path)(options, c_path.as_ptr());
    let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
    let cas = (up.llcas_cas_create)(options, &mut error);
    (up.llcas_cas_options_dispose)(options);
    if cas.is_null() {
        let message = if error.is_null() {
            "cas_create failed".to_string()
        } else {
            let text = std::ffi::CStr::from_ptr(error).to_string_lossy().into_owned();
            (up.llcas_string_dispose)(error);
            text
        };
        return Err(message);
    }
    Ok(cas)
}

unsafe fn store_node(state: &PathState, node: &reapi::Node) -> Result<(), String> {
    let mut ref_ids = Vec::with_capacity(node.refs.len());
    for reference in &node.refs {
        let digest = llcas_digest_t { data: reference.as_ptr(), size: reference.len() };
        let mut id = llcas_objectid_t { opaque: 0 };
        let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
        if (state.up.llcas_cas_get_objectid)(state.cas, digest, &mut id, &mut error) {
            if !error.is_null() {
                (state.up.llcas_string_dispose)(error);
            }
            return Err("objectid".into());
        }
        ref_ids.push(id);
    }
    let data = llcas_data_t {
        data: node.data.as_ptr() as *const std::ffi::c_void,
        size: node.data.len(),
    };
    let mut stored = llcas_objectid_t { opaque: 0 };
    let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_cas_store_object)(
        state.cas,
        data,
        ref_ids.as_ptr(),
        ref_ids.len(),
        &mut stored,
        &mut error,
    );
    if failed {
        if !error.is_null() {
            (state.up.llcas_string_dispose)(error);
        }
        return Err("store".into());
    }
    Ok(())
}

unsafe fn encode_node_blob(
    state: &PathState,
    digest: &[u8],
) -> Result<(Vec<u8>, Vec<Vec<u8>>), String> {
    let digest_t = llcas_digest_t { data: digest.as_ptr(), size: digest.len() };
    let mut id = llcas_objectid_t { opaque: 0 };
    let mut id_error: *mut std::ffi::c_char = std::ptr::null_mut();
    if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut id_error) {
        if !id_error.is_null() {
            (state.up.llcas_string_dispose)(id_error);
        }
        return Err("objectid".into());
    }
    let mut loaded = llcas_loaded_object_t { opaque: 0 };
    let mut load_error: *mut std::ffi::c_char = std::ptr::null_mut();
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
        let digest = (state.up.llcas_objectid_get_digest)(state.cas, child);
        ref_digests.push(std::slice::from_raw_parts(digest.data, digest.size).to_vec());
    }
    let blob = reapi::compress_frame(&reapi::encode_frame(&ref_digests, node_data));
    Ok((blob, ref_digests))
}
