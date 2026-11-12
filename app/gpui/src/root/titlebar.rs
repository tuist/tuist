//! Application chrome stays above workspace navigation, as in Zed's title bar.
//! Account snapshots are loaded off-thread by Root, never while rendering.
use gpui::{
    App, Context, FontWeight, IntoElement, KeyBinding, MouseButton, SharedString, Window,
    WindowControlArea, actions, div, prelude::*, px,
};
use tuist_navigation::Tab;
use tuist_session::{SavedAccount, Status};

use super::{Operation, Root};
use crate::keyboard::KeyboardControl;
use crate::theme::Theme;

actions!(tuist_accounts, [ToggleAccountMenu]);

pub fn init(cx: &mut App) {
    let shortcut = if cfg!(target_os = "macos") {
        "cmd-shift-a"
    } else {
        "ctrl-shift-a"
    };
    cx.bind_keys([KeyBinding::new(shortcut, ToggleAccountMenu, None)]);
}

#[derive(Clone)]
enum MenuAction {
    Profile,
    Switch(SavedAccount),
    Accounts,
    Settings,
    SignOut,
}

struct Entry {
    label: String,
    detail: Option<String>,
    action: MenuAction,
}

fn avatar(label: &str, theme: Theme) -> impl IntoElement {
    let initials: String = label
        .chars()
        .filter(|c| c.is_alphanumeric())
        .take(2)
        .flat_map(char::to_uppercase)
        .collect();
    div()
        .size(px(28.))
        .flex_none()
        .rounded_full()
        .bg(theme.accent)
        .text_color(theme.accent_foreground)
        .text_xs()
        .font_weight(FontWeight::SEMIBOLD)
        .flex()
        .items_center()
        .justify_center()
        .child(if initials.is_empty() {
            "?".to_owned()
        } else {
            initials
        })
}

