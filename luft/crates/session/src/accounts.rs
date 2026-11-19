//! Desktop account snapshots augment, never replace, the shared active file.
//! Always lock the registry first, then deduplicated host refresh locks sorted
//! by canonical path. Account-backed sessions use the same ordering for refresh.
//!
//! The CLI contract identifies active credentials by host, not port/base path,
//! and carries no full issuer URL. The registry tracks the last authenticated
//! or selected full server for each host, independently of the current selection.
//! Out-of-band CLI changes to the same subject on another base cannot be
//! distinguished; separate canonical files would break Swift interoperability.
use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;

use serde::{Deserialize, Serialize};
use tuist_credentials::{
    Credentials, CredentialsStore, Directories, RefreshLock, StoreError, atomic_write_private,
};
use tuist_oauth::OAuthClient;
use url::Url;

use crate::{
    Error, PendingSignIn, Session,
    session::{account, check_cancelled},
};

/// Token-free account metadata safe to hand to the UI.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SavedAccount {
    pub server: String,
    pub id: String,
    pub handle: Option<String>,
    pub email: Option<String>,
    pub rejected: bool,
}

#[derive(Clone, Debug)]
pub struct Accounts {
    directories: Directories,
    store: CredentialsStore,
}

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Registry {
    selected_server: Option<String>,
    accounts: Vec<Record>,
    /// Full origin owning each host-only canonical file, independently of selection.
    #[serde(default)]
    canonical_servers: BTreeMap<String, String>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    server: String,
    credentials: Credentials,
}

impl Record {
    fn metadata(&self) -> Result<SavedAccount, Error> {
        let account = account(&self.credentials)?;
        Ok(SavedAccount {
            server: self.server.clone(),
            id: account.id,
            handle: account.handle,
            email: account.email,
            rejected: self.credentials.is_rejected(),
        })
    }
}

impl Accounts {
    pub fn new(directories: Directories) -> Self {
        Self {
            store: CredentialsStore::new(&directories.config),
            directories,
        }
    }

    pub fn session_from_env(&self) -> Result<Session, Error> {
        self.session_with_override(std::env::var("TUIST_URL").ok().as_deref())
    }

    fn session_with_override(&self, explicit: Option<&str>) -> Result<Session, Error> {
        let _registry_lock = self.registry_lock()?;
        let registry = self.read()?;
        let server = parse_server(
            explicit
                .or(registry.selected_server.as_deref())
                .unwrap_or("https://tuist.dev"),
            true,
        )?;
        let _locks = self.host_locks(&[&server])?;
        if self.store.read(&server)?.is_some()
            && self.canonical_server(&registry, &server)?.as_ref() != Some(&server)
        {
            return Err(Error::IdentityChanged);
        }
        self.bound_session(server)
    }

    pub fn list(&self, current_server: &Url) -> Result<Vec<SavedAccount>, Error> {
        let server = parse_server(current_server.as_str(), true)?;
        let _registry_lock = self.registry_lock()?;
        let _locks = self.host_locks(&[&server])?;
        let mut registry = self.read()?;
        self.capture(&mut registry, &server)?;
        self.write(&registry)?;
        registry.accounts.iter().map(Record::metadata).collect()
    }

    pub fn remember(&self, server: &Url) -> Result<(), Error> {
        self.save_current(server, true)
    }

    pub fn preserve(&self, server: &Url) -> Result<(), Error> {
        self.save_current(server, false)
    }

    /// Prepare explicit browser authentication without changing either active
    /// credentials or the persisted selection. Dropping this session is safe.
    pub fn connect(&self, current_server: &Url, server: Url) -> Result<Session, Error> {
        let current = parse_server(current_server.as_str(), true)?;
        let server = parse_server(server.as_str(), true)?;
        let _registry_lock = self.registry_lock()?;
        let _locks = self.host_locks(&[&current, &server])?;
        let mut registry = self.read()?;
        self.capture(&mut registry, &current)?;
        self.capture(&mut registry, &server)?;
        self.write(&registry)?;
        Ok(Session::new(server, &self.directories, OAuthClient::new()))
    }

