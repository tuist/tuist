use std::sync::Arc;

use gpui::{
    Context, Entity, IntoElement, Render, SharedString, Subscription, Task, Window, div,
    prelude::*, px,
};
use serde_json::{Value, json};
use tuist_app_core::mcp_servers;
use tuist_session::Session;

use super::lounges::Scope;
use super::threads::Http;
use crate::components::{Button, Variant};
use crate::input::{Submitted, TextInput};
use crate::theme::Theme;

/// The list (`None` inside for the person's own) a started sign-in belongs to.
type Pending = Option<Option<String>>;

/// Profile's MCP servers, whose tools threads use: the person's own and,
/// when an organization is selected, the organization's, which only its
/// admins change. Signing in opens the browser; the server hands the answer
/// to `luft://mcp-callback`, which the root passes to [`Self::complete`].
pub struct McpServersPanel {
    session: Arc<Session>,
    /// The organization shown, as the scope last selected it.
    organization: Option<String>,
    personal: Option<Vec<Value>>,
    shared: Option<Vec<Value>>,
    pending: Pending,
    /// The list the add form adds to, while it shows.
    adding: Option<Option<String>>,
    input: Entity<TextInput>,
    error: Option<SharedString>,
    busy: bool,
    load: Vec<Task<()>>,
    change: Option<Task<()>>,
    _scope: Subscription,
    _submitted: Subscription,
}

impl McpServersPanel {
    pub fn new(session: Arc<Session>, scope: Entity<Scope>, cx: &mut Context<Self>) -> Self {
        let input = cx.new(|cx| TextInput::new("https://example.com/mcp", cx));
        let submitted = cx.subscribe(&input, |this, _, _: &Submitted, cx| this.add(cx));
        let observer = cx.observe(&scope, |this: &mut Self, scope, cx| {
            let organization = scope.read(cx).organization();
            if organization != this.organization {
                this.organization = organization;
                this.shared = None;
                this.reload(cx);
            }
        });
        let organization = scope.read(cx).organization();
        Self {
            session,
            organization,
            personal: None,
            shared: None,
            pending: None,
            adding: None,
            input,
            error: None,
            busy: false,
            load: Vec::new(),
            change: None,
            _scope: observer,
            _submitted: submitted,
        }
    }

    /// Runs one core operation off the UI thread, carrying the sign-in state through it.
    fn run(
        &self,
        operation: &'static str,
        args: Value,
        pending: Pending,
        cx: &mut Context<Self>,
    ) -> Task<(Result<Value, &'static str>, Pending)> {
        let session = self.session.clone();
        cx.background_executor().spawn(async move {
            let mut pending = pending;
            let result = mcp_servers::call(
                session.server(),
                operation,
                &args,
                &mut pending,
                &mut Http { session: &session },
            );
            (result, pending)
        })
    }

    fn args(list: &Option<String>) -> Value {
        match list {
            Some(handle) => json!({"account_handle": handle}),
            None => json!({}),
        }
    }

    pub fn reload(&mut self, cx: &mut Context<Self>) {
        let lists = [None, self.organization.clone()];
        self.load = lists
            .into_iter()
            .enumerate()
            .filter(|(index, list)| *index == 0 || list.is_some())
            .map(|(_, list)| {
                let work = self.run("mcp_servers", Self::args(&list), None, cx);
                cx.spawn(async move |this, cx| {
                    let (result, _) = work.await;
                    let _ = this.update(cx, |this, cx| {
                        let servers = result
                            .ok()
                            .and_then(|data| data["servers"].as_array().cloned())
                            .unwrap_or_default();
                        match list {
                            None => this.personal = Some(servers),
                            Some(handle) if this.organization.as_ref() == Some(&handle) => {
                                this.shared = Some(servers)
                            }
                            Some(_) => {}
                        }
                        cx.notify();
                    });
                })
            })
            .collect();
    }

    /// Runs a change, then reloads; `then` sees its answer.
    fn change(
        &mut self,
        operation: &'static str,
        args: Value,
        cx: &mut Context<Self>,
        then: impl FnOnce(&mut Self, Value, &mut Context<Self>) + 'static,
    ) {
        self.busy = true;
        self.error = None;
        let work = self.run(operation, args, self.pending.clone(), cx);
        self.change = Some(cx.spawn(async move |this, cx| {
            let (result, pending) = work.await;
            let _ = this.update(cx, |this, cx| {
                this.busy = false;
                this.pending = pending;
                match result {
                    Ok(data) => then(this, data, cx),
                    // The core's messages are fixed and carry no credentials.
                    Err(error) => this.error = Some(error.into()),
                }
                this.reload(cx);
                cx.notify();
            });
        }));
        cx.notify();
    }

    fn add(&mut self, cx: &mut Context<Self>) {
        let Some(list) = self.adding.clone() else {
            return;
        };
        let url = self.input.read(cx).value().trim().to_owned();
        if url.is_empty() {
            return;
        }
        let mut args = Self::args(&list);
        args["url"] = json!(url);
        self.change("add_mcp_server", args, cx, move |this, data, cx| {
            this.adding = None;
            this.input
                .update(cx, |input, cx| input.set_value(String::new(), cx));
            if let Some(id) = data["server"]["id"].as_str() {
                this.authorize(&list, id.to_owned(), cx);
            }
        });
    }

