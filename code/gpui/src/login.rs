use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use gpui::{
    AnyElement, Context, EventEmitter, FocusHandle, FontWeight, IntoElement, Render, ScrollHandle,
    SharedString, Subscription, Task, Window, div, img, prelude::*, px, svg,
};
use tuist_session::{Accounts, Provider, Session};

use crate::assets;
use crate::keyboard::KeyboardControl;
use crate::theme::Theme;

pub enum LoginEvent {
    SignedIn(Arc<Session>),
    Accounts,
}

/// The signed-out screen, laid out like the Swift app's `LogInView`. It owns
/// the sign-in in progress; the browser round trip runs on background threads.
pub struct LogIn {
    session: Arc<Session>,
    accounts: Accounts,
    cancelled: Option<Arc<AtomicBool>>,
    error: Option<SharedString>,
    scroll: ScrollHandle,
    primary_focus: FocusHandle,
    cancel_focus: FocusHandle,
    _sign_in: Option<Task<()>>,
    _appearance: Subscription,
    _theme: Subscription,
}

impl EventEmitter<LoginEvent> for LogIn {}

impl LogIn {
    pub fn new(
        session: Arc<Session>,
        accounts: Accounts,
        error: Option<SharedString>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let primary_focus = cx.focus_handle().tab_stop(true);
        window.focus(&primary_focus, cx);
        Self {
            session,
            accounts,
            cancelled: None,
            error,
            scroll: ScrollHandle::new(),
            primary_focus,
            cancel_focus: cx.focus_handle().tab_stop(true),
            _sign_in: None,
            _appearance: cx.observe_window_appearance(window, |_, _, cx| cx.notify()),
            _theme: cx.observe_global::<crate::theme::ThemeState>(|_, cx| cx.notify()),
        }
    }

    fn sign_in(&mut self, provider: Provider, window: &mut Window, cx: &mut Context<Self>) {
        if self.cancelled.is_some() {
            return;
        }
        let cancelled = Arc::new(AtomicBool::new(false));
        self.cancelled = Some(cancelled.clone());
        self.error = None;
        window.focus(&self.cancel_focus, cx);
        cx.notify();

        let session = self.session.clone();
        let accounts = self.accounts.clone();
        self._sign_in = Some(cx.spawn_in(window, async move |this, cx| {
            let pending = {
                let session = session.clone();
                cx.background_executor()
                    .spawn(async move { session.begin_sign_in(provider) })
                    .await
            };
            let result = match pending {
                Ok(pending) => {
                    if cancelled.load(Ordering::Relaxed) {
                        let _ = this.update_in(cx, |this, window, cx| {
                            this.cancelled = None;
                            window.focus(&this.primary_focus, cx);
                            cx.notify();
                        });
                        return;
                    }
                    let url = pending.url().to_string();
                    let _ = cx.update(|_, cx| cx.open_url(&url));
                    cx.background_executor()
                        .spawn(async move {
                            accounts
                                .complete_sign_in(&session, pending, &cancelled)
                                .map(Arc::new)
                        })
                        .await
                }
                Err(error) => Err(error),
            };
            let _ = this.update_in(cx, |this, window, cx| {
                this.cancelled = None;
                window.focus(&this.primary_focus, cx);
                match result {
                    Ok(session) => cx.emit(LoginEvent::SignedIn(session)),
                    Err(error) if error.is_cancelled() => {}
                    Err(error) => this.error = Some(error.to_string().into()),
                }
                cx.notify();
            });
        }));
    }

    fn cancel(&mut self, cx: &mut Context<Self>) {
        if let Some(cancelled) = &self.cancelled {
            cancelled.store(true, Ordering::Relaxed);
        }
        cx.notify();
    }

