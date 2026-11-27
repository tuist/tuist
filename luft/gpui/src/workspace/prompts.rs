use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use gpui::{
    Context, Entity, EventEmitter, FocusHandle, Focusable, IntoElement, Render, ScrollHandle,
    SharedString, Subscription, Task, Window, div, prelude::*, px,
};
use serde_json::{Value, json};
use tuist_app_core::{Transport, prompts};
use tuist_session::Session;
use url::Url;

use super::{lounges::Scope, threads::Http};
use crate::{
    components::{Button, Variant},
    input::TextInput,
    theme::Theme,
};

gpui::actions!(organization_prompts, [DismissPrompts]);

pub enum PromptEvent {
    Chosen(String),
    Dismissed,
}

/// Luft owns this library; a Tuist organization is only its identity boundary.
pub struct PromptsPanel {
    session: Arc<Session>,
    organization: Option<String>,
    picker: bool,
    rows: Option<Vec<Value>>,
    can_edit: bool,
    editing: Option<Value>,
    confirming: bool,
    name: Entity<TextInput>,
    title: Entity<TextInput>,
    body: Entity<TextInput>,
    error: Option<SharedString>,
    busy: bool,
    task: Option<Task<()>>,
    authorized: Arc<AtomicBool>,
    scope: Option<Subscription>,
    scroll: ScrollHandle,
    focus: FocusHandle,
    back_focus: FocusHandle,
    restore_focus: bool,
    focus_picker: bool,
}

impl EventEmitter<PromptEvent> for PromptsPanel {}

impl Drop for PromptsPanel {
    fn drop(&mut self) {
        self.authorized.store(false, Ordering::SeqCst);
    }
}

pub(super) struct Guarded<'a> {
    pub(super) session: &'a Session,
    pub(super) authorized: &'a AtomicBool,
}

impl Transport for Guarded<'_> {
    fn send(
        &mut self,
        method: &str,
        url: Url,
        body: Option<Value>,
    ) -> Result<(u64, Value), &'static str> {
        Http {
            session: self.session,
        }
        .send_guarded(method, url, body, || self.authorized.load(Ordering::SeqCst))
    }
}

impl PromptsPanel {
    pub fn new(
        session: Arc<Session>,
        organization: Option<String>,
        picker: bool,
        scroll: ScrollHandle,
        cx: &mut Context<Self>,
    ) -> Self {
        Self {
            session,
            organization,
            picker,
            rows: None,
            can_edit: false,
            editing: None,
            confirming: false,
            name: cx.new(|cx| TextInput::named("Prompt command name", "e.g. ship", cx)),
            title: cx.new(|cx| TextInput::named("Prompt title", "Title", cx)),
            body: cx.new(|cx| TextInput::multiline("Prompt instructions", cx)),
            error: None,
            busy: false,
            task: None,
            authorized: Arc::new(AtomicBool::new(true)),
            scope: None,
            scroll,
            focus: cx.focus_handle().tab_stop(true),
            back_focus: cx.focus_handle().tab_stop(true),
            restore_focus: false,
            focus_picker: picker,
        }
    }

    pub fn bind_scope(&mut self, scope: Entity<Scope>, cx: &mut Context<Self>) {
        self.scope = Some(cx.observe(&scope, |this, scope, cx| {
            let organization = scope.read(cx).organization();
            if this.organization != organization {
                this.authorized.store(false, Ordering::SeqCst);
                this.authorized = Arc::new(AtomicBool::new(true));
                this.task = None;
                this.organization = organization;
                this.rows = None;
                this.editing = None;
                this.confirming = false;
                this.can_edit = false;
                this.error = None;
                this.busy = false;
                this.request("prompts", json!({}), cx);
            }
        }));
    }

