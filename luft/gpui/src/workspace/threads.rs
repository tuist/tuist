use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;

use gpui::{
    Context, Div, Entity, Focusable, FontWeight, IntoElement, Render, ScrollHandle, SharedString,
    Subscription, Task, Window, div, prelude::*, px, svg,
};
use serde_json::{Value, json};
use tuist_app_core::navigation::Destination;
use tuist_app_core::{INBOX, Threads, Transport};
use tuist_navigation::{Navigation, Route};
use tuist_session::Session;
use url::Url;

use super::{
    lounges::Scope,
    prompts::{Guarded, PromptEvent, PromptsPanel},
};
use crate::components::{Button, Variant, composer, message};
use crate::input::{Submitted, TextInput};
use crate::theme::Theme;

/// Sends the core's thread and lounge requests with the desktop session's token.
pub(super) struct Http<'a> {
    pub(super) session: &'a Session,
}

impl Transport for Http<'_> {
    fn send(
        &mut self,
        method: &str,
        url: Url,
        body: Option<Value>,
    ) -> Result<(u64, Value), &'static str> {
        self.send_guarded(method, url, body, || true)
    }
}

impl Http<'_> {
    /// Release reviews invalidate queued work even if token refresh was blocked.
    pub(super) fn send_guarded(
        &mut self,
        method: &str,
        url: Url,
        body: Option<Value>,
        authorized: impl Fn() -> bool,
    ) -> Result<(u64, Value), &'static str> {
        if !authorized() {
            return Err("The release session changed. Open it again.");
        }
        let token = self
            .session
            .access_token()
            .map_err(|_| "Sign in again to continue")?;
        let client = reqwest::blocking::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|_| "Server request failed")?;
        let method =
            reqwest::Method::from_bytes(method.as_bytes()).map_err(|_| "Server request failed")?;
        let mut request = client
            .request(method, url)
            .bearer_auth(token)
            .header("Accept", "application/json");
        if let Some(body) = body {
            request = request
                .header("Content-Type", "application/json")
                .body(body.to_string());
        }
        if !authorized() {
            return Err("The release session changed. Open it again.");
        }
        let response = request.send().map_err(|_| "Server request failed")?;
        let status = u64::from(response.status().as_u16());
        let text = response.text().unwrap_or_default();
        Ok((status, serde_json::from_str(&text).unwrap_or(Value::Null)))
    }
}

/// The person's conversations. They run on the server: starting one asks
/// only what to talk about, never for a repository, machine or model.
pub struct ThreadsPanel {
    session: Arc<Session>,
    handle: Option<String>,
    personal: Option<String>,
    organization: Option<String>,
    scope: Option<Subscription>,
    picker: Option<Entity<PromptsPanel>>,
    picked: Option<Subscription>,
    focus_composer: bool,
    account_active: Arc<AtomicBool>,
    navigation: Entity<Navigation>,
    route_id: Option<String>,
    _navigation: Subscription,
    threads: Arc<Mutex<Threads>>,
    list: Vec<Value>,
    available: bool,
    /// The session predates Luft's first-party client, so the server refuses it.
    sign_in_required: bool,
    loaded: bool,
    open: Option<Value>,
    error: Option<SharedString>,
    busy: bool,
    prompt: Entity<TextInput>,
    reply: Entity<TextInput>,
    scroll: ScrollHandle,
    suggestions_scroll: ScrollHandle,
    task: Option<Task<()>>,
    follow: Option<Task<()>>,
    /// Whether the window is in front; the inbox is followed only then.
    active: bool,
    /// The inbox's live socket while the list shows (see `sync_inbox`).
    inbox: Option<Task<()>>,
    _activation: Subscription,
    _submitted: [Subscription; 3],
}

impl Drop for ThreadsPanel {
    fn drop(&mut self) {
        self.account_active.store(false, Ordering::SeqCst);
    }
}

