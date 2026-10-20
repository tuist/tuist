//! Advisory, pool-wide pressure sampling. Call `sample` under the registrar lock.
//! Missing probes and stale state fail open; no sample is an OS memory limit.
//!
//! A pool is shared by every process using one cache directory, which can span
//! several containers. Each container is its own memory domain, so the pool
//! keeps one state file per domain rather than one for the whole pool.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

pub(crate) const INTERVAL_MS: u64 = 500;
const STALE_MS: u64 = 3_000;
const VERSION: u8 = 1;
/// Pool subdirectory holding one state file per memory domain.
const DOMAINS_DIR: &str = "pressure";
/// A domain file this old belongs to a container or cgroup that is gone. Its
/// state expired long before this, so removing it loses nothing.
const DOMAIN_FILE_RETENTION: std::time::Duration = std::time::Duration::from_secs(24 * 60 * 60);

/// The newest state this process sampled but could not save. Without it, a
/// failing write would re-probe on every admission poll and reset hysteresis.
static UNSAVED: Mutex<Option<(PathBuf, State)>> = Mutex::new(None);

#[derive(Clone, Default, Serialize, Deserialize)]
pub(crate) struct Reading {
    pub total: Option<u64>,
    pub available: Option<u64>,
    /// Full-stall microseconds, keyed by the source (never sum nested groups).
    pub stalls: BTreeMap<String, u64>,
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub(crate) struct State {
    version: u8,
    pub sampled_ms: u64,
    reading: Reading,
    bad_samples: u8,
    healthy_since: Option<u64>,
    pub pressured: bool,
    pub valid: bool,
    pub recovered_ms: Option<u64>,
    pub last_admission_ms: Option<u64>,
}

pub(crate) fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |time| time.as_millis().min(u128::from(u64::MAX)) as u64)
}

/// Names the memory domain this process's probes describe.
///
/// A pathname cannot do this. Every container sees its own cgroup at
/// `/sys/fs/cgroup`, so two containers sharing a pool read different stall
/// counters and memory limits from identical paths. Subtracting one
/// container's counter from another's produces stalls that never happened,
/// and mixing their samples breaks hysteresis in both. The device and inode of
/// each memory cgroup directory do tell domains apart: a cgroup's inode is its
/// kernel-wide id, whichever namespace or mount shows it.
///
/// `/proc/pressure/memory` is left out. It reports the whole machine in every
/// container, and its identity changes with each proc mount, so including it
/// would split one cgroup's state between processes with different proc
/// mounts and let both skip the recovery spacing meant for that cgroup.
///
/// Computed once: a process does not change domain while it compiles.
pub(crate) fn domain() -> &'static str {
    static DOMAIN: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    DOMAIN.get_or_init(|| {
        #[cfg(target_os = "linux")]
        {
            use sha2::Digest;
            use std::os::unix::fs::MetadataExt;
            let mut hasher = sha2::Sha256::new();
            let mut identified = false;
            for path in crate::cgroup::memory_directories() {
                if let Ok(metadata) = std::fs::metadata(&path) {
                    hasher.update(format!("{}:{}\n", metadata.dev(), metadata.ino()));
                    identified = true;
                }
            }
            if identified {
                return hex::encode(&hasher.finalize()[..8]);
            }
        }
        // Without a visible cgroup the probes read only machine-wide figures,
        // which every process on the machine shares.
        "host".into()
    })
}

/// The pool's state file for one memory domain.
///
/// The first time a domain appears, files left by domains that have not
/// sampled for a day are removed, so a host that starts many containers does
/// not collect one file per container forever.
pub(crate) fn domain_state(pool: &Path, domain: &str) -> PathBuf {
    let directory = pool.join(DOMAINS_DIR);
    let path = directory.join(format!("{domain}.json"));
    if !path.exists() {
        prune(&directory, std::time::SystemTime::now());
    }
    path
}

fn prune(directory: &Path, now: std::time::SystemTime) {
    for entry in std::fs::read_dir(directory).into_iter().flatten().flatten() {
        let path = entry.path();
        let old = entry
            .metadata()
            .and_then(|metadata| metadata.modified())
            .ok()
            .and_then(|modified| now.duration_since(modified).ok())
            .is_some_and(|age| age >= DOMAIN_FILE_RETENTION);
        if old
            && path
                .extension()
                .is_some_and(|extension| extension == "json")
        {
            let _ = std::fs::remove_file(path);
        }
    }
}

pub(crate) fn probe() -> Reading {
    #[allow(unused_mut)]
    let mut reading = Reading {
        total: crate::util::memory_total_bytes(),
        available: crate::util::memory_available_bytes(),
        ..Reading::default()
    };
    #[cfg(target_os = "linux")]
    for path in std::iter::once(std::path::PathBuf::from("/proc/pressure/memory"))
        .chain(crate::cgroup::pressure_files())
    {
        if let Some(total) = std::fs::read_to_string(&path)
            .ok()
            .and_then(|s| full_total(&s))
        {
            reading
                .stalls
                .insert(path.to_string_lossy().into_owned(), total);
        }
    }
    reading
}

