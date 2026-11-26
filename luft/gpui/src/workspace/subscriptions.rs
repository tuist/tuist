use std::sync::Arc;
use std::time::Duration;

use gpui::{
    Context, FontWeight, IntoElement, Render, SharedString, Subscription, Task, Window, div,
    prelude::*, px,
};
use serde_json::{Value, json};
use tuist_app_core::{AI_SUBSCRIPTIONS, ai_subscriptions};
use tuist_session::Session;

use super::threads::Http;
use crate::components::{Button, Variant};
use crate::theme::Theme;

/// A pending ChatGPT device sign-in.
struct Login {
    id: String,
    code: SharedString,
    url: String,
    interval: u64,
    failed: bool,
}

/// Profile's AI subscriptions, which threads run on. While Profile shows in
/// the active window it follows the `ai_subscriptions` live socket, so a
/// subscription connected on another device or on Tuist shows at once.
pub struct SubscriptionsPanel {
    session: Arc<Session>,
    list: Option<Vec<Value>>,
    unavailable: bool,
    error: Option<SharedString>,
    /// A connect or disconnect is in flight.
    busy: bool,
    /// Connecting Claude: the instructions and the paste button show.
    claude: bool,
    login: Option<Login>,
    visible: bool,
    active: bool,
    live: Option<Task<()>>,
    load: Option<Task<()>>,
    change: Option<Task<()>>,
    poll: Option<Task<()>>,
    _activation: Subscription,
}

impl SubscriptionsPanel {
    pub fn new(session: Arc<Session>, window: &mut Window, cx: &mut Context<Self>) -> Self {
        Self {
            session,
            list: None,
            unavailable: false,
            error: None,
            busy: false,
            claude: false,
            login: None,
            visible: false,
            active: window.is_window_active(),
            live: None,
            load: None,
            change: None,
            poll: None,
            // Changes made while away show when the socket joins again.
            _activation: cx.observe_window_activation(window, |this, window, cx| {
                this.active = window.is_window_active();
                this.sync(cx);
            }),
        }
    }

    /// Whether Profile shows; the socket stays open only then.
    pub fn set_visible(&mut self, visible: bool, cx: &mut Context<Self>) {
        self.visible = visible;
        self.sync(cx);
    }

    fn sync(&mut self, cx: &mut Context<Self>) {
        if !(self.visible && self.active) {
            // Dropping the task drops its socket, which closes the connection.
            self.live = None;
            return;
        }
        if self.live.is_some() {
            return;
        }
        // The socket also reloads when it joins; this covers a server without it.
        self.reload(cx);
        // The topic names no account: the subscriptions are the person's.
        self.live = Some(super::live::follow(
            self.session.clone(),
            String::new(),
            AI_SUBSCRIPTIONS,
            cx,
            |this, cx| {
                // A change in flight answers with the list anyway.
                if this.busy {
                    return false;
                }
                this.reload(cx);
                true
            },
        ));
    }