impl ThreadsPanel {
    pub fn new(
        session: Arc<Session>,
        handle: Option<String>,
        navigation: Entity<Navigation>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let prompt = cx.new(|cx| TextInput::new("What do you want to talk about?", cx));
        let reply = cx.new(|cx| TextInput::new("Reply", cx));
        let submitted = [
            cx.subscribe(&prompt, |this, _, _: &Submitted, cx| this.start(cx)),
            cx.subscribe(&reply, |this, _, _: &Submitted, cx| this.send(cx)),
            cx.observe(&reply, |_, _, cx| cx.notify()),
        ];
        let mut panel = Self {
            session,
            personal: handle.clone(),
            handle,
            organization: None,
            scope: None,
            picker: None,
            picked: None,
            focus_composer: false,
            account_active: Arc::new(AtomicBool::new(true)),
            _navigation: cx.observe(&navigation, |this, _, cx| this.sync_navigation(cx)),
            navigation,
            route_id: None,
            threads: Arc::new(Mutex::new(Threads::new())),
            list: Vec::new(),
            available: true,
            sign_in_required: false,
            loaded: false,
            open: None,
            error: None,
            busy: false,
            prompt,
            reply,
            scroll: ScrollHandle::new(),
            suggestions_scroll: ScrollHandle::new(),
            task: None,
            follow: None,
            active: window.is_window_active(),
            inbox: None,
            // Changes made while away show when the socket joins again.
            _activation: cx.observe_window_activation(window, |this, window, cx| {
                this.active = window.is_window_active();
                this.sync_inbox(cx);
            }),
            _submitted: submitted,
        };
        if panel.navigation.read(cx).luft.thread_id.is_some() {
            panel.sync_navigation(cx);
        } else {
            panel.request("threads", json!({}), cx);
        }
        panel
    }

    pub fn bind_scope(&mut self, scope: Entity<Scope>, cx: &mut Context<Self>) {
        self.organization = scope.read(cx).organization();
        self.scope = Some(cx.observe(&scope, |this, scope, cx| {
            let organization = scope.read(cx).organization();
            if this.organization != organization {
                let using_organization = this.handle != this.personal;
                this.organization = organization;
                this.picker = None;
                if using_organization {
                    this.choose_account(this.personal.clone(), cx);
                }
                cx.notify();
            }
        }));
    }

    fn choose_account(&mut self, handle: Option<String>, cx: &mut Context<Self>) {
        self.account_active.store(false, Ordering::SeqCst);
        self.account_active = Arc::new(AtomicBool::new(true));
        self.task = None;
        self.follow = None;
        self.inbox = None;
        self.picker = None;
        self.picked = None;
        self.handle = handle;
        self.busy = false;
        self.loaded = false;
        self.open = None;
        self.route_id = None;
        self.list.clear();
        self.threads = Arc::new(Mutex::new(Threads::new()));
        self.prompt
            .update(cx, |input, cx| input.set_value(String::new(), cx));
        self.reply
            .update(cx, |input, cx| input.set_value(String::new(), cx));
        self.navigate(Destination::THREADS, cx);
        self.request("threads", json!({}), cx);
    }

    fn can_pick(&self) -> bool {
        self.handle.is_some()
            && self.handle != self.personal
            && !self.busy
            && !self.open.as_ref().is_some_and(|thread| {
                thread["reauthorization_required"] == true
                    || thread["messages"].as_array().is_some_and(|messages| {
                        messages
                            .iter()
                            .any(|message| message["decision"]["status"] == "pending")
                    })
            })
    }

    fn show_picker(&mut self, cx: &mut Context<Self>) {
        if !self.can_pick() {
            return;
        }
        let picker = cx.new(|cx| {
            PromptsPanel::new(
                self.session.clone(),
                self.handle.clone(),
                true,
                ScrollHandle::new(),
                cx,
            )
        });
        self.picked = Some(cx.subscribe(&picker, |this, _, event: &PromptEvent, cx| {
            if !this.can_pick() {
                return;
            }
            let input = if this.open.is_some() {
                &this.reply
            } else {
                &this.prompt
            };
            if let PromptEvent::Chosen(name) = event {
                if let Ok(draft) = tuist_app_core::prompts::draft(
                    &json!({"name": name, "content": input.read(cx).value()}),
                ) {
                    input.update(cx, |input, cx| {
                        input
                            .set_value(draft["content"].as_str().unwrap_or_default().to_owned(), cx)
                    });
                }
            }
            this.picker = None;
            this.focus_composer = true;
            cx.notify();
        }));
        self.picker = Some(picker);
        cx.notify();
    }