    fn request(&mut self, operation: &'static str, mut args: Value, cx: &mut Context<Self>) {
        let Some(organization) = self.organization.clone() else {
            return;
        };
        if self.busy {
            return;
        }
        args["account_handle"] = json!(organization);
        let session = self.session.clone();
        let authorized = self.authorized.clone();
        let still_current = authorized.clone();
        self.busy = true;
        self.error = None;
        let work = cx.background_executor().spawn(async move {
            prompts::call(
                session.server(),
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
                if !still_current.load(Ordering::SeqCst)
                    || this.organization.as_ref() != Some(&organization)
                {
                    return;
                }
                this.busy = false;
                match result {
                    Ok(data) if operation == "prompts" => {
                        this.rows = Some(data["prompts"].as_array().cloned().unwrap_or_default());
                        this.can_edit = data["can_edit"] == true;
                    }
                    Ok(_) => {
                        this.editing = None;
                        this.confirming = false;
                        this.restore_focus = true;
                        this.request("prompts", json!({}), cx);
                    }
                    Err(error) => {
                        this.error = Some(error.into());
                        this.restore_focus = true;
                    }
                }
                cx.notify();
            });
        }));
        cx.notify();
    }

    fn edit(&mut self, row: Value, window: &mut Window, cx: &mut Context<Self>) {
        for (input, key) in [
            (&self.name, "name"),
            (&self.title, "title"),
            (&self.body, "body"),
        ] {
            input.update(cx, |input, cx| {
                input.set_value(row[key].as_str().unwrap_or_default().to_owned(), cx)
            });
        }
        self.editing = Some(row.clone());
        self.confirming = false;
        self.error = None;
        window.focus(
            &if self.can_edit {
                if row["name"].is_string() {
                    self.title.focus_handle(cx)
                } else {
                    self.name.focus_handle(cx)
                }
            } else {
                self.back_focus.clone()
            },
            cx,
        );
        cx.notify();
    }

    fn save(&mut self, cx: &mut Context<Self>) {
        if !self.can_edit || self.editing.is_none() {
            return;
        }
        let name = self
            .editing
            .as_ref()
            .and_then(|row| row["name"].as_str())
            .unwrap_or_else(|| self.name.read(cx).value())
            .to_owned();
        self.request("save_prompt", json!({"name": name, "title": self.title.read(cx).value(), "body": self.body.read(cx).value()}), cx);
    }
}

impl Render for PromptsPanel {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        if self.rows.is_none() && !self.busy && self.error.is_none() {
            self.request("prompts", json!({}), cx);
        }
        if !self.busy && (self.restore_focus || self.focus_picker) {
            self.restore_focus = false;
            self.focus_picker = false;
            window.focus(
                &if self.editing.is_some() && self.can_edit {
                    self.body.focus_handle(cx)
                } else {
                    self.focus.clone()
                },
                cx,
            );
        }
        let mut content = div().flex().flex_col().gap_2();
        if let Some(row) = self.editing.clone() {
            let existing = row["name"].is_string();
            content = content.child(gpui::text!(if existing {
                format!("/{}", row["name"].as_str().unwrap_or_default())
            } else {
                "New prompt".to_owned()
            }));
            if self.can_edit {
                if !existing {
                    content = content.child(self.name.clone());
                }
                content = content
                    .child(self.title.clone())
                    .child(self.body.clone())
                    .child(
                        Button::new("save-prompt", "Save prompt", Variant::Primary)
                            .enabled(!self.busy)
                            .render(Some(&self.scroll), window, cx, |this, _, cx| this.save(cx))
                            .debug_selector(|| "save-prompt".into()),
                    );
                if existing {
                    let standard = row["standard"] == true;
                    let label = if standard {
                        "Reset to standard"
                    } else {
                        "Delete prompt"
                    };
                    content = content.child(
                        Button::new("remove-prompt", label, Variant::Secondary)
                            .enabled(!self.busy)
                            .render(Some(&self.scroll), window, cx, |this, _, cx| {
                                this.confirming = true;
                                cx.notify();
                            })
                            .debug_selector(|| "remove-prompt".into()),
                    );
                    if self.confirming {
                        let name = row["name"].as_str().unwrap_or_default().to_owned();
                        content = content
                            .child(gpui::text!(if standard {
                                "Replace your edits with the standard prompt?"
                            } else {
                                "Permanently delete this organization prompt?"
                            }))
                            .child(
                                Button::new("confirm-remove-prompt", "Confirm", Variant::Primary)
                                    .enabled(!self.busy)
                                    .render(Some(&self.scroll), window, cx, move |this, _, cx| {
                                        if this.can_edit {
                                            this.request(
                                                "delete_prompt",
                                                json!({"name": name}),
                                                cx,
                                            );
                                        }
                                    }),
                            )
                            .child(
                                Button::new("keep-prompt", "Keep prompt", Variant::Secondary)
                                    .enabled(!self.busy)
                                    .render(Some(&self.scroll), window, cx, |this, _, cx| {
                                        this.confirming = false;
                                        cx.notify();
                                    }),
                            );
                    }
                }
            } else {
                content = content
                    .child(gpui::text!(
                        row["title"].as_str().unwrap_or_default().to_owned()
                    ))
                    .child(div().whitespace_normal().child(gpui::text!(
                        row["body"].as_str().unwrap_or_default().to_owned()
                    )));
            }
            content = content.child(
                Button::new("close-prompt-editor", "Back to prompts", Variant::Secondary)
                    .focus(&self.back_focus)
                    .enabled(!self.busy)
                    .render(Some(&self.scroll), window, cx, |this, window, cx| {
                        this.editing = None;
                        this.confirming = false;
                        this.error = None;
                        window.focus(&this.focus, cx);
                        cx.notify();
                    }),
            );
        } else if let Some(organization) = self.organization.clone() {
            content = content.child(gpui::text!(format!("Prompts for {organization}")));
            if !self.picker {
                content = content.child(gpui::text!(
                    "Stored in Luft. Members can use prompts; organization admins can edit them."
                ));
            }
            for row in self.rows.clone().unwrap_or_default() {
                let name = row["name"].as_str().unwrap_or_default().to_owned();
                let selector = format!("prompt-{name}");
                let title = row["title"].as_str().unwrap_or_default();
                let standard = if row["standard"] == true {
                    " · Standard"
                } else {
                    ""
                };
                content = content.child(
                    Button::new(
                        SharedString::from(format!("prompt-{name}")),
                        format!("{title} /{name}{standard}"),
                        Variant::Secondary,
                    )
                    .enabled(!self.busy)
                    .render(Some(&self.scroll), window, cx, move |this, window, cx| {
                        if this.picker {
                            cx.emit(PromptEvent::Chosen(name.clone()));
                        } else {
                            this.edit(row.clone(), window, cx);
                        }
                    })
                    .debug_selector(move || selector.clone()),
                );
            }
            if self.busy {
                content = content.child(gpui::text!("Loading…"));
            }
            if self.can_edit && !self.picker {
                content = content.child(
                    Button::new("new-prompt", "New prompt", Variant::Primary)
                        .enabled(!self.busy)
                        .render(Some(&self.scroll), window, cx, |this, window, cx| {
                            this.edit(json!({}), window, cx)
                        }),
                );
            }
            content = content.child(
                Button::new("refresh-prompts", "Refresh prompts", Variant::Secondary)
                    .focus(&self.focus)
                    .enabled(!self.busy)
                    .render(Some(&self.scroll), window, cx, |this, _, cx| {
                        this.request("prompts", json!({}), cx)
                    }),
            );
        } else {
            content = content.child(gpui::text!("Select an organization in Lounges to manage its prompts. Personal accounts have no shared prompts."));
        }
        div()
            .id("organization-prompts")
            .role(gpui::Role::Group)
            .aria_label("Organization prompts")
            .key_context("OrganizationPrompts")
            .on_action(cx.listener(|this, _: &DismissPrompts, window, cx| {
                if this.busy {
                    return;
                }
                if this.picker {
                    cx.emit(PromptEvent::Dismissed);
                } else if this.editing.is_some() {
                    this.editing = None;
                    this.confirming = false;
                    this.error = None;
                    window.focus(&this.focus, cx);
                    cx.notify();
                }
            }))
            .flex()
            .flex_col()
            .gap_2()
            .min_w_0()
            .when(self.picker, |panel| {
                panel
                    .max_h(px(260.))
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
            })
            .child(content)
            .children(
                self.error
                    .clone()
                    .map(|error| div().text_color(theme.error).child(gpui::text!(error))),
            )
    }
}

