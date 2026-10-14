use eyre::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::os::fd::AsRawFd;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const TICK: Duration = Duration::from_millis(250);
const TIMEOUT: u64 = 3_000;

#[derive(Serialize, Deserialize)]
struct Heartbeat {
    generation: String,
    time: u64,
}

fn read<T: serde::de::DeserializeOwned>(path: &Path) -> Option<T> {
    serde_json::from_slice(&std::fs::read(path).ok()?).ok()
}
fn write<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    crate::util::write_advisory(path, &serde_json::to_vec(value)?)
}
fn token(s: &str) -> bool {
    s.len() == 24 && s.bytes().all(|b| b.is_ascii_hexdigit())
}
fn fresh(time: u64) -> bool {
    crate::pressure::now_ms()
        .checked_sub(time)
        .is_some_and(|age| age < TIMEOUT)
}
fn helper(
    role: &str,
    state: &Path,
    group: &Path,
    generation: Option<&str>,
) -> Result<std::process::Child> {
    let mut command = Command::new(std::env::current_exe()?);
    command
        .arg("__cargo_cache-control")
        .arg(role)
        .arg(state)
        .arg(group);
    if let Some(generation) = generation {
        command.arg(generation);
    }
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // A terminal's cancellation targets the compiler/shim, not its recovery worker.
    command.process_group(0);
    Ok(command.spawn()?)
}

/// Compiler identity probing can recognize a wrapper's forwarded --version.
/// Suspension is narrower: accept conventional native drivers, never scripts
/// or arbitrarily named launchers that may own unrelated side effects.
pub(super) fn direct_driver(program: &std::ffi::OsStr) -> bool {
    use std::io::Read;
    let Some(name) = Path::new(program)
        .file_name()
        .and_then(|name| name.to_str())
    else {
        return false;
    };
    let name = name
        .rsplit_once('-')
        .filter(|(_, version)| {
            !version.is_empty() && version.bytes().all(|b| b.is_ascii_digit() || b == b'.')
        })
        .map_or(name, |(name, _)| name);
    let driver = name.rsplit('-').next().unwrap_or(name);
    if !matches!(
        driver,
        "rustc" | "cc" | "c++" | "gcc" | "g++" | "clang" | "clang++"
    ) {
        return false;
    }
    let Ok(path) = which::which(program) else {
        return false;
    };
    let mut magic = [0u8; 4];
    std::fs::File::open(path)
        .and_then(|mut file| file.read_exact(&mut magic))
        .is_ok()
        && magic == *b"\x7fELF"
}