#[cfg(any(target_os = "linux", test))]
fn full_total(text: &str) -> Option<u64> {
    text.lines().find_map(|line| {
        let mut fields = line.split_whitespace();
        (fields.next()? == "full").then_some(())?;
        fields.find_map(|field| field.strip_prefix("total=")?.parse().ok())
    })
}

impl State {
    fn update(&mut self, now: u64, reading: Reading) {
        let elapsed = now
            .checked_sub(self.sampled_ms)
            .filter(|n| *n > 0 && *n <= STALE_MS);
        let comparable = self.version == VERSION && elapsed.is_some();
        let stall_percent = comparable
            .then(|| {
                reading
                    .stalls
                    .iter()
                    .filter_map(|(source, value)| {
                        let delta = value.checked_sub(*self.reading.stalls.get(source)?)?;
                        Some(delta as f64 / (elapsed.unwrap() as f64 * 10.0))
                    })
                    .reduce(f64::max)
            })
            .flatten();
        let headroom = reading
            .total
            .filter(|n| *n > 0)
            .zip(reading.available)
            .map(|(total, available)| available as f64 / total as f64);
        if !comparable {
            // A forward gap discards stale evidence but not recovery spacing,
            // which expires on its own; a clock step back discards both.
            let spacing = (self.version == VERSION && now > self.sampled_ms)
                .then_some((self.recovered_ms, self.last_admission_ms));
            *self = Self::default();
            if let Some((recovered_ms, last_admission_ms)) = spacing {
                self.recovered_ms = recovered_ms;
                self.last_admission_ms = last_admission_ms;
            }
        }
        self.valid = headroom.is_some() || stall_percent.is_some();
        let bad = headroom.is_some_and(|v| v < 0.05) || stall_percent.is_some_and(|v| v >= 10.0);
        let healthy = self.valid
            && headroom.is_none_or(|v| v > 0.10)
            && stall_percent.is_none_or(|v| v < 2.0);
        if !self.valid {
            self.pressured = false;
            self.bad_samples = 0;
            self.healthy_since = None;
            self.recovered_ms = None;
        } else if bad {
            self.bad_samples = self.bad_samples.saturating_add(1);
            self.healthy_since = None;
            if self.bad_samples >= 2 {
                self.pressured = true;
                self.recovered_ms = None;
            }
        } else {
            self.bad_samples = 0;
            if self.pressured && healthy {
                let start = *self.healthy_since.get_or_insert(now);
                if now.saturating_sub(start) >= 5_000 {
                    self.pressured = false;
                    self.recovered_ms = Some(now);
                    self.healthy_since = None;
                }
            } else {
                self.healthy_since = None;
            }
        }
        // Recovery ramping is temporary, not a permanent two-compiles/sec cap.
        if self
            .recovered_ms
            .is_some_and(|start| now.saturating_sub(start) >= 5_000)
        {
            self.recovered_ms = None;
        }
        self.version = VERSION;
        self.sampled_ms = now;
        self.reading = reading;
    }
}

/// The caller holds the pool registrar lock across sampling and any state write.
///
/// Every process sampling into `path` must read the same memory domain; see
/// `domain`.
pub(crate) fn sample(path: &Path, now: u64, probe: fn() -> Reading) -> eyre::Result<State> {
    let mut state: State = std::fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default();
    let mut unsaved = UNSAVED.lock().unwrap_or_else(|error| error.into_inner());
    if let Some((kept_path, kept)) = unsaved.as_ref()
        && kept_path == path
        && (state.version != VERSION || kept.sampled_ms > state.sampled_ms)
    {
        state = kept.clone();
    }
    if state.version == VERSION
        && now
            .checked_sub(state.sampled_ms)
            .is_some_and(|age| age < INTERVAL_MS)
    {
        return Ok(state);
    }
    state.update(now, probe());
    let saved = save(path, &state);
    if saved.is_err() {
        *unsaved = Some((path.to_path_buf(), state.clone()));
    } else if unsaved
        .as_ref()
        .is_some_and(|(kept_path, _)| kept_path == path)
    {
        *unsaved = None;
    }
    saved.map(|()| state)
}

