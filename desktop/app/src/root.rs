use std::sync::Arc;

use gpui::{
    AnyView, Context, Entity, FocusHandle, IntoElement, Render, ScrollHandle, SharedString,
    Subscription, Task, Window, div, prelude::*,
};
use tuist_navigation::{Navigation, Route};
use tuist_session::{Accounts, SavedAccount, Session, Status};
use url::Url;

use crate::accounts::{AccountAction, AccountsPanel};
use crate::keyboard::KeyboardControl;
use crate::login::{LogIn, LoginEvent};
use crate::workspace::{Workspace, WorkspaceEvent};

mod titlebar;
pub use titlebar::{ToggleAccountMenu, init};
// These tests locate controls with GPUI debug selectors, which GPUI records only
// with debug assertions, so the optimized release graph cannot run them.
#[cfg(all(test, debug_assertions))]
mod tests;

enum Operation {
    Accounts,
    Menu,
    Switch(SavedAccount),
    Connect(Url),
    SignOut,
    Sync,
}

enum Outcome {
    Accounts(Vec<SavedAccount>, Arc<Session>, Status, bool),
    Connect(Arc<Session>),
    Home(Arc<Session>, Result<Status, String>, bool),
}

/// Switches between the signed-out and signed-in screens. Features own their
/// state; this view only owns which one is shown.
pub struct Root {
    session: Arc<Session>,
    accounts: Accounts,
    navigation: Entity<Navigation>,
    screen: AnyView,
    status: Option<Status>,
    editing_accounts: bool,
    busy: bool,
    error: Option<SharedString>,
    task: Option<Task<()>>,
    menu: Option<Vec<SavedAccount>>,
    menu_selected: usize,
    focus: FocusHandle,
    avatar_focus: FocusHandle,
    settings_focus: FocusHandle,
    menu_focus: FocusHandle,
    menu_previous_focus: Option<FocusHandle>,
    menu_scroll: ScrollHandle,
    settings_scroll: ScrollHandle,
    settings_open: bool,
    _screen_events: Subscription,
    _activation: Subscription,
    _theme: Subscription,
    _appearance: Subscription,
    _updates: Subscription,
}

impl Root {
    pub fn new(
        session: Arc<Session>,
        accounts: Accounts,
        status: Result<Status, String>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        // Other Tuist clients share the credentials, so a sign-in or sign-out
        // from the CLI or the macOS app shows up when the window is focused.
        let activation = cx.observe_window_activation(window, |this, window, cx| {
            if window.is_window_active() && !this.editing_accounts {
                this.perform(Operation::Sync, window, cx);
            }
        });
        let navigation = cx.new(|_| Navigation::default());
        let (screen, status, events) =
            Self::screen_for(&session, &accounts, &navigation, status, window, cx);
        let focus = cx.focus_handle();
        window.focus(&focus, cx);
        Self {
            session,
            accounts,
            navigation,
            screen,
            status,
            editing_accounts: false,
            busy: false,
            error: None,
            task: None,
            menu: None,
            menu_selected: 0,
            focus,
            avatar_focus: cx.focus_handle().tab_stop(true),
            settings_focus: cx.focus_handle().tab_stop(true),
            menu_focus: cx.focus_handle(),
            menu_previous_focus: None,
            menu_scroll: ScrollHandle::new(),
            settings_scroll: ScrollHandle::new(),
            settings_open: false,
            _screen_events: events,
            _activation: activation,
            _theme: cx.observe_global::<crate::theme::ThemeState>(|_, cx| cx.notify()),
            _appearance: cx.observe_window_appearance(window, |_, _, cx| cx.notify()),
            _updates: cx.observe_global::<crate::updates::UpdateState>(|_, cx| cx.notify()),
        }
    }

