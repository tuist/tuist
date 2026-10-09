//! XDG Base Directory resolution.
//!
//! Once routes its cache, state, runtime, and data files through XDG
//! so users (and tests) can redirect them by setting the relevant env
//! var. The defaults follow the XDG spec; macOS users without XDG vars
//! get XDG-shaped fallbacks under `$HOME` rather than the platform
//! `Library/` tree, so a single mental model translates cleanly
//! between local hosts, CI runners, and remote-execution sandboxes.
//!
//! Build outputs (`.once/out/<target>`) intentionally stay
//! workspace-local. They're per-project artifacts users consume from
//! their checkout; moving them under `$HOME` would force ad-hoc
//! discovery and break the `./.once/out/...` muscle memory inherited
//! from the rust and apple rules. The split is:
//!
//! - `<workspace>/.once/out/...` - build outputs, runtime sessions
//! - `<XDG_CACHE_HOME>/once/cas` - CAS blobs and action results
//! - `<XDG_RUNTIME_DIR>/once` - daemon sockets and ephemeral runtime
//! - `<XDG_DATA_HOME>/once` - long-lived materialized assets like
//!   the embedded elixir daemon script
//!
//! All `from_env` lookups are cheap (just env reads and `PathBuf`
//! joins). Callers re-resolve on each invocation so per-test env
//! overrides take effect immediately.

use std::env;
use std::path::PathBuf;

/// Resolved XDG base directories. Construct with [`Xdg::from_env`].
#[derive(Debug, Clone)]
pub struct Xdg {
    pub cache_home: PathBuf,
    pub state_home: PathBuf,
    pub data_home: PathBuf,
    pub config_home: PathBuf,
    /// `XDG_RUNTIME_DIR` if set, otherwise a tempdir-rooted per-user
    /// fallback. macOS doesn't set `XDG_RUNTIME_DIR` natively, so the
    /// fallback is what most users hit there.
    pub runtime_dir: PathBuf,
}

impl Xdg {
    /// Resolve XDG paths from the process environment.
    ///
    /// Each base directory follows the spec: env var if set and
    /// non-empty, otherwise a sensible default under `$HOME`. The
    /// runtime dir has no XDG default, so we synthesize one under the
    /// system temp directory keyed by uid so concurrent users don't
    /// collide.
    pub fn from_env() -> Self {
        let home = env::var_os("HOME").map_or_else(|| PathBuf::from("/tmp"), PathBuf::from);
        Self {
            cache_home: lookup("XDG_CACHE_HOME").unwrap_or_else(|| home.join(".cache")),
            state_home: lookup("XDG_STATE_HOME")
                .unwrap_or_else(|| home.join(".local").join("state")),
            data_home: lookup("XDG_DATA_HOME").unwrap_or_else(|| home.join(".local").join("share")),
            config_home: lookup("XDG_CONFIG_HOME").unwrap_or_else(|| home.join(".config")),
            runtime_dir: lookup("XDG_RUNTIME_DIR").unwrap_or_else(default_runtime_dir),
        }
    }

    /// Root of Once's content-addressed cache. Holds blobs, action
    /// results, and scratch files - everything that can be regenerated
    /// from the source graph plus the toolchain.
    pub fn once_cas(&self) -> PathBuf {
        self.cache_home.join("once").join("cas")
    }

    /// Long-lived, non-reproducible Once state. Empty for now;
    /// reserved for things like recent-build history that survive a
    /// cache wipe but aren't user-edited config.
    pub fn once_state(&self) -> PathBuf {
        self.state_home.join("once")
    }

    /// Materialized assets and shared data. The elixir compile daemon
    /// script writes here, as do future tracer manifests and SDK
    /// snapshots.
    pub fn once_data(&self) -> PathBuf {
        self.data_home.join("once")
    }

    /// Per-user runtime directory for sockets and other ephemeral
    /// files. On hosts that set `XDG_RUNTIME_DIR` (most Linux) this is
    /// a tmpfs path owned by the user; on macOS we fall back to a uid
    /// keyed tempdir.
    pub fn once_runtime(&self) -> PathBuf {
        self.runtime_dir.join("once")
    }
}

fn lookup(name: &str) -> Option<PathBuf> {
    env::var_os(name)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
}

