//! One online review owner, using the same desktop session as Threads.
use super::threads::Http;
use crate::{
    components::{Button, Variant},
    theme::Theme,
};
use gpui::{
    ClipboardItem, Context, FocusHandle, IntoElement, Render, ScrollHandle, SharedString,
    Subscription, Task, Window, div, prelude::*,
};
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};
use tuist_app_core::{ReleaseReviews, Transport, organizations};
use tuist_session::{Account, Session};
use url::Url;

/// A request already in flight may complete, but cannot authorize a subsequent
/// request after deactivation, changing organization, or dropping the workspace.
struct AuthorizedHttp<'a> {
    session: &'a Session,
    epoch: Arc<AtomicU64>,
    generation: u64,
}
impl Transport for AuthorizedHttp<'_> {
    fn send(
        &mut self,
        method: &str,
        url: Url,
        body: Option<Value>,
    ) -> Result<(u64, Value), &'static str> {
        if self.epoch.load(Ordering::SeqCst) != self.generation {
            return Err("The release session changed. Open it again.");
        }
        Http {
            session: self.session,
        }
        .send_guarded(method, url, body, || {
            self.epoch.load(Ordering::SeqCst) == self.generation
        })
    }
}

pub struct ReleasesPanel {
    session: Arc<Session>,
    identity: String,
    personal: Option<String>,
    selected: Option<String>,
    choices: Vec<String>,
    reviews: ReleaseReviews,
    surface: Value,
    open: bool,
    active: bool,
    busy: bool,
    error: Option<String>,
    confirmation: Option<String>,
    definitions: bool,
    epoch: Arc<AtomicU64>,
    task: Option<Task<()>>,
    scroll: ScrollHandle,
    entry: FocusHandle,
    back: FocusHandle,
    activate: FocusHandle,
    cancel: FocusHandle,
    _activation: Subscription,
}

impl Drop for ReleasesPanel {
    fn drop(&mut self) {
        self.epoch.fetch_add(1, Ordering::SeqCst);
    }
}

impl ReleasesPanel {
    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn new(
        session: Arc<Session>,
        account: &Account,
        scroll: ScrollHandle,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        Self {
            session,
            identity: account.id.clone(),
            personal: account.handle.clone(),
            selected: account.handle.clone(),
            choices: Vec::new(),
            reviews: ReleaseReviews::default(),
            surface: Value::Null,
            open: false,
            active: window.is_window_active(),
            busy: false,
            error: None,
            confirmation: None,
            definitions: false,
            epoch: Arc::new(AtomicU64::new(1)),
            task: None,
            scroll,
            entry: cx.focus_handle().tab_stop(true),
            back: cx.focus_handle().tab_stop(true),
            activate: cx.focus_handle().tab_stop(true),
            cancel: cx.focus_handle().tab_stop(true),
            _activation: cx.observe_window_activation(window, |this, window, cx| {
                this.active = window.is_window_active();
                this.clear();
                if this.active && this.open {
                    this.request("releases", None, cx);
                    window.focus(&this.back, cx);
                }
                cx.notify();
            }),
        }
    }

    fn clear(&mut self) {
        self.epoch.fetch_add(1, Ordering::SeqCst);
        self.task = None;
        self.reviews = ReleaseReviews::default();
        self.surface = Value::Null;
        self.choices.clear();
        self.confirmation = None;
        self.definitions = false;
        self.error = None;
        self.busy = false;
    }

    pub fn close(&mut self, cx: &mut Context<Self>) {
        self.clear();
        self.open = false;
        cx.notify();
    }

    fn request(&mut self, operation: &'static str, hash: Option<String>, cx: &mut Context<Self>) {
        if self.busy || !self.active || !self.open {
            return;
        }
        self.busy = true;
        self.error = None;
        self.confirmation = None;
        self.definitions = false;
        // Hide authority immediately, including while a mutation's outcome is unknown.
        self.surface = Value::Null;
        let mut reviews = std::mem::take(&mut self.reviews);
        let session = self.session.clone();
        let identity = self.identity.clone();
        let selected = self.selected.clone();
        let personal = self.personal.clone();
        let epoch = self.epoch.clone();
        let generation = epoch.load(Ordering::SeqCst);
        let work = cx.background_executor().spawn(async move {
            let mut http = AuthorizedHttp {
                session: &session,
                epoch,
                generation,
            };
            let result = (|| {
                let mut choices = organizations(session.server(), &mut http)?;
                if let Some(personal) = personal {
                    choices.insert(0, personal);
                }
                choices.dedup();
                let selected = selected
                    .filter(|s| choices.contains(s))
                    .or_else(|| choices.first().cloned())
                    .ok_or("No release account is available with this session.")?;
                let response = reviews.call(
                    session.server(),
                    &selected,
                    &identity,
                    generation,
                    "desktop",
                    operation,
                    &json!({"hash":hash}),
                    &mut http,
                    |_| true,
                )?;
                Ok::<_, &'static str>((response, choices, selected))
            })();
            (reviews, result)
        });
        self.task = Some(cx.spawn(async move |this, cx| {
            let (reviews, result) = work.await;
            let _ = this.update(cx, |this, cx| {
                if !this.active || !this.open || this.epoch.load(Ordering::SeqCst) != generation {
                    return;
                }
                this.busy = false;
                this.reviews = reviews;
                match result {
                    Ok((response, choices, selected)) => {
                        this.surface = response["surface"].clone();
                        this.error = response["error"].as_str().map(str::to_owned);
                        this.choices = choices;
                        this.selected = Some(selected);
                    }
                    Err(error) => {
                        this.error = Some(error.into());
                        this.reviews = ReleaseReviews::default();
                    }
                }
                cx.notify();
            });
        }));
        cx.notify();
    }
}

