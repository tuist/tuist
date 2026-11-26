use std::collections::BTreeSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use gpui::{
    Context, Div, Entity, Focusable, FontWeight, IntoElement, Render, ScrollHandle, SharedString,
    Subscription, Task, Window, div, prelude::*, px,
};
use serde_json::{Value, json};
use tuist_app_core::navigation::Destination;
use tuist_app_core::{Lounges, Presence, organizations};
use tuist_navigation::{Navigation, Route, Tab};
use tuist_session::Session;

use super::socket::WebSocket;
use super::threads::Http;
use crate::components::{Button, Variant, chat_message, composer, presence_dot};
use crate::input::{Submitted, TextInput};
use crate::theme::Theme;

/// How often a visible lounge, or the visible list, rereads the server, a
/// failed organization lookup retries, and presence catches up.
const POLL: Duration = Duration::from_secs(3);

/// Which organization Lounges and DMs show, whether the window is in front,
/// and who in that organization has Luft open. The desktop account
/// menu selects profiles, not organizations, so both panels share this
/// choice: the person's first organization, until they pick another.
pub struct Scope {
    session: Arc<Session>,
    handle: Option<String>,
    organizations: Vec<String>,
    selected: Option<String>,
    loaded: bool,
    error: Option<SharedString>,
    /// The lookup in flight, or the pause before retrying a failed one.
    task: Option<Task<()>>,
    /// The window is active: only then do panels poll and mark messages
    /// read, and the person shows online.
    active: bool,
    /// The online user IDs while presence is joined; otherwise `None`, and
    /// the server's `online` in each response stands.
    online: Option<BTreeSet<u64>>,
    presence: Arc<Live>,
    watching: Option<Task<()>>,
    _activation: Subscription,
}

/// The core's presence and the socket it drives. `wanted` turns false as
/// soon as the window deactivates, so a poll that was already queued leaves
/// presence instead of rejoining.
#[derive(Default)]
struct Live {
    wanted: AtomicBool,
    state: Mutex<(Presence, WebSocket)>,
}

impl Live {
    fn disconnect(&self) {
        let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        if !self.wanted.load(Ordering::SeqCst) {
            let (presence, socket) = &mut *state;
            presence.disconnect(socket);
        }
    }
}

impl Scope {
    pub fn new(
        session: Arc<Session>,
        handle: Option<String>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let mut scope = Self {
            session,
            handle,
            organizations: Vec::new(),
            selected: None,
            loaded: false,
            error: None,
            task: None,
            active: window.is_window_active(),
            online: None,
            presence: Arc::default(),
            watching: None,
            _activation: cx.observe_window_activation(window, |this, window, cx| {
                this.active = window.is_window_active();
                this.activity(cx);
            }),
        };
        scope.activity(cx);
        scope
    }

    /// Joins presence while the window is active, and leaves it otherwise.
    fn activity(&mut self, cx: &mut Context<Self>) {
        if self.active {
            self.load(cx);
            self.watch(cx);
        } else {
            self.watching = None;
            self.online = None;
            self.presence.wanted.store(false, Ordering::SeqCst);
            let presence = self.presence.clone();
            cx.background_executor()
                .spawn(async move { presence.disconnect() })
                .detach();
        }
        cx.notify();
    }

    /// Looks the organizations up, unless they are known or a lookup is
    /// pending. A failed lookup retries after a pause while the window is
    /// active, or right away from Refresh.
    fn load(&mut self, cx: &mut Context<Self>) {
        if self.loaded || self.task.is_some() {
            return;
        }
        let session = self.session.clone();
        let work = cx
            .background_executor()
            .spawn(async move { organizations(session.server(), &mut Http { session: &session }) });
        self.task = Some(cx.spawn(async move |this, cx| {
            let result = work.await;
            let failed = this
                .update(cx, |this, cx| {
                    let failed = match result {
                        Ok(names) => {
                            this.loaded = true;
                            this.error = None;
                            this.selected = names.first().cloned();
                            this.organizations = names;
                            this.watch(cx);
                            false
                        }
                        Err(error) => {
                            this.error = Some(error.into());
                            true
                        }
                    };
                    cx.notify();
                    failed
                })
                .unwrap_or(false);
            if failed {
                cx.background_executor().timer(POLL).await;
                let _ = this.update(cx, |this, cx| {
                    this.task = None;
                    if this.active {
                        this.load(cx);
                    }
                });
            }
        }));
    }

    /// Retries a failed lookup now.
    fn retry(&mut self, cx: &mut Context<Self>) {
        self.task = None;
        self.error = None;
        self.load(cx);
        cx.notify();
    }

