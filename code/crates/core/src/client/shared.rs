//! macOS profiles that use the Tuist app's session. The host reads the Tuist
//! app's Keychain items and updates them in place; it never creates or deletes
//! them, so the Tuist app keeps access. Every refresh holds the lock the Tuist
//! app and CLI hold for the same storage key, so no two processes spend one
//! refresh token.
use super::*;
use tuist_credentials::{Directories, RefreshLock};

/// A rotated pair the Tuist app's Keychain has not accepted yet.
pub(super) struct Pending {
    key: String,
    spent: String,
    access: String,
    refresh: String,
}

struct Session {
    access: String,
    refresh: String,
    client_id: String,
    rejected: bool,
}

impl MobileClient {
    /// Adds a profile for each server the Tuist app is signed in to, unless
    /// the user signed out of it here or already has a profile for that
    /// identity, and drops profiles whose Tuist app session is gone.
    pub(super) fn sync_shared(&mut self, host: &mut dyn Host) -> Result<()> {
        let Ok(listed) = action(host, json!({"type":"shared_list"})) else {
            return Ok(());
        };
        let Some(keys) = listed["servers"].as_array() else {
            return Ok(());
        };
        let keys: Vec<String> = keys
            .iter()
            .filter_map(|k| k.as_str().map(str::to_string))
            .collect();
        let mut next = self.vault.clone();
        next.profiles
            .retain(|p| p.shared.as_ref().is_none_or(|k| keys.contains(k)));
        for key in &keys {
            let Ok(server) = server_url(key) else {
                continue;
            };
            let session = match read(host, key) {
                Ok(Some(session)) => session,
                Ok(None) => {
                    next.profiles.retain(|p| p.shared.as_ref() != Some(key));
                    continue;
                }
                Err(_) => continue,
            };
            let Ok((identity, handle, email)) = identify(&session.access) else {
                continue;
            };
            if let Some(i) = next
                .profiles
                .iter()
                .position(|p| p.shared.as_ref() == Some(key))
            {
                if next.profiles[i].identity == identity {
                    // Token changes alone do not advance the generation.
                    adopt(&mut next.profiles[i], &session);
                    if let Some(current) = self
                        .vault
                        .profiles
                        .iter_mut()
                        .find(|p| p.id == next.profiles[i].id)
                    {
                        adopt(current, &session);
                    }
                    continue;
                }
                next.profiles.remove(i);
            }
            if next.unlinked.contains(&(key.clone(), identity.clone()))
                || next.profiles.iter().any(|p| {
                    p.identity == identity
                        && Url::parse(&p.server).is_ok_and(|u| u.origin() == server.origin())
                })
            {
                continue;
            }
            next.profiles.push(Profile {
                id: Pkce::generate().state,
                server: server.to_string(),
                identity,
                handle,
                email,
                client_id: session.client_id,
                access: session.access,
                refresh: session.refresh,
                organization: None,
                organizations: Vec::new(),
                rejected: session.rejected,
                memberships_rejected: false,
                shared: Some(key.clone()),
            });
        }
        if !next
            .profiles
            .iter()
            .any(|p| Some(&p.id) == next.active_profile_id.as_ref())
        {
            next.active_profile_id = next
                .profiles
                .iter()
                .find(|p| !p.rejected && !p.memberships_rejected)
                .map(|p| p.id.clone());
        }
        self.commit(next, host)
    }

    /// Lock, reread, and refresh only if no peer already did, as
    /// `ServerAuthenticationController.executeRefresh` does.
    pub(super) fn refresh_shared(
        &mut self,
        index: usize,
        key: &str,
        host: &mut dyn Host,
    ) -> Result<()> {
        if !expiring(&self.vault.profiles[index].access)? {
            return Ok(());
        }
        let _lock = self.lock(key)?;
        let stored = read(host, key)?.ok_or("Sign in required")?;
        self.adopt_checked(index, &stored, host)?;
        if !expiring(&stored.access)? {
            return Ok(());
        }
        let server = server_url(&self.vault.profiles[index].server)?;
        let account = Claims::parse(&stored.refresh).is_ok_and(|c| c.is_account_token());
        let response = if account {
            let client_id = if stored.client_id.is_empty() {
                tuist_oauth::default_client_id()
            } else {
                stored.client_id.clone()
            };
            let body = form(&[
                ("grant_type", "refresh_token"),
                ("refresh_token", &stored.refresh),
                ("client_id", &client_id),
            ]);
            http(
                host,
                "POST",
                endpoint(&server, "oauth2/token"),
                json!({"Content-Type":"application/x-www-form-urlencoded"}),
                Some(body),
            )?
        } else {
            http(
                host,
                "POST",
                endpoint(&server, "api/auth/refresh_token"),
                json!({"Content-Type":"application/json"}),
                Some(json!({"refresh_token":stored.refresh}).to_string()),
            )?
        };
        // A Tuist app without the shared lock may still have rotated the pair;
        // its stored pair then wins, as in `refreshSessionTokens`.
        let peer_rotated = |host: &mut dyn Host| -> Result<Option<Session>> {
            Ok(read(host, key)?.filter(|s| s.refresh != stored.refresh && !s.rejected))
        };
        match token_pair(response) {
            Ok((access, refresh)) => {
                if let Some(current) = peer_rotated(host)? {
                    adopt(&mut self.vault.profiles[index], &current);
                    return Ok(());
                }
                let p = &self.vault.profiles[index];
                if identify(&access).map(|(identity, ..)| identity).as_ref() != Ok(&p.identity) {
                    self.mark_rejected(index, host)?;
                    return Err("Credentials rejected");
                }
                self.vault.profiles[index].access = access.clone();
                self.vault.profiles[index].refresh = refresh.clone();
                // The spent pair must never return, even if the Keychain update fails.
                self.pending_shared = Some(Pending {
                    key: key.into(),
                    spent: stored.refresh.clone(),
                    access,
                    refresh,
                });
                self.store_pending(host)
            }
            Err("Credentials rejected") => {
                if let Some(current) = peer_rotated(host)? {
                    adopt(&mut self.vault.profiles[index], &current);
                    return Ok(());
                }
                // The Tuist app marks its own items when it next refreshes.
                self.mark_rejected(index, host)?;
                Err("Credentials rejected")
            }
            Err(error) => Err(error),
        }
    }