impl Render for ReleasesPanel {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let mut body = div()
            .id("release-review")
            .on_key_down(cx.listener(|this, event: &gpui::KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" && this.confirmation.is_some() {
                    this.confirmation = None;
                    window.focus(&this.activate, cx);
                    cx.stop_propagation();
                    cx.notify();
                }
            }))
            .flex()
            .flex_col()
            .gap_3()
            .text_color(theme.text);
        if !self.open {
            return body.child(
                Button::new("open-releases", "Releases", Variant::Secondary)
                    .focus(&self.entry)
                    .render(Some(&self.scroll), window, cx, |this, window, cx| {
                        this.open = true;
                        this.request("releases", None, cx);
                        window.focus(&this.back, cx);
                    }),
            );
        }
        body = body.child(
            Button::new("close-releases", "Back to Profile", Variant::Ghost)
                .focus(&self.back)
                .render(Some(&self.scroll), window, cx, |this, window, cx| {
                    this.close(cx);
                    window.focus(&this.entry, cx);
                }),
        );
        body = body.child(
            div()
                .id("releases-heading")
                .role(gpui::Role::Heading)
                .aria_level(2)
                .child(gpui::text!("Releases")),
        );
        if !self.active {
            return body.child(div().debug_selector(|| "release-inactive".into()).child(
                gpui::text!("Releases are hidden while the window is inactive."),
            ));
        }
        if self.busy {
            return body.child(crate::accessibility::announcement(
                "release-loading",
                "Loading current release state…",
                false,
            ));
        }
        if let Some(error) = &self.error {
            body = body.child(crate::accessibility::announcement(
                "release-error",
                error.clone(),
                true,
            ));
        }
        body = body.child(
            Button::new("refresh-releases", "Refresh releases", Variant::Secondary).render(
                Some(&self.scroll),
                window,
                cx,
                |this, window, cx| {
                    this.request("releases", None, cx);
                    window.focus(&this.back, cx);
                },
            ),
        );
        for (i, choice) in self.choices.clone().into_iter().enumerate() {
            let label = format!(
                "{}{}",
                if self.selected.as_ref() == Some(&choice) {
                    "Selected account: "
                } else {
                    "Account: "
                },
                choice
            );
            body = body.child(
                Button::new(
                    SharedString::from(format!("release-account-{i}")),
                    label,
                    Variant::Ghost,
                )
                .render(Some(&self.scroll), window, cx, move |this, window, cx| {
                    this.clear();
                    this.selected = Some(choice.clone());
                    this.request("releases", None, cx);
                    window.focus(&this.back, cx);
                }),
            );
        }
        let detail = self.surface["detail"].clone();
        if detail.is_object() {
            body = body.child(
                Button::new(
                    "back-to-release-list",
                    "Back to releases",
                    Variant::Secondary,
                )
                .render(Some(&self.scroll), window, cx, |this, window, cx| {
                    this.request("releases", None, cx);
                    window.focus(&this.back, cx);
                })
                .debug_selector(|| "release-detail-back".into()),
            );
            let hash = detail["hash"].as_str().unwrap_or_default().to_owned();
            body = body.child(gpui::text!(format!("{}\nCandidate: {}\nBaseline: {}\nState: {}\nAuthor: {}\nReviewer: {}\nCreated: {}\nActivated: {}\nCompatible: {}\nBlockers: {}",
                detail["title"].as_str().unwrap_or_default(), hash, detail["baseline"], detail["state"], detail["author"], detail["reviewer"], detail["created_at"], detail["active_at"], detail["compatible"], detail["blockers"])));
            body = body.child(gpui::text!(format!(
                "Merge blockers: {}",
                detail["merge_blockers"]
            )));
            match detail["state"].as_str() {
                Some("merging") => {
                    body = body.child(gpui::text!(
                        "Merge outcome is uncertain; awaiting reconciliation."
                    ))
                }
                Some("merged") => {
                    body = body.child(gpui::text!("Merged into main, but not active."))
                }
                Some("merge_conflict") => {
                    body = body.child(gpui::text!("Main moved; a new proposal is required."))
                }
                _ => {}
            }
            let copy_hash = hash.clone();
            body = body.child(
                Button::new(
                    "copy-release-hash",
                    "Copy exact candidate hash",
                    Variant::Secondary,
                )
                .render(Some(&self.scroll), window, cx, move |_, _, cx| {
                    cx.write_to_clipboard(ClipboardItem::new_string(copy_hash.clone()))
                })
                .debug_selector(|| "release-copy-hash".into()),
            );
            let exact = serde_json::to_string_pretty(&detail).unwrap();
            body = body.child(
                Button::new(
                    "copy-release-json",
                    "Copy complete review JSON",
                    Variant::Secondary,
                )
                .render(Some(&self.scroll), window, cx, move |_, _, cx| {
                    cx.write_to_clipboard(ClipboardItem::new_string(exact.clone()))
                }),
            );
            for change in detail["review_changes"].as_array().into_iter().flatten() {
                body = body.child(gpui::text!(format!(
                    "{} {}\nBefore:\n{}\nAfter:\n{}",
                    change["kind"].as_str().unwrap_or_default(),
                    change["path"].as_str().unwrap_or_default(),
                    change["before"].as_str().unwrap_or_default(),
                    change["after"].as_str().unwrap_or_default()
                )));
            }
            body = body.child(
                Button::new(
                    "release-definitions",
                    if self.definitions {
                        "Hide full definitions"
                    } else {
                        "Show full definitions"
                    },
                    Variant::Secondary,
                )
                .render(Some(&self.scroll), window, cx, |this, _, cx| {
                    this.definitions = !this.definitions;
                    cx.notify();
                }),
            );
            if self.definitions {
                body = body.child(gpui::text!(format!(
                    "Baseline definition\n{}\nCandidate definition\n{}",
                    detail["baseline_text"].as_str().unwrap_or_default(),
                    detail["definition_text"].as_str().unwrap_or_default()
                )));
            }
            if let Some(candidate) = self.confirmation.clone() {
                body = body.child(div().id("release-confirmation").role(gpui::Role::Group).aria_label("Confirm release activation")
                    .child(gpui::text!(format!("Confirm activation of exactly {candidate}? This changes the active release.")))
                    .child(Button::new("cancel-release-activation", "Cancel", Variant::Secondary).focus(&self.cancel)
                        .render(Some(&self.scroll), window, cx, |this, window, cx| {
                            this.confirmation = None; window.focus(&this.activate, cx); cx.notify();
                        }))
                    .child(Button::new("confirm-release-activation", "Confirm activation", Variant::Primary)
                        .render(Some(&self.scroll), window, cx, move |this, window, cx| {
                            if this.confirmation.as_ref() == Some(&candidate) {
                                this.request("release_activate", Some(candidate.clone()), cx); window.focus(&this.back, cx);
                            }
                        })));
            } else {
                for action in detail["actions"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                {
                    let candidate = hash.clone();
                    if action == "approve" {
                        body = body.child(
                            Button::new("approve-release", "Approve release", Variant::Primary)
                                .render(Some(&self.scroll), window, cx, move |this, window, cx| {
                                    this.request("release_approve", Some(candidate.clone()), cx);
                                    window.focus(&this.back, cx);
                                }),
                        );
                    } else if action == "merge" {
                        body = body
                            .child(gpui::text!("Merging into main does not activate this release. Activation requires separate confirmation."))
                            .child(Button::new("merge-release", "Merge into main", Variant::Primary)
                                .render(Some(&self.scroll), window, cx, move |this, window, cx| {
                                    this.request("release_merge", Some(candidate.clone()), cx);
                                    window.focus(&this.back, cx);
                                })
                                .debug_selector(|| "release-merge".into()));
                    } else if action == "activate" {
                        body = body.child(
                            Button::new("activate-release", "Activate release…", Variant::Primary)
                                .focus(&self.activate)
                                .render(Some(&self.scroll), window, cx, move |this, window, cx| {
                                    this.confirmation = Some(candidate.clone());
                                    window.focus(&this.cancel, cx);
                                    cx.notify();
                                }),
                        );
                    }
                }
            }
        } else {
            if let Some(active) = self.surface["list"]["active"].as_str() {
                body = body.child(gpui::text!(format!("Active release: {active}")));
            }
            if self.surface["list"]["releases"]
                .as_array()
                .is_some_and(Vec::is_empty)
            {
                body = body.child(gpui::text!("No releases in this account."));
            }
            for (i, row) in self.surface["list"]["releases"]
                .as_array()
                .into_iter()
                .flatten()
                .enumerate()
            {
                let hash = row["hash"].as_str().unwrap_or_default().to_owned();
                let displayed_hash = hash.clone();
                body = body.child(
                    Button::new(
                        SharedString::from(format!("release-{i}")),
                        format!(
                            "{} — {}",
                            row["title"].as_str().unwrap_or_default(),
                            row["state"].as_str().unwrap_or_default(),
                        ),
                        Variant::Ghost,
                    )
                    .render(
                        Some(&self.scroll),
                        window,
                        cx,
                        move |this, window, cx| {
                            this.request("release_open", Some(hash.clone()), cx);
                            window.focus(&this.back, cx);
                        },
                    ),
                );
                body = body.child(gpui::text!(displayed_hash));
            }
        }
        body
    }
}