    /// Keeps presence joined in the selected organization, every `POLL`,
    /// while the window is active. It follows organization changes.
    fn watch(&mut self, cx: &mut Context<Self>) {
        if !self.active || !self.loaded || self.watching.is_some() {
            return;
        }
        let session = self.session.clone();
        let live = self.presence.clone();
        live.wanted.store(true, Ordering::SeqCst);
        self.watching = Some(cx.spawn(async move |this, cx| {
            loop {
                let Ok(Some(handle)) = this.update(cx, |this, _| this.selected.clone()) else {
                    return;
                };
                let (session, live) = (session.clone(), live.clone());
                let state = cx.background_executor().spawn(async move {
                    let mut state = live.state.lock().unwrap_or_else(PoisonError::into_inner);
                    if !live.wanted.load(Ordering::SeqCst) {
                        return None;
                    }
                    let (presence, socket) = &mut *state;
                    let now = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .map_or(0, |d| d.as_secs() as i64);
                    presence
                        .poll(
                            session.server(),
                            &handle,
                            &mut || {
                                session
                                    .access_token()
                                    .map_err(|_| "Sign in again to continue")
                            },
                            socket,
                            now,
                        )
                        .ok()
                });
                let state = state.await;
                let online = state.filter(|s| s["connected"] == true).map(|s| {
                    s["online"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|p| p["id"].as_u64())
                        .collect()
                });
                let updated = this.update(cx, |this, cx| {
                    if this.online != online {
                        this.online = online;
                        cx.notify();
                    }
                });
                if updated.is_err() {
                    return;
                }
                cx.background_executor().timer(POLL).await;
            }
        }));
    }

    /// The selected organization's handle, if one is selected.
    pub fn organization(&self) -> Option<String> {
        self.selected.clone()
    }

    /// The account the core's lounge operations run in, and whether it is an
    /// organization. Without one, the core explains that lounges need one.
    fn account(&self) -> Option<(String, bool)> {
        match &self.selected {
            Some(organization) => Some((organization.clone(), true)),
            None => self.handle.clone().map(|handle| (handle, false)),
        }
    }

    /// Whether `person` has Luft open: the live presence while it is
    /// joined, otherwise what the server answered.
    fn online(&self, person: &Value) -> bool {
        match (&self.online, person["id"].as_u64()) {
            (Some(online), Some(id)) => online.contains(&id),
            _ => person["online"] == true,
        }
    }
}

impl Drop for Scope {
    /// Signing out or switching accounts replaces the workspace: leave
    /// presence so the person shows offline.
    fn drop(&mut self) {
        self.presence.wanted.store(false, Ordering::SeqCst);
        let presence = self.presence.clone();
        let _ = std::thread::Builder::new()
            .name("presence-disconnect".into())
            .spawn(move || presence.disconnect());
    }
}

/// A message time: the time alone for today, otherwise the date too. The
/// server sends UTC and the desktop has no time zone database, so it says so.
fn time(value: &str) -> String {
    let (date, rest) = value.split_once('T').unwrap_or((value, ""));
    let clock = rest.get(..5).unwrap_or(rest);
    let days = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() / 86_400)
        .unwrap_or_default();
    // Howard Hinnant's civil_from_days.
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    if date == format!("{year:04}-{month:02}-{day:02}") {
        format!("{clock} UTC")
    } else {
        format!("{date} {clock} UTC")
    }
}

/// A presence dot at the start of a list row, which leaves room for it.
fn dot(id: String) -> gpui::Stateful<Div> {
    presence_dot(SharedString::from(id))
        .absolute()
        .left(px(10.))
        .top(px(12.))
}

/// An organization's lounges (`Tab::Lounges`) or the person's direct
/// conversations (`Tab::Dms`): conversations between people, with no agent.
pub struct LoungesPanel {
    tab: Tab,
    session: Arc<Session>,
    scope: Entity<Scope>,
    navigation: Entity<Navigation>,
    /// The account the shown list and conversation belong to.
    account: Option<String>,
    route_id: Option<String>,
    /// Shown in the active window: only then does it poll and mark read.
    visible: bool,
    /// Writes only: it keeps their idempotency key across retries. Reads
    /// each use their own, so they never wait behind a send.
    lounges: Arc<Mutex<Lounges>>,
    list: Vec<Value>,
    /// Why the core reports lounges unavailable, if it does.
    reason: Option<String>,
    loaded: bool,
    open: Option<Value>,
    /// The highest position this panel has marked read.
    read: u64,
    error: Option<SharedString>,
    busy: bool,
    /// New lounge, or New message's people picker, is showing.
    composing: bool,
    people: Option<Vec<Value>>,
    chosen: Vec<u64>,
    /// The form that created a conversation is gone; focus its composer
    /// once it shows.
    focus_reply: bool,
    name: Entity<TextInput>,
    topic: Entity<TextInput>,
    reply: Entity<TextInput>,
    scroll: ScrollHandle,
    task: Option<Task<()>>,
    refresh: Option<Task<()>>,
    poll: Option<Task<()>>,
    _subscriptions: Vec<Subscription>,
}