    /// Runs one core operation off the UI thread.
    fn run(
        &self,
        operation: &'static str,
        args: Value,
        cx: &mut Context<Self>,
    ) -> Task<Result<Value, &'static str>> {
        let session = self.session.clone();
        cx.background_executor().spawn(async move {
            ai_subscriptions::call(
                session.server(),
                operation,
                &args,
                &mut Http { session: &session },
            )
        })
    }

    fn reload(&mut self, cx: &mut Context<Self>) {
        let work = self.run("ai_subscriptions", json!({}), cx);
        self.load = Some(cx.spawn(async move |this, cx| {
            let result = work.await;
            let _ = this.update(cx, |this, cx| {
                match result {
                    Ok(data) => this.show(&data),
                    Err(_) => this.unavailable = this.list.is_none(),
                }
                cx.notify();
            });
        }));
    }

    fn show(&mut self, data: &Value) {
        if let Some(list) = data["subscriptions"].as_array() {
            self.list = Some(list.clone());
            self.unavailable = false;
        }
    }

    /// Runs a connect or disconnect, then shows the list it answers with.
    fn change(&mut self, operation: &'static str, args: Value, cx: &mut Context<Self>) {
        self.busy = true;
        self.error = None;
        let work = self.run(operation, args, cx);
        self.change = Some(cx.spawn(async move |this, cx| {
            let result = work.await;
            let _ = this.update(cx, |this, cx| {
                this.busy = false;
                match result {
                    Ok(data) => {
                        this.show(&data);
                        this.claude = false;
                    }
                    // The core's messages are fixed and carry no credentials.
                    Err(error) => this.error = Some(error.into()),
                }
                cx.notify();
            });
        }));
        cx.notify();
    }

    /// Sends the token `claude setup-token` printed, from the clipboard, so it
    /// is never typed into or shown on screen.
    fn paste_claude_token(&mut self, cx: &mut Context<Self>) {
        let token = cx
            .read_from_clipboard()
            .and_then(|item| item.text())
            .filter(|text| !text.trim().is_empty());
        match token {
            Some(token) => self.change("connect_claude", json!({"token": token}), cx),
            None => {
                self.error =
                    Some("Copy the token claude setup-token prints, then try again.".into());
                cx.notify();
            }
        }
    }

    fn start_chatgpt(&mut self, cx: &mut Context<Self>) {
        self.busy = true;
        self.error = None;
        let work = self.run("start_chatgpt_login", json!({}), cx);
        self.change = Some(cx.spawn(async move |this, cx| {
            let result = work.await;
            let _ = this.update(cx, |this, cx| {
                this.busy = false;
                match result {
                    Ok(data) => {
                        let id = data["login_id"].as_str().unwrap_or_default().to_owned();
                        if !id.is_empty() {
                            this.login = Some(Login {
                                id,
                                code: data["user_code"]
                                    .as_str()
                                    .unwrap_or_default()
                                    .to_owned()
                                    .into(),
                                url: data["verification_url"]
                                    .as_str()
                                    .unwrap_or_default()
                                    .to_owned(),
                                interval: data["interval"].as_u64().unwrap_or(5).max(1),
                                failed: false,
                            });
                            this.poll_chatgpt(cx);
                        }
                    }
                    Err(error) => this.error = Some(error.into()),
                }
                cx.notify();
            });
        }));
        cx.notify();
    }

    /// Asks every `interval` seconds until the person approves the code or the sign-in ends.
    fn poll_chatgpt(&mut self, cx: &mut Context<Self>) {
        let Some(login) = &self.login else { return };
        let (id, interval, session) = (login.id.clone(), login.interval, self.session.clone());
        self.poll = Some(cx.spawn(async move |this, cx| {
            loop {
                cx.background_executor()
                    .timer(Duration::from_secs(interval))
                    .await;
                let (session, id) = (session.clone(), id.clone());
                let result = cx
                    .background_executor()
                    .spawn(async move {
                        ai_subscriptions::call(
                            session.server(),
                            "poll_chatgpt_login",
                            &json!({"login_id": id}),
                            &mut Http { session: &session },
                        )
                    })
                    .await;
                // Offline for a moment counts as pending.
                let status = result
                    .ok()
                    .and_then(|data| data["status"].as_str().map(str::to_owned));
                let finished = this
                    .update(cx, |this, cx| match status.as_deref() {
                        Some("connected") => {
                            this.login = None;
                            this.reload(cx);
                            cx.notify();
                            true
                        }
                        Some("failed") => {
                            if let Some(login) = &mut this.login {
                                login.failed = true;
                            }
                            cx.notify();
                            true
                        }
                        _ => false,
                    })
                    .unwrap_or(true);
                if finished {
                    return;
                }
            }
        }));
    }

    fn cancel_chatgpt(&mut self, cx: &mut Context<Self>) {
        self.poll = None;
        if let Some(login) = self.login.take()
            && !login.failed
        {
            self.run("cancel_chatgpt_login", json!({"login_id": login.id}), cx)
                .detach();
        }
        cx.notify();
    }

    fn row(&mut self, item: &Value, window: &mut Window, cx: &mut Context<Self>) -> gpui::Div {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let provider = item["provider"].as_str().unwrap_or_default().to_owned();
        let name = match provider.as_str() {
            "claude" => "Claude".to_owned(),
            "chatgpt" => "ChatGPT".to_owned(),
            other => other.to_owned(),
        };
        let connected = item["connected"] == true;
        let available = item["login_available"] != false;
        let pending = (provider == "claude" && self.claude)
            || (provider == "chatgpt" && self.login.is_some());
        let action = if connected {
            let provider = provider.clone();
            Button::new(
                SharedString::from(format!("disconnect-{provider}")),
                "Disconnect",
                Variant::Secondary,
            )
            .enabled(!self.busy)
            .render(None, window, cx, move |this, _, cx| {
                this.change(
                    "disconnect_ai_subscription",
                    json!({"provider": provider}),
                    cx,
                )
            })
            .into_any_element()
        } else if !available {
            div()
                .text_color(theme.text_muted)
                .child(gpui::text!("Unavailable"))
                .into_any_element()
        } else {
            let provider = provider.clone();
            Button::new(
                SharedString::from(format!("connect-{provider}")),
                "Connect",
                Variant::Secondary,
            )
            .enabled(!self.busy && !pending)
            .render(None, window, cx, move |this, _, cx| {
                if provider == "claude" {
                    this.error = None;
                    this.claude = true;
                    cx.notify();
                } else {
                    this.start_chatgpt(cx);
                }
            })
            .into_any_element()
        };
        div()
            .flex()
            .items_center()
            .justify_between()
            .gap_4()
            .min_h(px(44.))
            .border_b_1()
            .border_color(theme.border)
            .child(
                div().flex().flex_col().child(gpui::text!(name)).child(
                    div()
                        .text_xs()
                        .text_color(if connected {
                            theme.accent
                        } else {
                            theme.text_muted
                        })
                        .child(gpui::text!(if connected {
                            "Connected"
                        } else {
                            "Not connected"
                        })),
                ),
            )
            .child(action)
    }
}