    /// Bind an already authenticated full-URL profile without consulting the
    /// startup-only TUIST_URL override. Unknown profiles must connect first;
    /// selecting an inactive known profile must go through switch.
    pub fn current_session(&self, server: Url) -> Result<Session, Error> {
        let server = parse_server(server.as_str(), true)?;
        let _registry_lock = self.registry_lock()?;
        let _locks = self.host_locks(&[&server])?;
        let registry = self.read()?;
        if let Some(credentials) = self.store.read(&server)? {
            if self.canonical_server(&registry, &server)?.as_ref() != Some(&server) {
                return Err(Error::IdentityChanged);
            }
            let identity = account(&credentials)?.id;
            if !registry.accounts.iter().any(|record| {
                record.server == server.as_str()
                    && account(&record.credentials).is_ok_and(|a| a.id == identity)
            }) {
                return Err(Error::IdentityChanged);
            }
        }
        self.bound_session(server)
    }

    /// No storage locks are held while waiting for the browser or server.
    pub fn complete_sign_in(
        &self,
        session: &Session,
        pending: PendingSignIn,
        cancelled: &AtomicBool,
    ) -> Result<Session, Error> {
        let credentials = session.exchange_sign_in(pending, cancelled)?;
        self.commit_sign_in(session, credentials, cancelled)
    }

    fn commit_sign_in(
        &self,
        session: &Session,
        credentials: Credentials,
        cancelled: &AtomicBool,
    ) -> Result<Session, Error> {
        let server = parse_server(session.server().as_str(), true)?;
        account(&credentials)?;
        let _registry_lock = self.registry_lock()?;
        let _locks = self.host_locks(&[&server])?;
        check_cancelled(cancelled)?;
        let mut registry = self.read()?;
        // A CLI may have rotated or changed the target account during the
        // browser flow. Preserve the pair observed now, not ten minutes ago.
        self.capture(&mut registry, &server)?;
        self.write(&registry)?;
        check_cancelled(cancelled)?;
        self.store.store(&server, &credentials)?;
        registry
            .canonical_servers
            .insert(server.host_str().unwrap().to_owned(), server.to_string());
        self.capture(&mut registry, &server)?;
        registry.selected_server = Some(server.to_string());
        self.write(&registry)?;
        self.bound_session(server)
    }

    fn save_current(&self, server: &Url, select: bool) -> Result<(), Error> {
        let server = parse_server(server.as_str(), true)?;
        let _registry_lock = self.registry_lock()?;
        let _locks = self.host_locks(&[&server])?;
        let mut registry = self.read()?;
        self.capture(&mut registry, &server)?;
        if select {
            registry.selected_server = Some(server.to_string());
        }
        self.write(&registry)
    }

    pub fn switch(&self, current_server: &Url, target: &SavedAccount) -> Result<Session, Error> {
        let current = parse_server(current_server.as_str(), true)?;
        let server = parse_server(&target.server, true)?;
        let _registry_lock = self.registry_lock()?;
        let _locks = self.host_locks(&[&current, &server])?;
        let mut registry = self.read()?;
        self.capture(&mut registry, &current)?;
        // Archive the actual target-host owner, which may be a third profile
        // on a different port/base path, even when its account ID is identical.
        self.capture(&mut registry, &server)?;
        let record = registry
            .accounts
            .iter()
            .find(|record| {
                record.server == server.as_str()
                    && account(&record.credentials).is_ok_and(|a| a.id == target.id)
            })
            .ok_or(Error::SignedOut)?;
        // Save both fresh snapshots before overwriting a canonical pair.
        self.write(&registry)?;
        self.store.store(&server, &record.credentials)?;
        registry
            .canonical_servers
            .insert(server.host_str().unwrap().to_owned(), server.to_string());
        registry.selected_server = Some(server.to_string());
        self.write(&registry)?;
        self.bound_session(server)
    }

    pub fn sign_out(&self, session: &Session) -> Result<(), Error> {
        let server = session.server();
        let _registry_lock = self.registry_lock()?;
        let _locks = self.host_locks(&[server])?;
        let mut registry = self.read()?;
        let credentials = self.store.read(server)?;
        let identity = if let Some(credentials) = &credentials {
            if self.canonical_server(&registry, server)?.as_ref() != Some(server) {
                return Err(Error::IdentityChanged);
            }
            session.check_identity(credentials)?;
            Some(account(credentials)?.id)
        } else {
            session.expected_identity().map(str::to_owned)
        };
        if let Some(identity) = identity {
            // The shared active file is host-scoped, but separately authenticated
            // desktop profiles on other ports/base paths remain independent.
            registry.accounts.retain(|record| {
                !(record.server == server.as_str()
                    && account(&record.credentials).is_ok_and(|a| a.id == identity))
            });
        }
        registry
            .canonical_servers
            .remove(server.host_str().unwrap());
        self.write(&registry)?;
        self.store.delete(server)?;
        Ok(())
    }