impl LoungesPanel {
    pub fn new(
        tab: Tab,
        session: Arc<Session>,
        scope: Entity<Scope>,
        navigation: Entity<Navigation>,
        cx: &mut Context<Self>,
    ) -> Self {
        let name = cx.new(|cx| TextInput::new("Name, for example releases", cx));
        let topic = cx.new(|cx| TextInput::new("Topic (optional)", cx));
        let reply = cx.new(|cx| TextInput::new("Message", cx));
        let subscriptions = vec![
            cx.observe(&navigation, |this, _, cx| this.sync(cx)),
            cx.observe(&scope, |this, _, cx| {
                this.sync(cx);
                cx.notify();
            }),
            cx.subscribe(&name, |this, _, _: &Submitted, cx| this.create(cx)),
            cx.subscribe(&topic, |this, _, _: &Submitted, cx| this.create(cx)),
            cx.subscribe(&reply, |this, _, _: &Submitted, cx| this.send(cx)),
        ];
        let mut panel = Self {
            tab,
            session,
            scope,
            navigation,
            account: None,
            route_id: None,
            visible: false,
            lounges: Arc::new(Mutex::new(Lounges::new())),
            list: Vec::new(),
            reason: None,
            loaded: false,
            open: None,
            read: 0,
            error: None,
            busy: false,
            composing: false,
            people: None,
            chosen: Vec::new(),
            focus_reply: false,
            name,
            topic,
            reply,
            scroll: ScrollHandle::new(),
            task: None,
            refresh: None,
            poll: None,
            _subscriptions: subscriptions,
        };
        panel.sync(cx);
        panel
    }