    fn sync_navigation(&mut self, cx: &mut Context<Self>) {
        let id = self.navigation.read(cx).luft.thread_id.clone();
        if id == self.route_id && (id.is_none() || self.open.is_some() || self.busy) {
            return;
        }
        self.route_id = id.clone();
        self.picker = None;
        self.picked = None;
        self.open = None;
        self.follow = None;
        self.reply
            .update(cx, |input, cx| input.set_value(String::new(), cx));
        match id {
            Some(id) => self.request("thread", json!({"id":id}), cx),
            None => self.request("threads", json!({}), cx),
        }
        self.sync_inbox(cx);
    }

    /// Follows the inbox while its list shows in the active window, where threads are on
    /// and the session can use them, so a thread that starts working, answers or finishes
    /// changes its row without Refresh. The core's `Live` decides when to connect,
    /// heartbeat and reconnect, and how often the list may reload (`refresh_ms`).
    fn sync_inbox(&mut self, cx: &mut Context<Self>) {
        let wanted = self.active
            && self.route_id.is_none()
            && self.available
            && !self.sign_in_required
            && self.handle.is_some();
        if !wanted {
            // Dropping the task drops its socket, which closes the connection.
            self.inbox = None;
            return;
        }
        if self.inbox.is_some() {
            return;
        }
        let (Some(handle), session) = (self.handle.clone(), self.session.clone()) else {
            return;
        };
        self.inbox = Some(super::live::follow(
            session,
            handle,
            INBOX,
            cx,
            |this, cx| {
                // A request in flight shows the latest anyway, or is the
                // person's own; try again on the next read.
                if this.busy || this.route_id.is_some() {
                    return false;
                }
                this.request("threads", json!({}), cx);
                true
            },
        ));
    }

    fn navigate(&mut self, destination: Destination, cx: &mut Context<Self>) {
        self.navigation.update(cx, |nav, cx| {
            nav.navigate(Route::Luft(destination));
            cx.notify();
        });
    }

    /// Runs one core operation off the UI thread.
    fn request(&mut self, operation: &'static str, args: Value, cx: &mut Context<Self>) {
        let Some(handle) = self.handle.clone() else {
            self.error = Some("This account has no handle to own threads.".into());
            return cx.notify();
        };
        self.busy = true;
        self.error = None;
        let session = self.session.clone();
        let threads = self.threads.clone();
        let navigation_revision = self.navigation.read(cx).luft.revision;
        let authorized = self.account_active.clone();
        let work = cx.background_executor().spawn(async move {
            let mut threads = threads.lock().map_err(|_| "Threads are unavailable")?;
            threads.call(
                session.server(),
                &handle,
                operation,
                &args,
                &mut Guarded {
                    session: &session,
                    authorized: &authorized,
                },
            )
        });
        self.task = Some(cx.spawn(async move |this, cx| {
            let result = work.await;
            let _ = this.update(cx, |this, cx| {
                this.busy = false;
                this.finish(operation, result, navigation_revision, cx);
                cx.notify();
            });
        }));
        cx.notify();
    }

    fn finish(
        &mut self,
        operation: &'static str,
        result: Result<Value, &'static str>,
        navigation_revision: u64,
        cx: &mut Context<Self>,
    ) {
        let data = match result {
            Ok(data) => data,
            Err(error) => {
                self.error = Some(error.into());
                return;
            }
        };
        match operation {
            "threads" => {
                self.loaded = true;
                self.available = data["available"] != false;
                self.sign_in_required = data["reason"] == "sign_in_required";
                self.list = data["threads"]
                    .as_array()
                    .map(|threads| {
                        threads
                            .iter()
                            .filter(|t| t["section"] != "archived")
                            .cloned()
                            .collect()
                    })
                    .unwrap_or_default();
                self.sync_inbox(cx);
            }
            _ => {
                if operation == "start_thread" {
                    self.prompt
                        .update(cx, |input, cx| input.set_value(String::new(), cx));
                }
                if operation == "send_message" {
                    self.reply
                        .update(cx, |input, cx| input.set_value(String::new(), cx));
                }
                let working = data["working"] == true;
                let id = data["id"].as_str().map(str::to_owned);
                if operation == "start_thread" {
                    // Creating a conversation is not permission to replace a
                    // destination selected while the request was in flight.
                    if navigation_revision != self.navigation.read(cx).luft.revision {
                        return;
                    }
                    if let Some(id) = &id {
                        self.route_id = Some(id.clone());
                        self.navigate(Destination::Conversation("threads", id.clone()), cx);
                    }
                }
                let grew = self.open.as_ref().is_none_or(|open| {
                    open["id"] != data["id"] || open["messages"] != data["messages"]
                });
                self.open = Some(data);
                if grew {
                    self.scroll.scroll_to_bottom();
                }
                if let (true, Some(id)) = (working, id) {
                    self.follow(id, cx);
                }
            }
        }
    }

