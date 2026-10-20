//! Allowlisted invocation-local cache inspection, separate from private agent events.
use crate::{ActionDiagnostic, CacheDigest};
use serde_json::json;
use std::{
    fs::{self, OpenOptions},
    io::{BufWriter, Write},
    path::{Path, PathBuf},
    sync::{OnceLock, mpsc},
    time::{Duration, Instant},
};

const LIMIT: u64 = 8_000_000;
static REPORTER: OnceLock<Option<Reporter>> = OnceLock::new();
struct Reporter {
    sender: mpsc::SyncSender<Message>,
    root: PathBuf,
}
enum Message {
    Record(Vec<u8>),
    Flush(mpsc::Sender<()>),
}

fn incomplete(root: &Path) {
    let _ = fs::write(root.join("truncated"), []);
}

fn reporter() -> Option<&'static Reporter> {
    REPORTER
        .get_or_init(|| {
            let root = PathBuf::from(std::env::var_os("TUIST_CARGO_CACHE_PUBLIC_REPORT_DIR")?);
            if root.as_os_str().is_empty() {
                return None;
            }
            let (sender, receiver) = mpsc::sync_channel(512);
            let destination = root.clone();
            if std::thread::Builder::new()
                .name("tuist-cache-report".into())
                .spawn(move || write_records(&destination, receiver))
                .is_err()
            {
                incomplete(&root);
                return None;
            }
            Some(Reporter { sender, root })
        })
        .as_ref()
}

fn write_records(root: &Path, receiver: mpsc::Receiver<Message>) {
    let opened = (|| -> std::io::Result<_> {
        fs::create_dir_all(root)?;
        let path = root.join(format!("{}.ndjson", std::process::id()));
        if fs::symlink_metadata(&path).is_ok_and(|metadata| metadata.file_type().is_symlink()) {
            return Err(std::io::Error::other(
                "cache inspection destination is a symlink",
            ));
        }
        let mut options = OpenOptions::new();
        options.create(true).append(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let file = options.open(path)?;
        let length = file.metadata()?.len();
        Ok((BufWriter::with_capacity(64 * 1024, file), length))
    })();
    let Ok((mut file, mut length)) = opened else {
        incomplete(root);
        return;
    };
    for message in receiver {
        match message {
            Message::Record(bytes) => {
                if length.saturating_add(bytes.len() as u64) > LIMIT {
                    incomplete(root);
                    continue;
                }
                length = length.saturating_add(bytes.len() as u64);
                if file.write_all(&bytes).is_err() {
                    incomplete(root);
                }
            }
            Message::Flush(acknowledge) => {
                if file.flush().is_err() {
                    incomplete(root);
                }
                let _ = acknowledge.send(());
            }
        }
    }
    if file.flush().is_err() {
        incomplete(root);
    }
}

fn append(value: serde_json::Value) {
    let Some(reporter) = reporter() else {
        return;
    };
    let Ok(mut bytes) = serde_json::to_vec(&value) else {
        incomplete(&reporter.root);
        return;
    };
    bytes.push(b'\n');
    if bytes.len() > 8192 || reporter.sender.try_send(Message::Record(bytes)).is_err() {
        incomplete(&reporter.root);
    }
}

/// Called after cache work drains, before the shipped runtime exits.
pub(crate) fn flush() {
    let Some(Some(reporter)) = REPORTER.get() else {
        return;
    };
    let (acknowledge, received) = mpsc::channel();
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut message = Message::Flush(acknowledge);
    loop {
        match reporter.sender.try_send(message) {
            Ok(()) => break,
            Err(mpsc::TrySendError::Full(returned)) if Instant::now() < deadline => {
                message = returned;
                std::thread::sleep(Duration::from_millis(1));
            }
            Err(_) => {
                incomplete(&reporter.root);
                return;
            }
        }
    }
    if received
        .recv_timeout(deadline.saturating_duration_since(Instant::now()))
        .is_err()
    {
        incomplete(&reporter.root);
    }
}

fn key(digest: &CacheDigest) -> String {
    format!("{}:{}:{}", digest.algorithm, digest.hash, digest.size)
}

pub(crate) fn task(
    action: &CacheDigest,
    name: Option<&str>,
    status: &str,
    diagnostic: Option<&ActionDiagnostic>,
) {
    let kind = if diagnostic.is_some_and(|d| {
        d.components
            .keys()
            .any(|key| key.starts_with("argument --crate-name"))
    }) {
        "rust"
    } else {
        "compiler"
    };
    append(
        json!({"record":"task", "key":key(action), "name":name.unwrap_or("Compiler action").chars().take(256).collect::<String>(), "kind":kind, "status":status}),
    );
}

pub(crate) fn timing(action: &CacheDigest, operation: &str, started: Instant) {
    append(
        json!({"record":"timing", "key":key(action), "operation":operation, "duration_ns":started.elapsed().as_nanos().min(9_000_000_000_000_000) as u64}),
    );
}

pub(crate) fn build_script(action: &CacheDigest, name: &str, status: &str) {
    if status == "hit" {
        append(json!({"record":"adapter", "key":key(action), "kind":"build_script"}));
    } else {
        append(
            json!({"record":"task", "key":key(action), "name":name.chars().take(256).collect::<String>(), "kind":"build_script", "status":status}),
        );
    }
}

pub(crate) fn reference(action: &CacheDigest, object: &CacheDigest) {
    append(json!({"record":"reference", "key":key(action), "object":key(object)}));
}

pub(crate) struct Transfer {
    key: String,
    size: u64,
    operation: &'static str,
    started: Instant,
    status: &'static str,
}
impl Transfer {
    pub(crate) fn new(hash: &str, size: i64, operation: &'static str) -> Self {
        Self {
            key: format!("sha256:{hash}:{size}"),
            size: size.max(0) as u64,
            operation,
            started: Instant::now(),
            status: "failed",
        }
    }
    pub(crate) fn complete(&mut self, status: &'static str) {
        self.status = status;
    }
}
impl Drop for Transfer {
    fn drop(&mut self) {
        append(
            json!({"record":"cas", "key":self.key, "size_bytes":self.size.min(9_000_000_000_000_000), "operation":self.operation, "status":self.status, "duration_ns":self.started.elapsed().as_nanos().min(9_000_000_000_000_000) as u64}),
        );
    }
}
