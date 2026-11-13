//! Synchronous mobile operations. The native host owns TLS and the private vault.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashSet;
use std::time::{SystemTime, UNIX_EPOCH};
use tuist_jwt::Claims;
use tuist_oauth::{Pkce, Provider, authorization_url, endpoint};
use url::Url;

const CALLBACK: &str = "tuist-code://oauth-callback";
type Result<T> = std::result::Result<T, &'static str>;

/// Called synchronously, on the caller's background thread, never reentrantly.
/// Errors are deliberately opaque; host/server text must not leak credentials.
pub trait Host {
    fn perform(&mut self, action: Value) -> std::result::Result<Value, String>;
}

#[derive(Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Vault {
    profiles: Vec<Profile>,
    active_profile_id: Option<String>,
    generation: u64,
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
struct Profile {
    id: String,
    server: String,
    identity: String,
    handle: String,
    email: String,
    client_id: String,
    access: String,
    refresh: String,
    organization: Option<String>,
    organizations: Vec<String>,
    rejected: bool,
    #[serde(default)]
    memberships_rejected: bool,
}

struct Attempt {
    server: Url,
    client_id: String,
    pkce: Pkce,
}

/// Independent instances support regression tests; the ABI uses one serialized instance.
#[derive(Default)]
pub struct MobileClient {
    vault: Vault,
    loaded: bool,
    dirty: bool,
    attempt: Option<Attempt>,
}

impl MobileClient {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn call(&mut self, input: &str, host: &mut dyn Host) -> String {
        let result = self.run(input, host);
        let (data, error) = match result {
            Ok(data) => (data, None),
            Err(error) => (Value::Null, Some(error)),
        };
        let profiles: Vec<Value> = self
            .vault
            .profiles
            .iter()
            .map(|p| {
                json!({
                    "id":p.id, "server":p.server, "handle":p.handle, "email":p.email,
                    "organization":p.organization, "organizations":p.organizations,
                    "rejected":p.rejected || p.memberships_rejected,
                })
            })
            .collect();
        let mut response = json!({"view":{
            "profiles":profiles, "active_profile_id":self.vault.active_profile_id,
            "generation":self.vault.generation,
        },"data":data});
        if let Some(error) = error {
            response["error"] = json!(error);
        }
        scrub(&mut response, &self.vault.profiles);
        response.to_string()
    }