    /// Rereads an open conversation while the server is answering.
    fn follow(&mut self, id: String, cx: &mut Context<Self>) {
        self.follow = Some(cx.spawn(async move |this, cx| {
            cx.background_executor().timer(Duration::from_secs(2)).await;
            let _ = this.update(cx, |this, cx| {
                if this.open.as_ref().and_then(|t| t["id"].as_str()) != Some(id.as_str()) {
                    return;
                }
                if this.busy {
                    this.follow(id, cx);
                } else {
                    this.request("thread", json!({ "id": id }), cx);
                }
            });
        }));
    }

    fn start(&mut self, cx: &mut Context<Self>) {
        let content = self.prompt.read(cx).value().trim().to_owned();
        if !self.busy && !content.is_empty() {
            self.request("start_thread", json!({ "content": content }), cx);
        }
    }

    fn send(&mut self, cx: &mut Context<Self>) {
        let content = self.reply.read(cx).value().trim().to_owned();
        let Some(id) = self.open.as_ref().and_then(|t| t["id"].as_str()) else {
            return;
        };
        if !self.busy
            && !content.is_empty()
            && self.open.as_ref().unwrap()["working"] != true
            && self.open.as_ref().unwrap()["reauthorization_required"] != true
        {
            let args = json!({ "id": id, "content": content });
            self.request("send_message", args, cx);
        }
    }

    fn close(&mut self, cx: &mut Context<Self>) {
        self.navigate(Destination::THREADS, cx);
    }