    /// Retries a rotation the Keychain did not accept, unless a peer has
    /// since replaced the spent pair.
    pub(super) fn flush_shared(&mut self, host: &mut dyn Host) -> Result<()> {
        let Some(pending) = &self.pending_shared else {
            return Ok(());
        };
        let _lock = self.lock(&pending.key)?;
        self.store_pending(host)
    }

    /// Called with the lock held.
    fn store_pending(&mut self, host: &mut dyn Host) -> Result<()> {
        let Some(pending) = &self.pending_shared else {
            return Ok(());
        };
        let failed = "Could not save the Tuist app session";
        let current = read(host, &pending.key).map_err(|_| failed)?;
        if current.is_some_and(|s| s.refresh == pending.spent) {
            let response = action(
                host,
                json!({"type":"shared_write","server":pending.key,
                    "access_token":pending.access,"refresh_token":pending.refresh}),
            )
            .map_err(|_| failed)?;
            if response["ok"] != true {
                return Err(failed);
            }
        }
        self.pending_shared = None;
        Ok(())
    }

    fn adopt_checked(&mut self, index: usize, stored: &Session, host: &mut dyn Host) -> Result<()> {
        // A different user signed in to the Tuist app; the next snapshot replaces this profile.
        if identify(&stored.access)
            .map(|(identity, ..)| identity)
            .as_ref()
            != Ok(&self.vault.profiles[index].identity)
        {
            return Err("Sign in required");
        }
        adopt(&mut self.vault.profiles[index], stored);
        if stored.rejected {
            self.mark_rejected(index, host)?;
            return Err("Sign in required");
        }
        Ok(())
    }

    fn mark_rejected(&mut self, index: usize, host: &mut dyn Host) -> Result<()> {
        self.vault.profiles[index].rejected = true;
        self.dirty = true;
        write(host, &self.vault)?;
        self.dirty = false;
        Ok(())
    }

    fn lock(&self, key: &str) -> Result<RefreshLock> {
        let state = self
            .state
            .clone()
            .unwrap_or_else(|| Directories::from_env().state);
        RefreshLock::acquire(&RefreshLock::path_for_key(&state, key))
            .map_err(|_| "Another Tuist app is still refreshing this session")
    }
}

/// Copies the Tuist app's pair. A profile this client found rejected stays
/// rejected until the Tuist app holds a different refresh token.
fn adopt(profile: &mut Profile, session: &Session) {
    profile.rejected = session.rejected || (profile.rejected && profile.refresh == session.refresh);
    profile.access = session.access.clone();
    profile.refresh = session.refresh.clone();
    profile.client_id = session.client_id.clone();
}

/// Tokens are not kept in the vault, so a missing token counts as expiring.
fn expiring(access: &str) -> Result<bool> {
    let Ok(claims) = Claims::parse(access) else {
        return Ok(true);
    };
    Ok(claims.exp <= now()? + 30)
}

fn read(host: &mut dyn Host, key: &str) -> Result<Option<Session>> {
    let response = action(host, json!({"type":"shared_read","server":key}))
        .map_err(|_| "Could not read the Tuist app session")?;
    let value = &response["value"];
    if value.is_null() {
        return Ok(None);
    }
    let field = |name| value[name].as_str().filter(|v| !v.is_empty());
    let (Some(access), Some(refresh)) = (field("access_token"), field("refresh_token")) else {
        // Without a refresh token the session cannot be shared.
        return Ok(None);
    };
    Ok(Some(Session {
        access: access.into(),
        refresh: refresh.into(),
        client_id: field("oauth_client_id").unwrap_or_default().into(),
        rejected: value["rejected"] == true,
    }))
}
