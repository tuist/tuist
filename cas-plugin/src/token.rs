//! Bearer token acquisition for the REAPI endpoint.
//!
//! The proxy holds no auth logic. It caches a bearer and, when it has none,
//! shells out to `tuist cache config --json <account/project>` for scoped cache
//! tokens, or `tuist auth token --url <url>` for the machine bearer (which resolves the
//! token, refreshing if needed, and prints it). The CLI's
//! ServerAuthenticationController owns the keychain read, the refresh, and the
//! cross-process refresh lock (the single source of truth). The cache is seeded
//! from TUIST_CAS_TOKEN (set directly on CI) and re-fetched only when the cached
//! JWT is close to expiry (see `refresh_if_expiring`), so a long-lived proxy
//! re-auths about once per token lifetime rather than on a fixed cadence.
//! Failed fetches share a per-provider retry delay, starting at 30 seconds and
//! doubling to five minutes; successful fetches reset it.

use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine;

pub struct TokenProvider {
    cached: Mutex<Option<CachedToken>>,
    // Serializes refreshes so a startup burst of resolves runs `tuist` once
    // rather than once per thread.
    refreshing: Mutex<RefreshState>,
    // How to fetch a fresh token. Absent (direct/bench mode) means the seeded
    // env token is all there is.
    fetch: Option<TokenFetch>,
}

const INITIAL_RETRY_DELAY: Duration = Duration::from_secs(30);
const MAX_RETRY_DELAY: Duration = Duration::from_secs(300);

struct RefreshState {
    retry_at: Option<Instant>,
    retry_delay: Duration,
    executable: Option<String>,
}

impl Default for RefreshState {
    fn default() -> Self {
        Self {
            retry_at: None,
            retry_delay: INITIAL_RETRY_DELAY,
            executable: None,
        }
    }
}

/// A bearer plus the expiry parsed from its JWT `exp` claim, if any. Opaque
/// (non-JWT) project tokens carry no expiry and are never proactively refreshed.
struct CachedToken {
    // None is an explicitly successful network-trusted cache configuration,
    // not a failed credential lookup.
    value: Option<String>,
    expiry: Option<SystemTime>,
    unsigned_endpoint: Option<String>,
}

impl CachedToken {
    fn new(value: String) -> Self {
        let expiry = jwt_expiry(&value);
        Self {
            value: Some(value),
            expiry,
            unsigned_endpoint: None,
        }
    }
}

pub struct TokenFetch {
    pub tuist_bin: String,
    launch_target: Option<std::path::PathBuf>,
    pub server_url: Option<String>,
    full_handle: Option<String>,
}

impl TokenFetch {
    pub fn executable(&self) -> String {
        self.launch_target
            .as_deref()
            .and_then(crate::proxy_upgrade::selected_executable)
            .map(|path| path.to_string_lossy().into_owned())
            .unwrap_or_else(|| self.tuist_bin.clone())
    }
}

impl TokenProvider {
    /// How the bearer is fetched, when it is fetched by shelling out to the
    /// CLI. Exposed so the same CLI can be asked where the cache is, rather
    /// than a second copy of how to find and address it. `None` in env-only
    /// (CI) mode, where there is no CLI to ask.
    pub fn cli_fetch(&self) -> Option<&TokenFetch> {
        self.fetch.as_ref()
    }

    pub fn account_handle(&self) -> Option<&str> {
        self.fetch
            .as_ref()?
            .full_handle
            .as_deref()?
            .split_once('/')
            .map(|(account, _)| account)
    }

    /// Anonymous permission belongs to the endpoint the CLI validated, not to
    /// a still-live Remote from before an endpoint or credential transition.
    pub fn current_for_endpoint(&self, endpoint: &str) -> Result<Option<String>, String> {
        self.current();
        match self.cached.lock().unwrap().as_ref() {
            Some(cached) => {
                if cached.value.is_none()
                    && !cached
                        .unsigned_endpoint
                        .as_deref()
                        .is_some_and(|allowed| crate::endpoint::same_endpoint(allowed, endpoint))
                {
                    return Err(
                        "network-trusted cache endpoint changed; awaiting endpoint resolution"
                            .into(),
                    );
                }
                Ok(cached.value.clone())
            }
            None => Ok(self.fetch.as_ref().map(|_| String::new())),
        }
    }

