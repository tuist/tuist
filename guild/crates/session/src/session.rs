use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tuist_credentials::{Credentials, CredentialsStore, Directories, RefreshLock};
use tuist_jwt::Claims;
use tuist_oauth::{
    LoopbackCallback, OAuthClient, Pkce, Provider, RefreshGrant, Tokens, authorization_url,
    default_client_id,
};
use url::Url;

use crate::{Accounts, AuthorizationServer, Error};

/// Tokens closer than this to expiry are refreshed, as in the Swift clients.
const REFRESH_MARGIN_SECONDS: i64 = 30;
/// How long the browser has to complete a sign-in.
const SIGN_IN_TIMEOUT: Duration = Duration::from_secs(10 * 60);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Account {
    pub id: String,
    pub handle: Option<String>,
    pub email: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    SignedOut,
    /// Credentials exist but the server refused them; sign in again.
    Rejected,
    SignedIn(Account),
}

/// A browser sign-in waiting for its redirect.
pub struct PendingSignIn {
    callback: LoopbackCallback,
    redirect_uri: String,
    client_id: String,
    pkce: Pkce,
    url: Url,
}

impl PendingSignIn {
    pub fn url(&self) -> &Url {
        &self.url
    }
}

/// The session for one server, shared with every Tuist client on the machine.
pub struct Session<S = OAuthClient> {
    server: Url,
    store: CredentialsStore,
    state_directory: PathBuf,
    authorization: S,
    expected_identity: Option<String>,
    pub(crate) accounts: Option<Accounts>,
}

impl Session<OAuthClient> {
    /// The server from `TUIST_URL`, or Tuist-hosted, with the shared credential locations.
    pub fn from_env() -> Result<Self, Error> {
        let server = std::env::var("TUIST_URL").unwrap_or_else(|_| "https://tuist.dev".into());
        let server = Url::parse(&server).map_err(|_| Error::InvalidServerUrl(server))?;
        Ok(Self::new(
            server,
            &Directories::from_env(),
            OAuthClient::new(),
        ))
    }
}

impl<S: AuthorizationServer> Session<S> {
    pub fn new(server: Url, directories: &Directories, authorization: S) -> Self {
        Self {
            server,
            store: CredentialsStore::new(&directories.config),
            state_directory: directories.state.clone(),
            authorization,
            expected_identity: None,
            accounts: None,
        }
    }

    pub(crate) fn bind_identity(&mut self, identity: String) {
        self.expected_identity = Some(identity);
    }

    pub(crate) fn expected_identity(&self) -> Option<&str> {
        self.expected_identity.as_deref()
    }

    pub(crate) fn check_identity(&self, credentials: &Credentials) -> Result<(), Error> {
        if let Some(expected) = &self.expected_identity
            && account(credentials)?.id != *expected
        {
            return Err(Error::IdentityChanged);
        }
        Ok(())
    }

    pub fn server(&self) -> &Url {
        &self.server
    }

    /// Reads who is signed in without refreshing or contacting the server.
    pub fn status(&self) -> Result<Status, Error> {
        let _locks = self.credential_locks()?;
        let credentials = self.store.read(&self.server)?;
        if let Some(credentials) = &credentials {
            self.check_identity(credentials)?;
        }
        match credentials {
            None => Ok(Status::SignedOut),
            Some(credentials) if credentials.is_rejected() => Ok(Status::Rejected),
            Some(credentials) => Ok(Status::SignedIn(account(&credentials)?)),
        }
    }

    /// Returns an access token, refreshing it first when it is about to expire.
    pub fn access_token(&self) -> Result<String, Error> {
        let _locks = self.credential_locks()?;
        self.refresh_locked()
    }