    fn bound_session(&self, server: Url) -> Result<Session, Error> {
        let credentials = self.store.read(&server)?;
        let mut session = Session::new(server, &self.directories, OAuthClient::new());
        if let Some(credentials) = credentials {
            session.bind_identity(account(&credentials)?.id);
        }
        session.accounts = Some(self.clone());
        Ok(session)
    }

    /// Caller holds the registry and host locks until credential use completes.
    pub(crate) fn check_server(&self, server: &Url) -> Result<(), Error> {
        if self.store.read(server)?.is_some()
            && self.canonical_server(&self.read()?, server)?.as_ref() != Some(server)
        {
            return Err(Error::IdentityChanged);
        }
        Ok(())
    }

    fn capture(&self, registry: &mut Registry, server: &Url) -> Result<(), Error> {
        let Some(server) = self.canonical_server(registry, server)? else {
            // An older registry can have ambiguous ownership. Keep snapshots
            // intact until explicit authentication or selection establishes it.
            return Ok(());
        };
        let Some(credentials) = self.store.read(&server)? else {
            return Ok(());
        };
        registry
            .canonical_servers
            .insert(server.host_str().unwrap().to_owned(), server.to_string());
        let identity = account(&credentials)?.id;
        if let Some(record) = registry.accounts.iter_mut().find(|record| {
            record.server == server.as_str()
                && account(&record.credentials).is_ok_and(|a| a.id == identity)
        }) {
            record.credentials = credentials;
        } else {
            registry.accounts.push(Record {
                server: server.to_string(),
                credentials,
            });
        }
        Ok(())
    }

    fn canonical_server(&self, registry: &Registry, server: &Url) -> Result<Option<Url>, Error> {
        if let Some(owner) = registry.canonical_servers.get(server.host_str().unwrap()) {
            return Ok(Some(parse_server(owner, true)?));
        }
        // Import old registries without guessing from an account ID shared by
        // independent deployments. Exact credential matches are useful only
        // when they identify one full URL; rotation is safe for a sole profile.
        let path = self.store.path(server)?;
        let credentials = self.store.read(server)?;
        let mut servers = Vec::new();
        let mut matching = Vec::new();
        for record in &registry.accounts {
            let origin = parse_server(&record.server, true)?;
            if self.store.path(&origin)? == path {
                if credentials.as_ref() == Some(&record.credentials) && !matching.contains(&origin)
                {
                    matching.push(origin.clone());
                }
                if !servers.contains(&origin) {
                    servers.push(origin);
                }
            }
        }
        Ok(match servers.len() {
            0 => Some(server.clone()),
            1 => servers.pop(),
            _ if matching.len() == 1 => matching.pop(),
            _ => None,
        })
    }

    fn path(&self) -> PathBuf {
        self.directories.data.join("desktop/accounts.json")
    }

    pub(crate) fn registry_lock(&self) -> Result<RefreshLock, Error> {
        Ok(RefreshLock::acquire(&self.path().with_extension("lock"))?)
    }

    fn host_locks(&self, servers: &[&Url]) -> Result<Vec<RefreshLock>, Error> {
        let mut paths = servers
            .iter()
            .map(|server| self.store.path(server))
            .collect::<Result<Vec<_>, _>>()?;
        paths.sort();
        paths.dedup();
        paths
            .iter()
            .map(|path| {
                RefreshLock::acquire(&RefreshLock::path(&self.directories.state, path))
                    .map_err(Error::from)
            })
            .collect()
    }

