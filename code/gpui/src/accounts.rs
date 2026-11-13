use gpui::{
    Bounds, Context, Entity, EventEmitter, FocusHandle, FontWeight, IntoElement, Pixels, Render,
    ScrollHandle, SharedString, Subscription, Window, canvas, div, prelude::*, px,
};
use std::{cell::Cell, rc::Rc};
use tuist_session::{SavedAccount, validate_server};
use url::Url;

use crate::input::{Submitted, TextInput};
use crate::keyboard::KeyboardControl;
use crate::theme::Theme;

pub enum AccountAction {
    Select(SavedAccount),
    Connect(Url),
    Close,
}

/// Account metadata only. Tokens and disk access belong to the session layer.
pub struct AccountsPanel {
    accounts: Vec<SavedAccount>,
    current: Option<(String, String)>,
    input: Entity<TextInput>,
    error: Option<SharedString>,
    scroll: ScrollHandle,
    input_bounds: Rc<Cell<Bounds<Pixels>>>,
    done_focus: FocusHandle,
    _input_focus: Subscription,
    _submitted: Subscription,
    _theme: Subscription,
    _appearance: Subscription,
}

impl EventEmitter<AccountAction> for AccountsPanel {}

impl AccountsPanel {
    pub fn new(
        accounts: Vec<SavedAccount>,
        server: String,
        current_id: Option<String>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let input = cx.new(|cx| {
            let mut input = TextInput::new("https://tuist.dev", cx);
            input.set_value(server.clone(), cx);
            input
        });
        let submitted = cx.subscribe(&input, |this, _, _: &Submitted, cx| this.connect(cx));
        let scroll = ScrollHandle::new();
        let input_bounds = Rc::new(Cell::new(Bounds::default()));
        let bounds = input_bounds.clone();
        let input_scroll = scroll.clone();
        let focus = input.read(cx).focus_handle.clone();
        let input_focus = cx.on_focus(&focus, window, move |_, window, cx| {
            crate::keyboard::reveal(bounds.get(), &input_scroll, window, cx);
            cx.notify();
        });
        let done_focus = cx.focus_handle().tab_stop(true);
        window.focus(&done_focus, cx);
        Self {
            accounts,
            current: current_id.map(|id| (server, id)),
            input,
            error: None,
            scroll,
            input_bounds,
            done_focus,
            _input_focus: input_focus,
            _submitted: submitted,
            _theme: cx.observe_global::<crate::theme::ThemeState>(|_, cx| cx.notify()),
            _appearance: cx.observe_window_appearance(window, |_, _, cx| cx.notify()),
        }
    }

    fn connect(&mut self, cx: &mut Context<Self>) {
        match validate_server(self.input.read(cx).value()) {
            Ok(server) => {
                self.input
                    .update(cx, |input, cx| input.set_validation_error(None, cx));
                cx.emit(AccountAction::Connect(server));
            }
            Err(_) => {
                self.error = Some(
                    "Enter an HTTPS server URL without credentials, a query, or a fragment.".into(),
                );
                self.input.update(cx, |input, cx| {
                    input.set_validation_error(self.error.clone(), cx)
                });
                cx.notify();
            }
        }
    }
}