    /// Prepares a browser sign-in: listens on a loopback port and registers a
    /// public client for it. Open [`PendingSignIn::url`], then call
    /// [`Session::complete_sign_in`].
    pub fn begin_sign_in(&self, provider: Provider) -> Result<PendingSignIn, Error> {
        let callback = LoopbackCallback::bind()?;
        let redirect_uri = callback.redirect_uri();
        let client_id = self.authorization.register(&self.server, &redirect_uri)?;
        let pkce = Pkce::generate();
        let url = authorization_url(
            &self.server,
            provider,
            &client_id,
            &redirect_uri,
            &pkce.challenge,
            &pkce.state,
        );
        Ok(PendingSignIn {
            callback,
            redirect_uri,
            client_id,
            pkce,
            url,
        })
    }

    /// Waits for the browser to return, then stores the new pair with the
    /// client that issued it, so any Tuist client can refresh it.
    pub fn complete_sign_in(
        &self,
        pending: PendingSignIn,
        cancelled: &AtomicBool,
    ) -> Result<Account, Error> {
        let credentials = self.exchange_sign_in(pending, cancelled)?;
        let account = account(&credentials)?;
        let _locks = self.credential_locks()?;
        check_cancelled(cancelled)?;
        self.store.store(&self.server, &credentials)?;
        Ok(account)
    }

    /// Waits and exchanges outside storage locks. Accounts commits the result
    /// separately so it can archive the latest canonical pair under its locks.
    pub(crate) fn exchange_sign_in(
        &self,
        pending: PendingSignIn,
        cancelled: &AtomicBool,
    ) -> Result<Credentials, Error> {
        let code = pending
            .callback
            .wait(&pending.pkce.state, cancelled, SIGN_IN_TIMEOUT)?;
        let tokens = self.authorization.exchange_code(
            &self.server,
            &pending.client_id,
            &code,
            &pending.pkce.verifier,
            &pending.redirect_uri,
        )?;
        let credentials = Credentials {
            access_token: tokens.access_token,
            refresh_token: Some(tokens.refresh_token),
            oauth_client_id: Some(pending.client_id),
            rejected: None,
        };
        account(&credentials)?;
        check_cancelled(cancelled)?;
        Ok(credentials)
    }

    /// Removes the credentials for this server, including legacy aliases.
    pub fn sign_out(&self) -> Result<(), Error> {
        let _locks = self.credential_locks()?;
        if let Some(credentials) = self.store.read(&self.server)? {
            self.check_identity(&credentials)?;
        }
        self.store.delete(&self.server)?;
        Ok(())
    }

    fn read_usable(&self) -> Result<Credentials, Error> {
        let credentials = self.store.read(&self.server)?;
        if let Some(credentials) = &credentials {
            self.check_identity(credentials)?;
        }
        match credentials {
            None => Err(Error::SignedOut),
            Some(credentials) if credentials.is_rejected() => Err(Error::Rejected),
            Some(credentials) => Ok(credentials),
        }
    }

    /// Keep ownership stable through reads, refresh requests and their writes.
    /// Registry-before-host ordering matches Accounts, preventing deadlocks.
    fn credential_locks(&self) -> Result<(Option<RefreshLock>, RefreshLock), Error> {
        let registry = self
            .accounts
            .as_ref()
            .map(Accounts::registry_lock)
            .transpose()?;
        let host = RefreshLock::acquire(&self.lock_path()?)?;
        if let Some(accounts) = &self.accounts {
            accounts.check_server(&self.server)?;
        }
        Ok((registry, host))
    }

    fn lock_path(&self) -> Result<PathBuf, Error> {
        Ok(RefreshLock::path(
            &self.state_directory,
            &self.store.path(&self.server)?,
        ))
    }