impl Render for SubscriptionsPanel {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let note = |text: SharedString| {
            div()
                .py_2()
                .text_xs()
                .text_color(theme.text_muted)
                .child(gpui::text!(text))
        };
        let rows: Vec<_> = match self.list.clone() {
            Some(list) => list
                .iter()
                .map(|item| self.row(item, window, cx).into_any_element())
                .collect(),
            None if self.unavailable => {
                vec![
                    note("AI subscriptions are not available for this account.".into())
                        .into_any_element(),
                ]
            }
            None => vec![note("Loading…".into()).into_any_element()],
        };
        let claude = self.claude.then(|| {
            div()
                .flex()
                .flex_col()
                .gap_2()
                .py_3()
                .child(note(
                    "Run claude setup-token in a terminal, sign in, and copy the token it prints. It is not an Anthropic API key."
                        .into(),
                ))
                .child(
                    div()
                        .flex()
                        .gap_2()
                        .child(
                            Button::new("paste-claude-token", "Paste token and connect", Variant::Primary)
                                .enabled(!self.busy)
                                .render(None, window, cx, |this, _, cx| this.paste_claude_token(cx)),
                        )
                        .child(
                            Button::new("cancel-claude", "Cancel", Variant::Secondary).render(
                                None,
                                window,
                                cx,
                                |this, _, cx| {
                                    this.claude = false;
                                    this.error = None;
                                    cx.notify();
                                },
                            ),
                        ),
                )
        });
        let login = self.login.as_ref().map(|login| {
            let (code, url, failed) = (login.code.clone(), login.url.clone(), login.failed);
            div()
                .flex()
                .flex_col()
                .gap_2()
                .py_3()
                .child(note(if failed {
                    "The sign-in expired or was refused. Cancel and connect again.".into()
                } else {
                    "Open OpenAI, sign in with your ChatGPT account and enter this code. Luft connects as soon as you approve it.".into()
                }))
                .child(
                    div()
                        .id("chatgpt-code")
                        .role(gpui::Role::Label)
                        .aria_label("ChatGPT sign-in code")
                        .text_xl()
                        .font_weight(FontWeight::SEMIBOLD)
                        .font_family("monospace")
                        .child(gpui::text!(code.to_string())),
                )
                .child(
                    div()
                        .flex()
                        .gap_2()
                        .when(!failed, |buttons| {
                            buttons
                                .child(Button::new("open-openai", "Open OpenAI", Variant::Primary).render(
                                    None,
                                    window,
                                    cx,
                                    move |_, _, cx| cx.open_url(&url),
                                ))
                                .child(Button::new("copy-chatgpt-code", "Copy code", Variant::Secondary).render(
                                    None,
                                    window,
                                    cx,
                                    move |_, _, cx| {
                                        cx.write_to_clipboard(gpui::ClipboardItem::new_string(code.to_string()))
                                    },
                                ))
                        })
                        .child(Button::new("cancel-chatgpt", "Cancel", Variant::Secondary).render(
                            None,
                            window,
                            cx,
                            |this, _, cx| this.cancel_chatgpt(cx),
                        )),
                )
        });
        div()
            .id("ai-subscriptions")
            .role(gpui::Role::Group)
            .aria_label("AI subscriptions")
            .flex()
            .flex_col()
            .children(rows)
            .children(claude)
            .children(login)
            .children(self.error.clone().map(|error| div().py_2().text_color(theme.error).child(gpui::text!(error))))
            .child(note(
                "Threads run on your ChatGPT subscription. Claude subscriptions can be saved, but Claude doesn't allow them to run Luft threads yet."
                    .into(),
            ))
    }
}
