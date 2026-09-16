//! Keeps a corrupt local store from crash-looping the proxy.
//!
//! Apple's on-disk CAS does not report all damage as an error. A damaged index
//! faults inside `llcas_cas_get_objectid` (`OnDiskHashMappedTrie::insertLazy`),
//! and a damaged data record aborts the process with `LLVM ERROR: OnDiskCAS:
//! corrupt internal reference`. Neither can be caught in-process. launchd
//! restarts the proxy, and the new process touches the same store again: the
//! startup snapshot warm opens every registered store, and every build that
//! uses the store asks about it.
//!
//! So a crash is remembered across the restart and charged to the store the
//! crashing thread was calling into:
//!
//! - Every upstream call on a store runs inside `enter`, which names the store
//!   in the calling thread's slot.
//! - A handler for the crash signals looks up the crashing thread's slot, writes
//!   the store it names to `<registry>.crash-<pid>`, and lets the crash proceed.
//! - The next proxy charges that crash in `<registry>.quarantine`.
//!   `STORE_CRASH_LIMIT` crashes within `STORE_CRASH_MEMORY` quarantine the store
//!   until `STORE_QUARANTINE_TTL` after its last crash.
//!
//! A marker left behind by an unfinished call would be simpler, but it would
//! also charge a proxy that was killed or terminated mid-call, which is what a
//! reinstall during a build does. Only a crash signal raised on the thread that
//! is inside the call is charged, so a crash on one store never counts against
//! another store that a different thread was using at the time.
//!
//! A quarantined store is not opened. Lookups on it answer misses, its spooled
//! publications stay on disk unread, and a drain reports them as owed without
//! waiting for them. The quarantine ends when the directory is recreated (a
//! different `CasGeneration`) or when its TTL passes. The crashes that led to it
//! still count after the TTL, so a store that crashes again is quarantined on
//! that first crash.

use std::cell::UnsafeCell;
use std::collections::{HashMap, HashSet};
use std::ffi::{c_int, c_void};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::IntoRawFd;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicPtr, AtomicUsize, Ordering};
use std::sync::{Mutex, Once};
use std::time::{Duration, UNIX_EPOCH};

use crate::proxy::{cas_generation, CasGeneration};

/// Crashes a store may cause within `STORE_CRASH_MEMORY` before the proxy stops
/// opening it. More than one, so a single crash that happened to land in a store
/// call does not take the store out of service.
pub const STORE_CRASH_LIMIT: usize = 3;

/// How long a crash counts against its store.
pub const STORE_CRASH_MEMORY: Duration = Duration::from_secs(7 * 24 * 60 * 60);

/// How long a store stays quarantined after its last crash.
pub const STORE_QUARANTINE_TTL: Duration = Duration::from_secs(24 * 60 * 60);

const CRASH_SIGNALS: [c_int; 6] = [
    libc::SIGSEGV,
    libc::SIGBUS,
    libc::SIGABRT,
    libc::SIGILL,
    libc::SIGTRAP,
    libc::SIGFPE,
];

/// More threads than the proxy runs at once. A thread that finds none free is
/// not attributed.
const THREAD_SLOTS: usize = 1024;

/// What the crash handler writes for a store: `path \t ino \t birth \t`,
/// followed by the signal number and a newline. Built ahead of time because
/// the handler cannot allocate.
pub(crate) struct StoreTag {
    record: Box<[u8]>,
}

impl StoreTag {
    /// Leaked: a thread's slot can point at it until the process exits. A path
    /// the ledger cannot store gets an empty record, which is never written.
    pub(crate) fn leak(cas_path: &str, generation: Option<CasGeneration>) -> *mut StoreTag {
        let record = if cas_path.contains(['\t', '\n']) {
            Vec::new()
        } else {
            let (ino, birth_nanos) = identity_fields(generation);
            format!("{cas_path}\t{ino}\t{birth_nanos}\t").into_bytes()
        };
        Box::into_raw(Box::new(StoreTag {
            record: record.into_boxed_slice(),
        }))
    }
}

struct ThreadSlot {
    thread: AtomicUsize,
    tag: AtomicPtr<StoreTag>,
}

static SLOTS: [ThreadSlot; THREAD_SLOTS] = [const {
    ThreadSlot {
        thread: AtomicUsize::new(0),
        tag: AtomicPtr::new(std::ptr::null_mut()),
    }
}; THREAD_SLOTS];