impl Root {
    pub(super) fn toggle_account_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.menu.is_some() {
            self.close_menu(window, cx);
        } else if !self.busy
            && !self.editing_accounts
            && matches!(self.status, Some(Status::SignedIn(_)))
        {
            self.menu_previous_focus = window.focused(cx);
            self.perform(Operation::Menu, window, cx);
        }
    }

    pub(super) fn close_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.menu = None;
        if let Some(focus) = self.menu_previous_focus.take() {
            window.focus(&focus, cx);
        }
        cx.notify();
    }

    fn menu_entries(&self) -> Vec<Entry> {
        let mut entries = Vec::new();
        if matches!(self.status, Some(Status::SignedIn(_))) {
            entries.push(Entry {
                label: "View profile".into(),
                detail: None,
                action: MenuAction::Profile,
            });
        }
        for account in self.menu.iter().flatten() {
            let active = matches!(&self.status, Some(Status::SignedIn(current)) if current.id == account.id && self.session.server().as_str() == account.server);
            let label = account
                .handle
                .clone()
                .or_else(|| account.email.clone())
                .unwrap_or_else(|| "Tuist account".into());
            let suffix = if account.rejected {
                " · Sign in again"
            } else if active {
                " · Current"
            } else {
                ""
            };
            entries.push(Entry {
                label,
                detail: Some(format!(
                    "{}{}",
                    account.server.trim_end_matches('/'),
                    suffix
                )),
                action: MenuAction::Switch(account.clone()),
            });
        }
        entries.push(Entry {
            label: "Add account or server…".into(),
            detail: None,
            action: MenuAction::Accounts,
        });
        entries.push(Entry {
            label: "App settings…".into(),
            detail: None,
            action: MenuAction::Settings,
        });
        if matches!(self.status, Some(Status::SignedIn(_) | Status::Rejected)) {
            entries.push(Entry {
                label: "Sign out".into(),
                detail: None,
                action: MenuAction::SignOut,
            });
        }
        entries
    }

    fn select_menu_entry(
        &mut self,
        action: MenuAction,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.close_menu(window, cx);
        match action {
            MenuAction::Profile => {
                if let Some(status) = self.status.clone() {
                    self.home(self.session.clone(), Ok(status), false, window, cx);
                    self.navigation.update(cx, |navigation, cx| {
                        navigation.tab = Tab::Profile;
                        cx.notify();
                    });
                }
            }
            MenuAction::Switch(account) => {
                let active = matches!(&self.status, Some(Status::SignedIn(current)) if current.id == account.id && self.session.server().as_str() == account.server);
                if !active || account.rejected {
                    self.settings_open = false;
                    self.perform(Operation::Switch(account), window, cx);
                }
            }
            MenuAction::Accounts => {
                self.settings_open = false;
                self.perform(Operation::Accounts, window, cx);
            }
            MenuAction::Settings => {
                self.settings_open = true;
                window.focus(&self.settings_focus, cx);
            }
            MenuAction::SignOut => self.perform(Operation::SignOut, window, cx),
        }
        cx.notify();
    }

    pub(super) fn title_bar(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let label = match &self.status {
            Some(Status::SignedIn(account)) => account
                .handle
                .clone()
                .or_else(|| account.email.clone())
                .unwrap_or_else(|| "Your account".into()),
            _ => "Accounts".into(),
        };
        let expand = cx.weak_entity();
        let collapse = expand.clone();
        let busy = self.busy;
        div()
            .id("application-titlebar")
            .role(gpui::Role::TitleBar)
            .aria_label("Tuist")
            .a11y_synthetic_children(move |tree| {
                if busy {
                    tree.parent_node().set_hidden();
                }
            })
            .h(px(44.))
            .flex_none()
            .flex()
            .items_center()
            .bg(theme.sidebar)
            .border_b_1()
            .border_color(theme.border)
            .child(
                div()
                    .id("titlebar-drag")
                    .window_control_area(WindowControlArea::Drag)
                    .h_full()
                    .flex_1()
                    .flex()
                    .items_center()
                    .px_4()
                    .when(cfg!(target_os = "macos"), |bar| bar.pl(px(80.)))
                    .text_xs()
                    .font_weight(FontWeight::MEDIUM)
                    .text_color(theme.text_muted)
                    .child("Tuist")
                    .on_mouse_down(MouseButton::Left, |event, window, _| {
                        if cfg!(target_os = "linux") {
                            window.start_window_move();
                        }
                        if cfg!(target_os = "macos") && event.click_count == 2 {
                            window.titlebar_double_click();
                        }
                    }),
            )
            .when(
                !self.editing_accounts && matches!(self.status, Some(Status::SignedIn(_))),
                |bar| {
                    bar.child(
                        div()
                            .id("account-menu-trigger")
                            .debug_selector(|| "account-menu-trigger".into())
                            .mx_2()
                            .px_1()
                            .py_1()
                            .rounded_md()
                            .cursor_pointer()
                            .hover(|button| button.bg(theme.row_hover))
                            .keyboard_control_focused(
                                format!("Account menu for {label}"),
                                theme,
                                None,
                                Some(&self.avatar_focus),
                                window,
                                cx,
                            )
                            .aria_expanded(self.menu.is_some())
                            .aria_keyshortcuts(if cfg!(target_os = "macos") {
                                "Meta+Shift+A"
                            } else {
                                "Control+Shift+A"
                            })
                            .a11y_synthetic_children(|tree| {
                                tree.parent_node()
                                    .set_has_popup(gpui::accesskit::HasPopup::Menu)
                            })
                            .on_a11y_action(gpui::AccessibleAction::Expand, move |_, window, cx| {
                                let _ = expand.update(cx, |root, cx| {
                                    if root.menu.is_none() {
                                        root.toggle_account_menu(window, cx);
                                    }
                                });
                            })
                            .on_a11y_action(
                                gpui::AccessibleAction::Collapse,
                                move |_, window, cx| {
                                    let _ =
                                        collapse.update(cx, |root, cx| root.close_menu(window, cx));
                                },
                            )
                            .child(avatar(&label, theme))
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.toggle_account_menu(window, cx)
                            })),
                    )
                },
            )
            .when(cfg!(target_os = "windows"), |bar| {
                bar.children(
                    [
                        ("window-minimize", "−", WindowControlArea::Min),
                        ("window-maximize", "□", WindowControlArea::Max),
                        ("window-close", "×", WindowControlArea::Close),
                    ]
                    .into_iter()
                    .map(|(id, label, area)| {
                        div()
                            .id(id)
                            .role(gpui::Role::Button)
                            .aria_label(match area {
                                WindowControlArea::Min => "Minimize window",
                                WindowControlArea::Max => "Maximize or restore window",
                                _ => "Close window",
                            })
                            .on_a11y_action(gpui::AccessibleAction::Click, move |_, window, _| {
                                match area {
                                    WindowControlArea::Min => window.minimize_window(),
                                    WindowControlArea::Max => window.zoom_window(),
                                    _ => window.remove_window(),
                                }
                            })
                            .window_control_area(area)
                            .w(px(46.))
                            .h_full()
                            .flex()
                            .items_center()
                            .justify_center()
                            .hover(move |button| {
                                if area == WindowControlArea::Close {
                                    button.bg(theme.error).text_color(gpui::white())
                                } else {
                                    button.bg(theme.row_hover)
                                }
                            })
                            .child(label)
                    }),
                )
            })
    }

    pub(super) fn account_menu(
        &self,
        theme: Theme,
        window: &Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let entries = self.menu_entries();
        let label = match &self.status {
            Some(Status::SignedIn(account)) => account
                .handle
                .clone()
                .or_else(|| account.email.clone())
                .unwrap_or_else(|| "Your account".into()),
            _ => "Accounts and settings".into(),
        };
        div()
            .id("account-menu-overlay")
            .role(gpui::Role::Menu)
            .aria_label("Accounts and settings")
            .absolute()
            .inset_0()
            .occlude()
            .track_focus(&self.menu_focus)
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _, window, cx| {
                    this.close_menu(window, cx);
                    cx.stop_propagation();
                }),
            )
            .on_key_down(cx.listener(|this, event: &gpui::KeyDownEvent, window, cx| {
                let count = this.menu_entries().len();
                match event.keystroke.key.as_str() {
                    "escape" => this.close_menu(window, cx),
                    "tab" => {
                        this.close_menu(window, cx);
                        if event.keystroke.modifiers.shift {
                            window.focus_prev(cx);
                        } else {
                            window.focus_next(cx);
                        }
                    }
                    "up" => this.menu_selected = (this.menu_selected + count - 1) % count,
                    "down" => this.menu_selected = (this.menu_selected + 1) % count,
                    "home" => this.menu_selected = 0,
                    "end" => this.menu_selected = count - 1,
                    "enter" | "space" => {}
                    _ => return,
                }
                this.menu_scroll.scroll_to_item(this.menu_selected);
                cx.stop_propagation();
                cx.notify();
            }))
            .on_key_up(cx.listener(|this, event: &gpui::KeyUpEvent, window, cx| {
                if matches!(event.keystroke.key.as_str(), "enter" | "space")
                    && !event.keystroke.modifiers.modified()
                {
                    if let Some(entry) = this.menu_entries().into_iter().nth(this.menu_selected) {
                        this.select_menu_entry(entry.action, window, cx);
                    }
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .id("account-menu")
                    .absolute()
                    .top(px(48.))
                    .right(px(if cfg!(target_os = "windows") {
                        146.
                    } else {
                        8.
                    }))
                    .w(px(312.))
                    .p_1()
                    .rounded_lg()
                    .bg(theme.background)
                    .border_1()
                    .border_color(theme.border)
                    .shadow_lg()
                    .occlude()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .child(
                        div()
                            .p_3()
                            .flex()
                            .flex_col()
                            .gap_1()
                            .child(div().font_weight(FontWeight::SEMIBOLD).truncate().child(gpui::text!(id = "menu-account-name", label)))
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(theme.text_muted)
                                    .truncate()
                                    .child(gpui::text!(
                                        self.session
                                            .server()
                                            .as_str()
                                            .trim_end_matches('/')
                                            .to_owned()
                                    )),
                            ),
                    )
                    .child(
                        div()
                            .id("account-menu-items")
                            .max_h((window.viewport_size().height - px(146.)).max(px(100.)))
                            .overflow_y_scroll()
                            .track_scroll(&self.menu_scroll)
                            .children(entries.into_iter().enumerate().map(|(index, entry)| {
                                let sign_out = matches!(entry.action, MenuAction::SignOut);
                                let account = matches!(entry.action, MenuAction::Switch(_));
                                let active = match &entry.action {
                                    MenuAction::Switch(account) => matches!(&self.status, Some(Status::SignedIn(current)) if current.id == account.id && self.session.server().as_str() == account.server),
                                    _ => false,
                                };
                                let id = match &entry.action {
                                    MenuAction::Switch(account) => format!("account:{}:{}", account.server, account.id),
                                    _ => entry.label.clone(),
                                };
                                let accessible_label = match &entry.detail {
                                    Some(detail) => format!("{}, {detail}", entry.label),
                                    None => entry.label.clone(),
                                };
                                let root = cx.weak_entity();
                                let assistive_action = entry.action.clone();
                                div()
                                    .id(SharedString::from(id))
                                    .role(if account { gpui::Role::MenuItemRadio } else { gpui::Role::MenuItem })
                                    .aria_label(accessible_label)
                                    .on_a11y_action(gpui::AccessibleAction::Click, move |_, window, cx| {
                                        let _ = root.update(cx, |root, cx| {
                                            root.select_menu_entry(assistive_action.clone(), window, cx);
                                        });
                                    })
                                    .when(account, |row| row.aria_toggled(if active { gpui::Toggled::True } else { gpui::Toggled::False }))
                                    .when(self.menu_selected == index, |row| row.aria_active_descendant())
                                    .p_2()
                                    .rounded_md()
                                    .cursor_pointer()
                                    .flex()
                                    .items_center()
                                    .gap_2()
                                    .when(self.menu_selected == index, |row| {
                                        row.bg(theme.row_selected)
                                    })
                                    .hover(|row| row.bg(theme.row_hover))
                                    .when(sign_out, |row| row.text_color(theme.error))
                                    .when(account, |row| row.child(avatar(&entry.label, theme)))
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
                                                    .child(SharedString::from(entry.label)),
                                            )
                                            .when_some(entry.detail, |row, detail| {
                                                row.child(
                                                    div()
                                                        .truncate()
                                                        .text_xs()
                                                        .text_color(theme.text_muted)
                                                        .child(SharedString::from(detail)),
                                                )
                                            }),
                                    )
                                    .on_click(cx.listener(move |this, _, window, cx| {
                                        this.select_menu_entry(entry.action.clone(), window, cx)
                                    }))
                            })),
                    ),
            )
    }

    pub(super) fn settings(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        div().size_full().flex().flex_col()
            .child(div().h(px(52.)).flex_none().px_6().flex().items_center().justify_between().border_b_1().border_color(theme.border)
                .child(div().id("settings-heading").role(gpui::Role::Heading).aria_label("App settings").aria_level(1).font_weight(FontWeight::SEMIBOLD).child("App settings"))
                .child(div().id("close-settings").px_3().py_1().rounded_md().cursor_pointer().hover(|row| row.bg(theme.row_hover)).child("Done")
                    .keyboard_control_focused("Done with settings", theme, None, Some(&self.settings_focus), window, cx)
                    .on_click(cx.listener(|this, _, window, cx| { this.settings_open = false; window.focus(&this.avatar_focus, cx); cx.notify(); }))))
            .child(div().id("settings-content").flex_1().min_h_0().overflow_y_scroll().track_scroll(&self.settings_scroll).p_6().flex().flex_col().items_center()
                .child(div().w_full().max_w(px(480.)).flex_none().whitespace_normal().flex().flex_col().gap_3()
                    .child(div().text_lg().font_weight(FontWeight::SEMIBOLD).child(gpui::text!("Appearance")))
                    .child(gpui::text!("Follows your operating system"))
                    .child(div().text_color(theme.text_muted).child(gpui::text!("Noora light and dark colors follow your system appearance automatically.")))
                    .child(div().mt_5().text_lg().font_weight(FontWeight::SEMIBOLD).child(gpui::text!("Updates")))
                    .child(gpui::text!(concat!("Tuist ", env!("CARGO_PKG_VERSION"))))
                    .child(div().id("settings-check-updates").px_3().py_2().rounded_md().border_1().border_color(theme.border).cursor_pointer().hover(|row| row.bg(theme.row_hover))
                        .keyboard_control(crate::updates::button_label(cx), theme, Some(&self.settings_scroll), window, cx)
                        .on_a11y_action(gpui::AccessibleAction::Click, |_, _, cx| cx.dispatch_action(&crate::updates::CheckForUpdates))
                        .child(crate::updates::button_label(cx)).on_click(|_, _, cx| cx.dispatch_action(&crate::updates::CheckForUpdates)))
                    .child(div().text_color(theme.text_muted).child(gpui::text!("Updates are downloaded only after signature verification. Installation requires your approval.")))))
    }
}