    fn provider_button(
        &self,
        provider: Provider,
        label: &'static str,
        icon: &'static str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        self.button(
            label,
            img(icon).size(px(18.)).into_any_element(),
            provider == Provider::Tuist,
            move |login, window, cx| login.sign_in(provider, window, cx),
            window,
            cx,
        )
    }

    fn button(
        &self,
        label: &'static str,
        icon: AnyElement,
        primary: bool,
        action: impl Fn(&mut Self, &mut Window, &mut Context<Self>) + Clone + 'static,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let busy = self.cancelled.is_some();
        div()
            .id(label)
            .role(gpui::Role::Button)
            .aria_label(label)
            .flex()
            .items_center()
            .justify_center()
            .gap_2()
            .w_full()
            .h(px(40.))
            .rounded_lg()
            .border_1()
            .font_weight(FontWeight::MEDIUM)
            .when(primary, |button| {
                button
                    .bg(theme.accent)
                    .border_color(theme.accent)
                    .text_color(theme.accent_foreground)
            })
            .when(!primary, |button| {
                button.bg(theme.background).border_color(theme.border)
            })
            .when(busy, |button| {
                button.opacity(0.5).a11y_synthetic_children(|tree| {
                    tree.parent_node().set_disabled();
                })
            })
            .when(!busy, |button| {
                let activate = action.clone();
                button
                    .keyboard_control_focused(
                        label,
                        theme,
                        Some(&self.scroll),
                        primary.then_some(&self.primary_focus),
                        window,
                        cx,
                    )
                    .cursor_pointer()
                    .hover(|button| button.opacity(0.85))
                    .on_a11y_action(gpui::AccessibleAction::Click, {
                        let login = cx.weak_entity();
                        move |_, window, cx| {
                            let _ = login.update(cx, |login, cx| activate(login, window, cx));
                        }
                    })
                    .on_click(cx.listener(move |this, _, window, cx| action(this, window, cx)))
            })
            .child(icon)
            .child(label)
    }
}

impl Render for LogIn {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let compact = window.viewport_size().height < px(600.);
        let (apple, github) = if theme.dark {
            (assets::APPLE_DARK, assets::GITHUB_DARK)
        } else {
            (assets::APPLE_LIGHT, assets::GITHUB_LIGHT)
        };

