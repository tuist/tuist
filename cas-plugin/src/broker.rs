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
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Instant;

use crate::broker_proto::{
    read_request, write_response, Request, OP_PUBLISH, OP_RESOLVE, STATUS_ERROR, STATUS_HIT,
    STATUS_MISS,
};
use crate::prefetch::Prefetcher;
use crate::reapi::{self, ManifestEntry, Remote, RemoteConfig};
use crate::token::TokenProvider;
use crate::types::*;
use crate::upstream::Upstream;
use crate::PublishRecord;

// Bounds for the per-path in-memory caches so a long-lived (machine-wide,
// launchd-managed) broker cannot grow without limit across many builds. They
// are correctness-preserving caches — clearing only forces a re-resolve or a
// re-check, never a wrong answer — so clearing on overflow is safe. The caps sit
// well above a single warm build's working set (a warm build touches ~1.9M
// known-local digests total, i.e. ~60k per shard), so within-build warmth is
// preserved and only cross-build accumulation is reclaimed.
const MAX_RESOLVED: usize = 1_000_000;
const MAX_KNOWN_LOCAL_PER_SHARD: usize = 250_000;
const MAX_PUBLISH_CACHE: usize = 500_000;

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
    grpc_url: String,
    tokens: Arc<TokenProvider>,
    upstream_plugin: String,
    // One REAPI client per account/project instance, created on first use.
    // All share the machine's endpoint + token; only the instance the request
    // is scoped to differs. This is what lets one broker serve every project.
    remotes: Mutex<HashMap<String, Arc<Remote>>>,
    // cas_path -> instance, primed by builds that declare their instance and
    // persisted so an Xcode ⌘B build (which declares none) still routes after
    // a broker restart. See broker_proto for why the fallback exists.
    path_instance: Mutex<HashMap<String, String>>,
    registry_path: Option<PathBuf>,
    paths: Mutex<HashMap<String, &'static PathState>>,
    publisher: Prefetcher,
    // Per-node transfer analytics, written to cas_analytics.db for parity with
    // the legacy daemon. `None` when no analytics path was configured.
    analytics: Option<crate::analytics::Analytics>,
}