pub(crate) fn save(path: &Path, state: &State) -> eyre::Result<()> {
    crate::util::write_advisory(path, &serde_json::to_vec(state)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn memory(available: u64) -> Reading {
        Reading {
            total: Some(100),
            available: Some(available),
            ..Reading::default()
        }
    }
    #[test]
    fn hysteresis_and_stale_recovery() {
        let mut state = State::default();
        state.update(1_000, memory(4));
        assert!(!state.pressured);
        state.update(1_500, memory(4));
        assert!(state.pressured);
        for now in (2_000..7_000).step_by(500) {
            state.update(now, memory(11));
            assert!(state.pressured);
        }
        state.update(7_000, memory(11));
        assert!(!state.pressured);
        assert_eq!(state.recovered_ms, Some(7_000));
        state.last_admission_ms = Some(7_000);
        let mut gap = state.clone();
        gap.update(10_100, memory(11));
        assert_eq!(gap.recovered_ms, Some(7_000), "a stale gap keeps spacing");
        assert_eq!(gap.last_admission_ms, Some(7_000));
        gap.update(12_000, memory(11));
        assert_eq!(gap.recovered_ms, None, "spacing still expires");
        let mut back = state.clone();
        back.update(6_000, memory(11));
        assert_eq!(back.recovered_ms, None, "a clock step back resets spacing");
        state.update(7_500, memory(0));
        state.update(8_000, memory(0));
        assert!(state.pressured);
        state.update(12_000, memory(0));
        assert!(
            !state.pressured,
            "stale observations cannot count as consecutive"
        );
        state.update(11_000, Reading::default());
        assert!(!state.valid);
    }
    #[test]
    fn psi_uses_deltas_and_discards_reset_counters() {
        fn psi(total: u64) -> Reading {
            Reading {
                stalls: BTreeMap::from([("host".into(), total)]),
                ..Reading::default()
            }
        }
        let mut state = State::default();
        state.update(1_000, psi(100));
        assert!(!state.valid);
        state.update(1_500, psi(50_100));
        state.update(2_000, psi(100_100));
        assert!(state.pressured);
        state.update(2_500, psi(0));
        assert!(!state.valid);
        assert!(!state.pressured);
        assert_eq!(
            full_total("some total=55\nfull avg10=0.0 total=42"),
            Some(42)
        );
        assert_eq!(full_total("some total=55"), None);
    }
    #[test]
    fn sampling_is_shared_and_rate_limited() {
        let dir = tempfile::tempdir().unwrap();
        let path = domain_state(dir.path(), "a");
        sample(&path, 1_000, || memory(0)).unwrap();
        sample(&path, 1_100, || panic!("too soon")).unwrap();
        let state = sample(&path, 1_500, || memory(0)).unwrap();
        assert!(state.pressured);
        let state = sample(&path, 1_600, || panic!("shared state")).unwrap();
        assert!(state.pressured);
    }
    #[test]
    fn failed_saves_keep_rate_limit_and_hysteresis() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("pressure.json");
        // A directory in place of the file makes every atomic write fail.
        std::fs::create_dir(&path).unwrap();
        assert!(sample(&path, 1_000, || memory(0)).is_err());
        let state = sample(&path, 1_100, || panic!("too soon")).unwrap();
        assert_eq!(state.sampled_ms, 1_000);
        assert!(sample(&path, 1_500, || memory(0)).is_err());
        let state = sample(&path, 1_600, || panic!("too soon")).unwrap();
        assert!(state.pressured);
    }
    /// Containers expose different cgroups at the same pathname. Each counter
    /// below is stationary, so no container is stalling at all.
    const COUNTERS: [u64; 3] = [21_764_622, 200_000_000, 393_795_795];
    fn container(counter: u64) -> Reading {
        Reading {
            total: Some(100),
            available: Some(50),
            stalls: BTreeMap::from([("/sys/fs/cgroup/memory.pressure".into(), counter)]),
        }
    }
    #[test]
    fn one_state_for_several_containers_invents_lasting_stalls() {
        // The hazard the per-domain files exist for. Rotating samples subtract
        // one container's counter from another's: each rise reads as a full
        // stall, so pressure begins and every rise restarts the healthy time
        // that recovery needs.
        let mut state = State::default();
        for (step, now) in (1_000..60_000).step_by(500).enumerate() {
            state.update(now, container(COUNTERS[step % 3]));
            if now >= 2_000 {
                assert!(state.pressured, "pressured from the third sample on");
            }
        }
    }
    #[test]
    fn containers_sharing_a_pool_keep_separate_state() {
        let dir = tempfile::tempdir().unwrap();
        let probes: [fn() -> Reading; 3] = [
            || container(COUNTERS[0]),
            || container(COUNTERS[1]),
            || container(COUNTERS[2]),
        ];
        let paths = ["one", "two", "three"].map(|name| domain_state(dir.path(), name));
        assert_ne!(paths[0], paths[1]);
        // Each domain samples at the pressure interval, interleaved with the others.
        for (step, now) in (1_000..60_000).step_by(100).enumerate() {
            let index = step % 3;
            let state = sample(&paths[index], now, probes[index]).unwrap();
            assert!(state.valid);
            assert!(!state.pressured, "no container stalled");
        }
    }
    #[test]
    fn a_new_domain_prunes_files_left_by_gone_domains() {
        let dir = tempfile::tempdir().unwrap();
        let path = domain_state(dir.path(), "live");
        sample(&path, 1_000, || memory(50)).unwrap();
        let gone = dir.path().join(DOMAINS_DIR).join("gone.json");
        std::fs::write(&gone, b"{}").unwrap();
        let later = std::time::SystemTime::now() + DOMAIN_FILE_RETENTION;
        std::fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_modified(later)
            .unwrap();
        // An existing domain never scans the directory.
        domain_state(dir.path(), "live");
        assert!(gone.exists());
        prune(&dir.path().join(DOMAINS_DIR), later);
        assert!(!gone.exists(), "a day without samples");
        assert!(path.exists(), "a domain that sampled recently stays");
        assert!(!domain().is_empty());
    }
}