    /// Builds a provider from the environment: `TUIST_CAS_TOKEN` seeds the
    /// cache; `TUIST_CAS_TUIST_BIN` (+ optional `TUIST_CAS_SERVER_URL`) enables
    /// shell-out refresh via the CLI.
    pub fn from_env() -> Arc<Self> {
        let cached = std::env::var_os("TUIST_CAS_TOKEN")
            .map(|value| CachedToken::new(value.into_string().unwrap_or_default()));
        let fetch = env_nonempty("TUIST_CAS_TUIST_BIN").map(|tuist_bin| TokenFetch {
            tuist_bin,
            launch_target: env_nonempty("TUIST_CAS_PROXY_LAUNCH_TARGET").map(Into::into),
            server_url: env_nonempty("TUIST_CAS_SERVER_URL"),
            full_handle: None,
        });
        Arc::new(Self {
            cached: Mutex::new(cached),
            refreshing: Mutex::new(RefreshState::default()),
            fetch,
        })
    }

    /// A separate cache-token provider for each project. Never seed it from
    /// another project's JWT; direct env-only integrations keep their bearer.
    pub fn for_instance(self: &Arc<Self>, full_handle: &str) -> Arc<Self> {
        let Some(fetch) = &self.fetch else {
            return self.clone();
        };
        Arc::new(Self {
            cached: Mutex::new(None),
            refreshing: Mutex::new(RefreshState::default()),
            fetch: Some(TokenFetch {
                tuist_bin: fetch.tuist_bin.clone(),
                launch_target: fetch.launch_target.clone(),
                server_url: fetch.server_url.clone(),
                full_handle: Some(full_handle.to_string()),
            }),
        })
    }

    /// The current bearer, fetching one lazily if the cache is empty. Concurrent
    /// cold callers coalesce onto a single `tuist` invocation.
    fn current(&self) -> Option<String> {
        if let Some(cached) = self.cached.lock().unwrap().as_ref() {
            if cached.value.is_some()
                || cached
                    .expiry
                    .is_some_and(|expiry| SystemTime::now() < expiry)
            {
                return cached.value.clone();
            }
        }
        self.refresh(Some(Duration::ZERO));
        match self.cached.lock().unwrap().as_ref() {
            Some(cached) => cached.value.clone(),
            // A failed CLI lookup must send an invalid credential rather than
            // silently select network trust. Direct, credential-free integrations
            // have no CLI fetch and retain their existing absent-header behavior.
            None => self.fetch.as_ref().map(|_| String::new()),
        }
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
        self.refresh(Some(lead));
    }