    fn authorize(&mut self, list: &Option<String>, id: String, cx: &mut Context<Self>) {
        let mut args = Self::args(list);
        args["id"] = json!(id);
        self.change("authorize_mcp_server", args, cx, |_, data, cx| {
            if let Some(url) = data["url"].as_str() {
                cx.open_url(url);
            }
        });
    }

    /// Completes the sign-in `luft://mcp-callback` answered.
    pub fn complete(&mut self, url: String, cx: &mut Context<Self>) {
        self.change("complete_mcp_server", json!({"url": url}), cx, |_, _, _| {});
    }

    fn group(
        &mut self,
        list: Option<String>,
        servers: Option<Vec<Value>>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let key = list.clone().unwrap_or_default();
        let title = match &list {
            Some(handle) => format!("MCP servers for {handle}"),
            None => "Your MCP servers".to_owned(),
        };
        let footer = if list.is_some() {
            "Every thread in this organization can use the tools of its servers. Only admins can change them."
        } else {
            "Threads you write in can use the tools of your servers."
        };
        let rows: Vec<_> = match servers {
            None => vec![
                div()
                    .py_2()
                    .text_color(theme.text_muted)
                    .child(gpui::text!("Loading…")),
            ],
            Some(servers) => servers
                .iter()
                .map(|server| {
                    let id = server["id"].as_str().unwrap_or_default().to_owned();
                    let connected = server["connected"] == true;
                    let (sign_in, remove) = (list.clone(), list.clone());
                    let (sign_in_id, remove_id) = (id.clone(), id.clone());
                    div()
                        .flex()
                        .items_center()
                        .justify_between()
                        .gap_4()
                        .min_h(px(44.))
                        .border_b_1()
                        .border_color(theme.border)
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .child(gpui::text!(
                                    server["name"].as_str().unwrap_or_default().to_owned()
                                ))
                                .child(
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
                        .child(
                            div()
                                .flex()
                                .gap_2()
                                .child(
                                    Button::new(
                                        SharedString::from(format!("mcp-sign-in-{id}")),
                                        if connected {
                                            "Sign in again"
                                        } else {
                                            "Sign in"
                                        },
                                        Variant::Secondary,
                                    )
                                    .enabled(!self.busy)
                                    .render(
                                        None,
                                        window,
                                        cx,
                                        move |this, _, cx| {
                                            this.authorize(&sign_in, sign_in_id.clone(), cx)
                                        },
                                    ),
                                )
                                .child(
                                    Button::new(
                                        SharedString::from(format!("mcp-remove-{id}")),
                                        "Remove",
                                        Variant::Secondary,
                                    )
                                    .enabled(!self.busy)
                                    .render(
                                        None,
                                        window,
                                        cx,
                                        move |this, _, cx| {
                                            let mut args = Self::args(&remove);
                                            args["id"] = json!(remove_id.clone());
                                            this.change("remove_mcp_server", args, cx, |_, _, _| {})
                                        },
                                    ),
                                ),
                        )
                })
                .collect(),
        };
        let adding = self.adding.as_ref() == Some(&list);
        let form = if adding {
            div()
                .flex()
                .gap_2()
                .py_2()
                .child(div().flex_1().child(self.input.clone()))
                .child(
                    Button::new(
                        SharedString::from(format!("mcp-add-{key}")),
                        "Add",
                        Variant::Primary,
                    )
                    .enabled(!self.busy)
                    .render(None, window, cx, |this, _, cx| this.add(cx)),
                )
                .child(
                    Button::new(
                        SharedString::from(format!("mcp-cancel-{key}")),
                        "Cancel",
                        Variant::Secondary,
                    )
                    .render(None, window, cx, |this, _, cx| {
                        this.adding = None;
                        cx.notify();
                    }),
                )
        } else {
            div().py_2().child(
                Button::new(
                    SharedString::from(format!("mcp-new-{key}")),
                    "Add server",
                    Variant::Secondary,
                )
                .enabled(!self.busy)
                .render(None, window, cx, move |this, _, cx| {
                    this.adding = Some(list.clone());
                    this.error = None;
                    cx.notify();
                }),
            )
        };
        div()
            .flex()
            .flex_col()
            .child(
                div()
                    .pt_3()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child(gpui::text!(title)),
            )
            .children(rows)
            .child(form)
            .child(
                div()
                    .text_xs()
                    .text_color(theme.text_muted)
                    .child(gpui::text!(footer)),
            )
    }
}

impl Render for McpServersPanel {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        if self.personal.is_none() && self.load.is_empty() {
            self.reload(cx);
        }
        let personal = self.group(None, self.personal.clone(), window, cx);
        let shared = self
            .organization
            .clone()
            .map(|handle| self.group(Some(handle), self.shared.clone(), window, cx));
        div()
            .id("mcp-servers")
            .role(gpui::Role::Group)
            .aria_label("MCP servers")
            .flex()
            .flex_col()
            .child(personal)
            .children(shared)
            .children(self.error.clone().map(|error| {
                div()
                    .py_2()
                    .text_color(theme.error)
                    .child(gpui::text!(error))
            }))
    }
}