static ARMED: AtomicBool = AtomicBool::new(false);
static CRASH_FD: AtomicI32 = AtomicI32::new(-1);
static RECORDED: AtomicBool = AtomicBool::new(false);
static INSTALL: Once = Once::new();

struct PreviousActions(UnsafeCell<[libc::sigaction; CRASH_SIGNALS.len()]>);

// Written once, inside `INSTALL`, before the handler that reads it is installed.
unsafe impl Sync for PreviousActions {}

static PREVIOUS: PreviousActions = PreviousActions(UnsafeCell::new(unsafe { std::mem::zeroed() }));

/// The slot a thread claimed on its first store call, released when the thread
/// exits.
struct ClaimedSlot(Option<&'static ThreadSlot>);

impl ClaimedSlot {
    fn claim() -> ClaimedSlot {
        let me = current_thread();
        let start = (me.wrapping_mul(0x9E37_79B9_7F4A_7C15) >> 32) % THREAD_SLOTS;
        for offset in 0..THREAD_SLOTS {
            let slot = &SLOTS[(start + offset) % THREAD_SLOTS];
            if slot
                .thread
                .compare_exchange(0, me, Ordering::AcqRel, Ordering::Relaxed)
                .is_ok()
            {
                return ClaimedSlot(Some(slot));
            }
        }
        ClaimedSlot(None)
    }
}

impl Drop for ClaimedSlot {
    fn drop(&mut self) {
        if let Some(slot) = self.0 {
            slot.tag.store(std::ptr::null_mut(), Ordering::Relaxed);
            slot.thread.store(0, Ordering::Release);
        }
    }
}

thread_local! {
    static SLOT: ClaimedSlot = ClaimedSlot::claim();
}

fn current_thread() -> usize {
    unsafe { libc::pthread_self() as usize }
}

/// The calling thread is inside the upstream plugin on one store until this is
/// dropped. A crash signal raised on the thread meanwhile is charged to that
/// store.
pub(crate) struct InStore {
    slot: Option<&'static ThreadSlot>,
    previous: *mut StoreTag,
}

impl Drop for InStore {
    fn drop(&mut self) {
        if let Some(slot) = self.slot {
            slot.tag.store(self.previous, Ordering::Relaxed);
        }
    }
}

/// Marks the calling thread as calling into the store `tag` names. Does nothing
/// in a process that never armed crash attribution.
pub(crate) fn enter(tag: *mut StoreTag) -> InStore {
    if !ARMED.load(Ordering::Relaxed) {
        return InStore {
            slot: None,
            previous: std::ptr::null_mut(),
        };
    }
    let slot = SLOT.try_with(|claimed| claimed.0).ok().flatten();
    let previous = slot.map_or(std::ptr::null_mut(), |slot| {
        slot.tag.swap(tag, Ordering::Relaxed)
    });
    InStore { slot, previous }
}

/// Opens `crash_file` for the handler and installs it for the crash signals.
/// Once per process: a later call leaves the first file in place.
pub(crate) fn arm(crash_file: &Path) -> std::io::Result<()> {
    if ARMED.load(Ordering::Acquire) {
        return Ok(());
    }
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(crash_file)?;
    let fd = file.into_raw_fd();
    if CRASH_FD
        .compare_exchange(-1, fd, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        unsafe { libc::close(fd) };
    }
    INSTALL.call_once(|| unsafe {
        let previous = &mut *PREVIOUS.0.get();
        for (index, signal) in CRASH_SIGNALS.iter().enumerate() {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = on_crash_signal as *const () as usize;
            action.sa_flags = libc::SA_SIGINFO | libc::SA_ONSTACK;
            libc::sigemptyset(&mut action.sa_mask);
            libc::sigaction(*signal, &action, &mut previous[index]);
        }
    });
    ARMED.store(true, Ordering::Release);
    Ok(())
}

/// Runs on the crashing thread, so everything here is async-signal-safe: atomics,
/// `pwrite`, `sigaction` and `raise`. No allocation, locks or formatting.
extern "C" fn on_crash_signal(signal: c_int, info: *mut libc::siginfo_t, _context: *mut c_void) {
    unsafe {
        // A signal another process sent says nothing about this store.
        let sender = if info.is_null() { 0 } else { (*info).si_pid };
        if sender == 0 || sender == libc::getpid() {
            record_crash(signal);
        }
        if let Some(index) = CRASH_SIGNALS.iter().position(|crash| *crash == signal) {
            libc::sigaction(signal, &(*PREVIOUS.0.get())[index], std::ptr::null_mut());
        }
        // A fault at an address repeats when the handler returns and reaches the
        // previous handler with that address, which Rust's stack overflow
        // handler needs. Anything else is raised again, and is delivered to the
        // previous action once this handler returns.
        let faulted = matches!(signal, libc::SIGSEGV | libc::SIGBUS)
            && !info.is_null()
            && !(*info).si_addr.is_null();
        if !faulted {
            libc::raise(signal);
        }
    }
}

unsafe fn record_crash(signal: c_int) {
    let fd = CRASH_FD.load(Ordering::Relaxed);
    if fd < 0 {
        return;
    }
    let me = current_thread();
    let Some(slot) = SLOTS
        .iter()
        .find(|slot| slot.thread.load(Ordering::Relaxed) == me)
    else {
        return;
    };
    let Some(tag) = slot.tag.load(Ordering::Relaxed).as_ref() else {
        return;
    };
    let record = &tag.record;
    if record.is_empty() || RECORDED.swap(true, Ordering::AcqRel) {
        return;
    }
    let mut suffix = [0u8; 12];
    let length = signal_suffix(signal, &mut suffix);
    libc::pwrite(fd, record.as_ptr().cast(), record.len(), 0);
    libc::pwrite(
        fd,
        suffix.as_ptr().cast(),
        length,
        record.len() as libc::off_t,
    );
}

/// `<signal>\n` into `buffer`, returning its length.
fn signal_suffix(signal: c_int, buffer: &mut [u8; 12]) -> usize {
    let mut digits = [0u8; 10];
    let mut value = signal.unsigned_abs();
    let mut count = 0;
    loop {
        digits[count] = b'0' + (value % 10) as u8;
        value /= 10;
        count += 1;
        if value == 0 {
            break;
        }
    }
    for index in 0..count {
        buffer[index] = digits[count - 1 - index];
    }
    buffer[count] = b'\n';
    count + 1
}

/// A crash the handler charged to a store.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CrashRecord {
    cas_path: String,
    generation: Option<CasGeneration>,
    signal: i32,
    at_ms: u64,
}

