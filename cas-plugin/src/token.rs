//! Bearer token acquisition for the REAPI endpoint.
//!
//! The broker holds no auth logic. It caches a bearer and, when it has none,
//! shells out to `tuist auth token <url>` (a hidden command that resolves the
//! token, refreshing if needed, and prints it). The CLI's
//! ServerAuthenticationController owns the keychain read, the refresh, and the
//! cross-process refresh lock (the single source of truth). The cache is seeded
//! from TUIST_CAS_TOKEN (set directly on CI) and refreshed on demand.

use std::process::Command;
use std::sync::{Arc, Mutex};

pub struct TokenProvider {
    cached: Mutex<Option<String>>,
    // Serializes refreshes so a startup burst of resolves runs `tuist` once
    // rather than once per thread.
    refreshing: Mutex<()>,
    // How to fetch a fresh token. Absent (direct/bench mode) means the seeded
    // env token is all there is.
    fetch: Option<TokenFetch>,
}

struct TokenFetch {
    tuist_bin: String,
    server_url: Option<String>,
}

impl TokenProvider {
    /// Builds a provider from the environment: `TUIST_CAS_TOKEN` seeds the
    /// cache; `TUIST_CAS_TUIST_BIN` (+ optional `TUIST_CAS_SERVER_URL`) enables
    /// shell-out refresh via the CLI.
    pub fn from_env() -> Arc<Self> {
        let cached = env_nonempty("TUIST_CAS_TOKEN");
        let fetch = env_nonempty("TUIST_CAS_TUIST_BIN").map(|tuist_bin| TokenFetch {
            tuist_bin,
            server_url: env_nonempty("TUIST_CAS_SERVER_URL"),
        });
        Arc::new(Self {
            cached: Mutex::new(cached),
            refreshing: Mutex::new(()),
            fetch,
        })
    }

    /// The current bearer, fetching one lazily if the cache is empty. Concurrent
    /// cold callers coalesce onto a single `tuist` invocation.
    pub fn current(&self) -> Option<String> {
        if let Some(token) = self.cached.lock().unwrap().clone() {
            return Some(token);
        }
        let fetch = self.fetch.as_ref()?;
        let _guard = self.refreshing.lock().unwrap();
        // The cache may have filled while we waited for the guard.
        if let Some(token) = self.cached.lock().unwrap().clone() {
            return Some(token);
        }
        let fresh = run_token_command(fetch);
        if let Some(token) = &fresh {
            *self.cached.lock().unwrap() = Some(token.clone());
        }
        fresh
    }

    /// Forces a fresh fetch, replacing the cache. The broker calls this
    /// periodically to stay ahead of expiry. A no-op without a fetch config.
    pub fn force_refresh(&self) {
        let Some(fetch) = self.fetch.as_ref() else {
            return;
        };
        let _guard = self.refreshing.lock().unwrap();
        if let Some(token) = run_token_command(fetch) {
            *self.cached.lock().unwrap() = Some(token);
        }
    }
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|value| !value.is_empty())
}

fn run_token_command(fetch: &TokenFetch) -> Option<String> {
    let mut command = Command::new(&fetch.tuist_bin);
    command.arg("auth").arg("token");
    if let Some(url) = &fetch.server_url {
        command.arg("--url").arg(url);
    }
    let output = command.output().ok()?;
    if !output.status.success() {
        return None;
    }
    // The command prints only the bearer, but take the last non-empty line
    // defensively so any leading CLI log noise on stdout can't corrupt it.
    let stdout = String::from_utf8_lossy(&output.stdout);
    stdout
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_string)
}
