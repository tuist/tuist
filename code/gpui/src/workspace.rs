use gpui::{
    Context, Entity, EventEmitter, FontWeight, IntoElement, Render, ScrollHandle, SharedString,
    Subscription, Window, div, prelude::*, px, svg,
};
use tuist_navigation::{Navigation, Tab as Destination};
use tuist_session::Account;

use crate::assets;
use crate::keyboard::KeyboardControl;
use crate::theme::Theme;

mod preview;

pub enum WorkspaceEvent {
    SignOut,
}

fn title(destination: Destination) -> &'static str {
    match destination {
        Destination::Previews => "Previews",
        Destination::Profile => "Profile",
    }
}

/// The signed-in shell: a sidebar of destinations next to the selected one.
pub struct Workspace {
    navigation: Entity<Navigation>,
    account: Account,
    server: SharedString,
    scroll: ScrollHandle,
    _appearance: Subscription,
    _navigation: Subscription,
    _theme: Subscription,
}

impl EventEmitter<WorkspaceEvent> for Workspace {}

impl Workspace {
    pub fn new(
        account: Account,
        server: SharedString,
        navigation: Entity<Navigation>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let observer = cx.observe(&navigation, |_, _, cx| cx.notify());
        Self {
            navigation,
            account,
            server,
            scroll: ScrollHandle::new(),
            _appearance: cx.observe_window_appearance(window, |_, _, cx| cx.notify()),
            _navigation: observer,
            _theme: cx.observe_global::<crate::theme::ThemeState>(|_, cx| cx.notify()),
        }
    }

    fn sidebar(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        div()
            .id("primary-navigation")
            .role(gpui::Role::Navigation)
            .aria_label("Primary navigation")
            .flex()
            .flex_col()
            .w(px(220.))
            .h_full()
            .flex_none()
            .gap_1()
            .px_2()
            .pt_4()
            .bg(theme.sidebar)
            .border_r_1()
            .border_color(theme.border)
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .px_2()
                    .pb_3()
                    .text_lg()
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(
                        svg()
                            .path(assets::MARK)
                            .size(px(22.))
                            .text_color(theme.accent),
                    )
                    .child("Tuist Code"),
            )
            .children(
                [Destination::Previews, Destination::Profile]
                    .into_iter()
                    .map(|destination| {
                        let selected = destination == self.navigation.read(cx).tab;
                        div()
                            .id(title(destination))
                            .px_2()
                            .py_1()
                            .rounded_md()
                            .cursor_pointer()
                            .when(selected, |row| {
                                row.bg(theme.row_selected).text_color(theme.accent)
                            })
                            .when(!selected, |row| row.hover(|row| row.bg(theme.row_hover)))
                            .keyboard_control(title(destination), theme, None, window, cx)
                            .when(selected, |row| row.aria_description("Current section"))
                            .child(title(destination))
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.navigation.update(cx, |navigation, cx| {
                                    navigation.tab = destination;
                                    cx.notify();
                                });
                            }))
                    }),
            )
            .child(div().flex_1())
    }

    fn profile(
        &self,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let row = |label: &'static str, value: Option<String>| {
            div()
                .id(label)
                .role(gpui::Role::Group)
                .aria_label(label)
                .flex()
                .justify_between()
                .gap_4()
                .py_2()
                .border_b_1()
                .border_color(theme.border)
                .child(div().text_color(theme.text_muted).child(label))
                .child(gpui::text!(value.unwrap_or_else(|| "Not provided".into())))
        };
        div()
            .flex()
            .flex_col()
            .w(px(420.))
            .p_6()
            .child(row("Handle", self.account.handle.clone()))
            .child(row("Email", self.account.email.clone()))
            .child(row("Server", Some(self.server.to_string())))
            .child(
                div()
                    .id("sign-out")
                    .mt_6()
                    .px_3()
                    .py_2()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme.border)
                    .text_color(theme.error)
                    .text_center()
                    .cursor_pointer()
                    .hover(|button| button.bg(theme.row_hover))
                    .keyboard_control("Sign out", theme, Some(&self.scroll), window, cx)
                    .child("Sign out")
                    .on_a11y_action(gpui::AccessibleAction::Click, {
                        let workspace = cx.weak_entity();
                        move |_, _, cx| {
                            let _ = workspace.update(cx, |_, cx| cx.emit(WorkspaceEvent::SignOut));
                        }
                    })
                    .on_click(cx.listener(|_, _, _, cx| cx.emit(WorkspaceEvent::SignOut))),
            )
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
        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .child(
                div()
                    .id("workspace-heading")
                    .role(gpui::Role::Heading)
                    .aria_label(title(selected))
                    .aria_level(1)
                    .flex()
                    .items_center()
                    .h(px(44.))
                    .px_4()
                    .border_b_1()
                    .border_color(theme.border)
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(SharedString::from(title(selected))),
            )
            .child(
                div()
                    .id("workspace-scroll")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .child(match selected {
                        Destination::Previews if preview.is_some() => self
                            .preview_detail(preview.unwrap(), theme, window, cx)
                            .into_any_element(),
                        Destination::Previews => div()
                            .flex()
                            .flex_1()
                            .items_center()
                            .justify_center()
                            .text_color(theme.text_muted)
                            .child(gpui::text!("Your projects' previews will appear here."))
                            .into_any_element(),
                        Destination::Profile => self.profile(theme, window, cx).into_any_element(),
                    }),
            )
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