fn parse_crash_record(bytes: &[u8], at_ms: u64) -> Option<CrashRecord> {
    let text = std::str::from_utf8(bytes).ok()?;
    let mut fields = text.trim_end_matches('\n').split('\t');
    let cas_path = fields.next().filter(|path| !path.is_empty())?.to_string();
    let generation = parse_identity(fields.next()?, fields.next()?)?;
    let signal = fields.next()?.parse().ok()?;
    Some(CrashRecord {
        cas_path,
        generation,
        signal,
        at_ms,
    })
}

fn identity_fields(generation: Option<CasGeneration>) -> (u64, u128) {
    generation.map_or((0, 0), |generation| (generation.ino, generation.birth_nanos))
}

/// Inode 0 is never a real directory, so `0 0` stands for "no directory".
fn parse_identity(ino: &str, birth_nanos: &str) -> Option<Option<CasGeneration>> {
    let ino: u64 = ino.parse().ok()?;
    let birth_nanos: u128 = birth_nanos.parse().ok()?;
    Some((ino != 0).then_some(CasGeneration { ino, birth_nanos }))
}

/// What the ledger remembers about one store.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Entry {
    generation: Option<CasGeneration>,
    /// Milliseconds since the Unix epoch, oldest first.
    crashes: Vec<u64>,
}

/// A store's standing in the ledger, from `ledger_standing`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum LedgerStanding {
    Serving,
    Quarantined { until_ms: u64 },
    /// The directory the crashes happened in is gone or was replaced.
    Recreated,
}

/// Whether the proxy opens a store.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Standing {
    Serving,
    Quarantined,
}

fn recent_crashes(entry: &Entry, now_ms: u64) -> impl Iterator<Item = u64> + '_ {
    let memory = STORE_CRASH_MEMORY.as_millis() as u64;
    entry
        .crashes
        .iter()
        .copied()
        .filter(move |at| now_ms.saturating_sub(*at) < memory)
}

/// Pure so the policy is unit-testable.
fn ledger_standing(entry: &Entry, current: Option<CasGeneration>, now_ms: u64) -> LedgerStanding {
    if current.is_none() || current != entry.generation {
        return LedgerStanding::Recreated;
    }
    if recent_crashes(entry, now_ms).count() < STORE_CRASH_LIMIT {
        return LedgerStanding::Serving;
    }
    let last = entry.crashes.last().copied().unwrap_or(0);
    let until_ms = last.saturating_add(STORE_QUARANTINE_TTL.as_millis() as u64);
    if now_ms < until_ms {
        LedgerStanding::Quarantined { until_ms }
    } else {
        LedgerStanding::Serving
    }
}

