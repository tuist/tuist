//! Synchronous mobile operations. The native host owns TLS and the private vault.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashSet;
// `std::time` natively; `Date.now()` in the browser, where std's clock panics.
use tuist_jwt::Claims;
use tuist_oauth::{LUFT_CLIENT_ID, Pkce, Provider, authorization_url, endpoint};
use url::Url;
use web_time::{SystemTime, UNIX_EPOCH};

use crate::store::{self, OFFLINE, Store};
use crate::threads::{Threads, Transport};
use crate::updates;

const CALLBACK: &str = "luft://oauth-callback";
pub(crate) type Result<T> = std::result::Result<T, &'static str>;

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
    /// The installation ID this profile registered this device for push under.
    #[serde(default)]
    push_installation: Option<String>,
    /// The person turned notifications on for this profile on this device.
    /// Off until they do, and off again when they remove this device from
    /// their device list.
    #[serde(default)]
    push_enabled: bool,
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
    threads: Threads,
    lounges: crate::Lounges,
    presence: crate::Presence,
    navigation: crate::navigation::Navigation,
    /// The live sockets of the threads the edge shows.
    live: crate::live::Live,
    /// The open local store and the profile it belongs to.
    store: Option<(String, Store)>,
    /// The newer preview `preview_update` last suggested installing, so edges prompt once per build.
    suggested_preview: Option<String>,
    /// The last `lounges` answer and the generation it belongs to, which `palette` searches.
    palette_lounges: Option<(u64, Value)>,
}

