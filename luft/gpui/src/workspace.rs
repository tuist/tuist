use gpui::{
    App, Context, Entity, EventEmitter, FocusHandle, FontWeight, IntoElement, KeyBinding, Pixels,
    Render, ScrollHandle, SharedString, Subscription, Window, actions, div, prelude::*, px, svg,
};
use std::sync::Arc;
use tuist_navigation::{Navigation, Tab as Destination};
use tuist_session::{Account, Session};

use crate::assets;
use crate::keyboard::KeyboardControl;
use crate::theme::{Theme, ThemeState};
use tuist_app_core::theme as theme_catalog;

mod live;
mod lounges;
mod preview;
mod socket;
mod subscriptions;
mod threads;

use lounges::{LoungesPanel, Scope};
use subscriptions::SubscriptionsPanel;
use threads::ThreadsPanel;

actions!(
    tuist_workspace,
    [ShowThreads, ShowLounges, ShowDms, ShowProfile]
);

/// Modifier+1 to 4 select the dock's destinations in order, as in chat apps.
/// Application shortcuts use Cmd on the macOS development host.
pub fn init(cx: &mut App) {
    let keys = if cfg!(target_os = "macos") {
        ["cmd-1", "cmd-2", "cmd-3", "cmd-4"]
    } else {
        ["ctrl-1", "ctrl-2", "ctrl-3", "ctrl-4"]
    };
    cx.bind_keys([
        KeyBinding::new(keys[0], ShowThreads, None),
        KeyBinding::new(keys[1], ShowLounges, None),
        KeyBinding::new(keys[2], ShowDms, None),
        KeyBinding::new(keys[3], ShowProfile, None),
    ]);
}

/// The shortcut shown next to a destination in the dock.
fn shortcut(destination: Destination) -> String {
    let modifier = if cfg!(target_os = "macos") {
        "⌘"
    } else {
        "Ctrl+"
    };
    format!("{modifier}{}", destination as usize + 1)
}

pub enum WorkspaceEvent {
    SignOut,
}

fn title(destination: Destination) -> &'static str {
    match destination {
        Destination::Threads => "Threads",
        Destination::Lounges => "Lounges",
        Destination::Dms => "DMs",
        Destination::Profile => "Profile",
    }
}

fn icon(destination: Destination) -> &'static str {
    match destination {
        Destination::Threads => assets::THREADS_ICON,
        Destination::Lounges => assets::LOUNGES_ICON,
        Destination::Dms => assets::DMS_ICON,
        Destination::Profile => assets::PROFILE_ICON,
    }
}