    pub fn receive_urls(&mut self, urls: Vec<String>, cx: &mut Context<Self>) {
        for url in urls {
            if Route::parse(&url, self.session.server()).is_err()
                && Route::is_server_web_url(&url, self.session.server())
            {
                cx.open_url(&url);
                continue;
            }
            self.navigation.update(cx, |navigation, cx| {
                navigation.receive(&url, self.session.server());
                if matches!(self.status, Some(Status::SignedIn(_))) && !self.editing_accounts {
                    navigation.resume();
                }
                cx.notify();
            });
        }
        cx.notify();
    }

    fn perform(&mut self, operation: Operation, window: &mut Window, cx: &mut Context<Self>) {
        if self.busy {
            return;
        }
        self.busy = true;
        self.error = None;
        let previous_focus = window.focused(cx);
        let previous_screen = self.screen.entity_id();
        // Covered inputs must not keep receiving typing or button activation.
        window.focus(&self.focus, cx);
        let session = self.session.clone();
        let accounts = self.accounts.clone();
        let work = cx.background_executor().spawn(async move {
            let (session, reset) = match operation {
                Operation::Accounts | Operation::Menu => {
                    let menu = matches!(operation, Operation::Menu);
                    let saved = accounts.list(session.server())?;
                    let session = Arc::new(accounts.current_session(session.server().clone())?);
                    let status = session.status()?;
                    return Ok(Outcome::Accounts(saved, session, status, menu));
                }
                Operation::Connect(server) => {
                    return accounts
                        .connect(session.server(), server)
                        .map(|session| Outcome::Connect(Arc::new(session)));
                }
                Operation::Switch(target) => (accounts.switch(session.server(), &target)?, true),
                Operation::SignOut => {
                    accounts.sign_out(&session)?;
                    (accounts.current_session(session.server().clone())?, true)
                }
                Operation::Sync => {
                    accounts.preserve(session.server())?;
                    (accounts.current_session(session.server().clone())?, false)
                }
            };
            let status = session.status().map_err(|error| error.to_string());
            Ok(Outcome::Home(Arc::new(session), status, reset))
        });
        self.task = Some(cx.spawn_in(window, async move |this, cx| {
            let result = work.await;
            let _ = this.update_in(cx, |this, window, cx| {
                this.busy = false;
                match result {
                    Ok(Outcome::Accounts(accounts, session, status, menu)) => {
                        if this.status.as_ref() != Some(&status) {
                            this.reset_navigation(cx);
                            this.home(session.clone(), Ok(status.clone()), false, window, cx);
                        }
                        this.session = session;
                        this.status = Some(status);
                        if menu {
                            this.menu = Some(accounts);
                            this.menu_selected = 0;
                            this.menu_scroll = ScrollHandle::new();
                            window.focus(&this.menu_focus, cx);
                            cx.notify();
                            return;
                        }
                        let id = match &this.status {
                            Some(Status::SignedIn(account)) => Some(account.id.clone()),
                            _ => None,
                        };
                        let server = this.session.server().to_string();
                        let panel =
                            cx.new(|cx| AccountsPanel::new(accounts, server, id, window, cx));
                        this._screen_events = cx.subscribe_in(
                            &panel,
                            window,
                            |this, _, event, window, cx| match event {
                                AccountAction::Select(account) => {
                                    this.perform(Operation::Switch(account.clone()), window, cx)
                                }
                                AccountAction::Connect(server) => {
                                    this.perform(Operation::Connect(server.clone()), window, cx)
                                }
                                AccountAction::Close => {
                                    this.perform(Operation::Sync, window, cx);
                                }
                            },
                        );
                        this.screen = panel.into();
                        this.editing_accounts = true;
                    }
                    Ok(Outcome::Connect(session)) => {
                        this.editing_accounts = true;
                        let (screen, _, events) =
                            Self::log_in(&session, &this.accounts, None, window, cx);
                        this.screen = screen;
                        this._screen_events = events;
                    }
                    Ok(Outcome::Home(session, status, reset)) => {
                        // A focus refresh must also notice a CLI/macOS account change,
                        // not just the transition between signed in and signed out.
                        let changed = this.status.as_ref() != status.as_ref().ok();
                        if reset || changed || this.editing_accounts {
                            let reset = reset
                                || changed && matches!(this.status, Some(Status::SignedIn(_)));
                            this.home(session, status, reset, window, cx);
                        }
                    }
                    Err(error) => this.error = Some(error.to_string().into()),
                }
                if this.screen.entity_id() == previous_screen
                    && this.focus.is_focused(window)
                    && let Some(focus) = previous_focus
                {
                    window.focus(&focus, cx);
                }
                cx.notify();
            });
        }));
        cx.notify();
    }