impl Render for AccountsPanel {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        div()
            .id("accounts-page")
            .role(gpui::Role::Form)
            .aria_label("Accounts and servers")
            .size_full()
            .flex()
            .flex_col()
            .bg(theme.background)
            .text_color(theme.text)
            .text_sm()
            .on_key_down(cx.listener(|_, event: &gpui::KeyDownEvent, _, cx| {
                if event.keystroke.key == "escape" {
                    cx.emit(AccountAction::Close);
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .h(px(52.))
                    .flex_none()
                    .flex()
                    .items_center()
                    .justify_between()
                    .px_6()
                    .border_b_1()
                    .border_color(theme.border)
                    .child(
                        div()
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(gpui::text!("Accounts")),
                    )
                    .child(
                        div()
                            .id("close-accounts")
                            .px_3()
                            .py_1()
                            .rounded_md()
                            .cursor_pointer()
                            .hover(|row| row.bg(theme.row_hover))
                            .keyboard_control_focused(
                                "Done with accounts",
                                theme,
                                None,
                                Some(&self.done_focus),
                                window,
                                cx,
                            )
                            .child("Done")
                            .on_click(cx.listener(|_, _, _, cx| cx.emit(AccountAction::Close))),
                    ),
            )
            .child(
                div()
                    .id("account-list")
                    .debug_selector(|| "account-scroll-viewport".into())
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .flex()
                    .flex_col()
                    .items_center()
                    .px_6()
                    .py_6()
                    .child(
                        div()
                            .w_full()
                            .max_w(px(480.))
                            .flex_none()
                            .whitespace_normal()
                            .flex()
                            .flex_col()
                            .gap_2()
                            .child(
                                div()
                                    .id("accounts-heading")
                                    .role(gpui::Role::Heading)
                                    .aria_label("Your accounts")
                                    .aria_level(1)
                                    .text_xl()
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .child("Your accounts"),
                            )
                            .child(div().mb_3().text_color(theme.text_muted).child(gpui::text!(
                                "Choose an account or connect to another server."
                            )))
                            .when(self.accounts.is_empty(), |column| {
                                column.child(
                                    div()
                                        .py_3()
                                        .text_color(theme.text_muted)
                                        .child(gpui::text!("No saved accounts yet.")),
                                )
                            })
                            .children(self.accounts.iter().map(|account| {
                                let active = self.current.as_ref().is_some_and(|(server, id)| {
                                    server == &account.server && id == &account.id
                                });
                                let account = account.clone();
                                let label = match (&account.handle, &account.email) {
                                    (Some(handle), Some(email)) => format!("{handle} · {email}"),
                                    (handle, email) => handle
                                        .clone()
                                        .or_else(|| email.clone())
                                        .unwrap_or_else(|| "Tuist account".into()),
                                };
                                let state = if account.rejected {
                                    "Sign in again"
                                } else if active {
                                    "Current account"
                                } else {
                                    "Switch account"
                                };
                                let accessible_label = format!(
                                    "{label}, {}, {state}",
                                    account.server.trim_end_matches('/')
                                );
                                div()
                                    .id(SharedString::from(format!(
                                        "account:{}:{}",
                                        account.server, account.id
                                    )))
                                    .role(gpui::Role::Button)
                                    .aria_label(accessible_label.clone())
                                    .when(active && !account.rejected, |row| {
                                        row.a11y_synthetic_children(|tree| {
                                            tree.parent_node().set_disabled()
                                        })
                                    })
                                    .flex_none()
                                    .flex()
                                    .items_center()
                                    .justify_between()
                                    .gap_4()
                                    .p_3()
                                    .rounded_lg()
                                    .border_1()
                                    .border_color(theme.border)
                                    .when(active, |row| row.bg(theme.row_selected))
                                    .when(!active, |row| {
                                        row.cursor_pointer().hover(|row| row.bg(theme.row_hover))
                                    })
                                    .child(
                                        div()
                                            .min_w_0()
                                            .flex_1()
                                            .flex()
                                            .flex_col()
                                            .gap_1()
                                            .child(
                                                div()
                                                    .truncate()
                                                    .font_weight(FontWeight::MEDIUM)
                                                    .child(SharedString::from(label)),
                                            )
                                            .child(
                                                div()
                                                    .truncate()
                                                    .text_xs()
                                                    .text_color(theme.text_muted)
                                                    .child(SharedString::from(
                                                        account
                                                            .server
                                                            .trim_end_matches('/')
                                                            .to_owned(),
                                                    )),
                                            ),
                                    )
                                    .child(
                                        div().flex_none().text_xs().text_color(theme.accent).child(
                                            if account.rejected {
                                                "Sign in again"
                                            } else if active {
                                                "Current"
                                            } else {
                                                "Switch"
                                            },
                                        ),
                                    )
                                    .when(!active || account.rejected, |row| {
                                        row.keyboard_control(
                                            accessible_label,
                                            theme,
                                            Some(&self.scroll),
                                            window,
                                            cx,
                                        )
                                        .on_a11y_action(gpui::AccessibleAction::Click, {
                                            let panel = cx.weak_entity();
                                            let account = account.clone();
                                            move |_, _, cx| {
                                                let _ = panel.update(cx, |_, cx| {
                                                    cx.emit(AccountAction::Select(account.clone()));
                                                });
                                            }
                                        })
                                        .on_click(
                                            cx.listener(move |_, _, _, cx| {
                                                cx.emit(AccountAction::Select(account.clone()));
                                            }),
                                        )
                                    })
                            }))
                            .child(
                                div()
                                    .mt_5()
                                    .mb_1()
                                    .font_weight(FontWeight::MEDIUM)
                                    .child(gpui::text!("Add an account or server")),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(theme.text_muted)
                                    .child(gpui::text!(
                                        "Use https://tuist.dev or your self-hosted Tuist URL."
                                    )),
                            )
                            .child(
                                div()
                                    .id("server-url-field")
                                    .debug_selector(|| "server-url-field".into())
                                    .relative()
                                    .child(self.input.clone())
                                    .child({
                                        let bounds = self.input_bounds.clone();
                                        canvas(
                                            move |value, _, _| bounds.set(value),
                                            |_, _, _, _| {},
                                        )
                                        .absolute()
                                        .inset_0()
                                    }),
                            )
                            .when_some(self.error.clone(), |column, error| {
                                column.child(
                                    crate::accessibility::announcement(
                                        "server-validation-error",
                                        error,
                                        true,
                                    )
                                    .debug_selector(|| "server-url-error".into())
                                    .text_xs()
                                    .text_color(theme.error),
                                )
                            })
                            .child(
                                div()
                                    .id("connect-server")
                                    .mt_1()
                                    .px_3()
                                    .py_2()
                                    .rounded_md()
                                    .bg(theme.accent)
                                    .text_color(theme.accent_foreground)
                                    .text_center()
                                    .cursor_pointer()
                                    .hover(|button| button.opacity(0.85))
                                    .keyboard_control(
                                        "Continue to sign in",
                                        theme,
                                        Some(&self.scroll),
                                        window,
                                        cx,
                                    )
                                    .child("Continue to sign in")
                                    .on_a11y_action(gpui::AccessibleAction::Click, {
                                        let panel = cx.weak_entity();
                                        move |_, _, cx| {
                                            let _ = panel.update(cx, |panel, cx| panel.connect(cx));
                                        }
                                    })
                                    .on_click(cx.listener(|this, _, _, cx| this.connect(cx))),
                            )
                            .child(div().mt_1().text_xs().text_color(theme.text_muted).child(
                                gpui::text!(
                                    "Adding a different login? Sign out in your browser first."
                                ),
                            )),
                    ),
            )
    }
}