    fn run(&mut self, input: &str, host: &mut dyn Host) -> Result<Value> {
        if !self.loaded {
            let read = action(host, json!({"type":"read"}))?;
            self.vault = match read.get("value") {
                Some(Value::Null) => Vault::default(),
                Some(Value::String(value)) => {
                    serde_json::from_str(value).map_err(|_| "Invalid private vault")?
                }
                _ => return Err("Could not read private vault"),
            };
            // Fail closed rather than letting a corrupted vault send credentials to a new origin.
            for profile in &self.vault.profiles {
                server_url(&profile.server)?;
            }
            self.loaded = true;
        }
        if self.dirty {
            write(host, &self.vault)?;
            self.dirty = false;
        }
        let request: Value = serde_json::from_str(input).map_err(|_| "Invalid request")?;
        let args = &request["args"];
        match text(&request, "operation")? {
            "snapshot" => Ok(Value::Null),
            "cancel_sign_in" => {
                self.attempt = None;
                Ok(Value::Null)
            }
            "begin_sign_in" => self.begin(args, host),
            "finish_sign_in" => self.finish(args, host),
            "switch_profile" | "select_organization" => {
                let id = text(args, "id")?;
                let mut next = self.vault.clone();
                let p = next
                    .profiles
                    .iter_mut()
                    .find(|p| p.id == id)
                    .ok_or("Unknown profile")?;
                if p.rejected || p.memberships_rejected {
                    return Err("Sign in again to use this profile");
                }
                if request["operation"] == "select_organization" {
                    let name = args.get("name").and_then(Value::as_str);
                    if name
                        .is_some_and(|n| n != p.handle && !p.organizations.iter().any(|v| v == n))
                    {
                        return Err("Unknown organization");
                    }
                    p.organization = name.filter(|n| *n != p.handle).map(str::to_string);
                }
                next.active_profile_id = Some(id.into());
                self.commit(next, host)?;
                Ok(Value::Null)
            }
            "sign_out" => {
                self.remove_active(host)?;
                Ok(Value::Null)
            }
            "organizations" => self.organizations(host),
            "projects" => self.projects(host),
            "previews" | "tracks" | "preview" | "delete_preview" => {
                let index = self.active()?;
                let project = text(args, "project")?;
                let parts: Vec<_> = project.split('/').collect();
                if parts.len() != 2 || parts.iter().any(|v| !segment(v)) {
                    return Err("Invalid project");
                }
                if parts[0] != self.account(index) {
                    return Err("Project is outside selected account");
                }
                let mut path = format!("api/projects/{project}/previews");
                let op = text(&request, "operation")?;
                if op == "tracks" {
                    path.push_str("/tracks");
                }
                if op == "preview" || op == "delete_preview" {
                    let id = text(args, "id")?;
                    if !segment(id) {
                        return Err("Invalid preview ID");
                    }
                    path.push('/');
                    path.push_str(id);
                }
                let mut url = endpoint(&server_url(&self.vault.profiles[index].server)?, &path);
                if op == "previews" {
                    let page = args.get("page").and_then(Value::as_u64).unwrap_or(1);
                    let size = args.get("page_size").and_then(Value::as_u64).unwrap_or(20);
                    if page == 0 || size == 0 || size > 100 {
                        return Err("Invalid pagination");
                    }
                    url.query_pairs_mut()
                        .append_pair("page", &page.to_string())
                        .append_pair("page_size", &size.to_string());
                    for key in ["track", "search"] {
                        if let Some(v) = args
                            .get(key)
                            .and_then(Value::as_str)
                            .filter(|v| !v.is_empty())
                        {
                            url.query_pairs_mut().append_pair(key, v);
                        }
                    }
                }
                let data = self.api(
                    index,
                    if op == "delete_preview" {
                        "DELETE"
                    } else {
                        "GET"
                    },
                    url,
                    host,
                )?;
                if op == "previews" {
                    validate_filters(&data, args)?;
                }
                if op == "tracks"
                    && (!data["total_count"].is_number() || !data["tracks"].is_array())
                {
                    return Err("Track discovery unsupported");
                }
                Ok(data)
            }
            "delete_account" => {
                let index = self.active()?;
                let handle = &self.vault.profiles[index].handle;
                if !segment(handle) {
                    return Err("Invalid account");
                }
                let url = endpoint(
                    &server_url(&self.vault.profiles[index].server)?,
                    &format!("api/accounts/{handle}"),
                );
                self.api(index, "DELETE", url, host)?;
                self.remove_active(host)?;
                Ok(Value::Null)
            }
            _ => Err("Unknown operation"),
        }
    }

    fn commit(&mut self, mut candidate: Vault, host: &mut dyn Host) -> Result<()> {
        if candidate == self.vault {
            return Ok(());
        }
        candidate.generation = self.vault.generation + 1;
        write(host, &candidate)?;
        self.vault = candidate;
        Ok(())
    }

    fn remove_active(&mut self, host: &mut dyn Host) -> Result<()> {
        let mut next = self.vault.clone();
        next.profiles
            .retain(|p| Some(&p.id) != next.active_profile_id.as_ref());
        next.active_profile_id = next
            .profiles
            .iter()
            .find(|p| !p.rejected && !p.memberships_rejected)
            .map(|p| p.id.clone());
        self.commit(next, host)
    }

    fn active(&self) -> Result<usize> {
        self.vault
            .profiles
            .iter()
            .position(|p| Some(&p.id) == self.vault.active_profile_id.as_ref() && !p.rejected)
            .ok_or("Sign in required")
    }

    fn account(&self, index: usize) -> &str {
        let p = &self.vault.profiles[index];
        p.organization.as_deref().unwrap_or(&p.handle)
    }