    fn home(
        &mut self,
        session: Arc<Session>,
        status: Result<Status, String>,
        reset: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if reset {
            self.reset_navigation(cx);
        }
        let (screen, status, events) = Self::screen_for(
            &session,
            &self.accounts,
            &self.navigation,
            status,
            window,
            cx,
        );
        self.session = session;
        self.screen = screen;
        self.status = status;
        self._screen_events = events;
        self.editing_accounts = false;
        self.menu = None;
        self.settings_open = false;
        if matches!(self.status, Some(Status::SignedIn(_))) {
            window.focus(&self.avatar_focus, cx);
        }
        cx.notify();
    }

    fn reset_navigation(&mut self, cx: &mut Context<Self>) {
        self.navigation.update(cx, |nav, cx| {
            // Pending routes were validated for the previous account/server.
            *nav = Navigation::default();
            cx.notify();
        });
    }

    fn screen_for(
        session: &Arc<Session>,
        accounts: &Accounts,
        navigation: &Entity<Navigation>,
        status: Result<Status, String>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> (AnyView, Option<Status>, Subscription) {
        match status {
            Ok(Status::SignedIn(account)) => {
                let server: SharedString = session
                    .server()
                    .as_str()
                    .trim_end_matches('/')
                    .to_owned()
                    .into();
                navigation.update(cx, |nav, cx| {
                    nav.resume();
                    cx.notify();
                });
                let view = cx.new(|cx| {
                    Workspace::new(account.clone(), server, navigation.clone(), window, cx)
                });
                let events = cx.subscribe_in(&view, window, |this, _, event, window, cx| {
                    this.perform(
                        match event {
                            WorkspaceEvent::SignOut => Operation::SignOut,
                        },
                        window,
                        cx,
                    );
                });
                (view.into(), Some(Status::SignedIn(account)), events)
            }
            status => {
                let known = status.as_ref().ok().cloned();
                let error = match status {
                    Ok(Status::Rejected) => Some("Your session expired. Sign in again.".into()),
                    Err(error) => Some(error.into()),
                    _ => None,
                };
                let (view, _, events) = Self::log_in(session, accounts, error, window, cx);
                (view, known, events)
            }
        }
    }

    fn log_in(
        session: &Arc<Session>,
        accounts: &Accounts,
        error: Option<SharedString>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> (AnyView, Option<Status>, Subscription) {
        let view = cx.new(|cx| LogIn::new(session.clone(), accounts.clone(), error, window, cx));
        let events = cx.subscribe_in(&view, window, |this, _, event: &LoginEvent, window, cx| {
            match event {
                LoginEvent::SignedIn(session) => {
                    // Status is local; schedule the read outside the UI thread.
                    this.session = session.clone();
                    if this.editing_accounts {
                        this.reset_navigation(cx);
                    }
                    this.perform(Operation::Sync, window, cx);
                }
                LoginEvent::Accounts => this.perform(Operation::Accounts, window, cx),
            }
        });
        (view.into(), None, events)
    }
}

impl Render for Root {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = crate::theme::Theme::for_appearance(window.appearance(), cx);
        let obscured = self.busy || self.menu.is_some();
        div()
            .id("application")
            .role(gpui::Role::Pane)
            .aria_label("Tuist")
            .track_focus(&self.focus)
            .flex()
            .flex_col()
            .size_full()
            .relative()
            .bg(theme.background)
            .text_color(theme.text)
            .text_sm()
            .on_action(cx.listener(|this, _: &ToggleAccountMenu, window, cx| {
                this.toggle_account_menu(window, cx);
            }))
            .on_action(
                cx.listener(|this, _: &crate::keyboard::NextFocus, window, cx| {
                    if !this.busy {
                        if this.menu.is_some() {
                            this.close_menu(window, cx);
                        }
                        window.focus_next(cx);
                    }
                }),
            )
            .on_action(
                cx.listener(|this, _: &crate::keyboard::PreviousFocus, window, cx| {
                    if !this.busy {
                        if this.menu.is_some() {
                            this.close_menu(window, cx);
                        }
                        window.focus_prev(cx);
                    }
                }),
            )
            .on_key_down(cx.listener(|this, event: &gpui::KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" && this.settings_open && !this.busy {
                    this.settings_open = false;
                    window.focus(&this.avatar_focus, cx);
                    cx.stop_propagation();
                    cx.notify();
                }
            }))
            .child(self.title_bar(theme, window, cx))
            .child(
                div()
                    .id("application-content")
                    .role(gpui::Role::Pane)
                    .a11y_synthetic_children(move |tree| {
                        if obscured {
                            tree.parent_node().set_hidden();
                        }
                    })
                    .flex_1()
                    .min_h_0()
                    .overflow_hidden()
                    .child(if self.settings_open {
                        self.settings(theme, window, cx).into_any_element()
                    } else {
                        self.screen.clone().into_any_element()
                    }),
            )
            .child(
                div()
                    .id("application-status")
                    .role(gpui::Role::Status)
                    .a11y_synthetic_children(move |tree| {
                        tree.parent_node().set_live(gpui::accesskit::Live::Polite);
                        if obscured {
                            tree.parent_node().set_hidden();
                        }
                    })
                    .flex_none()
                    .flex()
                    .items_center()
                    .justify_between()
                    .px_4()
                    .py_1()
                    .bg(theme.sidebar)
                    .text_xs()
                    .text_color(theme.text_muted)
                    .child(gpui::text!(concat!("Tuist ", env!("CARGO_PKG_VERSION"))))
                    .child(
                        div()
                            .id("check-for-updates")
                            .cursor_pointer()
                            .text_color(theme.accent)
                            .keyboard_control(
                                crate::updates::button_label(cx),
                                theme,
                                None,
                                window,
                                cx,
                            )
                            .child(crate::updates::button_label(cx))
                            .on_click(cx.listener(|_, _, _, cx| {
                                cx.dispatch_action(&crate::updates::CheckForUpdates);
                            })),
                    ),
            )
            .when(self.busy, |column| {
                column.child(
                    crate::accessibility::announcement(
                        "account-operation",
                        "Updating accounts…",
                        false,
                    )
                    .absolute()
                    .inset_0()
                    .occlude()
                    .bg(theme.background.opacity(0.8))
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(theme.text_muted),
                )
            })
            .when_some(self.error.clone(), |column, error| {
                column.child(
                    crate::accessibility::announcement("account-error", error, true)
                        .px_4()
                        .py_2()
                        .bg(theme.sidebar)
                        .text_sm()
                        .text_color(theme.error),
                )
            })
            .when_some(self.navigation.read(cx).error, |column, error| {
                column.child(
                    div()
                        .flex()
                        .justify_between()
                        .px_4()
                        .py_2()
                        .bg(theme.sidebar)
                        .text_color(theme.error)
                        .text_sm()
                        .child(crate::accessibility::announcement(
                            "link-error",
                            error.to_string(),
                            true,
                        ))
                        .child(
                            div()
                                .id("dismiss-link-error")
                                .cursor_pointer()
                                .keyboard_control("Dismiss link error", theme, None, window, cx)
                                .child("Dismiss")
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.navigation.update(cx, |nav, cx| {
                                        nav.error = None;
                                        cx.notify();
                                    });
                                    cx.notify();
                                })),
                        ),
                )
            })
            .when(self.menu.is_some(), |column| {
                column.child(self.account_menu(theme, window, cx))
            })
    }
}