#[cfg(all(test, debug_assertions))]
mod tests {
    use super::*;
    use gpui::{Modifiers, TestAppContext};
    use tuist_credentials::Directories;
    use tuist_session::Accounts;

    #[gpui::test]
    fn members_can_read_multiline_prompts_but_only_admins_get_mutations(cx: &mut TestAppContext) {
        cx.update(|cx| {
            crate::keyboard::init(cx);
            crate::input::init(cx);
            super::super::init(cx);
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
        for can_edit in [false, true] {
            let session = session.clone();
            let (panel, cx) = cx.add_window_view(|_, cx| {
                let mut panel = PromptsPanel::new(session, Some("team".into()), false, ScrollHandle::new(), cx);
                panel.rows = Some(vec![json!({"name":"ship", "title":"Ship", "body":"First line\nSecond line", "standard":true})]);
                panel.can_edit = can_edit;
                panel
            });
            cx.update(|window, cx| window.draw(cx).clear(cx));
            let row = cx.debug_bounds("prompt-ship").unwrap();
            cx.simulate_click(row.center(), Modifiers::none());
            cx.update(|window, cx| window.draw(cx).clear(cx));
            assert_eq!(cx.debug_bounds("save-prompt").is_some(), can_edit);
            assert_eq!(cx.debug_bounds("remove-prompt").is_some(), can_edit);
            if can_edit {
                panel.read_with(cx, |panel, cx| {
                    assert_eq!(panel.body.read(cx).value(), "First line\nSecond line")
                });
            }
            cx.dispatch_action(DismissPrompts);
            cx.update(|window, cx| window.draw(cx).clear(cx));
            assert!(cx.debug_bounds("prompt-ship").is_some());
        }
    }
}