impl MobileClient {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn call(&mut self, input: &str, host: &mut dyn Host) -> String {
        let result = self.run(input, host).and_then(|data| {
            if let Some(profile) = self.vault.profiles.iter().find(|p| {
                Some(&p.id) == self.vault.active_profile_id.as_ref()
                    && !p.rejected
                    && !p.memberships_rejected
            }) {
                self.navigation.resume(&server_url(&profile.server)?)?;
            }
            Ok(data)
        });
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
                    "push_enabled":p.push_enabled,
                })
            })
            .collect();
        let mut response = json!({"view":{
            "profiles":profiles, "accounts":self.accounts(),
            "active_profile_id":self.vault.active_profile_id,
            "generation":self.vault.generation,
            "navigation":self.navigation,
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
                    let (vault, migrated) = migrate(value)?;
                    self.dirty |= migrated;
                    vault
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
            "routes" => Ok(json!({"routes":crate::navigation::ROUTES})),
            "navigate" => {
                // Async completions must not replace a newer route or session,
                // including requests already queued by a native edge.
                if args
                    .get("if_generation")
                    .is_some_and(|v| v.as_u64() != Some(self.vault.generation))
                    || args
                        .get("if_revision")
                        .is_some_and(|v| v.as_u64() != Some(self.navigation.revision))
                {
                    return Ok(Value::Null);
                }
                let server = self
                    .vault
                    .profiles
                    .iter()
                    .find(|p| {
                        Some(&p.id) == self.vault.active_profile_id.as_ref()
                            && !p.rejected
                            && !p.memberships_rejected
                    })
                    .map(|p| server_url(&p.server))
                    .transpose()?;
                self.navigation
                    .receive(text(args, "url")?, server.as_ref())?;
                Ok(Value::Null)
            }
            "select_tab" => {
                self.navigation.select(text(args, "tab")?)?;
                Ok(Value::Null)
            }
            "navigation_back" => {
                self.navigation.back();
                Ok(Value::Null)
            }
            "boot" => self.boot(host),
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
                self.presence.disconnect(&mut HostSocket { host });
                let push_unregister_failed = !self.push_unregister(host);
                let profile = self.vault.active_profile_id.clone();
                self.remove_active(host)?;
                if let Some(profile) = profile {
                    self.clear_store(&profile, host)?;
                }
                Ok(json!({"push_unregister_failed":push_unregister_failed}))
            }
            "organizations" => self.organizations(host),
            "projects" => self.projects(host),
            op @ ("threads" | "start_thread" | "thread" | "send_message" | "answer_question"
            | "snooze_thread" | "archive_thread" | "reauthorize_thread") => {
                let mut view = self.threads_operation(op, args, host)?;
                crate::threads::present_stored(&mut view, now()?);
                Ok(view)
            }
            // Answer from the store without the network, so screens render at once.
            op @ ("cached_threads" | "cached_thread") => {
                let index = self.active()?;
                let account = self.account(index).to_string();
                let store = self.store(index, host)?;
                let mut view = if op == "cached_threads" {
                    store.inbox(&account)?
                } else {
                    let id = text(args, "id")?;
                    let mut view = store.conversation(id)?;
                    // Its live socket stores every change as it happens.
                    let resolved = store.resolve(id)?;
                    if self.live.synced(&resolved) {
                        view["freshness"] = json!({"state": "live"});
                    }
                    view
                };
                crate::threads::present_stored(&mut view, now()?);
                Ok(view)
            }
            "snooze_options" => Ok(crate::threads::snooze_options(
                now()?,
                args.get("offset_seconds")
                    .and_then(Value::as_i64)
                    .filter(|o| o.abs() <= 14 * 3600)
                    .ok_or("Invalid offset")?,
                args.get("working")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            )),
            "flush_outbox" => self.flush_outbox(host),
            // Pure; edges may also call `tuist_app_compose` to skip the client lock.
            "compose" => Ok(crate::compose::compose(args)),
            // The live sockets of the threads screens show (`crate::live`),
            // by a handle the edge picks for each. Opening one refreshes the
            // bearer first, which the edge needs to open it.
            "live_connect" => {
                let index = self.active()?;
                let id = text(args, "id")?;
                // `inbox` follows the whole inbox: the server pushes when any
                // of the person's threads in the account changes.
                if id != crate::live::INBOX && id != crate::live::AI_SUBSCRIPTIONS && !is_uuid(id) {
                    return Err("Invalid thread ID");
                }
                self.refresh(index, host)?;
                let server = server_url(&self.vault.profiles[index].server)?;
                let account = self.account(index).to_string();
                let access = self.vault.profiles[index].access.clone();
                // A thread syncs from the revision the store has, so the
                // server sends only what changed since; without a store it
                // reloads on each change, as before.
                let sync = match self.store(index, host) {
                    Ok(store) if is_uuid(id) => Some(store.revision(id)?),
                    _ => None,
                };
                self.live
                    .connect(text(args, "socket")?, &server, &account, id, &access, sync)
            }
            "live_wait" => Ok(json!({"delay_ms": self.live.wait(text(args, "socket")?)})),
            "live_tick" => Ok(self.live.tick(text(args, "socket")?)),
            // A `diff` is stored here and never reaches the edge: `changed`
            // says the stored thread changed, so the edge reads it again.
            "live_receive" => {
                let index = self.active()?;
                let account = self.account(index).to_string();
                let mut out = self.live.receive(
                    text(args, "socket")?,
                    &account,
                    text(args, "id")?,
                    text(args, "message")?,
                )?;
                let diff = out
                    .as_object_mut()
                    .and_then(|o| o.remove("diff"))
                    .unwrap_or_default();
                let mut changed = false;
                if !diff.is_null() {
                    match self
                        .store(index, host)
                        .and_then(|store| store.apply_diff(&diff, now()?))
                    {
                        Ok(applied) => changed = applied,
                        // The server moved past a diff the store doesn't
                        // have: joining again resends from what it does.
                        Err(error) => {
                            log(host, &format!("store: {error}"));
                            out["reconnect"] = json!(true);
                        }
                    }
                }
                out["changed"] = json!(changed);
                Ok(out)
            }
            "live_close" => {
                self.live.close(text(args, "socket")?);
                Ok(Value::Null)
            }
            op @ ("lounges"
            | "lounge"
            | "send_lounge_message"
            | "read_lounge"
            | "create_lounge"
            | "start_direct"
            | "lounge_people"
            | "invite_lounge") => {
                let index = self.active()?;
                let account = self.account(index).to_string();
                let organization = self.vault.profiles[index].organization.is_some();
                let server = server_url(&self.vault.profiles[index].server)?;
                let mut lounges = std::mem::take(&mut self.lounges);
                let result = lounges.call(
                    &server,
                    &account,
                    organization,
                    op,
                    args,
                    &mut Authorized {
                        client: self,
                        index,
                        host,
                    },
                );
                self.lounges = lounges;
                // People connected now, which is fresher than the server's answer.
                let mut result = result;
                if let (Ok(data), Some(online)) = (&mut result, self.presence.online_ids(&account))
                {
                    crate::presence::mark_online(data, &online);
                }
                if let ("lounges", Ok(data)) = (op, &result) {
                    self.palette_lounges = Some((self.vault.generation, data.clone()));
                }
                result
            }
            // Local only, so edges can call it on every keystroke: the stored
            // inbox and the lounges `lounges` last loaded for this generation.
            "palette" => {
                let index = self.active()?;
                let account = self.account(index).to_string();
                let threads = self.store(index, host)?.inbox(&account)?;
                let lounges = match &self.palette_lounges {
                    Some((generation, lounges)) if *generation == self.vault.generation => lounges,
                    _ => &Value::Null,
                };
                Ok(crate::palette::palette(
                    args.get("query").and_then(Value::as_str).unwrap_or(""),
                    &args["labels"],
                    &threads,
                    lounges,
                ))
            }
            "presence" => {
                let index = self.active()?;
                let profile = &self.vault.profiles[index];
                if profile.organization.is_none() {
                    self.presence.disconnect(&mut HostSocket { host });
                    return Ok(
                        json!({"available":false,"reason":"personal","connected":false,"online":[]}),
                    );
                }
                let account = self.account(index).to_string();
                let server = server_url(&profile.server)?;
                // Connects with a token valid for at least 30 s; the server checks it
                // again every 30 s, and a later reconnect refreshes it again.
                self.refresh(index, host)?;
                let access = self.vault.profiles[index].access.clone();
                self.presence.poll(
                    &server,
                    &account,
                    &mut || Ok(access.clone()),
                    &mut HostSocket { host },
                    now()?,
                )
            }
            "presence_disconnect" => {
                self.presence.disconnect(&mut HostSocket { host });
                Ok(Value::Null)
            }
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
            "preview_update" => self.preview_update(args, host),
            "push_register" => self.push_register(args, host),
            op @ ("runners" | "register_runner" | "remove_runner") => self.runners(op, args, host),
            op @ ("ai_subscriptions"
            | "connect_claude"
            | "start_chatgpt_login"
            | "poll_chatgpt_login"
            | "cancel_chatgpt_login"
            | "disconnect_ai_subscription") => self.ai_subscriptions(op, args, host),
            "push_enable" => self.push_enable(args, host),
            "live_activity_register" => self.live_activity_register(args, host),
            "live_activity_unregister" => self.live_activity_unregister(args, host),
            "live_activity_starter_register" => self.live_activity_starter_register(args, host),
            "live_activity_starter_unregister" => self.live_activity_starter_unregister(args, host),
            "open_notification" => self.open_notification(args, host),
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

    fn thread_call(
        &mut self,
        index: usize,
        account: &str,
        op: &str,
        args: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        let server = server_url(&self.vault.profiles[index].server)?;
        let mut threads = std::mem::take(&mut self.threads);
        let result = threads.call(
            &server,
            account,
            op,
            args,
            &mut Authorized {
                client: self,
                index,
                host,
            },
        );
        self.threads = threads;
        result
    }

    /// Runs a thread operation against the server and records it in the
    /// local store, which answers instead when the server can't be reached.
    fn threads_operation(&mut self, op: &str, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let account = self.account(index).to_string();
        let mut args = args.clone();
        let mut unsent = false;
        if let Some(id) = args.get("id").and_then(Value::as_str)
            && let Ok(store) = self.store(index, host)
        {
            // A thread started offline is reached by its local id until the
            // server has it, and by the server's id after.
            let id = store.resolve(id)?;
            unsent = store.unsent(&id)?;
            args["id"] = json!(id);
        }
        if matches!(op, "send_message" | "answer_question")
            && let Ok(store) = self.store(index, host)
            && let Ok(thread) = store.conversation(args["id"].as_str().unwrap_or_default())
            && thread["reauthorization_required"] == true
        {
            return Err("The owner must authorize future messages with their current sign-in");
        }
        if matches!(op, "start_thread" | "send_message" | "answer_question")
            && args.get("request_id").is_none()
        {
            let server = server_url(&self.vault.profiles[index].server)?;
            args["request_id"] = json!(self.threads.request_key(&server, &account, op, &args)?);
        }
        // The server doesn't have an unsent thread yet: read it from the
        // store and queue replies behind it, as if offline.
        let result = if unsent {
            Err(OFFLINE)
        } else {
            self.thread_call(index, &account, op, &args, host)
        };
        // The text-only outbox cannot preserve file bytes. Retain the draft
        // and its replay key in the caller rather than acknowledge a partial send.
        if args["attachments"]
            .as_array()
            .is_some_and(|files| !files.is_empty())
            && result == Err(OFFLINE)
        {
            return Err("Connect to the internet to send attachments");
        }
        // The outbox replays a thread's text only, so a thread on a runner is
        // started online or not at all.
        if op == "start_thread"
            && !args.get("runner_id").is_none_or(Value::is_null)
            && result == Err(OFFLINE)
        {
            return Err(RUNNER_NEEDS_NETWORK);
        }
        let now = now()?;
        let recorded = match self.store(index, host) {
            Ok(store) => store::record(store, op, &account, &args, result.clone(), now),
            Err(error) => Err(error),
        };
        match (recorded, result) {
            (Ok(view), _) => {
                // Polls must not forget a lost answer's retry key while the
                // person is still looking at the pending question.
                if matches!(op, "start_thread" | "send_message" | "answer_question") {
                    self.threads.settle();
                }
                Ok(view)
            }
            // The server answered; a local store that can't keep it (full
            // disk, a database from a newer build) mustn't turn that into an error.
            (Err(error), Ok(mut data)) => {
                log(host, &format!("store: {error}"));
                if matches!(op, "start_thread" | "send_message" | "answer_question") {
                    self.threads.settle();
                }
                data["freshness"] = json!({"state": "live"});
                Ok(data)
            }
            (Err(error), Err(_)) => Err(error),
        }
    }

    /// Sends the active profile's queued writes in order, each under the
    /// `request_id` it was queued with, so a replay never creates a duplicate.
    /// Stops at the first failure that may clear up (no network, a server
    /// error, a busy thread, credentials) and keeps the rest for the next
    /// flush; a write the server refuses for good is marked failed.
    fn flush_outbox(&mut self, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let outbox = self.store(index, host)?.outbox()?;
        let mut sent = 0;
        for entry in outbox.iter().filter(|e| e["failed"] != true) {
            let op = entry["operation"].as_str().ok_or("Invalid outbox")?;
            let account = entry["account"].as_str().ok_or("Invalid outbox")?;
            let request_id = entry["request_id"].as_str().ok_or("Invalid outbox")?;
            let mut args = json!({"content": entry["content"], "request_id": request_id});
            if op == "send_message" {
                let store = self.store(index, host)?;
                // Earlier entries may have sent the thread this replies to.
                let id = store.resolve(entry["thread_id"].as_str().ok_or("Invalid outbox")?)?;
                if store.unsent(&id)? {
                    // The thread itself failed, so its replies can't be sent.
                    store.settle(request_id, true)?;
                    continue;
                }
                args["id"] = json!(id);
            }
            let result = self.thread_call(index, account, op, &args, host);
            let store = self.store(index, host)?;
            match result {
                Ok(thread) => {
                    store.sent(request_id, &thread, now()?)?;
                    sent += 1;
                }
                Err(error) if retryable(error) => break,
                Err(_) => store.settle(request_id, true)?,
            }
        }
        Ok(json!({"sent": sent}))
    }

    /// The first call at launch: the vault is loaded by now, and every
    /// profile's store is migrated before any screen reads it. Each step is
    /// logged; a store that fails to open is logged and opened again on use.
    fn boot(&mut self, host: &mut dyn Host) -> Result<Value> {
        log(
            host,
            &format!("boot: vault loaded, {} profiles", self.vault.profiles.len()),
        );
        let directory = store_directory(host)?;
        let mut stores = Vec::new();
        for profile in self.vault.profiles.iter().map(|p| p.id.clone()) {
            match open_store(&directory, &profile, host) {
                Ok((store, migrated)) => {
                    stores.push(json!({"profile": profile, "migrated": migrated}));
                    if self.vault.active_profile_id.as_ref() == Some(&profile) {
                        self.store = Some((profile, store));
                    }
                }
                Err(error) => log(host, &format!("store {profile}: {error}")),
            }
        }
        log(host, "boot: ready");
        Ok(json!({"stores": stores}))
    }

    /// The profile's local store, opened (and migrated) on first use in the
    /// directory the host keeps it in.
    fn store(&mut self, index: usize, host: &mut dyn Host) -> Result<&mut Store> {
        let profile = &self.vault.profiles[index].id;
        if !self.store.as_ref().is_some_and(|(p, _)| p == profile) {
            self.store = None;
            let (store, _) = open_store(&store_directory(host)?, profile, host)?;
            self.store = Some((profile.clone(), store));
        }
        Ok(&mut self.store.as_mut().expect("store was just opened").1)
    }

    /// Forgets everything stored for a profile, for sign-out. Rows are deleted
    /// through SQLite on every platform, then native hosts remove the files,
    /// even when the database couldn't be opened or cleared.
    fn clear_store(&mut self, profile: &str, host: &mut dyn Host) -> Result<()> {
        let files = store::files(&store_directory(host)?, profile)?;
        let store = match self.store.take() {
            Some((p, store)) if p == profile => Ok(store),
            _ => Store::open(files.last().expect("the database file")).map(|(store, _)| store),
        };
        if let Err(error) = store.and_then(Store::clear) {
            log(host, &format!("store {profile}: {error}"));
        }
        for file in files {
            // The browser's VFS has no files to remove; its rows are gone.
            let _ = std::fs::remove_file(file);
        }
        Ok(())
    }

    fn commit(&mut self, mut candidate: Vault, host: &mut dyn Host) -> Result<()> {
        if candidate == self.vault {
            return Ok(());
        }
        candidate.generation = self.vault.generation + 1;
        write(host, &candidate)?;
        // Metadata refresh and same-profile reauthentication retain navigation.
        // Only a change to an existing active account/server/organization resets it.
        if self.vault.active_profile_id.is_some()
            && (self.vault.active_profile_id != candidate.active_profile_id
                || self
                    .vault
                    .profiles
                    .iter()
                    .find(|p| Some(&p.id) == self.vault.active_profile_id.as_ref())
                    .map(|p| (&p.server, &p.organization))
                    != candidate
                        .profiles
                        .iter()
                        .find(|p| Some(&p.id) == candidate.active_profile_id.as_ref())
                        .map(|p| (&p.server, &p.organization)))
        {
            self.navigation.reset();
        }
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

    /// Every personal account and organization across saved profiles, for one
    /// switcher. A membership shared by several profiles on the same server is
    /// listed once, through the active profile when it is one of them.
    fn accounts(&self) -> Vec<Value> {
        let active = self.vault.active_profile_id.as_deref();
        let ordered = self
            .vault
            .profiles
            .iter()
            .filter(|p| Some(p.id.as_str()) == active)
            .chain(
                self.vault
                    .profiles
                    .iter()
                    .filter(|p| Some(p.id.as_str()) != active),
            );
        let mut seen = HashSet::new();
        let mut accounts = Vec::new();
        for p in ordered {
            let rejected = p.rejected || p.memberships_rejected;
            let organizations: &[String] = if rejected { &[] } else { &p.organizations };
            for name in std::iter::once(&p.handle).chain(organizations) {
                if !seen.insert((p.server.as_str(), name.as_str())) {
                    continue;
                }
                accounts.push(json!({
                    "profile_id":p.id, "name":name, "server":p.server, "handle":p.handle,
                    "personal":*name == p.handle, "rejected":rejected,
                    "selected":Some(p.id.as_str()) == active
                        && p.organization.as_deref().unwrap_or(&p.handle) == name,
                }));
            }
        }
        accounts.sort_by(|a, b| {
            (a["name"].as_str(), a["server"].as_str())
                .cmp(&(b["name"].as_str(), b["server"].as_str()))
        });
        accounts
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
        // Luft is a first-party app with the same client on every server that
        // has it. Servers from before it would fail in the browser, so ask first.
        let discovery = http(
            host,
            "GET",
            endpoint(&server, ".well-known/luft.json"),
            json!({}),
            None,
        )?;
        match successful(discovery) {
            Ok(data) if data["luft_oauth_client_id"] == LUFT_CLIENT_ID => {}
            Ok(_) | Err(NOT_FOUND) => return Err(UNSUPPORTED_SERVER),
            Err(error) => return Err(error),
        }
        let client_id = LUFT_CLIENT_ID.to_string();
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
        Ok(json!({"url":url.as_str(), "callback_scheme":"luft"}))
    }

    fn finish(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        // Consume before parsing or networking: even a tampered callback cannot be replayed.
        let attempt = self.attempt.take().ok_or("No pending sign-in")?;
        let url = Url::parse(text(args, "url")?).map_err(|_| "Invalid callback")?;
        if url.scheme() != "luft"
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
        let (identity, handle, email) = identify(&access)?;
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
            organizations: old
                .as_ref()
                .map(|p| p.organizations.clone())
                .unwrap_or_default(),
            rejected: false,
            memberships_rejected: false,
            push_installation: old.as_ref().and_then(|p| p.push_installation.clone()),
            push_enabled: old.as_ref().is_some_and(|p| p.push_enabled),
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
        if claims.exp > now()? + 30 {
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
        successful(self.send(index, method, url, None, host)?)
    }

    fn send(
        &mut self,
        index: usize,
        method: &str,
        url: Url,
        body: Option<Value>,
        host: &mut dyn Host,
    ) -> Result<(u64, Value)> {
        self.refresh(index, host)?;
        let mut headers =
            json!({"Authorization":format!("Bearer {}",self.vault.profiles[index].access)});
        if body.is_some() {
            headers["Content-Type"] = json!("application/json");
        }
        http(host, method, url, headers, body.map(|b| b.to_string()))
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

    /// Asks tuist.dev, whatever profile is selected, because that is where Tuist
    /// Luft's previews live. People without a tuist.dev profile, or without
    /// access to the project, have no update to install.
    fn preview_update(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let platform = text(args, "platform")?;
        updates::build_type(platform)?;
        let binary_id = text(args, "binary_id")?;
        let server = server_url(updates::SERVER)?;
        let on_server = |p: &Profile| {
            !p.rejected && Url::parse(&p.server).is_ok_and(|u| u.origin() == server.origin())
        };
        let index = match self.active() {
            Ok(index) if on_server(&self.vault.profiles[index]) => index,
            _ => match self.vault.profiles.iter().position(on_server) {
                Some(index) => index,
                None => return Ok(json!({"update":null})),
            },
        };
        let mut url = endpoint(&server, updates::PATH);
        url.query_pairs_mut()
            .append_pair("track", updates::TRACK)
            .append_pair("supported_platforms", platform)
            .append_pair("page", "1")
            .append_pair("page_size", "20");
        let mut result = match self.api(index, "GET", url, host) {
            Ok(data) => updates::select(&data, platform, binary_id)?,
            Err("Access denied" | NOT_FOUND) => json!({"update":null}),
            Err(error) => return Err(error),
        };
        let id = result["update"]["id"].as_str().map(str::to_owned);
        result["suggest"] = json!(id.is_some() && id != self.suggested_preview);
        if id.is_some() {
            self.suggested_preview = id;
        }
        Ok(result)
    }

    /// The signed-in person's runners: their own machines, which threads can
    /// run on. `register_runner` answers with the runner's secret, which the
    /// edge hands to the runner daemon on this machine and never keeps.
    fn runners(&mut self, op: &str, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let server = server_url(&self.vault.profiles[index].server)?;
        let collection = endpoint(&server, "api/me/thread-runners");
        match op {
            "runners" => successful(self.send(index, "GET", collection, None, host)?),
            "register_runner" => {
                let platform = text(args, "platform")?;
                if !matches!(platform, "macos" | "linux" | "windows") {
                    return Err("Invalid runner");
                }
                let body = json!({"name": text(args, "name")?, "platform": platform});
                let mut runner =
                    successful(self.send(index, "POST", collection, Some(body), host)?)?;
                runner["server"] = json!(server.as_str().trim_end_matches('/'));
                Ok(runner)
            }
            _ => {
                let id = text(args, "id")?;
                if !is_uuid(id) {
                    return Err("Invalid runner");
                }
                let url = endpoint(&server, &format!("api/me/thread-runners/{id}"));
                successful(self.send(index, "DELETE", url, None, host)?).map(|_| Value::Null)
            }
        }
    }

    /// The person's AI subscriptions (`crate::ai_subscriptions`) with the
    /// active profile's session.
    fn ai_subscriptions(&mut self, op: &str, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let server = server_url(&self.vault.profiles[index].server)?;
        crate::ai_subscriptions::call(
            &server,
            op,
            args,
            &mut Authorized {
                client: self,
                index,
                host,
            },
        )
    }

    /// Registers this device's push token for the active profile at
    /// `/api/me/push-devices/{installation}`. A device token reaches one sign-in
    /// at a time, so edges call this again whenever the active profile changes.
    /// The profile keeps its installation ID; `installation_id` is a fresh UUID
    /// from the edge, used the first time and whenever the server retired the
    /// old one.
    fn push_register(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let platform = text(args, "platform")?;
        let environment = text(args, "environment")?;
        let token = text(args, "token")?;
        let candidate = text(args, "installation_id")?;
        if !matches!(
            (platform, environment),
            ("ios" | "macos", "sandbox" | "production") | ("android", "production")
        ) || !is_uuid(candidate)
        {
            return Err("Invalid push device");
        }
        if !self.vault.profiles[index].push_enabled {
            return Ok(json!({"registered":false,"reason":"disabled"}));
        }
        let mut body = json!({"platform":platform,"token":token,"environment":environment});
        // The device model the person sees in their device list.
        if let Some(name) = args
            .get("name")
            .and_then(Value::as_str)
            .filter(|n| !n.trim().is_empty())
        {
            body["name"] = json!(name);
        }
        let server = server_url(&self.vault.profiles[index].server)?;
        let mut installation = self.vault.profiles[index]
            .push_installation
            .clone()
            .unwrap_or_else(|| candidate.to_string());
        loop {
            let url = endpoint(&server, &format!("api/me/push-devices/{installation}"));
            let (status, data) = self.send(index, "PUT", url, Some(body.clone()), host)?;
            let rotate = installation != candidate
                && (status == 409 || (status == 410 && data["reason"] == "retired"));
            if rotate {
                installation = candidate.to_string();
                continue;
            }
            let (saved, enabled, result) = match status {
                200..=299 => (
                    Some(installation),
                    true,
                    json!({"registered":true,"registration_id":data["registration_id"]}),
                ),
                410 if data["reason"] != "retired" => {
                    (None, false, json!({"registered":false,"reason":"removed"}))
                }
                // `successful` reads 409 as a busy thread; here it's a registration the server refused.
                409 => return Err("Server request failed"),
                _ => return successful((status, data)).map(|_| Value::Null),
            };
            self.save_push(index, saved, enabled, host)?;
            return Ok(result);
        }
    }

    /// Turns notifications on or off for the active profile on this device, as
    /// the shipping app's Notifications switch does. Turning them on only
    /// records the choice: the edge then asks for permission and registers the
    /// token. Turning them off unregisters the installation first, so turning
    /// them back on registers a new one; if the server can't be told, they stay
    /// on so the person can try again.
    fn push_enable(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let enabled = args
            .get("enabled")
            .and_then(Value::as_bool)
            .ok_or("Missing required argument")?;
        let mut installation = self.vault.profiles[index].push_installation.clone();
        if !enabled && let Some(id) = installation.take() {
            let url = endpoint(
                &server_url(&self.vault.profiles[index].server)?,
                &format!("api/me/push-devices/{id}"),
            );
            match self.send(index, "DELETE", url, None, host)? {
                // Already gone, such as after removing it from the device list elsewhere.
                (404, _) => {}
                response => {
                    successful(response)?;
                }
            }
        }
        self.save_push(index, installation, enabled, host)?;
        Ok(Value::Null)
    }

    fn save_push(
        &mut self,
        index: usize,
        installation: Option<String>,
        enabled: bool,
        host: &mut dyn Host,
    ) -> Result<()> {
        let profile = &mut self.vault.profiles[index];
        if profile.push_installation != installation || profile.push_enabled != enabled {
            profile.push_installation = installation;
            profile.push_enabled = enabled;
            // Not a selection change: the generation stays, so screens keep their state.
            self.dirty = true;
            write(host, &self.vault)?;
            self.dirty = false;
        }
        Ok(())
    }

    /// Registers the threads Live Activity the edge started, `id` (the edge's
    /// lowercase UUID for it) with its ActivityKit push `token`, for the active
    /// profile at `/api/me/thread-live-activities/{id}`. The server then pushes
    /// the activity's content itself. Refreshing the same ID is idempotent.
    /// Returns `{registered:true}`, or `{registered:false,reason}`: `retired`
    /// (the edge ends the activity and starts another with a new ID) or
    /// `unavailable` (a server from before Live Activities).
    fn live_activity_register(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let index = self.active()?;
        let id = text(args, "id")?;
        let token = text(args, "token")?;
        let environment = text(args, "environment")?;
        if !is_uuid(id)
            || !matches!(environment, "sandbox" | "production")
            || token.len() < 32
            || token.len() % 2 != 0
            || !token.bytes().all(|b| b.is_ascii_hexdigit())
        {
            return Err("Invalid Live Activity");
        }
        let url = endpoint(
            &server_url(&self.vault.profiles[index].server)?,
            &format!("api/me/thread-live-activities/{id}"),
        );
        let body = json!({"token":token,"environment":environment});
        match self.send(index, "PUT", url, Some(body), host)? {
            (200..=299, _) => Ok(json!({"registered":true})),
            (410, _) => Ok(json!({"registered":false,"reason":"retired"})),
            (404, _) => Ok(json!({"registered":false,"reason":"unavailable"})),
            // `successful` reads 409 as a busy thread; here it's a registration the server refused.
            (409, _) => Err("Server request failed"),
            response => successful(response).map(|_| Value::Null),
        }
    }

    /// Retires Live Activity `id` on the server, best effort, for the profile
    /// `profile_id` that registered it (the active one when omitted), such as
    /// when the edge ends the activity because that profile signed out or is no
    /// longer active. Returns `{unregistered}`; the server also retires it when
    /// the sign-in ends or the activity expires.
    fn live_activity_unregister(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let id = text(args, "id")?;
        if !is_uuid(id) {
            return Err("Invalid Live Activity");
        }
        let index = match args.get("profile_id").and_then(Value::as_str) {
            Some(profile) => self
                .vault
                .profiles
                .iter()
                .position(|p| p.id == profile)
                .ok_or("Unknown profile")?,
            None => self.active()?,
        };
        let url = endpoint(
            &server_url(&self.vault.profiles[index].server)?,
            &format!("api/me/thread-live-activities/{id}"),
        );
        let unregistered = matches!(
            self.send(index, "DELETE", url, None, host),
            Ok((200..=299 | 404, _))
        );
        Ok(json!({"unregistered":unregistered}))
    }

    /// Registers this device's ActivityKit push-to-start `token` for the active
    /// profile at `/api/me/thread-live-activity-starter`, with the profile's ID,
    /// which the server puts in the attributes of the activities it starts. The
    /// server then starts the threads Live Activity when a thread starts working
    /// and the sign-in has none. Returns `{registered:true}`, or
    /// `{registered:false,reason:"unavailable"}` on a server without it (404).
    fn live_activity_starter_register(
        &mut self,
        args: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        let index = self.active()?;
        let token = text(args, "token")?;
        let environment = text(args, "environment")?;
        if !matches!(environment, "sandbox" | "production")
            || token.len() < 32
            || token.len() % 2 != 0
            || !token.bytes().all(|b| b.is_ascii_hexdigit())
        {
            return Err("Invalid Live Activity");
        }
        let profile = &self.vault.profiles[index];
        let url = endpoint(
            &server_url(&profile.server)?,
            "api/me/thread-live-activity-starter",
        );
        let body = json!({"token":token,"environment":environment,"profile_id":profile.id});
        match self.send(index, "PUT", url, Some(body), host)? {
            (200..=299, _) => Ok(json!({"registered":true})),
            (404, _) => Ok(json!({"registered":false,"reason":"unavailable"})),
            response => successful(response).map(|_| Value::Null),
        }
    }

    /// Forgets the push-to-start token of `profile_id` (the active profile when
    /// omitted) on its server, best effort, before it signs out or when the
    /// device moves to another profile. Returns `{unregistered}`; a 404 counts
    /// as done.
    fn live_activity_starter_unregister(
        &mut self,
        args: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        let index = match args.get("profile_id").and_then(Value::as_str) {
            Some(profile) => self
                .vault
                .profiles
                .iter()
                .position(|p| p.id == profile)
                .ok_or("Unknown profile")?,
            None => self.active()?,
        };
        let url = endpoint(
            &server_url(&self.vault.profiles[index].server)?,
            "api/me/thread-live-activity-starter",
        );
        let unregistered = matches!(
            self.send(index, "DELETE", url, None, host),
            Ok((200..=299 | 404, _))
        );
        Ok(json!({"unregistered":unregistered}))
    }

    /// Best effort before sign-out, which doesn't revoke the grant: a
    /// registration the server wasn't told about stays live for as long as the
    /// grant could be refreshed. Returns whether this device is unregistered,
    /// so the edge can invalidate its device token when it isn't.
    fn push_unregister(&mut self, host: &mut dyn Host) -> bool {
        let Ok(index) = self.active() else {
            return true;
        };
        let Some(installation) = self.vault.profiles[index].push_installation.clone() else {
            return true;
        };
        let Ok(server) = server_url(&self.vault.profiles[index].server) else {
            return false;
        };
        let url = endpoint(&server, &format!("api/me/push-devices/{installation}"));
        matches!(
            self.send(index, "DELETE", url, None, host),
            Ok((200..=299 | 404, _))
        )
    }

    /// Opens what a tapped notification points at: a server-scoped Luft URL and
    /// the handle of the account it belongs to. Switches to the saved profile on
    /// that server that has the account, and to the account, before navigating,
    /// preferring the active profile. Signed out, the link waits for sign-in like
    /// any other. It never signs in or reaches an account no profile has.
    fn open_notification(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        let value = text(args, "url")?;
        let link = crate::navigation::Link::parse(value)?;
        if link.server().is_none() {
            return Err("Invalid notification");
        }
        let account = args.get("account").and_then(Value::as_str);
        // Threads are visible only to their owner, so only the owner's profile can open one.
        let user = args.get("user").and_then(Value::as_str);
        if self.vault.active_profile_id.is_none() {
            self.navigation.receive(value, None)?;
            return Ok(Value::Null);
        }
        let owns = |p: &Profile| {
            !p.rejected
                && !p.memberships_rejected
                && server_url(&p.server).is_ok_and(|server| link.resolve(&server).is_ok())
                && user.is_none_or(|u| p.handle == u)
                && account.is_none_or(|a| p.handle == a || p.organizations.iter().any(|o| o == a))
        };
        let profiles = &self.vault.profiles;
        let index = profiles
            .iter()
            .position(|p| Some(&p.id) == self.vault.active_profile_id.as_ref() && owns(p))
            .or_else(|| profiles.iter().position(owns))
            .ok_or("This notification belongs to an account that isn't signed in")?;
        let mut next = self.vault.clone();
        let profile = &mut next.profiles[index];
        if let Some(account) = account {
            profile.organization = (account != profile.handle).then(|| account.to_string());
        }
        next.active_profile_id = Some(profile.id.clone());
        let server = server_url(&profile.server)?;
        self.commit(next, host)?;
        self.navigation.receive(value, Some(&server))?;
        Ok(Value::Null)
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

/// The platform's WebSocket, reached through `socket_*` host actions.
struct HostSocket<'a> {
    host: &'a mut dyn Host,
}

impl crate::Socket for HostSocket<'_> {
    fn open(&mut self, url: &Url, protocols: &[String]) -> Result<()> {
        let response = action(
            self.host,
            json!({"type":"socket_open","url":url.as_str(),"protocols":protocols}),
        )?;
        if response["ok"] == true {
            Ok(())
        } else {
            Err("Native operation failed")
        }
    }

    fn send(&mut self, text: &str) -> Result<()> {
        action(self.host, json!({"type":"socket_send","text":text})).map(|_| ())
    }

    fn read(&mut self) -> Result<(Vec<String>, bool)> {
        let response = action(self.host, json!({"type":"socket_read"}))?;
        let frames = response["frames"]
            .as_array()
            .ok_or("Native operation failed")?
            .iter()
            .filter_map(|f| f.as_str().map(str::to_string))
            .collect();
        Ok((frames, response["closed"] == true))
    }

    fn close(&mut self) {
        let _ = action(self.host, json!({"type":"socket_close"}));
    }
}

/// The active profile's credentials, refreshed before each request.
struct Authorized<'a> {
    client: &'a mut MobileClient,
    index: usize,
    host: &'a mut dyn Host,
}

impl Transport for Authorized<'_> {
    fn send(&mut self, method: &str, url: Url, body: Option<Value>) -> Result<(u64, Value)> {
        self.client.send(self.index, method, url, body, self.host)
    }
}

/// Opens a profile's store, logging the migrations it ran.
fn open_store(
    directory: &str,
    profile: &str,
    host: &mut dyn Host,
) -> Result<(Store, Vec<&'static str>)> {
    let files = store::files(directory, profile)?;
    let (store, migrated) = Store::open(files.last().expect("the database file"))?;
    for name in &migrated {
        log(host, &format!("store {profile}: migrated {name}"));
    }
    Ok((store, migrated))
}

/// Tells the host what the core is doing, for its system log. Messages never
/// carry tokens or server text; a host that can't log is ignored.
fn log(host: &mut dyn Host, message: &str) {
    let _ = host.perform(json!({"type":"log","message":message}));
}

/// Where the host keeps local stores: Application Support on Apple
/// platforms, no-backup files on Android, an OPFS directory in the browser.
fn store_directory(host: &mut dyn Host) -> Result<String> {
    let response =
        action(host, json!({"type":"store_directory"})).map_err(|_| "Could not read local data")?;
    response["path"]
        .as_str()
        .map(str::to_string)
        .ok_or("Could not read local data")
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

/// Earlier macOS builds used the Tuist app's Keychain session for some profiles
/// (`shared`, stored without tokens) and remembered the ones signed out here
/// (`unlinked`). Those profiles are dropped, so their users sign in to Luft
/// once; the Tuist app's session is never read or changed. Returns whether the
/// vault changed and must be written back.
fn migrate(value: &str) -> Result<(Vault, bool)> {
    let mut raw: Value = serde_json::from_str(value).map_err(|_| "Invalid private vault")?;
    let mut migrated = raw
        .as_object_mut()
        .and_then(|vault| vault.remove("unlinked"))
        .is_some();
    if let Some(profiles) = raw.get_mut("profiles").and_then(Value::as_array_mut) {
        let count = profiles.len();
        profiles.retain(|p| {
            p.get("shared").is_none_or(Value::is_null)
                && p["access"].as_str().is_some_and(|token| {
                    Claims::parse(token).is_ok_and(|claims| claims.iss.as_deref() == Some("luft"))
                })
        });
        migrated |= profiles.len() != count;
    }
    let mut vault: Vault = serde_json::from_value(raw).map_err(|_| "Invalid private vault")?;
    if migrated
        && !vault
            .profiles
            .iter()
            .any(|p| Some(&p.id) == vault.active_profile_id.as_ref())
    {
        vault.active_profile_id = vault
            .profiles
            .iter()
            .find(|p| !p.rejected && !p.memberships_rejected)
            .map(|p| p.id.clone());
    }
    Ok((vault, migrated))
}

fn now() -> Result<i64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "Clock unavailable")?
        .as_secs() as i64)
}