    /// Above the list: what conversations are, and a refresh control.
    fn inbox(&self, theme: Theme, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let refresh = Button::new("refresh-threads", "Refresh", Variant::Secondary)
            .enabled(!self.busy)
            .render(Some(&self.scroll), window, cx, |this, _, cx| {
                if let Some(id) = this.route_id.clone() {
                    this.request("thread", json!({"id":id}), cx);
                } else {
                    this.request("threads", json!({}), cx);
                }
            });
        let mut rows = Vec::new();
        for thread in &self.list {
            let Some(id) = thread["id"].as_str().map(str::to_owned) else {
                continue;
            };
            let title = thread["title"]
                .as_str()
                .or(thread["goal"].as_str())
                .unwrap_or_default()
                .to_owned();
            let state = match thread["state"].as_str() {
                Some("queued") => "Queued",
                Some("running") => "Running",
                Some("completed") => "Ready to review",
                Some("failed") => "Needs attention",
                Some("outcome_unknown") => "Outcome unknown",
                _ => "",
            };
            let in_progress = thread["section"] == "in_progress";
            rows.push(
                Button::new(
                    SharedString::from(format!("thread-{id}")),
                    title,
                    Variant::Ghost,
                )
                .enabled(!self.busy)
                .render(Some(&self.scroll), window, cx, move |this, _, cx| {
                    this.navigate(Destination::Conversation("threads", id.clone()), cx)
                })
                .w_full()
                .min_h(px(44.))
                .justify_between()
                .border_b_1()
                .border_color(theme.border)
                .rounded_none()
                .child(
                    div()
                        .flex_none()
                        .text_xs()
                        .text_color(if in_progress {
                            theme.accent
                        } else {
                            theme.text_muted
                        })
                        .child(state),
                ),
            );
        }
        let empty = self.loaded && self.list.is_empty();
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
                            .text_color(theme.text_muted)
                            .whitespace_normal()
                            .child(gpui::text!(
                                "Conversations run on Tuist's servers. You don't need a repository or a machine."
                            )),
                    )
                    .child(refresh),
            )
            .when(!self.available, |column| {
                column.child(if self.sign_in_required {
                    gpui::text!(
                        "Your session is from an earlier version of Luft. Sign out from the account menu and sign in again to use threads."
                    )
                } else {
                    gpui::text!("Threads aren't enabled for this account or server.")
                })
            })
            .when(self.available && empty, |column| {
                column.child(
                    div()
                        .flex()
                        .flex_col()
                        .items_center()
                        .gap_1()
                        .py_16()
                        .child(
                            div()
                                .text_base()
                                .font_weight(FontWeight::SEMIBOLD)
                                .child(gpui::text!("Big things start here")),
                        )
                        .child(div().text_color(theme.text_muted).child(gpui::text!(
                            "Ask a question, explore an idea, or solve a problem with Tuist below."
                        ))),
                )
            })
            .child(div().flex().flex_col().children(rows))
    }

    fn conversation(&self, thread: &Value, theme: Theme) -> Div {
        let working = thread["working"] == true;
        let messages = thread["messages"].as_array().cloned().unwrap_or_default();
        div()
            .flex()
            .flex_col()
            .gap_5()
            .children(messages.into_iter().map(|item| {
                message(
                    item["role"].as_str().unwrap_or_default(),
                    item["content"].as_str().unwrap_or_default().to_owned(),
                    theme,
                )
            }))
            .when(working, |column| {
                column.child(
                    div()
                        .text_color(theme.text_muted)
                        .child(gpui::text!("Thinking…")),
                )
            })
            .when(thread["reauthorization_required"] == true, |column| {
                column.child(gpui::text!("The owner must authorize future messages with their current sign-in. This does not resume previous work."))
            })
    }

    /// A bar above an open conversation: back to the inbox, and its title.
    fn conversation_header(
        &self,
        thread: &Value,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Div {
        let title = thread["title"]
            .as_str()
            .or(thread["goal"].as_str())
            .unwrap_or_default()
            .to_owned();
        let back = Button::new("close-thread", "← Threads", Variant::Ghost).render(
            None,
            window,
            cx,
            |this, _, cx| this.close(cx),
        );
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
            .child(
                div()
                    .min_w_0()
                    .truncate()
                    .font_weight(FontWeight::MEDIUM)
                    .child(gpui::text!(title)),
            )
    }
}

