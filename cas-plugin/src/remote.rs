//! Kura-backed remote store: read-through fetches and write-through uploads.
//!
//! Wire format (schema `tcp0`):
//! - Action-cache entries live at artifact id `tcp0-v-<key digest hex>` whose
//!   body is the raw digest bytes of the value object.
//! - Object nodes live at `tcp0-o-<digest hex>` as a zstd-compressed frame:
//!   `"TCP0" | u32 ref_count | (u32 len | digest bytes)* | data`.

use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Default)]
pub struct OpStats {
    pub count: AtomicU64,
    pub total_ms: AtomicU64,
    pub max_ms: AtomicU64,
}

impl OpStats {
    fn record(&self, elapsed: Duration) {
        let ms = elapsed.as_millis() as u64;
        self.count.fetch_add(1, Ordering::Relaxed);
        self.total_ms.fetch_add(ms, Ordering::Relaxed);
        self.max_ms.fetch_max(ms, Ordering::Relaxed);
    }

    pub fn summary(&self) -> String {
        let count = self.count.load(Ordering::Relaxed);
        format!(
            "n={} sum={}ms max={}ms",
            count,
            self.total_ms.load(Ordering::Relaxed),
            self.max_ms.load(Ordering::Relaxed),
        )
    }
}

pub struct RemoteConfig {
    pub base_url: String,
    pub account: String,
    pub project: String,
    pub token: Option<String>,
    pub pool: usize,
}

impl RemoteConfig {
    pub fn from_env() -> Option<Self> {
        let base_url = std::env::var("TUIST_CAS_REMOTE_URL").ok()?;
        Some(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            account: std::env::var("TUIST_CAS_ACCOUNT").unwrap_or_else(|_| "tuist".into()),
            project: std::env::var("TUIST_CAS_PROJECT").unwrap_or_else(|_| "tuist".into()),
            token: std::env::var("TUIST_CAS_TOKEN").ok(),
            pool: std::env::var("TUIST_CAS_POOL")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(16),
        })
    }
}

pub struct Node {
    pub refs: Vec<Vec<u8>>,
    pub data: Vec<u8>,
}

enum Job {
    UploadEntry { id: String, value_digest: Vec<u8> },
}

pub struct Remote {
    config: RemoteConfig,
    agent: ureq::Agent,
    tx: Mutex<Option<mpsc::Sender<Job>>>,
    // Held until the first entry upload; workers spawn lazily so processes
    // that never publish entries skip the pool entirely.
    pending_rx: Mutex<Option<mpsc::Receiver<Job>>>,
    workers: Mutex<Vec<std::thread::JoinHandle<()>>>,
    uploaded: Mutex<HashSet<String>>,
    pub get_stats: OpStats,
    pub post_stats: OpStats,
}

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