impl Broker {
    pub fn new(
        grpc_url: String,
        tokens: Arc<TokenProvider>,
        upstream_plugin: String,
        registry_path: Option<PathBuf>,
        analytics: Option<crate::analytics::Analytics>,
    ) -> &'static Broker {
        let path_instance = registry_path.as_deref().map(load_registry).unwrap_or_default();
        let broker: &'static Broker = Box::leak(Box::new(Broker {
            grpc_url,
            tokens,
            upstream_plugin,
            remotes: Mutex::new(HashMap::new()),
            path_instance: Mutex::new(path_instance),
            registry_path,
            paths: Mutex::new(HashMap::new()),
            publisher: Prefetcher::new(),
            analytics,
        }));
        let broker_addr = broker as *const Broker as usize;
        broker.publisher.configure(8, move |item| {
            let broker = unsafe { &*(broker_addr as *const Broker) };
            broker.publish_item(&item);
        });
        broker
    }

    /// The REAPI client for an instance, created and cached on first use.
    fn remote_for(&self, instance: &str) -> Arc<Remote> {
        if let Some(remote) = self.remotes.lock().unwrap().get(instance) {
            return remote.clone();
        }
        let remote = Remote::new(
            RemoteConfig {
                grpc_url: self.grpc_url.clone(),
                instance: instance.to_string(),
            },
            self.tokens.clone(),
        );
        self.remotes
            .lock()
            .unwrap()
            .entry(instance.to_string())
            .or_insert(remote)
            .clone()
    }

    /// The instance a connection routes to. A declared (non-empty) instance is
    /// authoritative and primes the cas_path mapping for later ⌘B builds; an
    /// empty one falls back to whatever a prior build primed. `None` means an
    /// unprimed ⌘B build: the caller degrades it to a miss.
    fn resolve_instance(&self, cas_path: &str, declared: &str) -> Option<String> {
        if !declared.is_empty() {
            let mut map = self.path_instance.lock().unwrap();
            if map.get(cas_path).map(String::as_str) != Some(declared) {
                map.insert(cas_path.to_string(), declared.to_string());
                self.persist_registry(&map);
            }
            return Some(declared.to_string());
        }
        self.path_instance.lock().unwrap().get(cas_path).cloned()
    }

    fn persist_registry(&self, map: &HashMap<String, String>) {
        let Some(path) = &self.registry_path else { return };
        let mut body = String::new();
        for (cas_path, instance) in map {
            if !cas_path.contains(['\t', '\n']) && !instance.contains(['\t', '\n']) {
                body.push_str(cas_path);
                body.push('\t');
                body.push_str(instance);
                body.push('\n');
            }
        }
        let _ = std::fs::write(path, body);
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
    fn resolve(
        &self,
        remote: &Remote,
        state: &'static PathState,
        key: &[u8],
    ) -> Result<Option<Vec<u8>>, String> {
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
        let outcome = self.resolve_uncached(remote, state, key);
        {
            let mut inflight = state.inflight.lock().unwrap();
            inflight.remove(key);
            state.inflight_cvar.notify_all();
        }
        outcome
    }

    fn resolve_uncached(
        &self,
        remote: &Remote,
        state: &'static PathState,
        key: &[u8],
    ) -> Result<Option<Vec<u8>>, String> {
        let op_start = Instant::now();
        let phase = Instant::now();
        let manifest = match remote.get_action(key)? {
            Some(manifest) if !manifest.is_empty() => manifest,
            _ => {
                state.stats_misses.fetch_add(1, Ordering::Relaxed);
                state.resolved.lock().unwrap().insert(key.to_vec(), None);
                if let Some(analytics) = &self.analytics {
                    analytics.record_keyvalue(key, "read", op_start.elapsed().as_secs_f64());
                }
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
            let contents = remote.batch_read(&digests)?;
            let fetch_elapsed = phase.elapsed();
            state
                .ms_fetch
                .fetch_add(fetch_elapsed.as_millis() as u64, Ordering::Relaxed);
            // The fetch is one batch RPC; attribute its wall time to each node in
            // proportion to that node's compressed bytes for the per-node
            // transfer analytics.
            let total_compressed: i64 = missing.iter().map(|entry| entry.blob.size_bytes).sum::<i64>().max(1);
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
                let codec_elapsed = phase.elapsed();
                state
                    .ms_decode
                    .fetch_add(codec_elapsed.as_millis() as u64, Ordering::Relaxed);
                if let Some(analytics) = &self.analytics {
                    let compressed = entry.blob.size_bytes;
                    let transfer =
                        fetch_elapsed.as_secs_f64() * (compressed as f64 / total_compressed as f64);
                    let codec = codec_elapsed.as_secs_f64();
                    // This node's own transfer, keyed by its content-digest hex
                    // (which equals the checksum in its parent's reference).
                    analytics.record_cas_output(
                        &crate::analytics::hex_upper(&entry.llcas_digest),
                        frame.len() as i64,
                        compressed,
                        transfer + codec,
                        transfer,
                        codec,
                    );
                    // The (casID -> checksum) references this node makes, for the
                    // nodes table the server maps build-log node ids through.
                    for (cas_id, hex) in crate::analytics::parse_cas_references(&node.data) {
                        analytics.record_node(&cas_id, &hex);
                    }
                }
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
        if let Some(analytics) = &self.analytics {
            analytics.record_keyvalue(key, "read", op_start.elapsed().as_secs_f64());
        }
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
    /// instance + cas_path + record path.
    fn enqueue_publish(&self, cas_path: &str, instance: &str, record_path: &str) {
        let mut item = Vec::with_capacity(4 + instance.len() + cas_path.len() + record_path.len());
        item.extend_from_slice(&(instance.len() as u16).to_be_bytes());
        item.extend_from_slice(instance.as_bytes());
        item.extend_from_slice(&(cas_path.len() as u16).to_be_bytes());
        item.extend_from_slice(cas_path.as_bytes());
        item.extend_from_slice(record_path.as_bytes());
        self.publisher.enqueue(item);
    }

    fn publish_item(&self, item: &[u8]) {
        let Some((instance, rest)) = take_u16_field(item) else { return };
        let Some((cas_path, record_path)) = take_u16_field(rest) else { return };
        let instance = String::from_utf8_lossy(instance).into_owned();
        let cas_path = String::from_utf8_lossy(cas_path).into_owned();
        let record_path = String::from_utf8_lossy(record_path).into_owned();
        let remote = self.remote_for(&instance);
        let Ok(state) = self.path_state(&cas_path) else { return };
        let Ok(bytes) = std::fs::read(&record_path) else { return };
        let Some(record) =
            PublishRecord::decode_body(&bytes, Some(std::path::PathBuf::from(&record_path)))
        else {
            let _ = std::fs::remove_file(&record_path);
            return;
        };
        match self.publish(&remote, state, &record) {
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

    fn publish(
        &self,
        remote: &Remote,
        state: &'static PathState,
        record: &PublishRecord,
    ) -> Result<(), String> {
        let op_start = Instant::now();
        if let Ok(Some(manifest)) = remote.get_action(&record.key) {
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
        let missing =
            remote.find_missing(entries.iter().map(|entry| entry.blob.clone()).collect())?;
        let missing_set: HashSet<(String, i64)> = missing
            .into_iter()
            .map(|digest| (digest.hash, digest.size_bytes))
            .collect();
        let mut uploads: Vec<(reapi::Digest, Vec<u8>)> = Vec::new();
        // (llcas_digest, uncompressed size, compressed size, node data) per
        // uploaded node, recorded once the batch transfer time is known.
        let mut upload_meta: Vec<(Vec<u8>, i64, i64, Vec<u8>)> = Vec::new();
        for (entry, blob) in entries.iter().zip(blobs) {
            if !missing_set.contains(&(entry.blob.hash.clone(), entry.blob.size_bytes)) {
                continue;
            }
            let bytes = match blob {
                Some(bytes) => bytes,
                None => unsafe { encode_node_blob(state, &entry.llcas_digest)?.0 },
            };
            if self.analytics.is_some() {
                let (size, data) = reapi::decompress_frame(&bytes)
                    .and_then(|frame| reapi::decode_frame(&frame).map(|node| (frame.len(), node.data)))
                    .unwrap_or((bytes.len(), Vec::new()));
                upload_meta.push((entry.llcas_digest.clone(), size as i64, entry.blob.size_bytes, data));
            }
            uploads.push((entry.blob.clone(), bytes));
        }
        if !uploads.is_empty() {
            let upload_start = Instant::now();
            remote.batch_update(uploads)?;
            if let Some(analytics) = &self.analytics {
                let elapsed = upload_start.elapsed().as_secs_f64();
                let total: i64 = upload_meta.iter().map(|(_, _, c, _)| c).sum::<i64>().max(1);
                for (digest, size, compressed, data) in &upload_meta {
                    let transfer = elapsed * (*compressed as f64 / total as f64);
                    analytics.record_cas_output(
                        &crate::analytics::hex_upper(digest),
                        *size,
                        *compressed,
                        transfer,
                        transfer,
                        0.0,
                    );
                    for (cas_id, hex) in crate::analytics::parse_cas_references(data) {
                        analytics.record_node(&cas_id, &hex);
                    }
                }
            }
        }
        let result = remote.update_action(&record.key, &entries);
        if let Some(analytics) = &self.analytics {
            analytics.record_keyvalue(&record.key, "write", op_start.elapsed().as_secs_f64());
        }
        result
    }

    /// Clears any per-path cache grown past its bound. Called from the periodic
    /// maintenance loop; a no-op while every map stays under its cap.
    pub fn enforce_cache_bounds(&self) {
        let states: Vec<&'static PathState> =
            self.paths.lock().unwrap().values().copied().collect();
        for state in states {
            if state.resolved.lock().unwrap().len() > MAX_RESOLVED {
                state.resolved.lock().unwrap().clear();
            }
            if state.publish_cache.lock().unwrap().len() > MAX_PUBLISH_CACHE {
                state.publish_cache.lock().unwrap().clear();
            }
            for shard in &state.known_local {
                if shard.lock().unwrap().len() > MAX_KNOWN_LOCAL_PER_SHARD {
                    shard.lock().unwrap().clear();
                }
            }
        }
    }

    /// Sweeps orphaned publication records for every known CAS path whose
    /// instance the broker knows (an unprimed path has nothing to publish to).
    pub fn sweep(&self) {
        let paths: Vec<String> = self.paths.lock().unwrap().keys().cloned().collect();
        for cas_path in paths {
            let Some(instance) = self.path_instance.lock().unwrap().get(&cas_path).cloned() else {
                continue;
            };
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
                    self.enqueue_publish(&cas_path, &instance, &path.to_string_lossy());
                }
            }
        }
    }

    /// Proactively refreshes the bearer so a long-lived broker stays ahead of
    /// token expiry. Called from the periodic maintenance loop; a no-op in
    /// env-only (CI) mode.
    pub fn refresh_token(&self) {
        self.tokens.force_refresh();
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
        // A plugin from a different CLI version speaks a different frame layout;
        // reject rather than misparse, so the plugin degrades to a local miss.
        if request.version != crate::broker_proto::PROTOCOL_VERSION {
            return write_response(&mut stream, STATUS_ERROR, b"broker protocol version mismatch");
        }
        match request.op {
            OP_RESOLVE => {
                let Some(instance) = self.resolve_instance(&request.cas_path, &request.instance)
                else {
                    // Unprimed ⌘B build: no instance to route to. Degrade to a
                    // miss so the compiler proceeds on the local CAS.
                    return write_response(&mut stream, STATUS_MISS, &[]);
                };
                let remote = self.remote_for(&instance);
                let outcome = self
                    .path_state(&request.cas_path)
                    .and_then(|state| self.resolve(&remote, state, &request.payload));
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
                // Ack even when unprimed: the record stays spooled for a later
                // sweep once a build primes the instance.
                if let Some(instance) = self.resolve_instance(&request.cas_path, &request.instance) {
                    let record_path = String::from_utf8_lossy(&request.payload).into_owned();
                    self.enqueue_publish(&request.cas_path, &instance, &record_path);
                }
                write_response(&mut stream, STATUS_HIT, &[])
            }
            _ => write_response(&mut stream, STATUS_ERROR, b"bad op"),
        }
    }
}

/// Reads a `u16`-length-prefixed field from the front of `buf`, returning it
/// and the remainder. `None` if the buffer is truncated.
fn take_u16_field(buf: &[u8]) -> Option<(&[u8], &[u8])> {
    if buf.len() < 2 {
        return None;
    }
    let len = u16::from_be_bytes([buf[0], buf[1]]) as usize;
    let rest = &buf[2..];
    if rest.len() < len {
        return None;
    }
    Some((&rest[..len], &rest[len..]))
}

/// Loads the persisted `cas_path -> instance` registry (tab-separated lines).
fn load_registry(path: &Path) -> HashMap<String, String> {
    let mut map = HashMap::new();
    if let Ok(body) = std::fs::read_to_string(path) {
        for line in body.lines() {
            if let Some((cas_path, instance)) = line.split_once('\t') {
                map.insert(cas_path.to_string(), instance.to_string());
            }
        }
    }
    map
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