impl Render for ThreadsPanel {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let open = self.open.clone();
        if self.focus_composer {
            self.focus_composer = false;
            window.focus(
                &if open.is_some() {
                    self.reply.focus_handle(cx)
                } else {
                    self.prompt.focus_handle(cx)
                },
                cx,
            );
        }
        let working = open.as_ref().is_some_and(|t| t["working"] == true);
        let (body, header, input, send) = match &open {
            Some(thread) => (
                self.conversation(thread, theme),
                Some(self.conversation_header(thread, theme, window, cx)),
                self.reply.clone(),
                if thread["reauthorization_required"] == true {
                    Button::new(
                        "reauthorize-thread",
                        "Authorize future messages",
                        Variant::Primary,
                    )
                    .enabled(!self.busy && thread["can_reauthorize"] == true)
                    .render(None, window, cx, |this, _, cx| {
                        if let Some(id) = this.open.as_ref().and_then(|t| t["id"].as_str()) {
                            this.request("reauthorize_thread", json!({"id":id,"consent":true}), cx);
                        }
                    })
                    .debug_selector(|| "reauthorize-thread".into())
                } else {
                    Button::new("send-reply", "Send", Variant::Primary)
                        .enabled(!self.busy && !working)
                        .render(None, window, cx, |this, _, cx| this.send(cx))
                        .debug_selector(|| "send-reply".into())
                },
            ),
            None => (
                self.inbox(theme, window, cx),
                None,
                self.prompt.clone(),
                Button::new("start-conversation", "Start conversation", Variant::Primary)
                    .enabled(!self.busy && self.available)
                    .render(None, window, cx, |this, _, cx| this.start(cx)),
            ),
        };
        let suggestions = open
            .as_ref()
            .and_then(|thread| thread["suggestions"].as_array())
            .filter(|_| !self.busy && self.reply.read(cx).value().is_empty())
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .enumerate()
            .map(|(index, suggestion)| {
                let icon = match open.as_ref().unwrap()["suggestion_icons"][suggestion].as_str() {
                    Some("investigate") => Some("icons/search.svg"),
                    Some("test") => Some("icons/circle-check.svg"),
                    Some("explain") => Some("icons/message-square.svg"),
                    Some("retry") => Some("icons/rotate-cw.svg"),
                    _ => None,
                };
                let suggestion = suggestion.to_owned();
                Button::new(
                    SharedString::from(format!("suggestion-{index}")),
                    suggestion.clone(),
                    Variant::Secondary,
                )
                .render(
                    Some(&self.suggestions_scroll),
                    window,
                    cx,
                    move |this, window, cx| {
                        this.reply
                            .update(cx, |input, cx| input.set_value(suggestion.clone(), cx));
                        window.focus(&this.reply.focus_handle(cx), cx);
                    },
                )
                .debug_selector(move || format!("suggestion-{index}"))
                .when_some(icon, |button, icon| {
                    button.child(
                        svg()
                            .path(icon)
                            .size(px(16.))
                            .flex_none()
                            .text_color(theme.text),
                    )
                })
            })
            .collect::<Vec<_>>();
        div()
            .id("threads")
            .flex()
            .flex_col()
            .size_full()
            .when(open.is_none(), |column| {
                column.child(
                    div()
                        .flex()
                        .flex_wrap()
                        .gap_2()
                        .px_6()
                        .py_2()
                        .child(gpui::text!(format!(
                            "Account: {}",
                            self.handle.as_deref().unwrap_or_default()
                        )))
                        .when_some(self.organization.clone(), |row, organization| {
                            let selected = self.handle.as_ref() == Some(&organization);
                            row.child(
                                Button::new(
                                    "thread-account",
                                    if selected {
                                        "Use personal account".to_owned()
                                    } else {
                                        format!("Use {organization}")
                                    },
                                    Variant::Secondary,
                                )
                                .enabled(!self.busy)
                                .render(
                                    None,
                                    window,
                                    cx,
                                    move |this, _, cx| {
                                        let handle = if selected {
                                            this.personal.clone()
                                        } else {
                                            Some(organization.clone())
                                        };
                                        this.choose_account(handle, cx);
                                    },
                                ),
                            )
                        }),
                )
            })
            .children(header)
            .child(
                div()
                    .id("threads-scroll")
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
                            .child(body),
                    ),
            )
            .when(!suggestions.is_empty(), |column| {
                column.child(
                    div()
                        .id("thread-suggestions")
                        .debug_selector(|| "thread-suggestions".into())
                        .flex()
                        .flex_none()
                        .overflow_x_scroll()
                        .track_scroll(&self.suggestions_scroll)
                        .gap_2()
                        .px_6()
                        .py_2()
                        .children(suggestions),
                )
            })
            .when(self.can_pick(), |column| {
                column
                    .child(
                        Button::new(
                            "pick-prompt",
                            if self.picker.is_some() {
                                "Close prompts"
                            } else {
                                "Choose prompt"
                            },
                            Variant::Secondary,
                        )
                        .render(None, window, cx, |this, _, cx| {
                            if this.picker.is_some() {
                                this.picker = None;
                            } else {
                                this.show_picker(cx);
                            }
                            cx.notify();
                        }),
                    )
                    .children(self.picker.clone())
            })
            .child(composer(&input, send, theme).debug_selector(|| "reply-composer".into()))
    }
}

#[cfg(all(test, debug_assertions))]
mod tests {
    use super::*;
    use gpui::{KeyUpEvent, Keystroke, TestAppContext, VisualTestContext, size};
    use tuist_credentials::Directories;
    use tuist_session::Accounts;

    fn draw(cx: &mut VisualTestContext) {
        cx.run_until_parked();
        for _ in 0..2 {
            cx.update(|window, cx| window.draw(cx).clear(cx));
        }
    }

