use std::path::{Path, PathBuf};

const SESSIONS_DIR: &str = "sessions/v1";

pub(crate) struct SessionPaths {
    pub events: PathBuf,
    pub lock: PathBuf,
}

pub(crate) fn session_paths(store: &Path, id: &str) -> SessionPaths {
    let directory = store.join(SESSIONS_DIR);
    SessionPaths {
        events: directory.join(format!("{id}.jsonl")),
        lock: directory.join(format!("{id}.lock")),
    }
}

fn locked(path: &Path) -> bool {
    match fslock::LockFile::open(path) {
        Ok(mut lock) => match lock.try_lock() {
            Ok(true) => {
                let _ = lock.unlock();
                false
            }
            Ok(false) => true,
            Err(_) => false,
        },
        Err(_) => false,
    }
}

pub(crate) fn session_is_live(store: &Path, id: &str) -> bool {
    locked(&session_paths(store, id).lock)
}

pub(crate) fn orphaned_locks(store: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(store.join(SESSIONS_DIR)) else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            let id = name.strip_suffix(".lock")?;
            let stream = session_paths(store, id).events;
            (!stream.exists() && !locked(&path)).then_some(path)
        })
        .collect()
}

pub(crate) fn session_ids(store: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(store.join(SESSIONS_DIR)) else {
        return Vec::new();
    };
    let mut ids: Vec<String> = entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            name.strip_suffix(".jsonl").map(str::to_string)
        })
        .collect();
    ids.sort();
    ids
}

#[cfg(test)]
pub(crate) struct EventWriter {
    id: String,
    paths: SessionPaths,
    lock: std::sync::Mutex<Option<fslock::LockFile>>,
}

#[cfg(test)]
impl EventWriter {
    pub(crate) fn new(store: &Path) -> Self {
        let id = format!(
            "{}-{}-test",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.as_millis())
                .unwrap_or(0),
            std::process::id()
        );
        Self {
            paths: session_paths(store, &id),
            id,
            lock: std::sync::Mutex::new(None),
        }
    }

    pub(crate) fn id(&self) -> &str {
        &self.id
    }

    pub(crate) fn started(&self, _workspace_root: &Path, _command: &[String]) {
        std::fs::create_dir_all(self.paths.events.parent().unwrap()).unwrap();
        let mut lock = fslock::LockFile::open(&self.paths.lock).unwrap();
        lock.lock().unwrap();
        std::fs::write(&self.paths.events, b"session\n").unwrap();
        *self.lock.lock().unwrap() = Some(lock);
    }
}