    fn refresh(&self, lead: Option<Duration>) {
        let Some(fetch) = self.fetch.as_ref() else {
            return;
        };
        let mut state = self.refreshing.lock().unwrap();
        let executable = fetch.executable();
        if state.executable.as_deref() != Some(executable.as_str()) {
            state.retry_at = None;
            state.retry_delay = INITIAL_RETRY_DELAY;
            state.executable = Some(executable.clone());
        }
        // Recheck after waiting: another caller may have fetched a token or
        // recorded a failure while this one waited for the refresh lock.
        let should_refresh = match self.cached.lock().unwrap().as_ref() {
            None => true,
            Some(cached) => lead.zip(cached.expiry).is_some_and(|(lead, expiry)| {
                expiry
                    .checked_sub(lead)
                    .is_none_or(|deadline| SystemTime::now() >= deadline)
            }),
        };
        if !should_refresh
            || state
                .retry_at
                .is_some_and(|deadline| Instant::now() < deadline)
        {
            return;
        }
        if let Some(token) = run_token_command(fetch, &executable) {
            *self.cached.lock().unwrap() = Some(token);
            *state = RefreshState::default();
        } else {
            let mut cached = self.cached.lock().unwrap();
            if cached.as_ref().is_some_and(|token| token.value.is_none()) {
                *cached = None;
            }
            state.retry_at = Some(Instant::now() + state.retry_delay);
            state.retry_delay = (state.retry_delay * 2).min(MAX_RETRY_DELAY);
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

fn run_token_command(fetch: &TokenFetch, executable: &str) -> Option<CachedToken> {
    let mut command = Command::new(executable);
    if let Some(full_handle) = &fetch.full_handle {
        command
            .arg("cache")
            .arg("config")
            .arg("--json")
            .arg(full_handle);
    } else {
        command.arg("auth").arg("token");
    }
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
    if fetch.full_handle.is_some() {
        let start = stdout.find('{')?;
        let value = serde_json::Deserializer::from_str(&stdout[start..])
            .into_iter::<serde_json::Value>()
            .next()?
            .ok()?;
        let token = value.get("token")?.as_str()?;
        return Some(if token.is_empty() {
            CachedToken {
                value: None,
                expiry: Some(SystemTime::now() + Duration::from_secs(60)),
                unsigned_endpoint: Some(value.get("url")?.as_str()?.to_owned()),
            }
        } else {
            CachedToken::new(token.to_owned())
        });
    }
    stdout
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(|token| CachedToken::new(token.to_owned()))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub(crate) struct FakeCli(pub(crate) std::path::PathBuf);

    impl FakeCli {
        pub(crate) fn new() -> Self {
            use std::os::unix::fs::PermissionsExt;
            static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
            let path = std::env::temp_dir().join(format!(
                "tuist-token-test-{}-{}-{}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
            ));
            std::fs::create_dir(&path).unwrap();
            let command = path.join("tuist");
            std::fs::write(
                &command,
                r#"#!/bin/sh
set -eu
[ "$1" = cache ] && [ "$2" = config ] && [ "$3" = --json ]
[ "$5" = --url ] && [ "$6" = https://tuist.dev ]
case "$4" in
    acme/one|acme/two) ;;
    *) exit 1 ;;
esac
printf '%s\n' "$4" >> "$(dirname "$0")/calls"
printf 'CLI log\n{"token":"%s","url":"https://acme.cache.tuist.dev"}\n' "$4"
"#,
            )
            .unwrap();
            std::fs::set_permissions(&command, std::fs::Permissions::from_mode(0o700)).unwrap();
            Self(path)
        }

        pub(crate) fn provider(&self) -> Arc<TokenProvider> {
            Arc::new(TokenProvider {
                cached: Mutex::new(Some(CachedToken::new("machine-bearer".into()))),
                refreshing: Mutex::new(RefreshState::default()),
                fetch: Some(TokenFetch {
                    tuist_bin: self.0.join("tuist").to_str().unwrap().to_string(),
                    launch_target: None,
                    server_url: Some("https://tuist.dev".into()),
                    full_handle: None,
                }),
            })
        }
    }

    #[test]
    fn a_removed_old_cli_does_not_strand_token_refresh_or_its_retry_backoff() {
        let old = FakeCli::new();
        let new = FakeCli::new();
        let target = old.0.join("target.json");
        let write_target = |executable: &std::path::Path, version: &str| {
            std::fs::write(
                &target,
                serde_json::json!({
                    "executable": executable, "tuistVersion": version
                })
                .to_string(),
            )
            .unwrap();
        };
        write_target(&old.0.join("tuist"), "4.213.0");
        let mut root = old.provider();
        Arc::get_mut(&mut root)
            .unwrap()
            .fetch
            .as_mut()
            .unwrap()
            .launch_target = Some(target.clone());
        let provider = root.for_instance("acme/one");
        std::fs::remove_file(old.0.join("tuist")).unwrap();
        assert_eq!(provider.current().as_deref(), Some(""));
        assert!(provider.refreshing.lock().unwrap().retry_at.is_some());
        write_target(&new.0.join("tuist"), "4.214.0");
        assert_eq!(provider.current().as_deref(), Some("acme/one"));
        assert_eq!(
            provider.cli_fetch().unwrap().executable(),
            new.0.join("tuist").to_str().unwrap()
        );
        assert_eq!(
            std::fs::read_to_string(new.0.join("calls")).unwrap(),
            "acme/one\n"
        );
    }

    impl Drop for FakeCli {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn reapi_preserves_credentials_accounts_and_endpoint_bound_network_trust() {
        use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
        use reapi::action_cache_server::{ActionCache, ActionCacheServer};
        use tonic::{Request, Response, Status};

        #[derive(Default)]
        struct Observed {
            calls: usize,
            account: Option<String>,
            authorization: Option<String>,
            instance: String,
        }
        struct NetworkCache(Arc<Mutex<Observed>>);
        #[tonic::async_trait]
        impl ActionCache for NetworkCache {
            async fn get_action_result(
                &self,
                request: Request<reapi::GetActionResultRequest>,
            ) -> Result<Response<reapi::ActionResult>, Status> {
                let mut observed = self.0.lock().unwrap();
                observed.calls += 1;
                observed.account = request
                    .metadata()
                    .get("x-tuist-account-handle")
                    .and_then(|value| value.to_str().ok())
                    .map(str::to_owned);
                observed.authorization = request
                    .metadata()
                    .get("authorization")
                    .and_then(|value| value.to_str().ok())
                    .map(str::to_owned);
                observed.instance = request.get_ref().instance_name.clone();
                if observed
                    .account
                    .as_deref()
                    .is_some_and(|account| account != "acme")
                {
                    return Err(Status::permission_denied("wrong account"));
                }
                if request
                    .metadata()
                    .get("authorization")
                    .is_some_and(|value| value.to_str().ok() != Some("Bearer accepted"))
                {
                    return Err(Status::unauthenticated("supplied credential rejected"));
                }
                Ok(Response::new(reapi::ActionResult::default()))
            }

            async fn update_action_result(
                &self,
                _: Request<reapi::UpdateActionResultRequest>,
            ) -> Result<Response<reapi::ActionResult>, Status> {
                Err(Status::unimplemented("unused"))
            }
        }

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap();
        let listener = runtime
            .block_on(tokio::net::TcpListener::bind("127.0.0.1:0"))
            .unwrap();
        let addr = listener.local_addr().unwrap();
        let (stop, stopped) = tokio::sync::oneshot::channel();
        let observed = Arc::new(Mutex::new(Observed::default()));
        let service = NetworkCache(observed.clone());
        let server = runtime.spawn(async move {
            tonic::transport::Server::builder()
                .add_service(ActionCacheServer::new(service))
                .serve_with_incoming_shutdown(
                    tonic::transport::server::TcpIncoming::from(listener),
                    async {
                        let _ = stopped.await;
                    },
                )
                .await
                .unwrap();
        });
        for token in [
            None,
            Some("accepted"),
            Some("rejected"),
            Some(""),
            Some("rejected\n"),
            Some("rejected\r"),
            Some("réjected"),
        ] {
            let tokens = Arc::new(TokenProvider {
                cached: Mutex::new(token.map(|value| CachedToken::new(value.to_owned()))),
                refreshing: Mutex::new(RefreshState::default()),
                fetch: None,
            });
            let remote = crate::reapi::Remote::new(
                crate::reapi::RemoteConfig {
                    grpc_url: format!("http://{addr}"),
                    instance: "acme/ios".into(),
                },
                tokens,
            );
            let result = remote.get_action(b"cache-key");
            if token.is_none() || token == Some("accepted") {
                assert!(result.is_ok(), "{token:?}: {:?}", result.err());
            } else {
                assert!(
                    matches!(result, Err(error) if error.contains("supplied credential rejected")),
                    "{token:?}"
                );
            }
        }

        let cli = FakeCli::new();
        let configure = |token: &str, endpoint: &str| {
            std::fs::write(
                cli.0.join("tuist"),
                format!(
                    "#!/bin/sh\nprintf '%s\\n' '{}'\n",
                    serde_json::json!({"token": token, "url": endpoint})
                ),
            )
            .unwrap();
        };
        let old_endpoint = format!("http://{addr}");
        let new_endpoint = format!("http://{addr}/new");
        let provider = cli.provider().for_instance("acme/ios");
        configure("accepted", &old_endpoint);
        let old = crate::reapi::Remote::new(
            crate::reapi::RemoteConfig {
                grpc_url: old_endpoint,
                instance: "ios".into(),
            },
            provider.clone(),
        );
        assert!(old.get_action(b"signed").is_ok());
        {
            let observed = observed.lock().unwrap();
            assert_eq!(observed.account.as_deref(), Some("acme"));
            assert_eq!(observed.authorization.as_deref(), Some("Bearer accepted"));
            assert_eq!(observed.instance, "ios");
        }

        configure("", &new_endpoint);
        provider.cached.lock().unwrap().as_mut().unwrap().expiry = Some(UNIX_EPOCH);
        provider.refresh_if_expiring(Duration::ZERO);
        let calls = observed.lock().unwrap().calls;
        assert!(old
            .get_action(b"must-not-leak")
            .err()
            .expect("the old destination must be rejected")
            .contains("endpoint changed"));
        assert_eq!(
            observed.lock().unwrap().calls,
            calls,
            "no request reaches the old endpoint"
        );
        let new = crate::reapi::Remote::new(
            crate::reapi::RemoteConfig {
                grpc_url: format!("{new_endpoint}/"),
                instance: "ios".into(),
            },
            provider,
        );
        assert!(new.get_action(b"unsigned").is_ok());
        {
            let observed = observed.lock().unwrap();
            assert_eq!(observed.account.as_deref(), Some("acme"));
            assert_eq!(observed.authorization, None);
            assert_eq!(observed.instance, "ios");
        }
        let wrong_account = crate::reapi::Remote::new(
            crate::reapi::RemoteConfig {
                grpc_url: new_endpoint,
                instance: "ios".into(),
            },
            cli.provider().for_instance("globex/ios"),
        );
        assert!(wrong_account
            .get_action(b"must-not-alias")
            .err()
            .expect("another account must not alias the node account")
            .contains("wrong account"));
        stop.send(()).unwrap();
        runtime.block_on(server).unwrap();
    }

    #[test]
    fn only_successful_network_trusted_configuration_may_omit_credentials() {
        let cli = FakeCli::new();
        let script = cli.0.join("tuist");
        std::fs::write(
            &script,
            "#!/bin/sh\nprintf '{\"token\":\"\",\"url\":\"https://private-cache.example\"}\\n'\n",
        )
        .unwrap();
        let provider = cli.provider().for_instance("acme/one");
        assert_eq!(provider.current(), None);
        std::fs::write(&script, "#!/bin/sh\nexit 1\n").unwrap();
        provider.cached.lock().unwrap().as_mut().unwrap().expiry = Some(UNIX_EPOCH);
        assert_eq!(provider.current().as_deref(), Some(""));
        assert_eq!(provider.current().as_deref(), Some(""));
        let direct = TokenProvider {
            cached: Mutex::new(Some(CachedToken::new(String::new()))),
            refreshing: Mutex::new(RefreshState::default()),
            fetch: None,
        };
        assert_eq!(direct.current().as_deref(), Some(""));
    }

    #[test]
    fn project_tokens_are_isolated_and_concurrent_fetches_coalesce() {
        let cli = FakeCli::new();
        let machine = cli.provider();
        let one = machine.for_instance("acme/one");
        let two = machine.for_instance("acme/two");
        let threads: Vec<_> = (0..8)
            .map(|_| {
                let one = one.clone();
                std::thread::spawn(move || one.current())
            })
            .collect();
        for thread in threads {
            assert_eq!(thread.join().unwrap().as_deref(), Some("acme/one"));
        }
        assert_eq!(two.current().as_deref(), Some("acme/two"));
        assert_eq!(machine.current().as_deref(), Some("machine-bearer"));
        assert_eq!(
            std::fs::read_to_string(cli.0.join("calls")).unwrap(),
            "acme/one\nacme/two\n"
        );
    }

    #[test]
    fn scoped_refresh_uses_the_same_project_and_failure_never_uses_the_machine_bearer() {
        let cli = FakeCli::new();
        let machine = cli.provider();
        let one = machine.for_instance("acme/one");
        *one.cached.lock().unwrap() = Some(CachedToken::new(make_jwt(r#"{"exp":1}"#)));
        one.refresh_if_expiring(Duration::from_secs(20));
        assert_eq!(one.current().as_deref(), Some("acme/one"));
        assert_eq!(
            machine.for_instance("acme/forbidden").current().as_deref(),
            Some("")
        );
        assert_eq!(machine.current().as_deref(), Some("machine-bearer"));
    }

    #[test]
    fn direct_integrations_keep_their_explicit_bearer() {
        let machine = Arc::new(TokenProvider {
            cached: Mutex::new(Some(CachedToken::new("explicit-bearer".into()))),
            refreshing: Mutex::new(RefreshState::default()),
            fetch: None,
        });
        let scoped = machine.for_instance("acme/one");
        assert!(Arc::ptr_eq(&machine, &scoped));
        assert_eq!(scoped.current().as_deref(), Some("explicit-bearer"));
    }

    #[test]
    fn failed_fetches_coalesce_and_back_off_across_requests_and_maintenance() {
        let cli = FakeCli::new();
        std::fs::write(
            cli.0.join("tuist"),
            "#!/bin/sh\nprintf 'call\\n' >> \"$(dirname \"$0\")/calls\"\nsleep 0.05\nexit 1\n",
        )
        .unwrap();
        let provider = cli.provider().for_instance("acme/one");
        let barrier = Arc::new(std::sync::Barrier::new(8));
        let threads: Vec<_> = (0..8)
            .map(|_| {
                let provider = provider.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    provider.current()
                })
            })
            .collect();
        for thread in threads {
            assert_eq!(thread.join().unwrap().as_deref(), Some(""));
        }
        for _ in 0..3 {
            assert_eq!(provider.current().as_deref(), Some(""));
            provider.refresh_if_expiring(Duration::from_secs(20));
        }
        assert_eq!(
            std::fs::read_to_string(cli.0.join("calls"))
                .unwrap()
                .lines()
                .count(),
            1
        );

        for attempt in 1..7 {
            provider.refreshing.lock().unwrap().retry_at =
                Some(Instant::now() - Duration::from_secs(1));
            assert_eq!(provider.current().as_deref(), Some(""));
            let state = provider.refreshing.lock().unwrap();
            let expected = (INITIAL_RETRY_DELAY * (1 << attempt)).min(MAX_RETRY_DELAY);
            let remaining = state.retry_at.unwrap().duration_since(Instant::now());
            assert!(remaining <= expected && remaining > expected - Duration::from_secs(1));
        }
        assert_eq!(
            std::fs::read_to_string(cli.0.join("calls"))
                .unwrap()
                .lines()
                .count(),
            7
        );
    }

    #[test]
    fn successful_retry_resets_backoff_and_failures_are_project_local() {
        let cli = FakeCli::new();
        let machine = cli.provider();
        let failed = machine.for_instance("acme/forbidden");
        let healthy = machine.for_instance("acme/one");
        assert_eq!(failed.current().as_deref(), Some(""));
        assert_eq!(healthy.current().as_deref(), Some("acme/one"));
        let script = std::fs::read_to_string(cli.0.join("tuist")).unwrap();
        std::fs::write(
            cli.0.join("tuist"),
            script.replace("acme/one|acme/two)", "acme/one|acme/two|acme/forbidden)"),
        )
        .unwrap();
        assert_eq!(failed.current().as_deref(), Some(""));
        failed.refreshing.lock().unwrap().retry_at = Some(Instant::now() - Duration::from_secs(1));
        assert_eq!(failed.current().as_deref(), Some("acme/forbidden"));
        let state = failed.refreshing.lock().unwrap();
        assert!(state.retry_at.is_none());
        assert_eq!(state.retry_delay, INITIAL_RETRY_DELAY);
    }

    #[test]
    fn failed_proactive_refresh_keeps_the_cached_token_and_backs_off() {
        let cli = FakeCli::new();
        std::fs::write(
            cli.0.join("tuist"),
            "#!/bin/sh\nprintf 'call\\n' >> \"$(dirname \"$0\")/calls\"\nexit 1\n",
        )
        .unwrap();
        let provider = cli.provider().for_instance("acme/one");
        let expiry = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
            + 60;
        let token = make_jwt(&format!("{{\"exp\":{expiry}}}"));
        *provider.cached.lock().unwrap() = Some(CachedToken::new(token.clone()));
        for _ in 0..8 {
            provider.refresh_if_expiring(Duration::from_secs(120));
            assert_eq!(provider.current(), Some(token.clone()));
        }
        assert_eq!(
            std::fs::read_to_string(cli.0.join("calls"))
                .unwrap()
                .lines()
                .count(),
            1
        );
    }

    fn make_jwt(payload_json: &str) -> String {
        let header = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(b"{\"alg\":\"none\"}");
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