    #[gpui::test]
    fn dormant_history_renders_owner_consent_without_sending_the_draft(cx: &mut TestAppContext) {
        cx.update(|cx| {
            crate::keyboard::init(cx);
            crate::input::init(cx);
        });
        let directory = tempfile::tempdir().unwrap();
        let accounts = Accounts::new(Directories {
            config: directory.path().join("config"),
            state: directory.path().join("state"),
            data: directory.path().join("data"),
        });
        let session = Arc::new(
            accounts
                .current_session(Url::parse("https://example.test").unwrap())
                .unwrap(),
        );
        let navigation = cx.new(|_| Navigation::default());
        let (panel, cx) = cx.add_window_view(|window, cx| {
            let mut panel = ThreadsPanel::new(session, None, navigation, window, cx);
            panel.task = None;
            panel.open = Some(json!({"id":"example", "working":false, "messages":[],
                "reauthorization_required":true,"can_reauthorize":true}));
            panel.reply.update(cx, |input, cx| {
                input.set_value("Keep this draft".into(), cx)
            });
            panel
        });
        draw(cx);
        assert!(cx.debug_bounds("reauthorize-thread").is_some());
        assert!(cx.debug_bounds("send-reply").is_none());
        panel.update(cx, |panel, cx| {
            panel.finish(
                "reauthorize_thread",
                Ok(json!({"id":"example", "working":false,
                "messages":[], "reauthorization_required":false,"can_reauthorize":false})),
                0,
                cx,
            );
            cx.notify();
        });
        draw(cx);
        assert!(cx.debug_bounds("reauthorize-thread").is_none());
        assert!(cx.debug_bounds("send-reply").is_some());
        panel.read_with(cx, |panel, cx| {
            assert_eq!(panel.reply.read(cx).value(), "Keep this draft")
        });
    }

    #[gpui::test]
    fn long_suggestions_scroll_to_keyboard_focus_and_fill_the_composer(cx: &mut TestAppContext) {
        cx.update(|cx| {
            crate::keyboard::init(cx);
            crate::input::init(cx);
        });
        let directory = tempfile::tempdir().unwrap();
        let accounts = Accounts::new(Directories {
            config: directory.path().join("config"),
            state: directory.path().join("state"),
            data: directory.path().join("data"),
        });
        let session = Arc::new(
            accounts
                .current_session(Url::parse("https://example.test").unwrap())
                .unwrap(),
        );
        let navigation = cx.new(|_| Navigation::default());
        let (panel, cx) = cx.add_window_view(|window, cx| {
            let mut panel = ThreadsPanel::new(session, None, navigation, window, cx);
            panel.task = None;
            panel.open = Some(json!({"id":"example", "working":false, "messages":[],
                "suggestions":["Explain how temporary network failures affect queued messages without duplicating requests", "x".repeat(120), "Run tests"]}));
            panel
        });
        // The 640px minimum window leaves 440px beside the desktop sidebar.
        cx.update(|window, _| window.activate_window());
        cx.simulate_resize(size(px(440.), px(300.)));
        draw(cx);
        let viewport = cx.debug_bounds("thread-suggestions").unwrap();
        assert!(cx.debug_bounds("suggestion-2").unwrap().right() > viewport.right());
        // Back, first suggestion, second suggestion, then the short third one.
        for _ in 0..4 {
            cx.update(|window, cx| window.focus_next(cx));
            draw(cx);
        }
        let focused = cx.debug_bounds("suggestion-2").unwrap();
        assert!(
            focused.left() >= viewport.left() && focused.right() <= viewport.right(),
            "focused: {focused:?}, viewport: {viewport:?}"
        );
        let composer = cx.debug_bounds("reply-composer").unwrap();
        assert!(composer.top() >= viewport.bottom() && composer.bottom() <= px(300.));
        cx.simulate_keystrokes("enter");
        cx.simulate_event(KeyUpEvent {
            keystroke: Keystroke::parse("enter").unwrap(),
        });
        draw(cx);
        panel.read_with(cx, |panel, cx| {
            assert_eq!(panel.reply.read(cx).value(), "Run tests")
        });
        assert!(cx.debug_bounds("thread-suggestions").is_none());
    }
}