/// Initials stand in for an avatar image, which the token contract does not provide.
pub fn avatar(label: &str, size: Pixels, theme: Theme) -> gpui::Div {
    let initials: String = label
        .chars()
        .filter(|c| c.is_alphanumeric())
        .take(2)
        .flat_map(char::to_uppercase)
        .collect();
    div()
        .size(size)
        .flex_none()
        .rounded_full()
        .bg(theme.accent)
        .text_color(theme.accent_foreground)
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

/// The signed-in shell, laid out like Zed's workspace: a left dock of
/// destinations next to the selected one, under the application title bar.
pub struct Workspace {
    navigation: Entity<Navigation>,
    account: Account,
    server: SharedString,
    scroll: ScrollHandle,
    threads: Entity<ThreadsPanel>,
    lounges: Entity<LoungesPanel>,
    dms: Entity<LoungesPanel>,
    subscriptions: Entity<SubscriptionsPanel>,
    /// One per destination, so closing a preview can return focus to the sidebar.
    destination_focus: [FocusHandle; Destination::ALL.len()],
    _appearance: Subscription,
    _navigation: Subscription,
    _theme: Subscription,
}

impl EventEmitter<WorkspaceEvent> for Workspace {}

impl Workspace {
    pub fn new(
        account: Account,
        server: SharedString,
        session: Arc<Session>,
        navigation: Entity<Navigation>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let handle = account.handle.clone();
        let scope = cx.new(|cx| Scope::new(session.clone(), handle.clone(), window, cx));
        let [lounges, dms] = [Destination::Lounges, Destination::Dms].map(|tab| {
            cx.new(|cx| {
                LoungesPanel::new(tab, session.clone(), scope.clone(), navigation.clone(), cx)
            })
        });
        let subscriptions = cx.new(|cx| SubscriptionsPanel::new(session.clone(), window, cx));
        let threads =
            cx.new(|cx| ThreadsPanel::new(session, handle, navigation.clone(), window, cx));
        // Profile follows the AI subscriptions' live socket only while it shows.
        let observer = cx.observe(&navigation, |this: &mut Self, _, cx| {
            this.sync_subscriptions(cx);
            cx.notify();
        });
        let mut workspace = Self {
            navigation,
            account,
            server,
            scroll: ScrollHandle::new(),
            threads,
            lounges,
            dms,
            subscriptions,
            destination_focus: Destination::ALL.map(|_| cx.focus_handle().tab_stop(true)),
            _appearance: cx.observe_window_appearance(window, |_, _, cx| cx.notify()),
            _navigation: observer,
            _theme: cx.observe_global::<crate::theme::ThemeState>(|_, cx| cx.notify()),
        };
        workspace.sync_subscriptions(cx);
        workspace
    }

    fn sync_subscriptions(&mut self, cx: &mut Context<Self>) {
        let navigation = self.navigation.read(cx);
        let visible = navigation.tab == Destination::Profile && navigation.preview.is_none();
        self.subscriptions
            .update(cx, |panel, cx| panel.set_visible(visible, cx));
    }

    /// Selects a destination from the keyboard and focuses its dock row, so
    /// focus never stays on a control of the destination it left.
    pub fn show(&mut self, destination: Destination, window: &mut Window, cx: &mut Context<Self>) {
        self.navigation.update(cx, |navigation, cx| {
            navigation.select(destination);
            cx.notify();
        });
        window.focus(&self.destination_focus[destination as usize], cx);
    }

    fn sidebar(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let current = self.navigation.read(cx).tab;
        div()
            .id("primary-navigation")
            .role(gpui::Role::Navigation)
            .aria_label("Primary navigation")
            .flex()
            .flex_col()
            .w(px(200.))
            .h_full()
            .flex_none()
            .gap_0p5()
            .p_1p5()
            .bg(theme.sidebar)
            .border_r_1()
            .border_color(theme.border)
            .children(Destination::ALL.into_iter().map(|destination| {
                let selected = destination == current;
                div()
                    .id(title(destination))
                    .flex()
                    .items_center()
                    .gap_2()
                    .h(px(28.))
                    .px_1p5()
                    .rounded_sm()
                    .cursor_pointer()
                    .text_color(if selected {
                        theme.text
                    } else {
                        theme.text_muted
                    })
                    .when(selected, |row| row.bg(theme.row_selected))
                    .when(!selected, |row| row.hover(|row| row.bg(theme.row_hover)))
                    .keyboard_control_focused(
                        title(destination),
                        theme,
                        None,
                        Some(&self.destination_focus[destination as usize]),
                        window,
                        cx,
                    )
                    .when(selected, |row| row.aria_description("Current section"))
                    .child(
                        svg()
                            .path(icon(destination))
                            .size(px(16.))
                            .flex_none()
                            .text_color(if selected {
                                theme.accent
                            } else {
                                theme.text_muted
                            }),
                    )
                    .child(title(destination))
                    .child(
                        div()
                            .ml_auto()
                            .text_xs()
                            .text_color(theme.text_muted)
                            .child(shortcut(destination)),
                    )
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.navigation.update(cx, |navigation, cx| {
                            navigation.select(destination);
                            cx.notify();
                        });
                    }))
            }))
    }

    /// The shipping apps' Profile page (`app/Sources/TuistProfile/ProfileView.swift`),
    /// laid out as a Zed settings page: sections of rows separated by dividers.
    fn profile(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let handle = self.account.handle.clone();
        let email = self.account.email.clone();
        let name = handle
            .clone()
            .or_else(|| email.clone())
            .unwrap_or_else(|| "Tuist".into());
        let section = |label: &'static str| {
            div()
                .pt_6()
                .pb_1()
                .text_xs()
                .font_weight(FontWeight::MEDIUM)
                .text_color(theme.text_muted)
                .child(gpui::text!(label))
        };
        let row = |id: &'static str| {
            div()
                .id(id)
                .flex()
                .items_center()
                .justify_between()
                .gap_4()
                .min_h(px(36.))
                .border_b_1()
                .border_color(theme.border)
        };
        let value = |id: &'static str, label: &'static str, value: String| {
            row(id)
                .role(gpui::Role::Group)
                .aria_label(label)
                .child(div().child(label))
                .child(
                    div()
                        .truncate()
                        .text_color(theme.text_muted)
                        .child(gpui::text!(value)),
                )
        };
        let mut link = |id: &'static str, label: &'static str, url: &'static str| {
            row(id)
                .cursor_pointer()
                .hover(|row| row.text_color(theme.accent))
                .keyboard_control(label, theme, Some(&self.scroll), window, cx)
                .on_a11y_action(gpui::AccessibleAction::Click, move |_, _, cx| {
                    cx.open_url(url)
                })
                .on_click(move |_, _, cx| cx.open_url(url))
                .child(label)
                .child(
                    svg()
                        .path(assets::EXTERNAL_LINK_ICON)
                        .size(px(14.))
                        .text_color(theme.text_muted),
                )
        };
        let terms = link("terms", "Terms of Service", "https://tuist.dev/terms");
        let privacy = link("privacy", "Privacy Policy", "https://tuist.dev/privacy");
        let help = link("help", "Get help", "mailto:contact@tuist.dev");
        let themes = self.themes(theme, window, cx);
        div()
            .flex()
            .flex_col()
            .w_full()
            .max_w(px(640.))
            .mx_auto()
            .px_8()
            .py_6()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_3()
                    .child(avatar(&name, px(48.), theme).text_base())
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .min_w_0()
                            .child(
                                div()
                                    .text_base()
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .truncate()
                                    .child(gpui::text!(
                                        id = "profile-handle",
                                        handle.map_or(name, |handle| format!("@{handle}"))
                                    )),
                            )
                            .child(
                                div()
                                    .text_color(theme.text_muted)
                                    .truncate()
                                    .child(gpui::text!(self.server.to_string())),
                            ),
                    ),
            )
            .child(section("Account"))
            .child(value(
                "email",
                "Email",
                email.unwrap_or_else(|| "Not provided".into()),
            ))
            .child(value("server", "Server", self.server.to_string()))
            .child(section("AI subscriptions"))
            .child(self.subscriptions.clone())
            .child(section("Theme"))
            .child(themes)
            .child(section("Legal"))
            .child(terms)
            .child(privacy)
            .child(section("Support"))
            .child(help)
            .child(value(
                "app-version",
                "App version",
                env!("CARGO_PKG_VERSION").into(),
            ))
            .child(
                div().flex().pt_6().child(
                    div()
                        .id("sign-out")
                        .px_3()
                        .py_1()
                        .rounded_sm()
                        .border_1()
                        .border_color(theme.border)
                        .text_color(theme.error)
                        .cursor_pointer()
                        .hover(|button| button.bg(theme.row_hover))
                        .keyboard_control("Sign out", theme, Some(&self.scroll), window, cx)
                        .child("Sign out")
                        .on_a11y_action(gpui::AccessibleAction::Click, {
                            let workspace = cx.weak_entity();
                            move |_, _, cx| {
                                let _ =
                                    workspace.update(cx, |_, cx| cx.emit(WorkspaceEvent::SignOut));
                            }
                        })
                        .on_click(cx.listener(|_, _, _, cx| cx.emit(WorkspaceEvent::SignOut))),
                ),
            )
    }

    /// One previewed choice per theme: the desktop's Omarchy theme while one is
    /// active, then the core's catalog, Noora first.
    fn themes(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let state = cx.try_global::<ThemeState>().cloned().unwrap_or_default();
        let dark = matches!(
            window.appearance(),
            gpui::WindowAppearance::Dark | gpui::WindowAppearance::VibrantDark
        );
        let choices = state
            .omarchy
            .map(|palette| (crate::theme::OMARCHY, "Desktop", palette))
            .into_iter()
            .chain(
                theme_catalog::themes()
                    .iter()
                    .map(|choice| (choice.id, choice.name, choice.palette(dark).into())),
            );
        let mut tiles = Vec::new();
        for (id, name, palette) in choices {
            let selected = id == state.current();
            let swatch = Theme::from_palette(palette);
            let line = |width: f32, color| div().h(px(4.)).w(px(width)).rounded_full().bg(color);
            tiles.push(
                div()
                    .id(SharedString::from(format!("theme-{id}")))
                    .flex()
                    .flex_col()
                    .gap_1p5()
                    .w(px(136.))
                    .p_1p5()
                    .rounded_md()
                    .border_1()
                    .border_color(if selected { theme.accent } else { theme.border })
                    .when(selected, |tile| tile.bg(theme.row_selected))
                    .when(!selected, |tile| {
                        tile.hover(|tile| tile.bg(theme.row_hover))
                    })
                    .cursor_pointer()
                    .keyboard_control(name, theme, Some(&self.scroll), window, cx)
                    .role(gpui::Role::RadioButton)
                    .aria_toggled(if selected {
                        gpui::Toggled::True
                    } else {
                        gpui::Toggled::False
                    })
                    .on_a11y_action(gpui::AccessibleAction::Click, move |_, _, cx| {
                        crate::theme::select(id, cx)
                    })
                    .on_click(move |_, _, cx| crate::theme::select(id, cx))
                    .child(
                        div()
                            .flex()
                            .h(px(48.))
                            .rounded_sm()
                            .overflow_hidden()
                            .border_1()
                            .border_color(swatch.border)
                            .bg(swatch.background)
                            .child(div().w(px(28.)).h_full().bg(swatch.sidebar))
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .flex_1()
                                    .gap_1()
                                    .p_1p5()
                                    .child(line(52., swatch.text))
                                    .child(line(36., swatch.text_muted))
                                    .child(
                                        div()
                                            .mt_auto()
                                            .h(px(10.))
                                            .w(px(30.))
                                            .rounded_sm()
                                            .bg(swatch.accent),
                                    ),
                            ),
                    )
                    .child(div().text_xs().truncate().child(name)),
            );
        }
        div()
            .id("themes")
            .role(gpui::Role::RadioGroup)
            .aria_label("Theme")
            .flex()
            .flex_col()
            .gap_2()
            .pt_1()
            .child(
                div()
                    .text_xs()
                    .text_color(theme.text_muted)
                    .child(gpui::text!(
                        "Tuist follows the system appearance. Other themes have their own."
                    )),
            )
            .child(div().flex().flex_wrap().gap_2().children(tiles))
    }

    fn content(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let navigation = self.navigation.read(cx);
        let selected = navigation.tab;
        let preview = navigation.preview.clone();
        let heading = if preview.is_some() {
            "Preview"
        } else {
            title(selected)
        };
        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .min_w_0()
            .child(
                div()
                    .id("workspace-heading")
                    .role(gpui::Role::Heading)
                    .aria_label(heading)
                    .aria_level(1)
                    .flex()
                    .items_center()
                    .h(px(32.))
                    .px_3()
                    .border_b_1()
                    .border_color(theme.border)
                    .font_weight(FontWeight::MEDIUM)
                    .child(SharedString::from(heading)),
            )
            .child(match (preview, selected) {
                // Conversations scroll their own body so its composer stays docked at the bottom.
                (None, Destination::Threads) => div()
                    .flex_1()
                    .min_h_0()
                    .child(self.threads.clone())
                    .into_any_element(),
                (None, Destination::Lounges) => div()
                    .flex_1()
                    .min_h_0()
                    .child(self.lounges.clone())
                    .into_any_element(),
                (None, Destination::Dms) => div()
                    .flex_1()
                    .min_h_0()
                    .child(self.dms.clone())
                    .into_any_element(),
                (preview, _) => div()
                    .id("workspace-scroll")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .child(match preview {
                        Some(preview) => self
                            .preview_detail(preview, theme, window, cx)
                            .into_any_element(),
                        None => self.profile(theme, window, cx).into_any_element(),
                    })
                    .into_any_element(),
            })
    }
}

impl Render for Workspace {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance(), cx);
        div()
            .flex()
            .size_full()
            .bg(theme.background)
            .text_color(theme.text)
            .text_sm()
            .child(self.sidebar(theme, window, cx))
            .child(self.content(theme, window, cx))
    }
}