impl Remote {
    pub fn new(config: RemoteConfig) -> Arc<Self> {
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(5))
            .timeout(Duration::from_secs(120))
            .max_idle_connections_per_host(64)
            .build();
        let (tx, rx) = mpsc::channel::<Job>();
        Arc::new(Self {
            config,
            agent,
            tx: Mutex::new(Some(tx)),
            pending_rx: Mutex::new(Some(rx)),
            workers: Mutex::new(Vec::new()),
            uploaded: Mutex::new(HashSet::new()),
            get_stats: OpStats::default(),
            post_stats: OpStats::default(),
        })
    }

    fn ensure_workers(&self) {
        let Some(rx) = self.pending_rx.lock().unwrap().take() else { return };
        let rx = Arc::new(Mutex::new(rx));
        let mut workers = self.workers.lock().unwrap();
        // Entry bodies are digest-sized; a few workers suffice. drain() joins
        // these before the owning CasState is freed.
        for _ in 0..self.config.pool.clamp(1, 4) {
            let rx = Arc::clone(&rx);
            let this: &'static Remote = unsafe { &*(self as *const Remote) };
            workers.push(std::thread::spawn(move || loop {
                let job = { rx.lock().unwrap().recv() };
                match job {
                    Ok(Job::UploadEntry { id, value_digest }) => {
                        let _ = this.put_artifact(&id, &value_digest);
                    }
                    Err(_) => break,
                }
            }));
        }
    }

    fn url(&self, id: &str) -> String {
        format!(
            "{}/api/cache/cas/{}?account_handle={}&project_handle={}",
            self.config.base_url, id, self.config.account, self.config.project
        )
    }

    // ureq can panic while returning a connection to its pool ("returning
    // stream to pool: ... Invalid argument"). A panic here would either wedge
    // a worker's bookkeeping or unwind across the plugin's extern "C"
    // boundary into the compiler, so both HTTP entry points contain panics
    // and report them as request failures.
    fn get_artifact(&self, id: &str) -> Option<Vec<u8>> {
        let started = Instant::now();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let mut request = self.agent.get(&self.url(id));
            if let Some(token) = &self.config.token {
                request = request.set("Authorization", &format!("Bearer {token}"));
            }
            match request.call() {
                Ok(response) => {
                    let mut body = Vec::new();
                    use std::io::Read;
                    match response.into_reader().take(1 << 30).read_to_end(&mut body) {
                        Ok(_) => Some(body),
                        Err(_) => None,
                    }
                }
                Err(_) => None,
            }
        }))
        .unwrap_or(None);
        self.get_stats.record(started.elapsed());
        result
    }

    fn put_artifact(&self, id: &str, body: &[u8]) -> Result<(), String> {
        {
            let mut uploaded = self.uploaded.lock().unwrap();
            if !uploaded.insert(id.to_string()) {
                return Ok(());
            }
        }
        let started = Instant::now();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let mut request = self.agent.post(&self.url(id));
            if let Some(token) = &self.config.token {
                request = request.set("Authorization", &format!("Bearer {token}"));
            }
            request
                .set("Content-Type", "application/octet-stream")
                .send_bytes(body)
                .map(|_| ())
                .map_err(|e| e.to_string())
        }))
        .unwrap_or_else(|_| Err("panic during upload".into()));
        self.post_stats.record(started.elapsed());
        result
    }

    /// Fetches an action-cache entry: key digest -> value object digest.
    pub fn get_entry(&self, key_digest: &[u8]) -> Option<Vec<u8>> {
        let id = format!("tcp0-v-{}", hex(key_digest));
        let body = self.get_artifact(&id)?;
        // Anything fetched is remote by definition; never re-upload it.
        self.uploaded.lock().unwrap().insert(id);
        Some(body)
    }

    /// Fetches and decodes an object node.
    pub fn get_node(&self, digest: &[u8]) -> Option<Node> {
        let id = format!("tcp0-o-{}", hex(digest));
        let compressed = self.get_artifact(&id)?;
        let frame = zstd::stream::decode_all(&compressed[..]).ok()?;
        let node = decode_frame(&frame)?;
        self.uploaded.lock().unwrap().insert(id);
        Some(node)
    }

    /// Uploads one node synchronously (dedup by artifact id). Returns false
    /// only on a transport failure for a not-yet-uploaded node.
    pub fn upload_node(&self, digest: &[u8], refs: &[Vec<u8>], data: &[u8]) -> bool {
        let id = format!("tcp0-o-{}", hex(digest));
        {
            let uploaded = self.uploaded.lock().unwrap();
            if uploaded.contains(&id) {
                return true;
            }
        }
        let frame = zstd::stream::encode_all(&encode_frame(refs, data)[..], 3).unwrap_or_default();
        self.put_artifact(&id, &frame).is_ok()
    }

    pub fn enqueue_entry(&self, key_digest: &[u8], value_digest: &[u8]) {
        let id = format!("tcp0-v-{}", hex(key_digest));
        self.ensure_workers();
        if let Some(tx) = self.tx.lock().unwrap().as_ref() {
            let _ = tx.send(Job::UploadEntry {
                id,
                value_digest: value_digest.to_vec(),
            });
        }
    }

    /// Blocks until all queued uploads are flushed. Called from cas_dispose so
    /// short-lived compiler processes do not drop pending writes.
    pub fn drain(&self) {
        let tx = self.tx.lock().unwrap().take();
        drop(tx);
        let workers = std::mem::take(&mut *self.workers.lock().unwrap());
        for worker in workers {
            let _ = worker.join();
        }
    }
}

fn encode_frame(refs: &[Vec<u8>], data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(16 + data.len() + refs.iter().map(|r| r.len() + 4).sum::<usize>());
    out.extend_from_slice(b"TCP0");
    out.extend_from_slice(&(refs.len() as u32).to_le_bytes());
    for reference in refs {
        out.extend_from_slice(&(reference.len() as u32).to_le_bytes());
        out.extend_from_slice(reference);
    }
    out.extend_from_slice(data);
    out
}

fn decode_frame(frame: &[u8]) -> Option<Node> {
    if frame.len() < 8 || &frame[0..4] != b"TCP0" {
        return None;
    }
    let mut offset = 4;
    let ref_count = u32::from_le_bytes(frame[offset..offset + 4].try_into().ok()?) as usize;
    offset += 4;
    let mut refs = Vec::with_capacity(ref_count);
    for _ in 0..ref_count {
        if frame.len() < offset + 4 {
            return None;
        }
        let len = u32::from_le_bytes(frame[offset..offset + 4].try_into().ok()?) as usize;
        offset += 4;
        if frame.len() < offset + len {
            return None;
        }
        refs.push(frame[offset..offset + len].to_vec());
        offset += len;
    }
    Some(Node {
        refs,
        data: frame[offset..].to_vec(),
    })
}