    fn begin(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        self.attempt = None;
        let server = server_url(text(args, "server")?)?;
        let provider = match args
            .get("provider")
            .and_then(Value::as_str)
            .unwrap_or("tuist")
        {
            "tuist" => Provider::Tuist,
            "github" => Provider::GitHub,
            "google" => Provider::Google,
            "apple" => Provider::Apple,
            _ => return Err("Unknown provider"),
        };
        let metadata = http(
            host,
            "GET",
            endpoint(&server, ".well-known/oauth-authorization-server"),
            json!({}),
            None,
        )?;
        let metadata = successful(metadata)?;
        let registration_text = text(&metadata, "registration_endpoint")?;
        server_url(registration_text)?;
        let registration =
            Url::parse(registration_text).map_err(|_| "Invalid registration endpoint")?;
        if registration.origin() != server.origin() {
            return Err("Unsafe registration endpoint");
        }
        let body = json!({"client_name":"Tuist mobile preview", "redirect_uris":[CALLBACK],
            "grant_types":["authorization_code","refresh_token"], "response_types":["code"],
            "token_endpoint_auth_method":"none"})
        .to_string();
        let registered = successful(http(
            host,
            "POST",
            registration,
            json!({"Content-Type":"application/json"}),
            Some(body),
        )?)?;
        let client_id = text(&registered, "client_id")?.to_string();
        let pkce = Pkce::generate();
        let url = authorization_url(
            &server,
            provider,
            &client_id,
            CALLBACK,
            &pkce.challenge,
            &pkce.state,
        );
        self.attempt = Some(Attempt {
            server,
            client_id,
            pkce,
        });
        Ok(json!({"url":url.as_str(), "callback_scheme":"tuist-code"}))
    }

    fn finish(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        // Consume before parsing or networking: even a tampered callback cannot be replayed.
        let attempt = self.attempt.take().ok_or("No pending sign-in")?;
        let url = Url::parse(text(args, "url")?).map_err(|_| "Invalid callback")?;
        if url.scheme() != "tuist-code"
            || url.host_str() != Some("oauth-callback")
            || !url.path().is_empty()
            || url.port().is_some()
            || !url.username().is_empty()
            || url.password().is_some()
            || url.fragment().is_some()
        {
            return Err("Invalid callback");
        }
        let pairs: Vec<_> = url.query_pairs().collect();
        let unique = |name| -> Result<String> {
            let values: Vec<_> = pairs.iter().filter(|(k, _)| k == name).collect();
            if values.len() != 1 || values[0].1.is_empty() {
                return Err("Invalid callback");
            }
            Ok(values[0].1.to_string())
        };
        if unique("state")? != attempt.pkce.state || pairs.iter().any(|(k, _)| k == "error") {
            return Err("Sign-in response rejected");
        }
        let code = unique("code")?;
        let body = form(&[
            ("grant_type", "authorization_code"),
            ("code", &code),
            ("client_id", &attempt.client_id),
            ("redirect_uri", CALLBACK),
            ("code_verifier", &attempt.pkce.verifier),
        ]);
        let (access, refresh) = token_pair(http(
            host,
            "POST",
            endpoint(&attempt.server, "oauth2/token"),
            json!({"Content-Type":"application/x-www-form-urlencoded"}),
            Some(body),
        )?)?;
        let claims = Claims::parse(&access).map_err(|_| "Invalid token identity")?;
        let identity = claims.identity().ok_or("Invalid token identity")?;
        let handle = claims
            .preferred_username
            .filter(|v| segment(v))
            .ok_or("Invalid token identity")?;
        let email = claims.email.ok_or("Invalid token identity")?;
        let mut next = self.vault.clone();
        let server = attempt.server.to_string();
        let existing = next.profiles.iter().position(|p| {
            Url::parse(&p.server).is_ok_and(|u| u.origin() == attempt.server.origin())
                && p.identity == identity
        });
        let id = existing
            .map(|i| next.profiles[i].id.clone())
            .unwrap_or_else(|| Pkce::generate().state);
        let old = existing.map(|i| next.profiles.remove(i));
        next.profiles.push(Profile {
            id: id.clone(),
            server,
            identity,
            handle,
            email,
            client_id: attempt.client_id,
            access,
            refresh,
            organization: old.as_ref().and_then(|p| p.organization.clone()),
            organizations: old.map(|p| p.organizations).unwrap_or_default(),
            rejected: false,
            memberships_rejected: false,
        });
        next.active_profile_id = Some(id);
        self.commit(next, host)?;
        Ok(Value::Null)
    }