    fn noun(&self) -> &'static str {
        if self.tab == Tab::Lounges {
            "Lounges"
        } else {
            "DMs"
        }
    }

    fn route(&self, cx: &Context<Self>) -> Option<String> {
        let luft = &self.navigation.read(cx).luft;
        if self.tab == Tab::Lounges {
            luft.lounge_id.clone()
        } else {
            luft.dm_id.clone()
        }
    }

    /// Follows navigation, the chosen organization and window activation:
    /// loads what became visible, and stops polling what is hidden.
    fn sync(&mut self, cx: &mut Context<Self>) {
        let navigation = self.navigation.read(cx);
        let scope = self.scope.read(cx);
        let visible = navigation.tab == self.tab && navigation.preview.is_none() && scope.active;
        if !scope.loaded {
            if visible {
                self.scope.update(cx, |scope, cx| scope.load(cx));
            }
            return;
        }
        let account = scope.account().map(|(handle, _)| handle);
        let id = self.route(cx);
        let appeared = visible && !self.visible;
        self.visible = visible;
        let switched = account != self.account;
        if switched {
            self.account = account;
            self.list.clear();
            self.loaded = false;
            self.open = None;
            self.composing = false;
            self.people = None;
        }
        if !visible {
            self.poll = None;
            self.refresh = None;
            return;
        }
        if !appeared && !switched && id == self.route_id {
            return;
        }
        if self.open.as_ref().and_then(|h| h["id"].as_str()) != id.as_deref() {
            self.open = None;
            self.read = 0;
            self.reply
                .update(cx, |input, cx| input.set_value(String::new(), cx));
        }
        self.route_id = id.clone();
        self.poll = None;
        match id {
            Some(id) => self.request("lounge", json!({ "id": id }), false, cx),
            None => self.request("lounges", json!({}), false, cx),
        }
    }

    fn navigate(&mut self, destination: Destination, cx: &mut Context<Self>) {
        self.navigation.update(cx, |nav, cx| {
            nav.navigate(Route::Luft(destination));
            cx.notify();
        });
    }

    fn open_conversation(&mut self, id: String, window: &mut Window, cx: &mut Context<Self>) {
        self.navigate(Destination::Conversation(self.tab.id(), id), cx);
        // The row that opened it is gone; the composer is where to continue.
        window.focus(&self.reply.focus_handle(cx), cx);
    }

    /// Choosing another organization closes both tabs' conversations, which
    /// belong to the previous one, and stays on this tab.
    fn choose(&mut self, organization: String, cx: &mut Context<Self>) {
        let other = if self.tab == Tab::Lounges {
            Tab::Dms
        } else {
            Tab::Lounges
        };
        self.navigation.update(cx, |nav, cx| {
            for tab in [other, self.tab] {
                nav.navigate(Route::Luft(Destination::List(tab.id())));
            }
            cx.notify();
        });
        self.scope.update(cx, |scope, cx| {
            scope.selected = Some(organization);
            cx.notify();
        });
    }

    /// Runs one core operation off the UI thread. A quiet request is a
    /// background refresh: it neither blocks controls nor reports errors.
    fn request(
        &mut self,
        operation: &'static str,
        args: Value,
        quiet: bool,
        cx: &mut Context<Self>,
    ) {
        let Some((handle, organization)) = self.scope.read(cx).account() else {
            self.error = Some("This account has no handle to own lounges.".into());
            return cx.notify();
        };
        if !quiet {
            self.busy = true;
            self.error = None;
        }
        let session = self.session.clone();
        let lounges = matches!(
            operation,
            "send_lounge_message" | "create_lounge" | "start_direct"
        )
        .then(|| self.lounges.clone());
        let revision = self.navigation.read(cx).luft.revision;
        let account = handle.clone();
        let work = cx.background_executor().spawn(async move {
            let mut fresh = Lounges::new();
            let mut shared = match &lounges {
                Some(lounges) => Some(lounges.lock().map_err(|_| "Lounges are unavailable")?),
                None => None,
            };
            shared.as_deref_mut().unwrap_or(&mut fresh).call(
                session.server(),
                &handle,
                organization,
                operation,
                &args,
                &mut Http { session: &session },
            )
        });
        let task = cx.spawn(async move |this, cx| {
            let result = work.await;
            let _ = this.update(cx, |this, cx| {
                if !quiet {
                    this.busy = false;
                }
                // A result for the previous organization doesn't belong here.
                if this.account.as_deref() == Some(account.as_str()) {
                    this.finish(operation, result, quiet, revision, cx);
                }
                cx.notify();
            });
        });
        if quiet {
            self.refresh = Some(task);
        } else {
            self.task = Some(task);
        }
        cx.notify();
    }

    fn finish(
        &mut self,
        operation: &'static str,
        result: Result<Value, &'static str>,
        quiet: bool,
        revision: u64,
        cx: &mut Context<Self>,
    ) {
        let data = match result {
            Ok(data) => data,
            Err(error) => {
                if !quiet {
                    self.error = Some(error.into());
                }
                // Keep trying while visible, as when the connection drops.
                if quiet || matches!(operation, "lounge" | "lounges") {
                    self.schedule(cx);
                }
                return;
            }
        };
        match operation {
            "lounges" => {
                self.loaded = true;
                self.reason = (data["available"] == false)
                    .then(|| data["reason"].as_str().unwrap_or("disabled").to_owned());
                let key = if self.tab == Tab::Lounges {
                    "lounges"
                } else {
                    "directs"
                };
                self.list = data[key].as_array().cloned().unwrap_or_default();
                if self.route_id.is_none() {
                    self.schedule(cx);
                }
            }
            "lounge_people" => {
                self.people = Some(data["people"].as_array().cloned().unwrap_or_default());
            }
            "create_lounge" | "start_direct" => {
                for input in [&self.name, &self.topic] {
                    input.update(cx, |input, cx| input.set_value(String::new(), cx));
                }
                self.composing = false;
                self.chosen.clear();
                // Creating a conversation is not permission to replace a
                // destination selected while the request was in flight.
                if revision != self.navigation.read(cx).luft.revision {
                    return;
                }
                if let Some(id) = data["id"].as_str().map(str::to_owned) {
                    self.focus_reply = true;
                    self.route_id = Some(id.clone());
                    self.navigate(Destination::Conversation(self.tab.id(), id), cx);
                    self.show(data, cx);
                }
            }
            "lounge" | "send_lounge_message" => {
                if data["id"].as_str() != self.route_id.as_deref() {
                    return;
                }
                if operation == "send_lounge_message" {
                    self.reply
                        .update(cx, |input, cx| input.set_value(String::new(), cx));
                }
                self.show(data, cx);
            }
            _ => {}
        }
    }

    /// Shows a conversation, marks what it shows read, and keeps it current.
    fn show(&mut self, lounge: Value, cx: &mut Context<Self>) {
        let grew = self.open.as_ref().is_none_or(|open| {
            open["id"] != lounge["id"] || open["messages"] != lounge["messages"]
        });
        let last = lounge["last_position"].as_u64().unwrap_or_default();
        let read = lounge["read_position"].as_u64().unwrap_or_default();
        let id = lounge["id"].as_str().map(str::to_owned);
        // A retry that finally opened the conversation supersedes the failure
        // it retried; a failed send stays visible.
        if self.open.is_none() {
            self.error = None;
        }
        self.open = Some(lounge);
        if grew {
            self.scroll.scroll_to_bottom();
        }
        if let Some(id) = id
            && self.visible
            && last > read.max(self.read)
        {
            self.read = last;
            self.request_read(id, last, cx);
        }
        self.schedule(cx);
    }

    /// Moves the read position forward; nothing waits for it.
    fn request_read(&mut self, id: String, position: u64, cx: &mut Context<Self>) {
        let Some((handle, organization)) = self.scope.read(cx).account() else {
            return;
        };
        let session = self.session.clone();
        cx.background_executor()
            .spawn(async move {
                let _ = Lounges::new().call(
                    session.server(),
                    &handle,
                    organization,
                    "read_lounge",
                    &json!({ "id": id, "position": position }),
                    &mut Http { session: &session },
                );
            })
            .detach();
    }

    /// Rereads the visible conversation, or the visible list, after a pause.
    fn schedule(&mut self, cx: &mut Context<Self>) {
        if !self.visible {
            return;
        }
        let route = self.route_id.clone();
        self.poll = Some(cx.spawn(async move |this, cx| {
            cx.background_executor().timer(POLL).await;
            let _ = this.update(cx, |this, cx| {
                if !this.visible || this.route_id != route {
                    return;
                }
                if this.busy {
                    return this.schedule(cx);
                }
                match route {
                    Some(id) => this.request("lounge", json!({ "id": id }), true, cx),
                    None => this.request("lounges", json!({}), true, cx),
                }
            });
        }));
    }

    fn compose(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.composing = true;
        self.error = None;
        if self.tab == Tab::Lounges {
            window.focus(&self.name.focus_handle(cx), cx);
        } else {
            self.chosen.clear();
            self.request("lounge_people", json!({}), false, cx);
        }
        cx.notify();
    }

    fn cancel(&mut self, cx: &mut Context<Self>) {
        self.composing = false;
        self.chosen.clear();
        cx.notify();
    }

    fn create(&mut self, cx: &mut Context<Self>) {
        let name = self.name.read(cx).value().trim().to_owned();
        let topic = self.topic.read(cx).value().trim().to_owned();
        if !self.busy && self.composing && !name.is_empty() {
            let args = json!({ "name": name, "topic": topic });
            self.request("create_lounge", args, false, cx);
        }
    }

    fn start(&mut self, cx: &mut Context<Self>) {
        if !self.busy && (1..=7).contains(&self.chosen.len()) {
            let args = json!({ "user_ids": self.chosen });
            self.request("start_direct", args, false, cx);
        }
    }

    fn send(&mut self, cx: &mut Context<Self>) {
        let content = self.reply.read(cx).value().trim().to_owned();
        let Some(id) = self.open.as_ref().and_then(|h| h["id"].as_str()) else {
            return;
        };
        if !self.busy && !content.is_empty() {
            let args = json!({ "id": id, "content": content });
            self.request("send_lounge_message", args, false, cx);
        }
    }

    /// The organization these conversations belong to, with a choice when
    /// the person has several.
    fn organizations(&self, theme: Theme, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let scope = self.scope.read(cx);
        let selected = scope.selected.clone();
        let names = scope.organizations.clone();
        let mut row = div().flex().flex_wrap().items_center().gap_2();
        if names.len() > 1 {
            row = row.child(div().text_color(theme.text_muted).child("Organization"));
            for name in names {
                let current = selected.as_deref() == Some(name.as_str());
                let choice = name.clone();
                row = row.child(
                    Button::new(
                        SharedString::from(format!("{}-organization-{name}", self.tab.id())),
                        name,
                        if current {
                            Variant::Primary
                        } else {
                            Variant::Secondary
                        },
                    )
                    .enabled(!self.busy && !current)
                    .render(
                        Some(&self.scroll),
                        window,
                        cx,
                        move |this, _, cx| this.choose(choice.clone(), cx),
                    ),
                );
            }
        }
        row
    }

    fn unavailable(&self, reason: &str) -> gpui::Text {
        match reason {
            "personal" => gpui::text!(if self.tab == Tab::Lounges {
                "Lounges belong to organizations. Join or create an organization on Tuist to talk with your team here."
            } else {
                "Direct messages are between members of an organization. Join or create an organization on Tuist to message your team."
            }),
            "sign_in_required" => gpui::text!(
                "Your session is from an earlier version of Luft. Sign out from the account menu and sign in again to use lounges."
            ),
            _ => gpui::text!("Lounges aren't enabled for this organization or server."),
        }
    }

    /// New lounge: a name and an optional topic.
    fn lounge_form(&self, theme: Theme, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let create = Button::new("create-lounge", "Create lounge", Variant::Primary)
            .enabled(!self.busy && !self.name.read(cx).value().trim().is_empty())
            .render(Some(&self.scroll), window, cx, |this, _, cx| {
                this.create(cx)
            });
        let cancel = Button::new("cancel-lounge", "Cancel", Variant::Secondary).render(
            Some(&self.scroll),
            window,
            cx,
            |this, _, cx| this.cancel(cx),
        );
        div()
            .flex()
            .flex_col()
            .gap_2()
            .p_3()
            .rounded_md()
            .border_1()
            .border_color(theme.border)
            .child(
                div()
                    .font_weight(FontWeight::MEDIUM)
                    .child(gpui::text!("New lounge")),
            )
            .child(self.name.clone())
            .child(self.topic.clone())
            .child(div().flex().gap_2().child(create).child(cancel))
    }

    /// New message: pick one to seven of the organization's other members.
    fn people_form(&self, theme: Theme, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let scope = self.scope.read(cx);
        let online: Vec<bool> = self
            .people
            .iter()
            .flatten()
            .map(|p| scope.online(p))
            .collect();
        let mut rows = Vec::new();
        for (person, online) in self.people.iter().flatten().zip(online) {
            let (Some(id), Some(handle)) = (person["id"].as_u64(), person["handle"].as_str())
            else {
                continue;
            };
            let chosen = self.chosen.contains(&id);
            rows.push(
                Button::new(
                    SharedString::from(format!("person-{id}")),
                    format!("@{handle}"),
                    Variant::Ghost,
                )
                .enabled(!self.busy && (chosen || self.chosen.len() < 7))
                .render(Some(&self.scroll), window, cx, move |this, _, cx| {
                    if let Some(index) = this.chosen.iter().position(|c| *c == id) {
                        this.chosen.remove(index);
                    } else if this.chosen.len() < 7 {
                        this.chosen.push(id);
                    }
                    cx.notify();
                })
                .role(gpui::Role::CheckBox)
                .aria_toggled(if chosen {
                    gpui::Toggled::True
                } else {
                    gpui::Toggled::False
                })
                .relative()
                .w_full()
                .pl_6()
                .justify_between()
                .when(chosen, |row| row.bg(theme.row_selected))
                .when(online, |row| row.child(dot(format!("person-{id}-online"))))
                .child(
                    div()
                        .text_color(theme.accent)
                        .child(if chosen { "✓" } else { "" }),
                ),
            );
        }
        let start = Button::new("start-direct", "Start conversation", Variant::Primary)
            .enabled(!self.busy && !self.chosen.is_empty())
            .render(Some(&self.scroll), window, cx, |this, _, cx| this.start(cx));
        let cancel = Button::new("cancel-direct", "Cancel", Variant::Secondary).render(
            Some(&self.scroll),
            window,
            cx,
            |this, _, cx| this.cancel(cx),
        );
        let empty = self.people.as_ref().is_some_and(Vec::is_empty);
        div()
            .flex()
            .flex_col()
            .gap_2()
            .p_3()
            .rounded_md()
            .border_1()
            .border_color(theme.border)
            .child(
                div()
                    .font_weight(FontWeight::MEDIUM)
                    .child(gpui::text!("New message")),
            )
            .child(
                div()
                    .text_color(theme.text_muted)
                    .child(gpui::text!(if empty {
                        "Nobody else is in this organization yet."
                    } else {
                        "Choose up to seven people."
                    })),
            )
            .child(div().flex().flex_col().children(rows))
            .child(div().flex().gap_2().child(start).child(cancel))
    }

    fn inbox(&self, theme: Theme, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let available = self.reason.is_none() && self.loaded;
        let (new_label, about) = if self.tab == Tab::Lounges {
            (
                "New lounge",
                "Lounges are your organization's long-lived conversations. Every member reads and writes them.",
            )
        } else {
            (
                "New message",
                "Direct conversations between you and up to seven people in your organization.",
            )
        };
        let new = Button::new(
            SharedString::from(format!("new-{}", self.tab.id())),
            new_label,
            Variant::Primary,
        )
        .enabled(!self.busy && available && !self.composing)
        .render(Some(&self.scroll), window, cx, |this, window, cx| {
            this.compose(window, cx)
        });
        let refresh = Button::new(
            SharedString::from(format!("refresh-{}", self.tab.id())),
            "Refresh",
            Variant::Secondary,
        )
        .enabled(!self.busy)
        .render(Some(&self.scroll), window, cx, |this, _, cx| {
            if this.scope.read(cx).loaded {
                this.request("lounges", json!({}), false, cx)
            } else {
                this.scope.update(cx, |scope, cx| scope.retry(cx));
            }
        });
        let scope = self.scope.read(cx);
        // A direct conversation shows whether anyone else in it is online.
        let online: Vec<bool> = self
            .list
            .iter()
            .map(|lounge| {
                lounge["members"]
                    .as_array()
                    .is_some_and(|members| members.iter().any(|p| scope.online(p)))
            })
            .collect();
        let mut rows = Vec::new();
        for (lounge, online) in self.list.iter().zip(online) {
            let Some(id) = lounge["id"].as_str().map(str::to_owned) else {
                continue;
            };
            let title = lounge["title"].as_str().unwrap_or_default().to_owned();
            let unread = lounge["unread"].as_u64().unwrap_or_default();
            let online_id = format!("{}-{id}-online", self.tab.id());
            let last = &lounge["last_message"];
            let preview = match (last["author"]["handle"].as_str(), last["body"].as_str()) {
                (Some(author), Some(body)) => {
                    let body = body.lines().next().unwrap_or_default();
                    if last["mine"] == true {
                        format!("You: {body}")
                    } else {
                        format!("{author}: {body}")
                    }
                }
                (None, Some(body)) => body.lines().next().unwrap_or_default().to_owned(),
                _ => lounge["topic"].as_str().unwrap_or_default().to_owned(),
            };
            rows.push(
                Button::new(
                    SharedString::from(format!("{}-{id}", self.tab.id())),
                    title,
                    Variant::Ghost,
                )
                .enabled(!self.busy)
                .render(Some(&self.scroll), window, cx, move |this, window, cx| {
                    this.open_conversation(id.clone(), window, cx)
                })
                .when(unread > 0, |row| {
                    row.font_weight(FontWeight::SEMIBOLD)
                        .aria_description(format!("{unread} unread"))
                })
                .relative()
                .w_full()
                .min_h(px(52.))
                .flex_col()
                .items_start()
                .justify_center()
                .gap_0p5()
                .when(self.tab == Tab::Dms, |row| row.pl_6())
                .pr_12()
                .border_b_1()
                .border_color(theme.border)
                .rounded_none()
                .child(
                    div()
                        .w_full()
                        .truncate()
                        .text_xs()
                        .font_weight(FontWeight::NORMAL)
                        .text_color(theme.text_muted)
                        .child(preview),
                )
                .when(online, |row| row.child(dot(online_id)))
                .when(unread > 0, |row| {
                    row.child(
                        div()
                            .absolute()
                            .right_3()
                            .top(px(18.))
                            .px_1p5()
                            .rounded_full()
                            .bg(theme.accent)
                            .text_color(theme.accent_foreground)
                            .text_xs()
                            .child(unread.to_string()),
                    )
                }),
            );
        }
        let empty = available && self.list.is_empty();
        let scope = self.scope.read(cx);
        let scope_error = scope.error.clone();
        let subject = scope.selected.clone();
        div()
            .flex()
            .flex_col()
            .gap_4()
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .gap_4()
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .text_color(theme.text_muted)
                            .whitespace_normal()
                            .child(gpui::text!(match subject {
                                Some(organization) => format!("{about} In {organization}."),
                                None => about.to_owned(),
                            })),
                    )
                    .child(div().flex().flex_none().gap_2().child(refresh).child(new)),
            )
            .child(self.organizations(theme, window, cx))
            .when_some(scope_error, |column, error| {
                column.child(
                    div()
                        .text_color(theme.error)
                        .child(gpui::text!(error.to_string())),
                )
            })
            .when_some(self.reason.clone(), |column, reason| {
                column.child(self.unavailable(&reason))
            })
            .when(self.composing && available, |column| {
                column.child(if self.tab == Tab::Lounges {
                    self.lounge_form(theme, window, cx)
                } else {
                    self.people_form(theme, window, cx)
                })
            })
            .when(empty && !self.composing, |column| {
                column.child(
                    div()
                        .py_16()
                        .flex()
                        .justify_center()
                        .text_color(theme.text_muted)
                        .child(gpui::text!(if self.tab == Tab::Lounges {
                            "No lounges yet. Start one for your team."
                        } else {
                            "No direct messages yet."
                        })),
                )
            })
            .child(div().flex().flex_col().children(rows))
    }

    fn conversation(&self, lounge: &Value, theme: Theme, cx: &Context<Self>) -> Div {
        let scope = self.scope.read(cx);
        let messages = lounge["messages"].as_array().cloned().unwrap_or_default();
        let empty = messages.is_empty();
        div()
            .flex()
            .flex_col()
            .gap_4()
            .when(empty, |column| {
                column.child(
                    div()
                        .py_16()
                        .flex()
                        .justify_center()
                        .text_color(theme.text_muted)
                        .child(gpui::text!("No messages yet. Say hello.")),
                )
            })
            .children(messages.into_iter().map(|item| {
                let author = item["author"]["handle"]
                    .as_str()
                    .map_or("Someone".to_owned(), |handle| handle.to_owned());
                chat_message(
                    SharedString::from(format!(
                        "message-{}-online",
                        item["id"].as_str().unwrap_or_default()
                    )),
                    author,
                    scope.online(&item["author"]),
                    time(item["inserted_at"].as_str().unwrap_or_default()),
                    item["body"].as_str().unwrap_or_default().to_owned(),
                    theme,
                )
            }))
    }

    /// A bar above an open conversation: back to the list, its title and topic.
    fn conversation_header(
        &self,
        lounge: &Value,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Div {
        let title = lounge["title"].as_str().unwrap_or_default().to_owned();
        let topic = lounge["topic"].as_str().unwrap_or_default().to_owned();
        // A direct conversation is titled by its other members, each with
        // whether they are online.
        let scope = self.scope.read(cx);
        let members: Vec<(u64, String, bool)> = lounge["members"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|p| {
                let (id, handle) = (p["id"].as_u64()?, p["handle"].as_str()?);
                Some((id, handle.to_owned(), scope.online(p)))
            })
            .collect();
        let back = Button::new(
            SharedString::from(format!("close-{}", self.tab.id())),
            format!("← {}", self.noun()),
            Variant::Ghost,
        )
        .render(None, window, cx, |this, _, cx| {
            this.navigate(Destination::List(this.tab.id()), cx)
        });
        div()
            .flex_none()
            .flex()
            .items_center()
            .gap_3()
            .h(px(44.))
            .px_3()
            .border_b_1()
            .border_color(theme.border)
            .child(back.text_color(theme.accent))
            .when(members.is_empty(), |bar| {
                bar.child(
                    div()
                        .flex_none()
                        .font_weight(FontWeight::MEDIUM)
                        .child(gpui::text!(title)),
                )
            })
            .children(members.into_iter().map(|(id, handle, online)| {
                div()
                    .flex_none()
                    .flex()
                    .items_center()
                    .gap_1p5()
                    .font_weight(FontWeight::MEDIUM)
                    .child(gpui::text!(handle))
                    .when(online, |member| {
                        member.child(presence_dot(SharedString::from(format!(
                            "member-{id}-online"
                        ))))
                    })
            }))
            .when(!topic.is_empty(), |bar| {
                bar.child(
                    div()
                        .min_w_0()
                        .truncate()
                        .text_color(theme.text_muted)
                        .child(gpui::text!(topic)),
                )
            })
    }
}