        div()
            .id("login-scroll")
            .role(gpui::Role::Form)
            .aria_label("Sign in to Tuist Code")
            .flex()
            .flex_col()
            .items_center()
            .size_full()
            .overflow_y_scroll()
            .track_scroll(&self.scroll)
            .on_key_down(cx.listener(|this, event: &gpui::KeyDownEvent, _, cx| {
                if event.keystroke.key == "escape" && this.cancelled.is_some() {
                    this.cancel(cx);
                    cx.stop_propagation();
                }
            }))
            .when(compact, |column| column.py_2())
            .when(!compact, |column| column.py_8())
            .bg(theme.sidebar)
            .text_color(theme.text)
            .text_sm()
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_none()
                    .my_auto()
                    .items_center()
                    .w(px(320.))
                    .whitespace_normal()
                    .when(compact, |column| column.gap_2())
                    .when(!compact, |column| {
                        column
                            .gap_3()
                            .child(img(assets::ROUNDED_ICON).size(px(60.)))
                    })
                    .child(
                        div()
                            .id("login-heading")
                            .role(gpui::Role::Heading)
                            .aria_label("Welcome to Tuist Code")
                            .aria_level(1)
                            .when(!compact, |heading| heading.pt_4())
                            .text_2xl()
                            .font_weight(FontWeight::MEDIUM)
                            .child("Welcome to Tuist Code"),
                    )
                    .child(
                        div()
                            .when(!compact, |description| description.pb_4())
                            .text_color(theme.text_muted)
                            .text_center()
                            .child(gpui::text!(
                                "Sign in to access your projects and collaborate with your team"
                            )),
                    )
                    .child(self.provider_button(
                        Provider::Tuist,
                        "Sign in with Tuist",
                        assets::TUIST_LOGO,
                        window,
                        cx,
                    ))
                    .when(
                        self.session.server().as_str() == "https://tuist.dev/",
                        |column| {
                            column
                                .child(self.provider_button(
                                    Provider::Apple,
                                    "Sign in with Apple",
                                    apple,
                                    window,
                                    cx,
                                ))
                                .child(self.provider_button(
                                    Provider::Google,
                                    "Sign in with Google",
                                    assets::GOOGLE_LOGO,
                                    window,
                                    cx,
                                ))
                                .child(self.provider_button(
                                    Provider::GitHub,
                                    "Sign in with GitHub",
                                    github,
                                    window,
                                    cx,
                                ))
                        },
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .w_full()
                            .text_xs()
                            .text_color(theme.text_muted)
                            .child(div().flex_1().h(px(1.)).bg(theme.border))
                            .child("or")
                            .child(div().flex_1().h(px(1.)).bg(theme.border)),
                    )
                    .child(
                        self.button(
                            "Self-hosted server",
                            svg()
                                .path(assets::SERVER_ICON)
                                .size(px(18.))
                                .text_color(theme.text)
                                .into_any_element(),
                            false,
                            |_, _, cx| cx.emit(LoginEvent::Accounts),
                            window,
                            cx,
                        ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_1()
                            .when(!compact, |row| row.pt_2())
                            .text_xs()
                            .text_color(theme.text_muted)
                            .child(gpui::text!(format!(
                                "Server: {}",
                                self.session.server().as_str().trim_end_matches('/')
                            )))
                            // Self-hosted server opens the same panel to add a server; this
                            // link switches to a login saved on this device. It shares the
                            // server row so it stays visible without scrolling.
                            .when(self.cancelled.is_none(), |row| {
                                row.child("·").child(
                                    div()
                                        .id("login-accounts")
                                        .px_1()
                                        .rounded_md()
                                        .text_color(theme.accent)
                                        .cursor_pointer()
                                        .hover(|button| button.bg(theme.row_hover))
                                        .keyboard_control(
                                            "Saved accounts",
                                            theme,
                                            Some(&self.scroll),
                                            window,
                                            cx,
                                        )
                                        .child("Saved accounts…")
                                        .on_a11y_action(gpui::AccessibleAction::Click, {
                                            let login = cx.weak_entity();
                                            move |_, _, cx| {
                                                let _ = login.update(cx, |_, cx| {
                                                    cx.emit(LoginEvent::Accounts)
                                                });
                                            }
                                        })
                                        .on_click(
                                            cx.listener(|_, _, _, cx| {
                                                cx.emit(LoginEvent::Accounts)
                                            }),
                                        ),
                                )
                            }),
                    )
                    .when_some(self.cancelled.as_ref(), |column, _| {
                        column.child(
                            div()
                                .flex()
                                .items_center()
                                .gap_2()
                                .text_color(theme.text_muted)
                                .child(crate::accessibility::announcement(
                                    "login-progress",
                                    "Continue in your browser…",
                                    false,
                                ))
                                .child(
                                    div()
                                        .id("cancel")
                                        .px_2()
                                        .py_1()
                                        .rounded_md()
                                        .cursor_pointer()
                                        .text_color(theme.accent)
                                        .hover(|button| button.bg(theme.row_hover))
                                        .keyboard_control_focused(
                                            "Cancel sign-in",
                                            theme,
                                            Some(&self.scroll),
                                            Some(&self.cancel_focus),
                                            window,
                                            cx,
                                        )
                                        .child("Cancel")
                                        .on_a11y_action(gpui::AccessibleAction::Click, {
                                            let login = cx.weak_entity();
                                            move |_, _, cx| {
                                                let _ =
                                                    login.update(cx, |login, cx| login.cancel(cx));
                                            }
                                        })
                                        .on_click(cx.listener(|this, _, _, cx| this.cancel(cx))),
                                ),
                        )
                    })
                    .when_some(self.error.clone(), |column, error| {
                        column.child(
                            crate::accessibility::announcement("login-error", error, true)
                                .text_center()
                                .text_color(theme.error),
                        )
                    }),
            )
    }
}

impl Drop for LogIn {
    fn drop(&mut self) {
        if let Some(cancelled) = &self.cancelled {
            cancelled.store(true, Ordering::Relaxed);
        }
    }
}