    fn refresh(&mut self, index: usize, host: &mut dyn Host) -> Result<()> {
        let p = &self.vault.profiles[index];
        if p.rejected {
            return Err("Sign in required");
        }
        let claims = Claims::parse(&p.access).map_err(|_| "Invalid token identity")?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| "Clock unavailable")?
            .as_secs() as i64;
        if claims.exp > now + 30 {
            return Ok(());
        }
        let body = form(&[
            ("grant_type", "refresh_token"),
            ("refresh_token", &p.refresh),
            ("client_id", &p.client_id),
        ]);
        let response = http(
            host,
            "POST",
            endpoint(&server_url(&p.server)?, "oauth2/token"),
            json!({"Content-Type":"application/x-www-form-urlencoded"}),
            Some(body),
        )?;
        match token_pair(response) {
            Ok((access, refresh)) => {
                let valid_identity = Claims::parse(&access)
                    .is_ok_and(|claims| claims.identity().as_deref() == Some(&p.identity));
                self.vault.profiles[index].access = access;
                self.vault.profiles[index].refresh = refresh;
                self.vault.profiles[index].rejected = !valid_identity;
                // The spent pair must never return, even if native persistence fails.
                self.dirty = true;
                write(host, &self.vault)?;
                self.dirty = false;
                if valid_identity {
                    Ok(())
                } else {
                    Err("Credentials rejected")
                }
            }
            Err("Credentials rejected") => {
                self.vault.profiles[index].rejected = true;
                self.dirty = true;
                write(host, &self.vault)?;
                self.dirty = false;
                Err("Credentials rejected")
            }
            Err(error) => Err(error),
        }
    }

    fn api(&mut self, index: usize, method: &str, url: Url, host: &mut dyn Host) -> Result<Value> {
        self.refresh(index, host)?;
        let response = http(
            host,
            method,
            url,
            json!({"Authorization":format!("Bearer {}",self.vault.profiles[index].access)}),
            None,
        )?;
        successful(response)
    }

    fn organizations(&mut self, host: &mut dyn Host) -> Result<Value> {
        let mut results = Vec::new();
        let mut failed = false;
        for index in 0..self.vault.profiles.len() {
            let url = endpoint(
                &server_url(&self.vault.profiles[index].server)?,
                "api/organizations",
            );
            match self.api(index, "GET", url, host) {
                Ok(data) => {
                    let names = data["organizations"]
                        .as_array()
                        .ok_or("Invalid organizations")?
                        .iter()
                        .map(|v| text(v, "name").map(str::to_string))
                        .collect::<Result<Vec<_>>>()?;
                    let mut next = self.vault.clone();
                    let p = &mut next.profiles[index];
                    p.organizations = names;
                    p.memberships_rejected = false;
                    if p.organization
                        .as_ref()
                        .is_some_and(|n| !p.organizations.contains(n))
                    {
                        p.organization = None;
                    }
                    self.commit(next, host)?;
                    results.push(json!({"id":self.vault.profiles[index].id,"response":data}));
                }
                Err(error) => {
                    failed = true;
                    if error == "Access denied" {
                        self.vault.profiles[index].memberships_rejected = true;
                        self.dirty = true;
                        write(host, &self.vault)?;
                        self.dirty = false;
                    }
                    // Never perform another operation with an unpersisted rotation.
                    if self.dirty {
                        return Err(error);
                    }
                }
            }
        }
        if failed {
            Err("Some memberships could not be refreshed")
        } else {
            Ok(json!(results))
        }
    }

    fn projects(&mut self, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let mut projects = Vec::new();
        let mut seen = HashSet::new();
        let mut page = 1u64;
        loop {
            let mut url = endpoint(
                &server_url(&self.vault.profiles[index].server)?,
                "api/projects",
            );
            url.query_pairs_mut()
                .append_pair("page", &page.to_string())
                .append_pair("page_size", "100");
            let data = self.api(index, "GET", url, host)?;
            let rows = data["projects"].as_array().ok_or("Invalid projects")?;
            let mut added = 0;
            for row in rows {
                let name = text(row, "full_name")?;
                if seen.insert(name.to_string()) {
                    added += 1;
                    if name.split('/').next() == Some(self.account(index)) {
                        projects.push(row.clone());
                    }
                }
            }
            let more = data["pagination_metadata"]["has_next_page"]
                .as_bool()
                .unwrap_or(false);
            if page > 1 && !rows.is_empty() && added == 0 {
                return Err("Project pagination did not advance");
            }
            if !more {
                break;
            }
            if added == 0 {
                return Err("Project pagination did not advance");
            }
            page = page.checked_add(1).ok_or("Invalid pagination")?;
        }
        Ok(json!({"projects":projects}))
    }
}

fn action(host: &mut dyn Host, value: Value) -> Result<Value> {
    let response = host.perform(value).map_err(|_| "Native operation failed")?;
    if response.get("error").is_some() {
        return Err("Native operation failed");
    }
    Ok(response)
}

fn write(host: &mut dyn Host, vault: &Vault) -> Result<()> {
    let response = action(host,json!({"type":"write","value":serde_json::to_string(vault).map_err(|_| "Could not encode private vault")?}))
        .map_err(|_| "Could not save private vault")?;
    if response["ok"] != true {
        return Err("Could not save private vault");
    }
    Ok(())
}