impl Render for LoungesPanel {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let open = self.open.clone();
        if self.focus_reply && open.is_some() {
            self.focus_reply = false;
            window.focus(&self.reply.focus_handle(cx), cx);
        }
        let scope = self.scope.read(cx);
        let loading = (!scope.loaded && scope.error.is_none())
            || (self.busy && !self.loaded && open.is_none());
        let (body, header, composer) = match &open {
            Some(lounge) => {
                let send = Button::new(
                    SharedString::from(format!("send-{}", self.tab.id())),
                    "Send",
                    Variant::Primary,
                )
                .enabled(!self.busy)
                .render(None, window, cx, |this, _, cx| this.send(cx));
                (
                    self.conversation(lounge, theme, cx),
                    Some(self.conversation_header(lounge, theme, window, cx)),
                    Some(composer(&self.reply, send, theme)),
                )
            }
            None => (self.inbox(theme, window, cx), None, None),
        };
        div()
            .id(self.tab.id())
            .flex()
            .flex_col()
            .size_full()
            .children(header)
            .child(
                div()
                    .id(SharedString::from(format!("{}-scroll", self.tab.id())))
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_3()
                            .w_full()
                            .max_w(px(760.))
                            .mx_auto()
                            .px_6()
                            .py_6()
                            .when_some(self.error.clone(), |column, error| {
                                column.child(
                                    div()
                                        .text_color(theme.error)
                                        .whitespace_normal()
                                        .child(gpui::text!(error.to_string())),
                                )
                            })
                            .when(loading, |column| {
                                column.child(
                                    div()
                                        .text_color(theme.text_muted)
                                        .child(gpui::text!("Loading…")),
                                )
                            })
                            .child(body),
                    ),
            )
            .children(composer)
    }
}