    fn read(&self) -> Result<Registry, Error> {
        let path = self.path();
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Registry::default()),
            Err(error) => return Err(StoreError::Io(error).into()),
        };
        let registry: Registry =
            serde_json::from_slice(&bytes).map_err(|_| StoreError::Corrupt(path.clone()))?;
        // Validate the entire file before touching canonical credentials.
        if let Some(server) = &registry.selected_server {
            parse_server(server, true)?;
        }
        for record in &registry.accounts {
            if parse_server(&record.server, true)?.as_str() != record.server {
                return Err(StoreError::Corrupt(path).into());
            }
            record.metadata()?;
        }
        for (host, server) in &registry.canonical_servers {
            let origin = parse_server(server, true)?;
            if origin.as_str() != server || origin.host_str() != Some(host.as_str()) {
                return Err(StoreError::Corrupt(path).into());
            }
        }
        Ok(registry)
    }

    fn write(&self, registry: &Registry) -> Result<(), Error> {
        let bytes = serde_json::to_vec(registry)
            .map_err(io::Error::other)
            .map_err(StoreError::Io)?;
        atomic_write_private(&self.path(), &bytes).map_err(StoreError::Io)?;
        Ok(())
    }
}

/// Validates the HTTPS-only user entry contract before URL parsing can silently
/// discard whitespace, backslashes or empty userinfo.
pub fn validate_server(input: &str) -> Result<Url, Error> {
    parse_server(input, false)
}

