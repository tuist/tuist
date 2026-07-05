//! Kura-backed remote store: read-through fetches and write-through uploads.
//!
//! Wire format (schema `tcp0`):
//! - Action-cache entries live at artifact id `tcp0-v-<key digest hex>` whose
//!   body is the raw digest bytes of the value object.
//! - Object nodes live at `tcp0-o-<digest hex>` as a zstd-compressed frame:
//!   `"TCP0" | u32 ref_count | (u32 len | digest bytes)* | data`.

use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Default)]
pub struct OpStats {
    pub count: AtomicU64,
    pub total_ms: AtomicU64,
    pub max_ms: AtomicU64,
}

impl OpStats {
    pub fn record(&self, elapsed: Duration) {
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
}

impl RemoteConfig {
    pub fn from_env() -> Option<Self> {
        let base_url = std::env::var("TUIST_CAS_REMOTE_URL").ok()?;
        Some(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            account: std::env::var("TUIST_CAS_ACCOUNT").unwrap_or_else(|_| "tuist".into()),
            project: std::env::var("TUIST_CAS_PROJECT").unwrap_or_else(|_| "tuist".into()),
            token: std::env::var("TUIST_CAS_TOKEN").ok(),
        })
    }
}

pub struct Node {
    pub refs: Vec<Vec<u8>>,
    pub data: Vec<u8>,
}

pub struct Remote {
    config: RemoteConfig,
    agent: ureq::Agent,
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
            .max_idle_connections_per_host(4)
            .build();
        Arc::new(Self {
            config,
            agent,
            uploaded: Mutex::new(HashSet::new()),
            get_stats: OpStats::default(),
            post_stats: OpStats::default(),
        })
    }

    fn url(&self, id: &str) -> String {
        format!(
            "{}/api/cache/cas/{}?account_handle={}&project_handle={}",
            self.config.base_url, id, self.config.account, self.config.project
        )
    }

    // Both HTTP entry points retry transport-class failures: ureq reuses
    // keep-alive connections that the server may have closed, a request on a
    // stale connection fails (reset/EOF/EINVAL-in-header), and ureq does not
    // retry request bodies itself. A retry consumes the dead pooled
    // connection and reconnects. Requests are content-addressed and
    // idempotent, so retrying is always safe. catch_unwind contains ureq's
    // pool-return panic, which must not cross the plugin's extern "C"
    // boundary or skip worker bookkeeping.
    const ATTEMPTS: usize = 3;

    fn get_artifact(&self, id: &str) -> Option<Vec<u8>> {
        let started = Instant::now();
        let mut result = None;
        for attempt_index in 0..Self::ATTEMPTS {
            // The pool may hold several stale connections from an idle burst;
            // the final attempt bypasses it with a fresh connection.
            let fresh_agent;
            let agent = if attempt_index + 1 == Self::ATTEMPTS {
                fresh_agent = ureq::AgentBuilder::new()
                    .timeout_connect(std::time::Duration::from_secs(5))
                    .timeout(std::time::Duration::from_secs(120))
                    .build();
                &fresh_agent
            } else {
                &self.agent
            };
            let attempt = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let mut request = agent.get(&self.url(id));
                if let Some(token) = &self.config.token {
                    request = request.set("Authorization", &format!("Bearer {token}"));
                }
                match request.call() {
                    Ok(response) => {
                        let mut body = Vec::new();
                        use std::io::Read;
                        match response.into_reader().take(1 << 30).read_to_end(&mut body) {
                            Ok(_) => Ok(Some(body)),
                            // A truncated body is a stale/broken connection.
                            Err(_) => Err(()),
                        }
                    }
                    // A definitive status (404 miss etc.) is not retryable.
                    Err(ureq::Error::Status(_, _)) => Ok(None),
                    Err(ureq::Error::Transport(_)) => Err(()),
                }
            }))
            .unwrap_or(Err(()));
            match attempt {
                Ok(value) => {
                    result = value;
                    break;
                }
                Err(()) => continue,
            }
        }
        self.get_stats.record(started.elapsed());
        result
    }

    fn put_artifact(&self, id: &str, body: &[u8]) -> Result<(), String> {
        if self.uploaded.lock().unwrap().contains(id) {
            return Ok(());
        }
        let started = Instant::now();
        let mut last_error = String::new();
        let mut outcome = Err(());
        for attempt_index in 0..Self::ATTEMPTS {
            let fresh_agent;
            let agent = if attempt_index + 1 == Self::ATTEMPTS {
                fresh_agent = ureq::AgentBuilder::new()
                    .timeout_connect(std::time::Duration::from_secs(5))
                    .timeout(std::time::Duration::from_secs(120))
                    .build();
                &fresh_agent
            } else {
                &self.agent
            };
            let attempt = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let mut request = agent.post(&self.url(id));
                if let Some(token) = &self.config.token {
                    request = request.set("Authorization", &format!("Bearer {token}"));
                }
                match request
                    .set("Content-Type", "application/octet-stream")
                    .send_bytes(body)
                {
                    Ok(_) => Ok(()),
                    Err(ureq::Error::Status(code, _)) if code < 500 => {
                        Err((false, format!("status {code}")))
                    }
                    Err(error) => Err((true, error.to_string())),
                }
            }))
            .unwrap_or(Err((true, "panic during upload".into())));
            match attempt {
                Ok(()) => {
                    outcome = Ok(());
                    break;
                }
                Err((retryable, error)) => {
                    last_error = error;
                    if !retryable {
                        break;
                    }
                }
            }
        }
        self.post_stats.record(started.elapsed());
        match outcome {
            Ok(()) => {
                // Marked only on success so a failure stays retryable for
                // later publications in this process.
                self.uploaded.lock().unwrap().insert(id.to_string());
                Ok(())
            }
            Err(()) => {
                crate::log_line(&format!(
                    "post failed id={} error={last_error}",
                    &id[..24.min(id.len())]
                ));
                Err(last_error)
            }
        }
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
        let frame = zstd::stream::encode_all(&encode_frame(refs, data)[..], 1).unwrap_or_default();
        self.put_artifact(&id, &frame).is_ok()
    }

    /// Uploads one action-cache entry synchronously (dedup by artifact id).
    pub fn upload_entry(&self, key_digest: &[u8], value_digest: &[u8]) -> bool {
        let id = format!("tcp0-v-{}", hex(key_digest));
        self.put_artifact(&id, value_digest).is_ok()
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