/// The identity, handle, and email a profile shows for an access token.
fn identify(access: &str) -> Result<(String, String, String)> {
    let claims = Claims::parse(access).map_err(|_| "Invalid token identity")?;
    if claims.iss.as_deref() != Some("luft") {
        return Err("Sign in through a Luft server");
    }
    let identity = claims.identity().ok_or("Invalid token identity")?;
    let handle = claims
        .preferred_username
        .filter(|v| segment(v))
        .ok_or("Invalid token identity")?;
    let email = claims.email.ok_or("Invalid token identity")?;
    Ok((identity, handle, email))
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
    let response = host
        .perform(request)
        .map_err(|_| "Native operation failed")?;
    if response["error"] == "offline" {
        return Err(OFFLINE);
    }
    if response.get("error").is_some() {
        return Err("Native operation failed");
    }
    let status = response["status"].as_u64().ok_or("Invalid HTTP response")?;
    let body = response["body"].as_str().ok_or("Invalid HTTP response")?;
    let data = if body.is_empty() {
        Value::Null
    } else {
        serde_json::from_str(body).unwrap_or(Value::Null)
    };
    Ok((status, data))
}

pub(crate) const NOT_FOUND: &str = "Resource not found or server unsupported";
const UNSUPPORTED_SERVER: &str =
    "This server doesn't support signing in from Luft; ask your administrator to update it";