fn parse_server(input: &str, allow_loopback: bool) -> Result<Url, Error> {
    let invalid = || Error::InvalidServerUrl(input.to_string());
    let value = input.trim();
    if value
        .chars()
        .any(|c| c.is_whitespace() || c.is_control() || c == '\\')
    {
        return Err(invalid());
    }
    let authority = value
        .split_once("://")
        .ok_or_else(invalid)?
        .1
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default();
    if authority.is_empty() || authority.contains('@') {
        return Err(invalid());
    }
    let mut url = Url::parse(value).map_err(|_| invalid())?;
    let loopback = url
        .host_str()
        .is_some_and(|host| host.eq_ignore_ascii_case("localhost"))
        || url.host().is_some_and(|host| match host {
            url::Host::Ipv4(ip) => ip.is_loopback(),
            url::Host::Ipv6(ip) => ip.is_loopback(),
            _ => false,
        });
    if !(url.scheme() == "https" || (allow_loopback && url.scheme() == "http" && loopback))
        || url.host_str().is_none()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.port() == Some(0)
    {
        return Err(invalid());
    }
    if let Some(url::Host::Domain(host)) = url.host() {
        let host = host.trim_end_matches('.').to_lowercase();
        if host.is_empty() {
            return Err(invalid());
        }
        url.set_host(Some(&host)).map_err(|_| invalid())?;
    }
    let path = url.path().trim_end_matches('/').to_string();
    url.set_path(&path);
    Ok(url)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Status;
    use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};

    struct Fixture {
        root: PathBuf,
        accounts: Accounts,
        server: Url,
    }

    impl Fixture {
        fn new(name: &str) -> Self {
            let root =
                std::env::temp_dir().join(format!("tuist-accounts-{name}-{}", std::process::id()));
            let _ = fs::remove_dir_all(&root);
            let accounts = Accounts::new(Directories {
                config: root.join("config"),
                state: root.join("state"),
                data: root.join("data"),
            });
            Self {
                root,
                accounts,
                server: validate_server("https://tuist.dev").unwrap(),
            }
        }

        fn store(&self, server: &Url, subject: &str, generation: &str) -> Credentials {
            let payload = serde_json::json!({
                "exp": 4102444800_i64, "sub": subject,
                "preferred_username": "same-handle", "email": "same@email.dev",
                "type": "account", "jti": generation,
            });
            let credentials = Credentials {
                access_token: format!("e30.{}.", URL_SAFE_NO_PAD.encode(payload.to_string())),
                refresh_token: Some(format!("refresh-{subject}-{generation}")),
                oauth_client_id: Some(format!("client-{subject}")),
                rejected: None,
            };
            self.accounts.store.store(server, &credentials).unwrap();
            credentials
        }

        fn saved(&self, id: &str) -> SavedAccount {
            self.accounts
                .list(&self.server)
                .unwrap()
                .into_iter()
                .find(|a| a.id == format!("sub:{id}"))
                .unwrap()
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn same_host_accounts_switch_and_survive_restart_with_issuing_clients() {
        let f = Fixture::new("same-host");
        let a = f.store(&f.server, "a", "1");
        f.accounts.remember(&f.server).unwrap();
        let saved_a = f.saved("a");
        let old_session = f.accounts.current_session(f.server.clone()).unwrap();
        let b = f.store(&f.server, "b", "1");
        f.accounts.remember(&f.server).unwrap();
        let saved_b = f.saved("b");
        assert_ne!(saved_a.id, saved_b.id); // Identical handles and emails.
        assert!(matches!(
            old_session.access_token(),
            Err(Error::IdentityChanged)
        ));
        assert!(matches!(
            f.accounts.sign_out(&old_session),
            Err(Error::IdentityChanged)
        ));
        assert!(matches!(
            old_session.sign_out(),
            Err(Error::IdentityChanged)
        ));
        let active_a = f.accounts.switch(&f.server, &saved_a).unwrap();
        assert_eq!(active_a.access_token().unwrap(), a.access_token);
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(a));
        let restarted = Accounts::new(f.accounts.directories.clone());
        assert_eq!(
            restarted.session_with_override(None).unwrap().server(),
            &f.server
        );
        assert_eq!(restarted.list(&f.server).unwrap().len(), 2);
        let active_b = restarted.switch(&f.server, &saved_b).unwrap();
        assert_eq!(active_b.access_token().unwrap(), b.access_token);
        assert_eq!(restarted.store.read(&f.server).unwrap(), Some(b));
    }

    #[test]
    fn repeated_selection_uses_fresh_canonical_tokens_and_rejected_state() {
        let f = Fixture::new("fresh");
        f.store(&f.server, "a", "old");
        f.accounts.remember(&f.server).unwrap();
        let saved = f.saved("a");
        let mut fresh = f.store(&f.server, "a", "rotated");
        fresh.rejected = Some(true);
        f.accounts.store.store(&f.server, &fresh).unwrap();
        let session = f.accounts.switch(&f.server, &saved).unwrap();
        assert_eq!(session.status().unwrap(), Status::Rejected);
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(fresh));
        assert!(f.saved("a").rejected);
    }

    #[test]
    fn other_server_isolation_and_signout_do_not_resurrect_a_snapshot() {
        let f = Fixture::new("signout");
        f.store(&f.server, "a", "1");
        f.accounts.remember(&f.server).unwrap();
        let saved_a = f.saved("a");
        f.store(&f.server, "b", "1");
        f.accounts.remember(&f.server).unwrap();
        let saved_b = f.saved("b");
        let other = validate_server("https://self.host/base").unwrap();
        let other_credentials = f.store(&other, "a", "other");
        f.accounts.preserve(&other).unwrap();
        let same_host_other = validate_server("https://tuist.dev:8443/base").unwrap();
        let login = f
            .accounts
            .connect(&f.server, same_host_other.clone())
            .unwrap();
        let canonical = f.accounts.store.read(&f.server).unwrap().unwrap();
        let authenticated = f.store(&same_host_other, "a", "independent-origin");
        f.accounts.store.store(&f.server, &canonical).unwrap();
        f.accounts
            .commit_sign_in(&login, authenticated, &AtomicBool::new(false))
            .unwrap();
        let active_a = f.accounts.switch(&same_host_other, &saved_a).unwrap();
        f.accounts.sign_out(&active_a).unwrap();
        assert!(f.accounts.store.read(&f.server).unwrap().is_none());
        assert_eq!(
            f.accounts.store.read(&other).unwrap(),
            Some(other_credentials)
        );
        let listed = f.accounts.list(&f.server).unwrap();
        assert_eq!(listed.len(), 3);
        assert!(!listed.contains(&saved_a));
        assert!(
            listed
                .iter()
                .any(|a| a.server == same_host_other.as_str() && a.id == saved_a.id)
        );
        assert!(matches!(
            f.accounts.switch(&f.server, &saved_a),
            Err(Error::SignedOut)
        ));
        let b = f.accounts.switch(&f.server, &saved_b).unwrap();
        assert!(matches!(b.status().unwrap(), Status::SignedIn(a) if a.id == "sub:b"));
        assert_eq!(f.accounts.list(&f.server).unwrap().len(), 3);
    }

    #[test]
    fn preserves_other_target_server_canonical_before_switch() {
        let f = Fixture::new("target-canonical");
        let other = validate_server("https://other.host").unwrap();
        f.store(&other, "a", "archived");
        f.accounts.preserve(&other).unwrap();
        let target = f.accounts.list(&other).unwrap().remove(0);
        let b = f.store(&other, "b", "cli");
        f.store(&f.server, "current", "1");
        f.accounts.switch(&f.server, &target).unwrap();
        let saved_b = f
            .accounts
            .list(&other)
            .unwrap()
            .into_iter()
            .find(|a| a.id == "sub:b")
            .unwrap();
        f.accounts.switch(&other, &saved_b).unwrap();
        assert_eq!(f.accounts.store.read(&other).unwrap(), Some(b));
    }

    #[test]
    fn connect_is_unbound_and_cancel_leaves_both_canonical_files_and_selection_intact() {
        let f = Fixture::new("connect");
        let current = f.store(&f.server, "a", "1");
        f.accounts.remember(&f.server).unwrap();
        let other = validate_server("https://other.host").unwrap();
        let target = f.store(&other, "b", "1");
        let login = f.accounts.connect(&f.server, other.clone()).unwrap();
        assert!(login.expected_identity().is_none());
        drop(login);
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(current));
        assert_eq!(f.accounts.store.read(&other).unwrap(), Some(target));
        assert_eq!(
            f.accounts.session_with_override(None).unwrap().server(),
            &f.server
        );
        f.accounts.remember(&other).unwrap();
        assert_eq!(
            f.accounts
                .session_with_override(Some("https://tuist.dev"))
                .unwrap()
                .server(),
            &f.server
        );
        let workspace = f.accounts.current_session(other.clone()).unwrap();
        assert_eq!(workspace.server(), &other);
        assert_eq!(workspace.expected_identity(), Some("sub:b"));
    }

    #[test]
    fn corrupt_registry_and_canonical_are_errors_not_signed_out() {
        let f = Fixture::new("corrupt");
        let credentials = f.store(&f.server, "a", "1");
        f.accounts.remember(&f.server).unwrap();
        fs::write(f.accounts.path(), "{").unwrap();
        assert!(matches!(
            f.accounts.list(&f.server),
            Err(Error::Store(StoreError::Corrupt(_)))
        ));
        assert!(f.accounts.session_with_override(None).is_err());
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(credentials));
        fs::remove_file(f.accounts.path()).unwrap();
        fs::write(f.accounts.store.path(&f.server).unwrap(), "{").unwrap();
        assert!(matches!(
            f.accounts.list(&f.server),
            Err(Error::Store(StoreError::Corrupt(_)))
        ));
    }

    #[test]
    fn server_validation_matches_the_https_entry_contract() {
        assert_eq!(
            validate_server("  https://TUIST.dev.:443/base///  ")
                .unwrap()
                .as_str(),
            "https://tuist.dev/base"
        );
        for invalid in [
            "",
            "tuist.dev",
            "https:tuist.dev",
            "https:///tuist.dev",
            "http://tuist.dev",
            "http://localhost",
            "https://@tuist.dev",
            "https://user@tuist.dev",
            "https://user:pass@tuist.dev",
            "https://tuist.dev?",
            "https://tuist.dev#",
            "https://tuist.dev:0",
            "https://tuist.dev/a b",
            "https://tuist.dev/a\nb",
            "https://tuist.dev\\path",
            "https://tuist.dev/\u{0}a",
        ] {
            assert!(validate_server(invalid).is_err(), "accepted {invalid:?}");
        }
        for allowed in [
            "http://127.0.0.1:4000",
            "http://[::1]:4000",
            "http://localhost:4000",
        ] {
            assert!(parse_server(allowed, true).is_ok());
        }
        assert!(parse_server("http://remote.host:4000", true).is_err());
    }

    #[test]
    fn different_base_and_port_on_one_host_do_not_clone_current_credentials() {
        let f = Fixture::new("same-host-origins");
        let current = f.store(&f.server, "a", "1");
        f.accounts.remember(&f.server).unwrap();
        f.accounts.preserve(&f.server).unwrap();
        let saved_a = f.saved("a");
        let target = validate_server("https://tuist.dev:8443/custom/").unwrap();
        let login = f.accounts.connect(&f.server, target.clone()).unwrap();
        assert_eq!(f.accounts.read().unwrap().accounts.len(), 1);
        assert!(matches!(
            f.accounts.current_session(target.clone()),
            Err(Error::IdentityChanged)
        ));
        let mut forged = saved_a.clone();
        forged.server = target.to_string();
        assert!(matches!(
            f.accounts.switch(&f.server, &forged),
            Err(Error::SignedOut)
        ));
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(current));

        let fresh_a = f.store(&f.server, "a", "cli-rotated");
        let signed_in_b = f.store(&target, "b", "authenticated-target");
        f.accounts.store.store(&f.server, &fresh_a).unwrap();
        f.accounts
            .commit_sign_in(&login, signed_in_b.clone(), &AtomicBool::new(false))
            .unwrap();
        let registry = f.accounts.read().unwrap();
        assert_eq!(registry.accounts.len(), 2);
        assert!(
            !registry
                .accounts
                .iter()
                .any(|r| r.server == target.as_str()
                    && account(&r.credentials).unwrap().id == "sub:a")
        );
        let saved_b = registry
            .accounts
            .iter()
            .find(|r| r.server == target.as_str())
            .unwrap()
            .metadata()
            .unwrap();
        f.accounts.switch(&target, &saved_a).unwrap();
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(fresh_a));
        f.accounts.switch(&f.server, &saved_b).unwrap();
        assert_eq!(f.accounts.store.read(&target).unwrap(), Some(signed_in_b));
    }

    #[test]
    fn startup_override_never_binds_another_full_origins_credentials() {
        let f = Fixture::new("startup-origin");
        let owner = validate_server("https://shared.host:8443/base-b").unwrap();
        let other = validate_server("https://shared.host:9443/base-c").unwrap();
        let credentials = f.store(&owner, "42", "issuer-b");
        f.accounts.remember(&owner).unwrap();
        let registry = fs::read(f.accounts.path()).unwrap();
        let restarted = Accounts::new(f.accounts.directories.clone());
        assert_eq!(
            restarted
                .session_with_override(None)
                .unwrap()
                .access_token()
                .unwrap(),
            credentials.access_token
        );
        assert!(matches!(
            restarted.session_with_override(Some(other.as_str())),
            Err(Error::IdentityChanged)
        ));
        assert_eq!(restarted.store.read(&owner).unwrap(), Some(credentials));
        assert_eq!(fs::read(restarted.path()).unwrap(), registry);
    }

    #[test]
    fn same_identity_on_shared_host_keeps_origin_across_other_hosts_and_restart() {
        for (connect_first, legacy_registry) in
            [(false, false), (true, false), (true, true), (false, true)]
        {
            let f = Fixture::new(if connect_first {
                "origin-connect"
            } else {
                "origin-switch"
            });
            let b = validate_server("https://shared.host:8443/base-b").unwrap();
            let c = validate_server("https://shared.host:9443/base-c").unwrap();
            f.store(&f.server, "a", "host-a");
            f.accounts.remember(&f.server).unwrap();
            let saved_a = f.saved("a");
            let credentials_b = f.store(&b, "42", "issuer-b");
            f.accounts.remember(&b).unwrap();
            let retained_b = f.accounts.current_session(b.clone()).unwrap();
            let saved_b = f
                .accounts
                .list(&b)
                .unwrap()
                .into_iter()
                .find(|a| a.server == b.as_str())
                .unwrap();
            let login = f.accounts.connect(&b, c.clone()).unwrap();
            let credentials_c = f.store(&c, "42", "issuer-c");
            f.accounts.store.store(&b, &credentials_b).unwrap();
            f.accounts
                .commit_sign_in(&login, credentials_c.clone(), &AtomicBool::new(false))
                .unwrap();
            assert!(matches!(
                retained_b.access_token(),
                Err(Error::IdentityChanged)
            ));
            assert!(matches!(retained_b.status(), Err(Error::IdentityChanged)));
            assert!(matches!(retained_b.sign_out(), Err(Error::IdentityChanged)));
            assert_eq!(
                f.accounts.store.read(&c).unwrap(),
                Some(credentials_c.clone())
            );
            let saved_c = f
                .accounts
                .list(&c)
                .unwrap()
                .into_iter()
                .find(|a| a.server == c.as_str())
                .unwrap();
            assert!(matches!(
                f.accounts.current_session(b.clone()),
                Err(Error::IdentityChanged)
            ));
            f.accounts.switch(&c, &saved_a).unwrap();
            if legacy_registry {
                let mut registry: serde_json::Value =
                    serde_json::from_slice(&fs::read(f.accounts.path()).unwrap()).unwrap();
                registry.as_object_mut().unwrap().remove("canonicalServers");
                fs::write(f.accounts.path(), serde_json::to_vec(&registry).unwrap()).unwrap();
            }
            let restarted = Accounts::new(f.accounts.directories.clone());
            // CLI refreshes on an inactive host must be attributed to its last
            // full origin, not the target profile being selected on that host.
            let credentials_c = if legacy_registry {
                if !connect_first {
                    // With neither ownership nor an exact match, keep both
                    // original snapshots rather than guessing from subject 42.
                    f.store(&c, "42", "unknown-legacy-origin");
                    assert!(matches!(
                        restarted.current_session(b.clone()),
                        Err(Error::IdentityChanged)
                    ));
                }
                credentials_c
            } else {
                f.store(&c, "42", "issuer-c-rotated-while-a-active")
            };
            if connect_first {
                drop(restarted.connect(&f.server, b.clone()).unwrap());
            }
            let active_b = restarted.switch(&f.server, &saved_b).unwrap();
            assert_eq!(active_b.access_token().unwrap(), credentials_b.access_token);
            assert_eq!(restarted.store.read(&b).unwrap(), Some(credentials_b));
            restarted.switch(&b, &saved_c).unwrap();
            assert_eq!(restarted.store.read(&c).unwrap(), Some(credentials_c));
        }
    }

    #[test]
    fn preserve_waits_for_shared_host_refresh_lock_and_reads_after_it() {
        use std::sync::mpsc;
        use std::time::Duration;
        let f = Fixture::new("lock");
        f.store(&f.server, "a", "old");
        let lock = f.accounts.host_locks(&[&f.server]).unwrap();
        let accounts = f.accounts.clone();
        let server = f.server.clone();
        let (tx, rx) = mpsc::channel();
        let thread = std::thread::spawn(move || {
            tx.send(accounts.preserve(&server)).unwrap();
        });
        assert!(rx.recv_timeout(Duration::from_millis(200)).is_err());
        let fresh = f.store(&f.server, "a", "fresh");
        drop(lock);
        rx.recv_timeout(Duration::from_secs(5)).unwrap().unwrap();
        thread.join().unwrap();
        assert_eq!(f.accounts.read().unwrap().accounts[0].credentials, fresh);
    }

    #[test]
    fn signin_commit_archives_rotation_that_happened_during_browser_flow() {
        let f = Fixture::new("signin-rotation");
        f.store(&f.server, "a", "before-browser");
        f.accounts.remember(&f.server).unwrap();
        let saved_a = f.saved("a");
        let login = f.accounts.connect(&f.server, f.server.clone()).unwrap();
        let fresh = f.store(&f.server, "a", "cli-rotation-during-browser");
        let new = f.store(&f.server, "b", "signin-response");
        f.accounts.store.store(&f.server, &fresh).unwrap();
        let workspace = f
            .accounts
            .commit_sign_in(&login, new.clone(), &AtomicBool::new(false))
            .unwrap();
        assert_eq!(workspace.expected_identity(), Some("sub:b"));
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(new));
        f.accounts.switch(&f.server, &saved_a).unwrap();
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(fresh));
    }

    #[test]
    fn cancellation_before_commit_does_not_replace_shared_credentials_or_selection() {
        let f = Fixture::new("signin-cancelled");
        let old = f.store(&f.server, "a", "1");
        f.accounts.remember(&f.server).unwrap();
        let registry = fs::read(f.accounts.path()).unwrap();
        let new = f.store(&f.server, "b", "response");
        f.accounts.store.store(&f.server, &old).unwrap();
        let login = Session::new(
            f.server.clone(),
            &f.accounts.directories,
            OAuthClient::new(),
        );
        let result = f
            .accounts
            .commit_sign_in(&login, new, &AtomicBool::new(true));
        assert!(result.err().unwrap().is_cancelled());
        assert_eq!(f.accounts.store.read(&f.server).unwrap(), Some(old));
        assert_eq!(fs::read(f.accounts.path()).unwrap(), registry);
    }

    #[cfg(unix)]
    #[test]
    fn registry_is_private_even_after_replacing_a_broadly_readable_file() {
        use std::os::unix::fs::PermissionsExt;
        let f = Fixture::new("permissions");
        f.store(&f.server, "a", "1");
        f.accounts.remember(&f.server).unwrap();
        fs::set_permissions(f.accounts.path(), fs::Permissions::from_mode(0o644)).unwrap();
        f.accounts.preserve(&f.server).unwrap();
        assert_eq!(
            fs::metadata(f.accounts.path())
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }
}