fn server_url(value: &str) -> Result<Url> {
    let mut url = Url::parse(value).map_err(|_| "Invalid server URL")?;
    let loopback = matches!(url.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"));
    if (url.scheme() != "https" && !(url.scheme() == "http" && loopback))
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err("Server requires HTTPS");
    }
    let path = url.path().trim_end_matches('/').to_string();
    url.set_path(&format!("{path}/"));
    Ok(url)
}

fn http(
    host: &mut dyn Host,
    method: &str,
    url: Url,
    mut headers: Value,
    body: Option<String>,
) -> Result<(u64, Value)> {
    headers["Accept"] = json!("application/json");
    let mut request = json!({"type":"http","method":method,"url":url.as_str(),"headers":headers});
    if let Some(body) = body {
        request["body"] = json!(body);
    }
    let response = action(host, request)?;
    let status = response["status"].as_u64().ok_or("Invalid HTTP response")?;
    let body = response["body"].as_str().ok_or("Invalid HTTP response")?;
    let data = if body.is_empty() {
        Value::Null
    } else {
        serde_json::from_str(body).unwrap_or(Value::Null)
    };
    Ok((status, data))
}

fn successful((status, data): (u64, Value)) -> Result<Value> {
    match status {
        200..=299 => Ok(data),
        401 | 403 => Err("Access denied"),
        404 => Err("Resource not found or server unsupported"),
        _ => Err("Server request failed"),
    }
}

fn token_pair((status, data): (u64, Value)) -> Result<(String, String)> {
    if status == 401 || (status == 400 && data["error"] == "invalid_grant") {
        return Err("Credentials rejected");
    }
    if !(200..300).contains(&status) {
        return Err("Token service unavailable");
    }
    let access = data["access_token"]
        .as_str()
        .filter(|v| !v.trim().is_empty())
        .ok_or("Credentials rejected")?;
    let refresh = data["refresh_token"]
        .as_str()
        .filter(|v| !v.trim().is_empty())
        .ok_or("Credentials rejected")?;
    Ok((access.into(), refresh.into()))
}

fn form(pairs: &[(&str, &str)]) -> String {
    url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(pairs.iter().copied())
        .finish()
}
fn text<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v.get(key)
        .and_then(Value::as_str)
        .filter(|v| !v.trim().is_empty())
        .ok_or("Missing required argument")
}
fn segment(v: &str) -> bool {
    !v.is_empty()
        && v != "."
        && v != ".."
        && v.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
}

fn validate_filters(data: &Value, args: &Value) -> Result<()> {
    let previews = data["previews"].as_array().ok_or("Invalid previews")?;
    let metadata = &data["pagination_metadata"];
    if metadata["current_page"]
        .as_u64()
        .is_some_and(|page| page != args["page"].as_u64().unwrap_or(1))
        || (previews.is_empty() && metadata["has_next_page"] == true)
    {
        return Err("Preview pagination did not advance");
    }
    for preview in previews {
        if let Some(track) = args
            .get("track")
            .and_then(Value::as_str)
            .filter(|v| !v.is_empty())
            && !preview["track"]
                .as_str()
                .is_some_and(|v| v.to_lowercase() == track.to_lowercase())
        {
            return Err("Track filtering unsupported");
        }
        if let Some(search) = args
            .get("search")
            .and_then(Value::as_str)
            .filter(|v| !v.is_empty())
            && !["display_name", "release_notes"].iter().any(|key| {
                preview[key]
                    .as_str()
                    .is_some_and(|v| v.to_lowercase().contains(&search.to_lowercase()))
            })
        {
            return Err("Search filtering unsupported");
        }
    }
    Ok(())
}

fn scrub(value: &mut Value, profiles: &[Profile]) {
    match value {
        Value::Object(map) => {
            map.retain(|k, _| {
                !matches!(
                    k.as_str(),
                    "access_token" | "refresh_token" | "access" | "refresh" | "code_verifier"
                )
            });
            for value in map.values_mut() {
                scrub(value, profiles);
            }
        }
        Value::Array(values) => {
            for value in values {
                scrub(value, profiles);
            }
        }
        Value::String(value) => {
            for p in profiles {
                for secret in [&p.access, &p.refresh] {
                    if !secret.is_empty() && value.contains(secret) {
                        *value = value.replace(secret, "[redacted]");
                    }
                }
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests;