/// The store's entry after `crash`. A crash in a different directory than the
/// one the entry remembers starts a new history. Pure so the policy is
/// unit-testable.
fn charge(entry: Option<Entry>, crash: &CrashRecord) -> Entry {
    let mut entry = entry
        .filter(|entry| entry.generation == crash.generation)
        .unwrap_or(Entry {
            generation: crash.generation,
            crashes: Vec::new(),
        });
    entry.crashes = recent_crashes(&entry, crash.at_ms).collect();
    entry.crashes.push(crash.at_ms);
    entry.crashes.sort_unstable();
    let excess = entry.crashes.len().saturating_sub(STORE_CRASH_LIMIT);
    entry.crashes.drain(..excess);
    entry
}

/// `path \t ino \t birth \t crash,crash,...` per line. Lines that do not parse
/// are dropped.
fn decode_ledger(body: &str) -> HashMap<String, Entry> {
    body.lines()
        .filter_map(|line| {
            let mut fields = line.split('\t');
            let cas_path = fields.next().filter(|path| !path.is_empty())?.to_string();
            let generation = parse_identity(fields.next()?, fields.next()?)?;
            let crashes = fields
                .next()?
                .split(',')
                .map(|at| at.parse::<u64>().ok())
                .collect::<Option<Vec<u64>>>()?;
            Some((
                cas_path,
                Entry {
                    generation,
                    crashes,
                },
            ))
        })
        .collect()
}

fn encode_ledger(entries: &HashMap<String, Entry>) -> String {
    let mut body = String::new();
    for (cas_path, entry) in entries {
        if cas_path.contains(['\t', '\n']) || entry.crashes.is_empty() {
            continue;
        }
        let (ino, birth_nanos) = identity_fields(entry.generation);
        let crashes: Vec<String> = entry.crashes.iter().map(u64::to_string).collect();
        body.push_str(&format!(
            "{cas_path}\t{ino}\t{birth_nanos}\t{}\n",
            crashes.join(",")
        ));
    }
    body
}

/// Quarantine events are rare, and the proxy on a developer machine has no
/// `TUIST_CAS_LOG`, so they also go to stderr, which launchd writes to the
/// agent's log file.
fn report(message: &str) {
    crate::log_line(message);
    eprintln!("tuist-cas-proxy: {message}");
}

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut path = path.to_path_buf().into_os_string();
    path.push(suffix);
    PathBuf::from(path)
}

fn process_alive(pid: libc::pid_t) -> bool {
    let signalled = unsafe { libc::kill(pid, 0) } == 0;
    signalled || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
}

/// The proxy's view of which stores it may open.
pub(crate) struct StoreQuarantine {
    ledger_path: Option<PathBuf>,
    entries: Mutex<HashMap<String, Entry>>,
    /// Stores this process has reported as quarantined, so a lapse is reported
    /// once.
    reported: Mutex<HashSet<String>>,
    /// Requests refused per quarantined store, for the stats line.
    refused: Mutex<HashMap<String, u64>>,
}

impl StoreQuarantine {
    /// Loads the ledger beside `registry`, charges the crashes earlier proxies
    /// recorded, and arms crash attribution for this process. Without a registry
    /// nothing is remembered and nothing is quarantined.
    pub(crate) fn open(registry: Option<&Path>) -> StoreQuarantine {
        let quarantine = StoreQuarantine {
            ledger_path: registry.map(|registry| with_suffix(registry, ".quarantine")),
            entries: Mutex::new(HashMap::new()),
            reported: Mutex::new(HashSet::new()),
            refused: Mutex::new(HashMap::new()),
        };
        let (Some(registry), Some(ledger_path)) = (registry, &quarantine.ledger_path) else {
            return quarantine;
        };
        let now_ms = crate::reapi::now_ms();
        let mut entries = std::fs::read_to_string(ledger_path)
            .map(|body| decode_ledger(&body))
            .unwrap_or_default();
        let consumed = leftover_crashes(registry);
        for crash in consumed.iter().filter_map(|(_, crash)| crash.as_ref()) {
            let entry = charge(entries.remove(&crash.cas_path), crash);
            report(&format!(
                "cas store {} crashed the proxy (signal {}): {} of {STORE_CRASH_LIMIT} crashes that quarantine it",
                crash.cas_path,
                crash.signal,
                recent_crashes(&entry, now_ms).count(),
            ));
            entries.insert(crash.cas_path.clone(), entry);
        }
        let before = entries.len();
        entries.retain(|_, entry| recent_crashes(entry, now_ms).next().is_some());
        if !consumed.is_empty() || entries.len() != before {
            quarantine.persist(&entries);
        }
        for (file, _) in &consumed {
            let _ = std::fs::remove_file(file);
        }
        let stores: Vec<String> = entries.keys().cloned().collect();
        *quarantine.entries.lock().unwrap() = entries;
        // Reported now rather than on the first request, so a log read after a
        // restart says which stores this proxy will not open.
        for cas_path in stores {
            quarantine.standing(&cas_path);
        }
        let crash_file = with_suffix(registry, &format!(".crash-{}", std::process::id()));
        if let Err(error) = arm(&crash_file) {
            report(&format!(
                "cas store crash attribution is off: {}: {error}",
                crash_file.display()
            ));
        }
        quarantine
    }