#[cfg(all(test, debug_assertions))]
mod tests {
    use super::*;
    use gpui::{KeyUpEvent, Keystroke, TestAppContext, VisualTestContext};
    use tuist_credentials::Directories;
    use tuist_session::Accounts;

    fn draw(cx: &mut VisualTestContext) {
        cx.run_until_parked();
        for _ in 0..2 {
            cx.update(|window, cx| window.draw(cx).clear(cx));
        }
    }

    fn enter(cx: &mut VisualTestContext) {
        cx.simulate_keystrokes("enter");
        cx.simulate_event(KeyUpEvent {
            keystroke: Keystroke::parse("enter").unwrap(),
        });
        draw(cx);
    }

    #[gpui::test]
    fn activation_confirmation_captures_exact_hash_and_keyboard_cancel_never_sends(
        cx: &mut TestAppContext,
    ) {
        cx.update(crate::keyboard::init);
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
        let (panel, cx) = cx.add_window_view(|window, cx| {
            ReleasesPanel::new(
                session,
                &Account {
                    id: "user:1".into(),
                    handle: Some("team".into()),
                    email: None,
                },
                ScrollHandle::new(),
                window,
                cx,
            )
        });
        panel.update(cx, |this, cx| {
            this.open = true;
            this.active = true;
            this.surface = json!({"detail":{"hash":"exact-candidate-0123456789", "title":"Release", "state":"approved", "merge_blockers":[], "actions":["merge"]}});
            cx.notify();
        });
        draw(cx);
        assert!(cx.debug_bounds("release-merge").is_some());
        panel.read_with(cx, |this, _| {
            assert!(this.confirmation.is_none());
            assert!(!this.busy);
        });
        panel.update(cx, |this, cx| {
            this.open = true;
            this.active = true;
            this.surface = json!({"detail":{"hash":"exact-candidate-0123456789", "title":"Release", "state":"merged", "actions":["activate"]}});
            cx.notify();
        });
        draw(cx);
        assert!(cx.debug_bounds("release-merge").is_none());
        cx.update(|window, cx| {
            let focus = panel.read(cx).activate.clone();
            window.focus(&focus, cx);
        });
        enter(cx);
        panel.read_with(cx, |this, _| {
            assert_eq!(
                this.confirmation.as_deref(),
                Some("exact-candidate-0123456789")
            );
            assert!(!this.busy);
            assert!(this.task.is_none());
        });
        cx.update(|window, cx| assert!(panel.read(cx).cancel.is_focused(window)));
        enter(cx);
        panel.read_with(cx, |this, _| {
            assert!(this.confirmation.is_none());
            assert!(!this.busy);
            assert!(this.task.is_none());
            assert_eq!(this.surface["detail"]["hash"], "exact-candidate-0123456789");
        });
        cx.update(|window, cx| assert!(panel.read(cx).activate.is_focused(window)));
    }

    #[gpui::test]
    fn deactivation_hides_review_and_foreground_cannot_restore_old_detail(cx: &mut TestAppContext) {
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
        let (panel, cx) = cx.add_window_view(|window, cx| {
            ReleasesPanel::new(
                session.clone(),
                &Account {
                    id: "user:1".into(),
                    handle: None,
                    email: None,
                },
                ScrollHandle::new(),
                window,
                cx,
            )
        });
        cx.update(|window, _| window.activate_window());
        draw(cx);
        panel.update(cx, |this, cx| {
            this.open = true;
            this.surface = json!({"detail":{"hash":"private"}});
            cx.notify();
        });
        draw(cx);
        assert!(cx.debug_bounds("release-detail-back").is_some());
        cx.deactivate_window();
        draw(cx);
        assert!(cx.debug_bounds("release-detail-back").is_none());
        assert!(cx.debug_bounds("release-inactive").is_some());
        cx.update(|window, _| window.activate_window());
        draw(cx);
        assert!(cx.debug_bounds("release-detail-back").is_none());
        assert!(cx.debug_bounds("release-inactive").is_none());
    }
}