fn default_runtime_dir() -> PathBuf {
    let tmp = env::var_os("TMPDIR").map_or_else(|| PathBuf::from("/tmp"), PathBuf::from);
    let uid = current_uid();
    tmp.join(format!("once-runtime-{uid}"))
}

#[cfg(unix)]
fn current_uid() -> u32 {
    // Reading /proc/self/status or calling libc::getuid would be more
    // direct, but we avoid `unsafe` and the libc dependency by going
    // through std. SAFETY-free `geteuid` via the file system isn't
    // portable; fall back to a stable per-host token instead when uid
    // isn't readable so two users on the same box still get separate
    // dirs.
    env::var("UID")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

#[cfg(not(unix))]
fn current_uid() -> u32 {
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // env::set_var is process-wide; cargo test runs tests in parallel
    // by default, so concurrent runs of these cases would race on the
    // very env vars they manipulate. Serialize through one mutex to
    // keep snapshot/restore semantics honest.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn with_env<F: FnOnce()>(vars: &[(&str, Option<&str>)], f: F) {
        let _guard = ENV_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let saved: Vec<_> = vars.iter().map(|(k, _)| (*k, env::var_os(*k))).collect();
        for (k, v) in vars {
            match v {
                Some(value) => env::set_var(k, value),
                None => env::remove_var(k),
            }
        }
        f();
        for (k, prior) in saved {
            match prior {
                Some(value) => env::set_var(k, value),
                None => env::remove_var(k),
            }
        }
    }

    #[test]
    fn env_overrides_take_precedence() {
        with_env(
            &[
                ("XDG_CACHE_HOME", Some("/tmp/fab-cache-test")),
                ("XDG_STATE_HOME", Some("/tmp/fab-state-test")),
                ("XDG_DATA_HOME", Some("/tmp/fab-data-test")),
                ("XDG_CONFIG_HOME", Some("/tmp/fab-config-test")),
                ("XDG_RUNTIME_DIR", Some("/tmp/fab-runtime-test")),
            ],
            || {
                let xdg = Xdg::from_env();
                assert_eq!(xdg.cache_home, PathBuf::from("/tmp/fab-cache-test"));
                assert_eq!(xdg.state_home, PathBuf::from("/tmp/fab-state-test"));
                assert_eq!(xdg.data_home, PathBuf::from("/tmp/fab-data-test"));
                assert_eq!(xdg.config_home, PathBuf::from("/tmp/fab-config-test"));
                assert_eq!(xdg.runtime_dir, PathBuf::from("/tmp/fab-runtime-test"));
            },
        );
    }

    #[test]
    fn empty_env_var_falls_through_to_default() {
        // Empty strings would otherwise collapse to "" and silently
        // re-root every once path under the workspace; treat them as
        // unset to match what most XDG-conforming tools do.
        with_env(
            &[("HOME", Some("/home/test")), ("XDG_CACHE_HOME", Some(""))],
            || {
                let xdg = Xdg::from_env();
                assert_eq!(xdg.cache_home, PathBuf::from("/home/test/.cache"));
            },
        );
    }

    #[test]
    fn once_paths_namespace_under_once() {
        with_env(
            &[
                ("XDG_CACHE_HOME", Some("/c")),
                ("XDG_STATE_HOME", Some("/s")),
                ("XDG_DATA_HOME", Some("/d")),
                ("XDG_CONFIG_HOME", Some("/g")),
                ("XDG_RUNTIME_DIR", Some("/r")),
            ],
            || {
                let xdg = Xdg::from_env();
                assert_eq!(xdg.once_cas(), PathBuf::from("/c/once/cas"));
                assert_eq!(xdg.once_state(), PathBuf::from("/s/once"));
                assert_eq!(xdg.once_data(), PathBuf::from("/d/once"));
                assert_eq!(xdg.once_runtime(), PathBuf::from("/r/once"));
            },
        );
    }

    #[test]
    fn runtime_dir_falls_back_under_tmpdir() {
        with_env(
            &[
                ("XDG_RUNTIME_DIR", None),
                ("TMPDIR", Some("/var/tmp")),
                ("UID", Some("1234")),
            ],
            || {
                let xdg = Xdg::from_env();
                assert_eq!(xdg.runtime_dir, PathBuf::from("/var/tmp/once-runtime-1234"));
            },
        );
    }
}