    /// Whether `cas_path` may not be opened. Callers refuse the request when it
    /// is, which the stats line counts.
    pub(crate) fn holds(&self, cas_path: &str) -> bool {
        if self.standing(cas_path) != Standing::Quarantined {
            return false;
        }
        *self
            .refused
            .lock()
            .unwrap()
            .entry(cas_path.to_string())
            .or_default() += 1;
        true
    }

    /// The store's standing now. A quarantine whose store was recreated is
    /// dropped here, and one whose TTL passed is reported as lapsed.
    fn standing(&self, cas_path: &str) -> Standing {
        let entry = self.entries.lock().unwrap().get(cas_path).cloned();
        let Some(entry) = entry else {
            return Standing::Serving;
        };
        let now_ms = crate::reapi::now_ms();
        match ledger_standing(&entry, cas_generation(cas_path), now_ms) {
            LedgerStanding::Quarantined { until_ms } => {
                self.report_quarantine(cas_path, until_ms, now_ms);
                Standing::Quarantined
            }
            LedgerStanding::Recreated => {
                // Persisted under the lock, so two releases cannot interleave
                // their writes to the staged file. Releases are rare.
                let released = {
                    let mut entries = self.entries.lock().unwrap();
                    let released = entries.remove(cas_path).is_some();
                    if released {
                        self.persist(&entries);
                    }
                    released
                };
                if released {
                    self.reported.lock().unwrap().remove(cas_path);
                    self.refused.lock().unwrap().remove(cas_path);
                    report(&format!(
                        "cas store {cas_path} was recreated: its crash history is cleared and the proxy opens it again"
                    ));
                }
                Standing::Serving
            }
            LedgerStanding::Serving => {
                let lapsed = self.reported.lock().unwrap().remove(cas_path);
                if lapsed {
                    self.refused.lock().unwrap().remove(cas_path);
                    report(&format!(
                        "cas store {cas_path}'s quarantine lapsed: the proxy opens it again, and one more crash quarantines it again"
                    ));
                }
                Standing::Serving
            }
        }
    }

    /// `quarantined <path>: refused=<n>` for every store a request was refused
    /// on, joined for the stats line.
    pub(crate) fn stats(&self) -> Vec<String> {
        let mut parts: Vec<String> = self
            .refused
            .lock()
            .unwrap()
            .iter()
            .map(|(cas_path, refused)| format!("quarantined {cas_path}: refused={refused}"))
            .collect();
        parts.sort();
        parts
    }

    fn report_quarantine(&self, cas_path: &str, until_ms: u64, now_ms: u64) {
        let first = self.reported.lock().unwrap().insert(cas_path.to_string());
        if !first {
            return;
        }
        let hours = until_ms.saturating_sub(now_ms).div_ceil(60 * 60 * 1000);
        report(&format!(
            "cas store {cas_path} is quarantined for {hours}h after crashing the proxy {STORE_CRASH_LIMIT} times: \
             nothing opens it and its lookups answer misses. Delete the directory to release it now; \
             the next build recreates it"
        ));
    }

    fn persist(&self, entries: &HashMap<String, Entry>) {
        let Some(ledger_path) = &self.ledger_path else {
            return;
        };
        let staged = with_suffix(ledger_path, &format!(".tmp-{}", std::process::id()));
        if std::fs::write(&staged, encode_ledger(entries)).is_ok() {
            let _ = std::fs::rename(&staged, ledger_path);
        }
    }
}

