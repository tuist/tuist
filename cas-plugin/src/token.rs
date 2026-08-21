//! Bearer token acquisition for the REAPI endpoint.
//!
//! The proxy holds no auth logic. It caches a bearer and, when it has none,
//! shells out to `tuist auth token <url>` (a hidden command that resolves the
//! token, refreshing if needed, and prints it). The CLI's
//! ServerAuthenticationController owns the keychain read, the refresh, and the
//! cross-process refresh lock (the single source of truth). The cache is seeded
//! from TUIST_CAS_TOKEN (set directly on CI) and re-fetched only when the cached
//! JWT is close to expiry (see `refresh_if_expiring`), so a long-lived proxy
//! re-auths about once per token lifetime rather than on a fixed cadence.

use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine;

pub struct TokenProvider {
    cached: Mutex<Option<CachedToken>>,
    // Serializes refreshes so a startup burst of resolves runs `tuist` once
    // rather than once per thread.
    refreshing: Mutex<()>,
    // How to fetch a fresh token. Absent (direct/bench mode) means the seeded
    // env token is all there is.
    fetch: Option<TokenFetch>,
}

/// A bearer plus the expiry parsed from its JWT `exp` claim, if any. Opaque
/// (non-JWT) project tokens carry no expiry and are never proactively refreshed.
struct CachedToken {
    value: String,
    expiry: Option<SystemTime>,
}

impl CachedToken {
    fn new(value: String) -> Self {
        let expiry = jwt_expiry(&value);
        Self { value, expiry }
    }
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
        let cached = env_nonempty("TUIST_CAS_TOKEN").map(CachedToken::new);
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
        if let Some(cached) = self.cached.lock().unwrap().as_ref() {
            return Some(cached.value.clone());
        }
        let fetch = self.fetch.as_ref()?;
        let _guard = self.refreshing.lock().unwrap();
        // The cache may have filled while we waited for the guard.
        if let Some(cached) = self.cached.lock().unwrap().as_ref() {
            return Some(cached.value.clone());
        }
        let fresh = run_token_command(fetch);
        if let Some(token) = &fresh {
            *self.cached.lock().unwrap() = Some(CachedToken::new(token.clone()));
        }
        fresh
    }

    /// Refreshes the bearer only when the cached JWT is within `lead` of its
    /// expiry, so the maintenance loop can call this every tick cheaply: it
    /// shells out to `tuist` inside the pre-expiry window, not on a fixed
    /// cadence. A no-op without a fetch config.
    ///
    /// `lead` must be smaller than the CLI's own refresh threshold (currently
    /// 30s in ServerAuthenticationController): only then does `tuist auth token`
    /// mint a *fresh* token when we ask, rather than handing back the still-valid
    /// one — which would make us re-shell every tick until that threshold. It
    /// must also exceed the maintenance tick interval so a tick cannot step over
    /// the window. Tokens with no parseable expiry (opaque project tokens) are
    /// never refreshed here: there is nothing to renew.
    pub fn refresh_if_expiring(&self, lead: Duration) {
        if self.fetch.is_none() {
            return;
        }
        let should_refresh = match self.cached.lock().unwrap().as_ref() {
            None => true,
            Some(cached) => match cached.expiry {
                None => false,
                Some(expiry) => expiry
                    .checked_sub(lead)
                    .is_none_or(|deadline| SystemTime::now() >= deadline),
            },
        };
        if should_refresh {
            self.force_refresh();
        }
    }

    /// Forces a fresh fetch, replacing the cache. A no-op without a fetch config.
    fn force_refresh(&self) {
        let Some(fetch) = self.fetch.as_ref() else {
            return;
        };
        let _guard = self.refreshing.lock().unwrap();
        if let Some(token) = run_token_command(fetch) {
            *self.cached.lock().unwrap() = Some(CachedToken::new(token));
        }
    }
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|value| !value.is_empty())
}

/// Parses the `exp` (seconds since the Unix epoch) out of a JWT bearer's
/// payload, mirroring the CLI's `JWT.parse`. Returns `None` for opaque, non-JWT
/// tokens (e.g. project tokens) or any bearer whose payload we cannot read.
fn jwt_expiry(token: &str) -> Option<SystemTime> {
    let payload_b64 = token.split('.').nth(1)?;
    let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload_b64.trim_end_matches('='))
        .ok()?;
    let exp = extract_exp(&payload)?;
    Some(UNIX_EPOCH + Duration::from_secs(exp))
}

/// Reads the integer `exp` claim from a flat JWT payload without a JSON
/// dependency. The payload is JSON we mint ourselves; `exp` is a top-level
/// number. Matches `"exp"` only as a key (followed by `:`), so a string value
/// that happens to contain `exp` is not mistaken for the claim.
fn extract_exp(payload: &[u8]) -> Option<u64> {
    let text = std::str::from_utf8(payload).ok()?;
    const KEY: &str = "\"exp\"";
    let mut from = 0;
    while let Some(rel) = text[from..].find(KEY) {
        let after_key = &text[from + rel + KEY.len()..];
        if let Some(rest) = after_key.trim_start().strip_prefix(':') {
            let digits: String = rest
                .trim_start()
                .chars()
                .take_while(char::is_ascii_digit)
                .collect();
            if !digits.is_empty() {
                return digits.parse().ok();
            }
        }
        from += rel + KEY.len();
    }
    None
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

#[cfg(test)]
mod tests {
    use super::*;

    fn make_jwt(payload_json: &str) -> String {
        let header =
            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(b"{\"alg\":\"none\"}");
        let payload =
            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(payload_json.as_bytes());
        format!("{header}.{payload}.")
    }

    #[test]
    fn parses_exp_from_a_jwt_bearer() {
        let jwt = make_jwt(r#"{"exp":1700000000,"email":"a@b.co","type":"user"}"#);
        assert_eq!(
            jwt_expiry(&jwt),
            Some(UNIX_EPOCH + Duration::from_secs(1_700_000_000))
        );
    }

    #[test]
    fn tolerates_key_ordering_and_whitespace() {
        let jwt = make_jwt(r#"{ "email": "x@y.z", "exp": 1699999999 }"#);
        assert_eq!(
            jwt_expiry(&jwt),
            Some(UNIX_EPOCH + Duration::from_secs(1_699_999_999))
        );
    }

    #[test]
    fn ignores_exp_appearing_as_a_string_value() {
        // A field whose value is the literal "exp" must not be read as the claim.
        let jwt = make_jwt(r#"{"type":"exp","foo":5,"exp":1700000123}"#);
        assert_eq!(
            jwt_expiry(&jwt),
            Some(UNIX_EPOCH + Duration::from_secs(1_700_000_123))
        );
    }

    #[test]
    fn opaque_project_tokens_have_no_expiry() {
        assert_eq!(jwt_expiry("tuist_abc123opaqueprojecttoken"), None);
    }

    #[test]
    fn malformed_payload_has_no_expiry() {
        assert_eq!(jwt_expiry("header.not-base64-!!!.sig"), None);
    }
}