    /// Runs while holding the refresh lock. A peer may have refreshed while we
    /// waited, so the stored credentials are read again before spending them.
    fn refresh_locked(&self) -> Result<String, Error> {
        let credentials = self.read_usable()?;
        if !needs_refresh(&credentials)? {
            return Ok(credentials.access_token);
        }
        let Some(grant) = grant(&credentials)? else {
            // Account tokens without an account refresh token cannot be renewed;
            // the server decides whether the current one is still accepted.
            return Ok(credentials.access_token);
        };
        let spent = grant.refresh_token().to_string();

        match self.authorization.refresh(&self.server, grant.as_oauth()) {
            Ok(tokens) => self.store_rotation(&credentials, &spent, tokens),
            Err(tuist_oauth::Error::Rejected(_)) => {
                self.mark_rejected_unless_rotated(&spent)?;
                Err(Error::Rejected)
            }
            Err(error) => Err(error.into()),
        }
    }

    /// The server answers a refresh token spent in the last minute with the
    /// pair it first minted, which a peer may already have rotated. Once the
    /// stored pair no longer holds the spent token, the stored pair wins.
    fn store_rotation(
        &self,
        before: &Credentials,
        spent: &str,
        tokens: Tokens,
    ) -> Result<String, Error> {
        let stored = self.store.read(&self.server)?;
        if let Some(stored) = &stored {
            self.check_identity(stored)?;
        } else if self.expected_identity.is_some() {
            return Err(Error::SignedOut);
        }
        if let Some(stored) = stored
            && stored
                .refresh_token
                .as_deref()
                .is_some_and(|refresh| refresh != spent)
            && !stored.is_rejected()
        {
            return Ok(stored.access_token);
        }
        self.store.store(
            &self.server,
            &Credentials {
                access_token: tokens.access_token.clone(),
                refresh_token: Some(tokens.refresh_token),
                oauth_client_id: before.oauth_client_id.clone(),
                rejected: None,
            },
        )?;
        Ok(tokens.access_token)
    }

    /// A refusal only means the session ended when nobody rotated the pair
    /// meanwhile; otherwise the peer's newer credentials are kept.
    fn mark_rejected_unless_rotated(&self, spent: &str) -> Result<(), Error> {
        if let Some(stored) = self.store.read(&self.server)? {
            self.check_identity(&stored)?;
            if stored.refresh_token.as_deref() == Some(spent) {
                self.store.store(
                    &self.server,
                    &Credentials {
                        rejected: Some(true),
                        ..stored
                    },
                )?;
            }
        }
        Ok(())
    }
}

enum Grant {
    OAuth {
        refresh_token: String,
        client_id: String,
    },
    Legacy {
        refresh_token: String,
    },
}

impl Grant {
    fn refresh_token(&self) -> &str {
        match self {
            Self::OAuth { refresh_token, .. } | Self::Legacy { refresh_token } => refresh_token,
        }
    }

    fn as_oauth(&self) -> RefreshGrant<'_> {
        match self {
            Self::OAuth {
                refresh_token,
                client_id,
            } => RefreshGrant::OAuth {
                refresh_token,
                client_id,
            },
            Self::Legacy { refresh_token } => RefreshGrant::Legacy { refresh_token },
        }
    }
}

/// `fetchTokenFromStore` and `refreshTokens`: the refresh token's type picks
/// the endpoint, and OAuth refreshes present the client that issued the pair.
fn grant(credentials: &Credentials) -> Result<Option<Grant>, Error> {
    let access = Claims::parse(&credentials.access_token).map_err(|_| Error::InvalidCredentials)?;
    let refresh = credentials
        .refresh_token
        .as_deref()
        .map(|token| (token, Claims::parse(token)));
    match refresh {
        Some((token, Ok(claims))) if claims.is_account_token() => Ok(Some(Grant::OAuth {
            refresh_token: token.to_string(),
            client_id: credentials
                .oauth_client_id
                .clone()
                .unwrap_or_else(default_client_id),
        })),
        _ if access.is_account_token() => Ok(None),
        Some((token, Ok(_))) => Ok(Some(Grant::Legacy {
            refresh_token: token.to_string(),
        })),
        _ => Err(Error::InvalidCredentials),
    }
}

