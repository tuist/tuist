//! Opt-in compiler-tree supervision. The watchdog and supervisor never enter
//! action cgroups. Unsupported hosts retain ordinary admission scheduling.
use std::process::{Command, ExitCode};

#[cfg(target_os = "linux")]
#[path = "supervision/linux.rs"]
mod linux;
#[cfg(any(target_os = "linux", test))]
#[path = "supervision/policy.rs"]
mod policy;
#[cfg(target_os = "linux")]
pub(crate) use linux::Action;
#[cfg(not(target_os = "linux"))]
pub(crate) struct Action;
#[cfg(not(target_os = "linux"))]
impl Action {
    pub(crate) fn started(&mut self) {}
}

pub(crate) fn prepare(command: &mut Command, eligible: bool) -> Option<Action> {
    if !eligible || std::env::var_os("TUIST_CARGO_CACHE_CONTROL_CHILD").is_some() {
        return None;
    }
    let pool = crate::scheduler::pool()?;
    let settings = crate::config::Config::load().ok()?.scheduler;
    let enabled = std::env::var("TUIST_CARGO_CACHE_SCHED_SUSPEND")
        .ok()
        .map_or(
            settings.suspend && settings.pressure && settings.memory_bytes.is_some(),
            |v| v == "1",
        );
    if !enabled {
        return None;
    }
    #[cfg(target_os = "linux")]
    {
        if !linux::direct_driver(command.get_program()) {
            return None;
        }
        let root = std::env::var_os("TUIST_CARGO_CACHE_SCHED_CGROUP_ROOT")
            .map(std::path::PathBuf::from)
            .or(settings.cgroup_root);
        match root
            .filter(|p| !p.as_os_str().is_empty())
            .ok_or_else(|| eyre::eyre!("scheduler.cgroup_root is not configured"))
            .and_then(|root| linux::prepare(command, &pool.dir, &root))
        {
            Ok(action) => return Some(action),
            Err(error) => warn_once(
                &pool.dir,
                &format!("compiler suspension unavailable: {error:#}; using admission only"),
            ),
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = command;
        warn_once(
            &pool.dir,
            "compiler suspension requires Linux cgroup v2; using admission only",
        );
    }
    None
}

fn warn_once(pool: &std::path::Path, message: &str) {
    let session = std::env::var("TUIST_CARGO_CACHE_SCHED_BUILD_ID")
        .unwrap_or_else(|_| std::process::id().to_string());
    let key = key(session.as_bytes());
    let _ = std::fs::create_dir_all(pool);
    if std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(pool.join(format!("suspension-warning-{key}")))
        .is_ok()
    {
        crate::session::report_shim_warning(message);
    }
}

/// Internal helper dispatch, before argv0 shim dispatch and normal CLI parsing.
pub fn dispatch() -> Option<ExitCode> {
    if std::env::args_os().nth(1).as_deref() != Some(std::ffi::OsStr::new("__cargo_cache-control"))
    {
        return None;
    }
    #[cfg(target_os = "linux")]
    return Some(match linux::dispatch() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("tuist_cargo_cache[supervision]: {error:#}");
            ExitCode::FAILURE
        }
    });
    #[cfg(not(target_os = "linux"))]
    Some(ExitCode::FAILURE)
}

/// Captured compiler output uses the same post-spawn registration as streaming.
pub(crate) fn output(
    command: &mut Command,
    eligible: bool,
) -> std::io::Result<std::process::Output> {
    let mut action = prepare(command, eligible);
    let child = command
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()?;
    if let Some(action) = &mut action {
        action.started();
    }
    child.wait_with_output()
}

fn key(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// A stale supervisor must never leave admission closed indefinitely.
pub(crate) fn resumes_pending(pool: &std::path::Path, now: u64) -> bool {
    std::fs::read_dir(pool.join("suspended"))
        .into_iter()
        .flatten()
        .any(|entry| {
            entry
                .ok()
                .and_then(|entry| std::fs::read_to_string(entry.path()).ok())
                .and_then(|s| s.parse::<u64>().ok())
                .is_some_and(|stamp| now.checked_sub(stamp).is_some_and(|age| age < 3_000))
        })
}