pub(super) fn prepare(command: &mut Command, pool: &Path, root: &Path) -> Result<Action> {
    if !root.is_absolute() {
        bail!("delegated cgroup root must be absolute");
    }
    let root = root.canonicalize()?;
    if !root.join("cgroup.controllers").is_file() {
        bail!("not a cgroup v2 directory");
    }
    let pool = pool.canonicalize()?;
    let pool_key = super::key(pool.as_os_str().as_encoded_bytes());
    let root_key = super::key(root.as_os_str().as_encoded_bytes());
    let group = root.join(format!("tuist_cargo_cache-{}", &pool_key[..24]));
    std::fs::create_dir_all(&group)?;
    enable_memory(&group)?;
    let state = pool.join(format!("supervision-{}", &root_key[..24]));
    std::fs::create_dir_all(&state)?;
    // Serialize launches; the helper also holds a lifetime election lock.
    let mut launch = fslock::LockFile::open(&state.join("launch.lock"))?;
    let startup = Instant::now();
    while !launch.try_lock()? {
        if startup.elapsed() > Duration::from_secs(2) {
            bail!("supervisor startup is busy");
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let current = || {
        read::<Heartbeat>(&state.join("current.json")).filter(|h| {
            token(&h.generation)
                && fresh(h.time)
                && !state.join(&h.generation).join("disabled").exists()
                && read::<u64>(&state.join(&h.generation).join("watchdog.json")).is_some_and(fresh)
        })
    };
    let heartbeat = if let Some(current) = current() {
        current
    } else {
        let mut child = helper("supervisor", &state, &group, None)?;
        let start = Instant::now();
        loop {
            if let Some(current) = current() {
                // Reap if it exits during this shim's life without blocking compiler startup.
                std::thread::spawn(move || {
                    let _ = child.wait();
                });
                break current;
            }
            if child.try_wait()?.is_some() || start.elapsed() > Duration::from_secs(2) {
                bail!("supervisor did not become ready");
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    };
    let registry = state.join(&heartbeat.generation);
    let id = super::key(crate::util::random_string(32).as_bytes())[..24].to_owned();
    let path = group.join(&heartbeat.generation).join(&id);
    let lease_path = registry.join(format!("{id}.lease"));
    let mut lease = fslock::LockFile::open(&lease_path)?;
    lease.lock()?;
    std::fs::create_dir(&path)?;
    let membership = std::fs::OpenOptions::new()
        .write(true)
        .open(path.join("cgroup.procs"))?;
    let freeze = std::fs::OpenOptions::new()
        .write(true)
        .open(path.join("cgroup.freeze"))?;
    drop(freeze);
    let action = Action {
        registry,
        path,
        id,
        _lease: lease,
    };
    command.env("TUIST_CARGO_CACHE_CONTROL_CHILD", "1");
    // SAFETY: only an async-signal-safe write is performed between fork and exec.
    // The inherited descriptor pins this cgroup; no PID lookup or path allocation
    // occurs in the child. Writing zero moves the calling process before exec.
    unsafe {
        command.pre_exec(move || {
            // If delegation disappears during startup, run without supervision.
            // `started` will not register an empty group with the controller.
            libc::write(membership.as_raw_fd(), b"0".as_ptr().cast(), 1);
            Ok(())
        });
    }
    drop(launch);
    Ok(action)
}

pub(crate) struct Action {
    registry: PathBuf,
    path: PathBuf,
    id: String,
    _lease: fslock::LockFile,
}
impl Action {
    /// Publish only after spawn's exec handshake. Freezing before then could
    /// block spawn itself and strand the supervisor's view of live work.
    pub(crate) fn started(&mut self) {
        if !populated(&self.path) {
            return;
        }
        let _ = write(
            &self.registry.join(format!("{}.json", self.id)),
            &crate::pressure::now_ms(),
        );
    }
}
impl Drop for Action {
    fn drop(&mut self) {
        let _ = thaw(&self.path);
        if let Some(mut stats) = read::<Stats>(&self.registry.join(format!("{}.stats", self.id))) {
            stats.resume(crate::pressure::now_ms());
            let _ = write(&self.registry.join(format!("{}.stats", self.id)), &stats);
            if stats.suspended_ms > 0 {
                crate::session::report_shim_warning(&format!(
                    "compiler resumed after {:.2}s suspended for memory pressure",
                    stats.suspended_ms as f64 / 1_000.0
                ));
            }
        }
        let _ = std::fs::remove_file(self.registry.join(format!("{}.json", self.id)));
        // All processes normally exited with the compiler. Cancellation may
        // leave descendants: thaw first, then terminate this owned tree only.
        if populated(&self.path) {
            let _ = std::fs::write(self.path.join("cgroup.kill"), "1");
        }
        let _ = std::fs::remove_dir(&self.path);
        let _ = std::fs::remove_file(self.registry.join(format!("{}.lease", self.id)));
    }
}
fn enable_memory(group: &Path) -> Result<()> {
    let controllers = std::fs::read_to_string(group.join("cgroup.controllers"))?;
    if controllers.split_whitespace().any(|name| name == "memory") {
        std::fs::write(group.join("cgroup.subtree_control"), "+memory")?;
    }
    Ok(())
}
fn populated(group: &Path) -> bool {
    std::fs::read_to_string(group.join("cgroup.events"))
        .is_ok_and(|s| s.lines().any(|l| l == "populated 1"))
}
fn thaw(group: &Path) -> std::io::Result<()> {
    std::fs::write(group.join("cgroup.freeze"), "0")
}
/// An action that finishes normally removes its group without the scanner's
/// lease; a write that lost that race has nothing left to act on.
fn unless_gone(group: &Path, result: std::io::Result<()>) -> std::io::Result<()> {
    result.or_else(|error| if group.exists() { Err(error) } else { Ok(()) })
}
fn groups(group: &Path) -> Vec<PathBuf> {
    std::fs::read_dir(group)
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            let entry = entry.ok()?;
            (entry.file_type().ok()?.is_dir() && token(entry.file_name().to_str()?))
                .then(|| entry.path())
        })
        .collect()
}
fn thaw_all(group: &Path) {
    for path in groups(group) {
        let _ = thaw(&path);
    }
}
fn clean_orphans(registry: &Path, group: &Path) -> Result<usize> {
    let mut live = 0;
    for path in groups(group) {
        let id = path.file_name().unwrap().to_string_lossy();
        let lease_path = registry.join(format!("{id}.lease"));
        let mut lease = fslock::LockFile::open(&lease_path)?;
        if !lease.try_lock()? {
            live += 1;
            continue;
        }
        unless_gone(&path, thaw(&path))?;
        if populated(&path) {
            unless_gone(&path, std::fs::write(path.join("cgroup.kill"), "1"))?;
        }
        // The kill is asynchronous and a populated group cannot be removed.
        // Count a draining group as live so the next scan removes it, without
        // delaying this scan's heartbeat.
        if std::fs::remove_dir(&path).is_err() && populated(&path) {
            live += 1;
            continue;
        }
        let _ = std::fs::remove_file(registry.join(format!("{id}.json")));
        // Keep the locked inode until this scan finishes; action IDs never repeat.
        let _ = std::fs::remove_file(lease_path);
    }
    Ok(live)
}

pub(super) fn dispatch() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(2).collect();
    if args.len() < 3 {
        bail!("invalid control arguments");
    }
    let state = Path::new(&args[1]);
    let group = Path::new(&args[2]);
    if args[0] == "supervisor" {
        supervisor(state, group)
    } else if args[0] == "watchdog" {
        let generation = args
            .get(3)
            .and_then(|s| s.to_str())
            .filter(|s| token(s))
            .ok_or_else(|| eyre::eyre!("invalid generation"))?;
        watchdog(state, group, generation)
    } else {
        bail!("unknown control role")
    }
}

fn supervisor(state: &Path, group: &Path) -> Result<()> {
    let mut election = fslock::LockFile::open(&state.join("supervisor.lock"))?;
    // An exiting predecessor holds the lock until its watchdog exits, briefly
    // after it stops accepting registrations. Wait that out, within the
    // launcher's readiness timeout, rather than leave the compile unsupervised.
    // A disabled predecessor that is still running keeps the lock until it
    // drains, so give up at once and let the compile fall back.
    let exiting = || {
        read::<Heartbeat>(&state.join("current.json")).is_some_and(|h| {
            let registry = state.join(&h.generation);
            token(&h.generation)
                && (registry.join("finished").exists()
                    || std::fs::read_to_string(registry.join("disabled"))
                        .is_ok_and(|r| r == "idle shutdown" || r == "supervisor exited"))
        })
    };
    let start = Instant::now();
    while !election.try_lock()? {
        if !exiting() || start.elapsed() > Duration::from_millis(1_500) {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let generation = super::key(crate::util::random_string(32).as_bytes())[..24].to_owned();
    let registry = state.join(&generation);
    let actions = group.join(&generation);
    std::fs::create_dir_all(&registry)?;
    std::fs::create_dir_all(&actions)?;
    enable_memory(&actions)?;
    let mut watchdog = helper("watchdog", state, group, Some(&generation))?;
    // Probe from a sibling of the action groups so delegated-root limits and
    // PSI are visible even when that root is outside the caller's ancestry.
    // Spawn the watchdog first: it retains the caller's original cgroup.
    let controller = group.join(format!("controller-{generation}"));
    std::fs::create_dir(&controller)?;
    std::fs::write(controller.join("cgroup.procs"), "0")?;
    let start = Instant::now();
    while !read::<u64>(&registry.join("watchdog.json")).is_some_and(fresh) {
        if watchdog.try_wait()?.is_some() || start.elapsed() > Duration::from_secs(2) {
            bail!("watchdog did not become ready");
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let result = supervise(
        state,
        group,
        &registry,
        &actions,
        &generation,
        &mut watchdog,
    );
    let _ = std::fs::write(registry.join("disabled"), "supervisor exited");
    thaw_owned(&registry, &actions);
    let _ = std::fs::write(registry.join("finished"), "1");
    let deadline = Instant::now();
    while watchdog.try_wait()?.is_none() {
        if deadline.elapsed() >= Duration::from_secs(1) {
            // The owned helper may itself be hung. Compilers are already thawed.
            let _ = watchdog.kill();
            let _ = watchdog.wait();
            break;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    result
}
fn supervise(
    state: &Path,
    group: &Path,
    registry: &Path,
    actions: &Path,
    generation: &str,
    watchdog: &mut std::process::Child,
) -> Result<()> {
    let mut idle = Instant::now();
    let mut respawned = Instant::now();
    let mut policy = super::policy::Policy::default();
    let mut monitored = Instant::now();
    loop {
        if !read::<u64>(&registry.join("watchdog.json")).is_some_and(fresh) {
            std::fs::write(registry.join("disabled"), "watchdog heartbeat lost")?;
            // This generation still owns live actions. Replace the watchdog so
            // their cleanup never depends on this process alone.
            if respawned.elapsed() > Duration::from_millis(TIMEOUT) {
                respawned = Instant::now();
                let _ = watchdog.kill();
                let _ = watchdog.wait();
                if let Ok(child) = helper("watchdog", state, group, Some(generation)) {
                    *watchdog = child;
                }
            }
        }
        if registry.join("disabled").exists() {
            // Keep ownership cleanup alive after suspension is disabled.
            thaw_all(actions);
        }
        write(
            &state.join("current.json"),
            &Heartbeat {
                generation: generation.to_owned(),
                time: crate::pressure::now_ms(),
            },
        )?;
        if clean_orphans(registry, actions)? > 0 {
            idle = Instant::now();
        } else if idle.elapsed() > Duration::from_secs(5) {
            let mut launch = fslock::LockFile::open(&state.join("launch.lock"))?;
            if launch.try_lock()? && clean_orphans(registry, actions)? == 0 {
                // Publish shutdown while holding the same lock as registration.
                std::fs::write(registry.join("disabled"), "idle shutdown")?;
                prune(state, group, generation);
                return Ok(());
            }
        }
        if !registry.join("disabled").exists() {
            let failure = match control(state, registry, actions, generation, &mut policy) {
                Ok(true) => {
                    monitored = Instant::now();
                    None
                }
                Ok(false) if monitored.elapsed() < Duration::from_millis(TIMEOUT) => None,
                Ok(false) => Some("pressure sampling blocked by a stale registrar lock".to_owned()),
                Err(error) => Some(format!("pressure monitoring failed: {error:#}")),
            };
            if let Some(reason) = failure {
                std::fs::write(registry.join("disabled"), reason)?;
            }
        }
        if registry.join("disabled").exists() {
            thaw_owned(registry, actions);
            if let Some(pool) = state.parent() {
                let _ = std::fs::remove_file(pool.join("suspended").join(generation));
            }
        }
        std::thread::sleep(TICK);
    }
}
/// Remove earlier generations once none of their actions remain. The caller
/// holds the election and launch locks, so nothing can register into them.
fn prune(state: &Path, group: &Path, current: &str) {
    for entry in std::fs::read_dir(state).into_iter().flatten().flatten() {
        let name = entry.file_name();
        let Some(generation) = name.to_str().filter(|s| token(s) && *s != current) else {
            continue;
        };
        let actions = group.join(generation);
        if !clean_orphans(&entry.path(), &actions).is_ok_and(|live| live == 0) {
            continue;
        }
        // The kernel refuses to remove a group that still has action groups
        // or, for the controller, a replacement watchdog that has not exited.
        let controller = group.join(format!("controller-{generation}"));
        let _ = std::fs::remove_dir(&actions);
        let _ = std::fs::remove_dir(&controller);
        if !actions.exists() && !controller.exists() {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
}
fn watchdog(state: &Path, group: &Path, generation: &str) -> Result<()> {
    let registry = state.join(generation);
    let actions = group.join(generation);
    let start = Instant::now();
    loop {
        write(&registry.join("watchdog.json"), &crate::pressure::now_ms())
            .context("watchdog heartbeat")?;
        let heartbeat = read::<Heartbeat>(&state.join("current.json"));
        let healthy = heartbeat
            .as_ref()
            .is_some_and(|h| h.generation == generation && fresh(h.time));
        if registry.join("finished").exists() {
            thaw_owned(&registry, &actions);
            return Ok(());
        }
        if !healthy && start.elapsed() > Duration::from_millis(TIMEOUT) {
            std::fs::write(registry.join("disabled"), "supervisor heartbeat lost")?;
            // Repeat while a stalled supervisor might wake up in an actuation.
            // No election/registrar lock is needed to rescue a frozen action.
            thaw_owned(&registry, &actions);
            let _ = clean_orphans(&registry, &actions);
            // A successor's heartbeat also proves this generation's supervisor
            // is gone: it held the election lock for its whole life.
            let replaced = heartbeat
                .as_ref()
                .is_some_and(|h| h.generation != generation && fresh(h.time));
            let mut election = fslock::LockFile::open(&state.join("supervisor.lock"))?;
            if (replaced || election.try_lock()?) && clean_orphans(&registry, &actions)? == 0 {
                return Ok(());
            }
        }
        std::thread::sleep(TICK);
    }
}

#[derive(Default, Serialize, Deserialize)]
struct Stats {
    suspended_ms: u64,
    frozen_since: Option<u64>,
    freeze_count: u64,
    peak_memory: u64,
}
impl Stats {
    fn resume(&mut self, now: u64) {
        if let Some(start) = self.frozen_since.take() {
            self.suspended_ms = self.suspended_ms.saturating_add(now.saturating_sub(start));
        }
    }
}

fn control(
    state: &Path,
    registry: &Path,
    actions: &Path,
    generation: &str,
    policy: &mut super::policy::Policy,
) -> Result<bool> {
    use super::policy::Change;
    let pool = state
        .parent()
        .ok_or_else(|| eyre::eyre!("missing scheduler pool"))?;
    let now = crate::pressure::now_ms();
    let mut registrar = fslock::LockFile::open(&pool.join("pool.lock"))?;
    // Never block the control heartbeat behind an admission process.
    if !registrar.try_lock()? {
        return Ok(false);
    }
    // Keep this generation's own samples. Shims refresh the pool's shared
    // state from outside the delegated tree, and mixing the two views would
    // reset hysteresis and judge the delegated root by host readings.
    let pressure =
        crate::pressure::sample(&registry.join("pressure.json"), now, crate::pressure::probe)?;
    if !pressure.valid {
        bail!("memory pressure probes unavailable");
    }
    // Compilers finish without the registrar lock, so an action group can
    // vanish at any point below. Skip it instead of failing the generation.
    let mut ordered = Vec::new();
    for path in groups(actions) {
        let Some(id) = path.file_name().and_then(|s| s.to_str()).map(str::to_owned) else {
            continue;
        };
        let Some(started) = read::<u64>(&registry.join(format!("{id}.json"))) else {
            continue;
        };
        let frozen = match std::fs::read_to_string(path.join("cgroup.freeze")) {
            Ok(value) => value.trim() == "1",
            Err(_) if !path.exists() => continue,
            Err(error) => return Err(error.into()),
        };
        ordered.push((started, id, path, frozen));
    }
    ordered.sort_by(|left, right| (&left.0, &left.1).cmp(&(&right.0, &right.1)));
    let mut frozen: Vec<_> = ordered.iter().map(|action| action.3).collect();
    for (_, id, path, _) in &ordered {
        let mut stats = read::<Stats>(&registry.join(format!("{id}.stats"))).unwrap_or_default();
        let memory = std::fs::read_to_string(path.join("memory.current"))
            .ok()
            .and_then(|s| s.trim().parse::<u64>().ok())
            .unwrap_or(0);
        stats.peak_memory = stats.peak_memory.max(memory);
        write(&registry.join(format!("{id}.stats")), &stats)?;
    }
    if let Some(change) = policy.step(now, pressure.pressured, &frozen) {
        // A watchdog can disable this generation without taking our locks.
        if registry.join("disabled").exists() {
            bail!("watchdog disabled suspension");
        }
        if !read::<u64>(&registry.join("watchdog.json")).is_some_and(fresh) {
            bail!("watchdog heartbeat lost");
        }
        let (index, freeze) = match change {
            Change::Freeze(index) => (index, true),
            Change::Resume(index) => (index, false),
        };
        let (_, id, path, _) = &ordered[index];
        let written = std::fs::write(path.join("cgroup.freeze"), if freeze { "1" } else { "0" });
        unless_gone(path, written)?;
        // A compiler that already finished has nothing left to account for.
        if path.exists() {
            frozen[index] = freeze;
            record(registry, id, now, freeze)?;
        } else {
            frozen[index] = false;
        }
    }
    let pending = pool.join("suspended");
    std::fs::create_dir_all(&pending)?;
    let marker = pending.join(generation);
    if frozen.iter().any(|frozen| *frozen) {
        crate::util::write_advisory(&marker, now.to_string().as_bytes())?;
    } else {
        let _ = std::fs::remove_file(marker);
    }
    Ok(true)
}

fn record(registry: &Path, id: &str, now: u64, freeze: bool) -> Result<()> {
    let mut stats = read::<Stats>(&registry.join(format!("{id}.stats"))).unwrap_or_default();
    if freeze {
        stats.frozen_since = Some(now);
        stats.freeze_count += 1;
    } else {
        stats.resume(now);
    }
    write(&registry.join(format!("{id}.stats")), &stats)?;
    // Machine-readable diagnostics survive detached helper lifetimes.
    use std::io::Write;
    let mut events = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(registry.join("events.jsonl"))?;
    writeln!(
        events,
        "{}",
        serde_json::json!({"time_ms":now,"action":id,"event":if freeze {"suspend"} else {"resume"},"suspended_ms":stats.suspended_ms})
    )?;
    Ok(())
}

fn thaw_owned(registry: &Path, group: &Path) {
    let now = crate::pressure::now_ms();
    for path in groups(group) {
        if thaw(&path).is_ok() {
            let id = path.file_name().unwrap().to_string_lossy();
            let file = registry.join(format!("{id}.stats"));
            if let Some(mut stats) = read::<Stats>(&file) {
                stats.resume(now);
                let _ = write(&file, &stats);
            }
        }
    }
}

#[cfg(test)]
mod eligibility_tests {
    use super::*;
    #[test]
    fn native_drivers_are_distinguished_from_forwarding_scripts() {
        use std::os::unix::fs::PermissionsExt;
        let directory = tempfile::tempdir().unwrap();
        for (name, bytes, accepted) in [
            ("rustc", &b"\x7fELF"[..], true),
            ("aarch64-linux-gnu-gcc-13", &b"\x7fELF"[..], true),
            ("clang++-18", &b"\x7fELF"[..], true),
            ("custom-launcher", &b"\x7fELF"[..], false),
            ("gcc", &b"#!/bin/sh\nexec /usr/bin/gcc \"$@\""[..], false),
        ] {
            let path = directory.path().join(name);
            std::fs::write(&path, bytes).unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
            assert_eq!(direct_driver(path.as_os_str()), accepted, "{name}");
        }
    }
}