/// Crash files earlier proxies on this registry left, with the crash each one
/// recorded. Called before this process creates its own, so a file with this
/// pid is an earlier process's. A file without a record belongs to a proxy
/// that did not crash on a store, and is only returned once that proxy is gone,
/// so a proxy still running keeps its file.
fn leftover_crashes(registry: &Path) -> Vec<(PathBuf, Option<CrashRecord>)> {
    let (Some(directory), Some(name)) = (registry.parent(), registry.file_name()) else {
        return Vec::new();
    };
    let prefix = format!("{}.crash-", name.to_string_lossy());
    let Ok(listing) = std::fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut leftovers = Vec::new();
    for file in listing.flatten() {
        let file_name = file.file_name().to_string_lossy().into_owned();
        let Some(pid) = file_name
            .strip_prefix(&prefix)
            .and_then(|pid| pid.parse::<libc::pid_t>().ok())
        else {
            continue;
        };
        let Ok(bytes) = std::fs::read(file.path()) else {
            continue;
        };
        if bytes.is_empty() {
            if !process_alive(pid) {
                leftovers.push((file.path(), None));
            }
            continue;
        }
        let at_ms = file
            .metadata()
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
            .map_or_else(crate::reapi::now_ms, |since| since.as_millis() as u64);
        leftovers.push((file.path(), parse_crash_record(&bytes, at_ms)));
    }
    leftovers
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::process::ExitStatusExt;
    use std::process::{Command, Stdio};

    const HOUR_MS: u64 = 60 * 60 * 1000;

    fn generation(ino: u64) -> Option<CasGeneration> {
        Some(CasGeneration {
            ino,
            birth_nanos: 1_700_000_000_000_000_000,
        })
    }

    fn crash(at_ms: u64) -> CrashRecord {
        CrashRecord {
            cas_path: "/stores/a".into(),
            generation: generation(7),
            signal: libc::SIGSEGV,
            at_ms,
        }
    }

    fn charged(times: &[u64]) -> Entry {
        times
            .iter()
            .fold(None, |entry, at| Some(charge(entry, &crash(*at))))
            .unwrap()
    }

    #[test]
    fn a_store_is_quarantined_by_its_third_crash() {
        let start = 1_000 * HOUR_MS;
        let two = charged(&[start, start + 60_000]);
        assert_eq!(ledger_standing(&two, generation(7), start + 120_000), LedgerStanding::Serving);

        let three = charged(&[start, start + 60_000, start + 120_000]);
        assert_eq!(
            ledger_standing(&three, generation(7), start + 180_000),
            LedgerStanding::Quarantined {
                until_ms: start + 120_000 + STORE_QUARANTINE_TTL.as_millis() as u64
            }
        );
    }

    #[test]
    fn crashes_older_than_the_memory_do_not_count() {
        let start = 1_000 * HOUR_MS;
        let memory = STORE_CRASH_MEMORY.as_millis() as u64;
        let entry = charged(&[start, start + 1, start + memory + 10]);
        assert_eq!(entry.crashes, vec![start + memory + 10]);
        assert_eq!(ledger_standing(&entry, generation(7), start + memory + 20), LedgerStanding::Serving);
    }

    #[test]
    fn a_lapsed_quarantine_returns_on_the_next_crash() {
        let start = 1_000 * HOUR_MS;
        let ttl = STORE_QUARANTINE_TTL.as_millis() as u64;
        let entry = charged(&[start, start + 1, start + 2]);
        let lapsed = start + 2 + ttl;
        assert_eq!(ledger_standing(&entry, generation(7), lapsed), LedgerStanding::Serving);

        let crashed_again = charge(Some(entry), &crash(lapsed + HOUR_MS));
        assert!(matches!(
            ledger_standing(&crashed_again, generation(7), lapsed + HOUR_MS + 1),
            LedgerStanding::Quarantined { .. }
        ));
    }

    #[test]
    fn a_recreated_store_is_released_and_starts_a_new_history() {
        let start = 1_000 * HOUR_MS;
        let entry = charged(&[start, start + 1, start + 2]);
        assert_eq!(ledger_standing(&entry, generation(8), start + 3), LedgerStanding::Recreated);
        assert_eq!(ledger_standing(&entry, None, start + 3), LedgerStanding::Recreated);

        let recreated = CrashRecord {
            generation: generation(8),
            ..crash(start + 4)
        };
        let fresh = charge(Some(entry), &recreated);
        assert_eq!(fresh.generation, generation(8));
        assert_eq!(fresh.crashes, vec![start + 4]);
    }

    #[test]
    fn the_ledger_round_trips_and_drops_lines_it_cannot_read() {
        let mut entries = HashMap::new();
        entries.insert("/stores/a".to_string(), charged(&[10, 20, 30]));
        entries.insert(
            "/stores/b".to_string(),
            Entry {
                generation: None,
                crashes: vec![40],
            },
        );
        let body = encode_ledger(&entries);
        assert_eq!(decode_ledger(&body), entries);

        let damaged = format!("{body}/stores/c\tnot-a-number\t0\t1\n/stores/d\t1\t2\n");
        assert_eq!(decode_ledger(&damaged), entries);
    }

    #[test]
    fn the_handler_record_parses_back_into_the_crash() {
        let tag = StoreTag::leak("/stores/a", generation(7));
        let mut suffix = [0u8; 12];
        let length = signal_suffix(libc::SIGABRT, &mut suffix);
        let mut bytes = unsafe { (*tag).record.to_vec() };
        bytes.extend_from_slice(&suffix[..length]);
        assert_eq!(
            parse_crash_record(&bytes, 99),
            Some(CrashRecord {
                cas_path: "/stores/a".into(),
                generation: generation(7),
                signal: libc::SIGABRT,
                at_ms: 99,
            })
        );
    }

    // The child half of the attribution tests: this same test binary, re-run
    // for one test with a role in the environment.
    const CHILD_ROLE: &str = "TUIST_CAS_STORE_CRASH_CHILD";
    const CHILD_FILE: &str = "TUIST_CAS_STORE_CRASH_FILE";

    struct ChildRun {
        crash_file: PathBuf,
    }

    impl ChildRun {
        fn new(label: &str) -> Self {
            let crash_file = std::env::temp_dir().join(format!(
                "tuist-store-crash-attribution-{label}-{}",
                std::process::id()
            ));
            let _ = std::fs::remove_file(&crash_file);
            Self { crash_file }
        }

        fn command(&self, test: &str, role: &str) -> Command {
            let mut command = Command::new(std::env::current_exe().unwrap());
            command
                .args(["--exact", test, "--nocapture", "--test-threads=1"])
                .env(CHILD_ROLE, role)
                .env(CHILD_FILE, &self.crash_file)
                .stdout(Stdio::null())
                .stderr(Stdio::null());
            command
        }

        fn run(&self, test: &str, role: &str) -> std::process::ExitStatus {
            self.command(test, role).status().unwrap()
        }

        fn recorded(&self) -> Option<CrashRecord> {
            parse_crash_record(&std::fs::read(&self.crash_file).ok()?, 0)
        }
    }

    impl Drop for ChildRun {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.crash_file);
            let _ = std::fs::remove_file(with_suffix(&self.crash_file, ".ready"));
        }
    }

    /// Runs `body` when this process is the child for `role`, and exits if it
    /// returns.
    fn as_child(role: &str, body: impl FnOnce(&Path)) {
        if std::env::var(CHILD_ROLE).as_deref() != Ok(role) {
            return;
        }
        let crash_file = PathBuf::from(std::env::var(CHILD_FILE).unwrap());
        arm(&crash_file).unwrap();
        body(&crash_file);
        std::process::exit(0);
    }

    fn child_role() -> bool {
        std::env::var_os(CHILD_ROLE).is_some()
    }

    fn fault() {
        unsafe { std::ptr::null_mut::<u8>().wrapping_add(16).write_volatile(1) };
    }

    #[test]
    fn an_abort_inside_a_store_call_is_charged_to_that_store() {
        as_child("abort", |_| {
            let _in_store = enter(StoreTag::leak("/stores/aborted", generation(3)));
            unsafe { libc::abort() };
        });
        if child_role() {
            return;
        }
        let run = ChildRun::new("abort");
        let status = run.run("store_quarantine::tests::an_abort_inside_a_store_call_is_charged_to_that_store", "abort");
        assert_eq!(status.signal(), Some(libc::SIGABRT), "the crash still happens");
        let recorded = run.recorded().expect("the crash is recorded");
        assert_eq!(recorded.cas_path, "/stores/aborted");
        assert_eq!(recorded.generation, generation(3));
        assert_eq!(recorded.signal, libc::SIGABRT);
    }

    #[test]
    fn a_fault_inside_a_store_call_is_charged_to_that_store() {
        as_child("fault", |_| {
            let _in_store = enter(StoreTag::leak("/stores/faulted", generation(4)));
            fault();
        });
        if child_role() {
            return;
        }
        let run = ChildRun::new("fault");
        let status = run.run("store_quarantine::tests::a_fault_inside_a_store_call_is_charged_to_that_store", "fault");
        assert!(
            matches!(status.signal(), Some(libc::SIGSEGV | libc::SIGBUS)),
            "the crash still happens: {status:?}"
        );
        let recorded = run.recorded().expect("the crash is recorded");
        assert_eq!(recorded.cas_path, "/stores/faulted");
        assert!(matches!(recorded.signal, libc::SIGSEGV | libc::SIGBUS));
    }

    #[test]
    fn a_crash_is_charged_only_to_the_store_its_own_thread_was_in() {
        as_child("other-thread", |crash_file| {
            let ready = with_suffix(crash_file, ".ready");
            std::thread::spawn(move || {
                let _in_store = enter(StoreTag::leak("/stores/innocent", generation(5)));
                std::fs::write(&ready, b"").unwrap();
                std::thread::sleep(Duration::from_secs(60));
            });
            while !with_suffix(crash_file, ".ready").exists() {
                std::thread::sleep(Duration::from_millis(5));
            }
            let _in_store = enter(StoreTag::leak("/stores/corrupt", generation(6)));
            unsafe { libc::abort() };
        });
        if child_role() {
            return;
        }
        let run = ChildRun::new("other-thread");
        run.run(
            "store_quarantine::tests::a_crash_is_charged_only_to_the_store_its_own_thread_was_in",
            "other-thread",
        );
        assert_eq!(run.recorded().expect("recorded").cas_path, "/stores/corrupt");
    }

    #[test]
    fn a_crash_outside_any_store_call_is_charged_to_no_store() {
        as_child("outside", |_| {
            drop(enter(StoreTag::leak("/stores/finished", generation(7))));
            unsafe { libc::abort() };
        });
        if child_role() {
            return;
        }
        let run = ChildRun::new("outside");
        let status = run.run("store_quarantine::tests::a_crash_outside_any_store_call_is_charged_to_no_store", "outside");
        assert_eq!(status.signal(), Some(libc::SIGABRT));
        assert_eq!(run.recorded(), None);
    }

    // A reinstall terminates the proxy whatever it is doing. That says nothing
    // about the store a thread was in.
    #[test]
    fn a_proxy_terminated_mid_call_is_charged_to_no_store() {
        as_child("terminated", |crash_file| {
            let _in_store = enter(StoreTag::leak("/stores/busy", generation(8)));
            std::fs::write(with_suffix(crash_file, ".ready"), b"").unwrap();
            loop {
                std::thread::sleep(Duration::from_secs(1));
            }
        });
        if child_role() {
            return;
        }
        for signal in [libc::SIGTERM, libc::SIGKILL] {
            let run = ChildRun::new(&format!("terminated-{signal}"));
            let mut child = run
                .command(
                    "store_quarantine::tests::a_proxy_terminated_mid_call_is_charged_to_no_store",
                    "terminated",
                )
                .spawn()
                .unwrap();
            let ready = with_suffix(&run.crash_file, ".ready");
            let deadline = std::time::Instant::now() + Duration::from_secs(10);
            while !ready.exists() {
                assert!(std::time::Instant::now() < deadline, "the child never entered the store");
                std::thread::sleep(Duration::from_millis(5));
            }
            unsafe { libc::kill(child.id() as libc::pid_t, signal) };
            let status = child.wait().unwrap();
            assert_eq!(status.signal(), Some(signal));
            assert_eq!(run.recorded(), None, "signal {signal} is not a store crash");
        }
    }

    // `kill -ABRT` from a shell lands on whichever thread the kernel picks, so
    // the handler is called directly with the sender such a signal carries.
    #[test]
    fn a_crash_signal_another_process_sent_is_charged_to_no_store() {
        as_child("sent", |_| {
            let _in_store = enter(StoreTag::leak("/stores/signalled", generation(9)));
            unsafe {
                let mut info: libc::siginfo_t = std::mem::zeroed();
                info.si_signo = libc::SIGABRT;
                info.si_pid = libc::getppid();
                on_crash_signal(libc::SIGABRT, &mut info, std::ptr::null_mut());
            }
        });
        if child_role() {
            return;
        }
        let run = ChildRun::new("sent");
        let status = run.run(
            "store_quarantine::tests::a_crash_signal_another_process_sent_is_charged_to_no_store",
            "sent",
        );
        assert_eq!(status.signal(), Some(libc::SIGABRT), "the signal still ends the process");
        assert_eq!(run.recorded(), None);
    }
}