fn needs_refresh(credentials: &Credentials) -> Result<bool, Error> {
    let claims = Claims::parse(&credentials.access_token).map_err(|_| Error::InvalidCredentials)?;
    Ok(claims.exp - now() < REFRESH_MARGIN_SECONDS)
}

pub(crate) fn check_cancelled(cancelled: &AtomicBool) -> Result<(), Error> {
    if cancelled.load(std::sync::atomic::Ordering::Acquire) {
        return Err(tuist_oauth::Error::Cancelled.into());
    }
    Ok(())
}

pub(crate) fn account(credentials: &Credentials) -> Result<Account, Error> {
    let claims = Claims::parse(&credentials.access_token).map_err(|_| Error::InvalidCredentials)?;
    Ok(Account {
        id: claims.identity().ok_or(Error::InvalidCredentials)?,
        handle: claims.preferred_username,
        email: claims.email,
    })
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use base64::Engine;
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;

    use super::*;

    fn jwt(kind: &str, expires_in: i64, id: &str) -> String {
        let payload = format!(
            r#"{{"exp":{},"type":"{kind}","email":"ana@tuist.dev","preferred_username":"ana","jti":"{id}"}}"#,
            now() + expires_in
        );
        format!("e30.{}.", URL_SAFE_NO_PAD.encode(payload))
    }

    /// Records grants and runs `on_refresh` to simulate a peer process writing
    /// the shared store while the request is in flight.
    #[derive(Default)]
    struct FakeServer {
        grants: Mutex<Vec<String>>,
        response: Mutex<Option<Result<Tokens, tuist_oauth::Error>>>,
        on_refresh: Mutex<Option<Box<dyn FnOnce() + Send>>>,
    }

    impl AuthorizationServer for FakeServer {
        fn register(&self, _: &Url, _: &str) -> Result<String, tuist_oauth::Error> {
            unreachable!()
        }

        fn exchange_code(
            &self,
            _: &Url,
            _: &str,
            _: &str,
            _: &str,
            _: &str,
        ) -> Result<Tokens, tuist_oauth::Error> {
            unreachable!()
        }

        fn refresh(&self, _: &Url, grant: RefreshGrant<'_>) -> Result<Tokens, tuist_oauth::Error> {
            self.grants.lock().unwrap().push(match grant {
                RefreshGrant::OAuth {
                    refresh_token,
                    client_id,
                } => format!("oauth {refresh_token} {client_id}"),
                RefreshGrant::Legacy { refresh_token } => format!("legacy {refresh_token}"),
            });
            if let Some(peer) = self.on_refresh.lock().unwrap().take() {
                peer();
            }
            self.response
                .lock()
                .unwrap()
                .take()
                .expect("a refresh response was configured")
        }
    }

    struct Fixture {
        session: Session<FakeServer>,
        store: CredentialsStore,
        server: Url,
    }

    fn fixture(name: &str, credentials: Credentials) -> Fixture {
        let root =
            std::env::temp_dir().join(format!("tuist-session-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let directories = Directories {
            config: root.join("config"),
            state: root.join("state"),
            data: root.join("data"),
        };
        let server = Url::parse("https://tuist.dev").unwrap();
        let store = CredentialsStore::new(&directories.config);
        store.store(&server, &credentials).unwrap();
        Fixture {
            session: Session::new(server.clone(), &directories, FakeServer::default()),
            store,
            server,
        }
    }

    fn expired_oauth_credentials() -> (Credentials, String) {
        let refresh = jwt("account", 3600, "r1");
        let credentials = Credentials {
            access_token: jwt("account", 10, "a1"),
            refresh_token: Some(refresh.clone()),
            oauth_client_id: Some("desktop-client".into()),
            rejected: None,
        };
        (credentials, refresh)
    }

    #[test]
    fn another_profile_with_the_same_identity_is_never_read_refreshed_or_deleted() {
        let root =
            std::env::temp_dir().join(format!("tuist-session-origin-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let directories = Directories {
            config: root.join("config"),
            state: root.join("state"),
            data: root.join("data"),
        };
        let b = crate::validate_server("https://shared.host:8443/base-b").unwrap();
        let c = crate::validate_server("https://shared.host:9443/base-c").unwrap();
        let accounts = Accounts::new(directories.clone());
        let store = CredentialsStore::new(&directories.config);
        let mut retained = Session::new(b, &directories, FakeServer::default());
        retained.bind_identity("username:ana".into());
        retained.accounts = Some(accounts.clone());
        // Establish C as the canonical owner independently of the retained B session.
        let mut credentials = expired_oauth_credentials().0;
        store.store(&c, &credentials).unwrap();
        accounts.remember(&c).unwrap();
        *retained.authorization.response.lock().unwrap() =
            Some(Err(tuist_oauth::Error::Rejected("invalid_grant".into())));
        for expiry in [3600, 10] {
            credentials.access_token = jwt("account", expiry, "issuer-c");
            store.store(&c, &credentials).unwrap();
            let path = store.path(&c).unwrap();
            let before = std::fs::read(&path).unwrap();
            assert!(matches!(
                retained.access_token(),
                Err(Error::IdentityChanged)
            ));
            assert!(matches!(retained.status(), Err(Error::IdentityChanged)));
            assert!(matches!(retained.sign_out(), Err(Error::IdentityChanged)));
            assert!(retained.authorization.grants.lock().unwrap().is_empty());
            assert_eq!(std::fs::read(&path).unwrap(), before);
        }
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_valid_token_is_returned_without_contacting_the_server() {
        let mut credentials = expired_oauth_credentials().0;
        credentials.access_token = jwt("account", 3600, "a1");
        let fixture = fixture("valid", credentials.clone());
        assert_eq!(
            fixture.session.access_token().unwrap(),
            credentials.access_token
        );
        assert!(
            fixture
                .session
                .authorization
                .grants
                .lock()
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn rotation_spends_the_pair_with_its_issuing_client_and_keeps_that_client() {
        let (credentials, refresh) = expired_oauth_credentials();
        let fixture = fixture("rotate", credentials);
        let new = Tokens {
            access_token: jwt("account", 3600, "a2"),
            refresh_token: jwt("account", 7200, "r2"),
        };
        *fixture.session.authorization.response.lock().unwrap() = Some(Ok(new.clone()));

        assert_eq!(fixture.session.access_token().unwrap(), new.access_token);
        assert_eq!(
            *fixture.session.authorization.grants.lock().unwrap(),
            vec![format!("oauth {refresh} desktop-client")]
        );
        let stored = fixture.store.read(&fixture.server).unwrap().unwrap();
        assert_eq!(stored.refresh_token, Some(new.refresh_token));
        assert_eq!(stored.oauth_client_id.as_deref(), Some("desktop-client"));
    }

    #[test]
    fn a_peer_rotation_during_the_request_wins_over_the_replayed_pair() {
        let (credentials, _) = expired_oauth_credentials();
        let fixture = fixture("peer", credentials.clone());
        let peer = Credentials {
            access_token: jwt("account", 3600, "peer-a"),
            refresh_token: Some(jwt("account", 7200, "peer-r")),
            ..credentials
        };
        let (store, server, written) =
            (fixture.store.clone(), fixture.server.clone(), peer.clone());
        *fixture.session.authorization.on_refresh.lock().unwrap() =
            Some(Box::new(move || store.store(&server, &written).unwrap()));
        *fixture.session.authorization.response.lock().unwrap() = Some(Ok(Tokens {
            access_token: jwt("account", 3600, "replayed-a"),
            refresh_token: jwt("account", 7200, "replayed-r"),
        }));

        assert_eq!(fixture.session.access_token().unwrap(), peer.access_token);
        assert_eq!(fixture.store.read(&fixture.server).unwrap(), Some(peer));
    }

    #[test]
    fn a_refused_refresh_marks_the_session_rejected_unless_a_peer_rotated_it() {
        let (credentials, _) = expired_oauth_credentials();
        let fixture = fixture("rejected", credentials.clone());
        *fixture.session.authorization.response.lock().unwrap() =
            Some(Err(tuist_oauth::Error::Rejected("invalid_grant".into())));
        assert!(matches!(
            fixture.session.access_token(),
            Err(Error::Rejected)
        ));
        assert_eq!(fixture.session.status().unwrap(), Status::Rejected);

        let fixture = fixture_with_peer_then_rejection(credentials);
        assert!(matches!(
            fixture.session.access_token(),
            Err(Error::Rejected)
        ));
        assert!(
            !fixture
                .store
                .read(&fixture.server)
                .unwrap()
                .unwrap()
                .is_rejected()
        );
    }

    fn fixture_with_peer_then_rejection(credentials: Credentials) -> Fixture {
        let fixture = fixture("rejected-peer", credentials.clone());
        let peer = Credentials {
            refresh_token: Some(jwt("account", 7200, "peer-r")),
            ..credentials
        };
        let (store, server) = (fixture.store.clone(), fixture.server.clone());
        *fixture.session.authorization.on_refresh.lock().unwrap() =
            Some(Box::new(move || store.store(&server, &peer).unwrap()));
        *fixture.session.authorization.response.lock().unwrap() =
            Some(Err(tuist_oauth::Error::Rejected("invalid_grant".into())));
        fixture
    }

    #[test]
    fn transient_failures_keep_the_credentials() {
        let (credentials, _) = expired_oauth_credentials();
        let fixture = fixture("transient", credentials.clone());
        *fixture.session.authorization.response.lock().unwrap() =
            Some(Err(tuist_oauth::Error::Unavailable(503)));
        assert!(matches!(
            fixture.session.access_token(),
            Err(Error::Server(_))
        ));
        assert_eq!(
            fixture.store.read(&fixture.server).unwrap(),
            Some(credentials)
        );
    }

    #[test]
    fn cli_user_tokens_refresh_through_the_legacy_endpoint() {
        let refresh = jwt("refresh", 3600, "r1");
        let credentials = Credentials {
            access_token: jwt("access", 10, "a1"),
            refresh_token: Some(refresh.clone()),
            oauth_client_id: None,
            rejected: None,
        };
        let fixture = fixture("legacy", credentials);
        *fixture.session.authorization.response.lock().unwrap() = Some(Ok(Tokens {
            access_token: jwt("access", 3600, "a2"),
            refresh_token: jwt("refresh", 7200, "r2"),
        }));
        fixture.session.access_token().unwrap();
        assert_eq!(
            *fixture.session.authorization.grants.lock().unwrap(),
            vec![format!("legacy {refresh}")]
        );
    }

    #[test]
    fn a_bound_refresh_never_returns_or_overwrites_another_identity() {
        let (credentials, _) = expired_oauth_credentials();
        let mut fixture = fixture("identity-during-refresh", credentials.clone());
        fixture.session.bind_identity("username:ana".into());
        let payload =
            r#"{"exp":4102444800,"sub":"different","preferred_username":"ana","type":"account"}"#;
        let other = Credentials {
            access_token: format!("e30.{}.", URL_SAFE_NO_PAD.encode(payload)),
            ..credentials
        };
        let (store, server, written) =
            (fixture.store.clone(), fixture.server.clone(), other.clone());
        *fixture.session.authorization.on_refresh.lock().unwrap() =
            Some(Box::new(move || store.store(&server, &written).unwrap()));
        *fixture.session.authorization.response.lock().unwrap() = Some(Ok(Tokens {
            access_token: jwt("account", 3600, "response-a"),
            refresh_token: jwt("account", 7200, "response-r"),
        }));
        assert!(matches!(
            fixture.session.access_token(),
            Err(Error::IdentityChanged)
        ));
        assert_eq!(fixture.store.read(&fixture.server).unwrap(), Some(other));
    }
}