const BUSY: &str = "The thread is busy; try again when it finishes";
const REFUSED: &str = "The server refused the request";
const RUNNER_NEEDS_NETWORK: &str = "Connect to the internet to start a thread on a runner";
pub(crate) fn successful((status, data): (u64, Value)) -> Result<Value> {
    match status {
        200..=299 => Ok(data),
        400 | 422 => Err(REFUSED),
        401 | 403 => Err("Access denied"),
        404 => Err(NOT_FOUND),
        409 => Err(BUSY),
        _ => Err("Server request failed"),
    }
}

/// Whether a queued write that failed with `error` may succeed later, so the
/// flush stops and keeps it, rather than marking it failed. Only answers that
/// say the write itself is wrong (refused, not found, threads off, no model)
/// fail it.
fn retryable(error: &str) -> bool {
    matches!(
        error,
        OFFLINE
            | BUSY
            | "Server request failed"
            | "Native operation failed"
            | "Token service unavailable"
            | "Access denied"
            | "Credentials rejected"
            | "Sign in required"
            | "Could not save private vault"
    )
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
pub(crate) fn text<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v.get(key)
        .and_then(Value::as_str)
        .filter(|v| !v.trim().is_empty())
        .ok_or("Missing required argument")
}
/// A lowercase hyphenated UUID, as the server's installation IDs are.
fn is_uuid(v: &str) -> bool {
    v.len() == 36
        && v.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
            }
        })
}
pub(crate) fn segment(v: &str) -> bool {
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
