//! Spike: Luft's signed-out screen drawn by GPUI in the browser.
//!
//! It reuses the desktop's embedded assets and the core's Noora palette, and
//! mirrors `gpui/src/login.rs`. Sign-in is not wired up: the desktop's
//! session runs blocking HTTP and a loopback listener, which the browser
//! does not offer.
#![cfg(target_arch = "wasm32")]

use std::borrow::Cow;

use gpui::{
    AnyElement, App, Context, FontWeight, Hsla, IntoElement, Render, SharedString, Window,
    WindowAppearance, WindowOptions, div, img, prelude::*, px, rgb, svg,
};
use wasm_bindgen::prelude::*;

#[path = "../../gpui/src/assets.rs"]
#[allow(dead_code)]
mod assets;
#[path = "../../gpui/src/theme/palette.rs"]
#[allow(dead_code)]
mod palette;

use assets::Assets;
use palette::Palette;

const FONT_FAMILY: &str = "IBM Plex Sans";

struct Theme {
    dark: bool,
    background: Hsla,
    sidebar: Hsla,
    border: Hsla,
    text: Hsla,
    text_muted: Hsla,
    accent: Hsla,
    accent_foreground: Hsla,
}

impl Theme {
    fn for_appearance(appearance: WindowAppearance) -> Self {
        let dark = matches!(
            appearance,
            WindowAppearance::Dark | WindowAppearance::VibrantDark
        );
        let palette = Palette::noora(dark);
        Self {
            dark,
            background: rgb(palette.background).into(),
            sidebar: rgb(palette.sidebar).into(),
            border: rgb(palette.border).into(),
            text: rgb(palette.text).into(),
            text_muted: rgb(palette.text_muted).into(),
            accent: rgb(palette.accent).into(),
            accent_foreground: rgb(palette.accent_foreground).into(),
        }
    }
}

struct LogIn {
    notice: Option<SharedString>,
}

impl LogIn {
    fn button(
        &self,
        label: &'static str,
        icon: AnyElement,
        primary: bool,
        theme: &Theme,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
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
            .cursor_pointer()
            .hover(|button| button.opacity(0.85))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.notice =
                    Some(format!("{label}: sign-in is not wired up on the web yet.").into());
                cx.notify();
            }))
            .child(icon)
            .child(label)
    }
}

impl Render for LogIn {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = Theme::for_appearance(window.appearance());
        let (apple, github) = if theme.dark {
            (assets::APPLE_DARK, assets::GITHUB_DARK)
        } else {
            (assets::APPLE_LIGHT, assets::GITHUB_LIGHT)
        };
        let logo = |path: &'static str| img(path).size(px(18.)).into_any_element();

        div()
            .id("login-scroll")
            .role(gpui::Role::Form)
            .aria_label("Sign in to Luft")
            .flex()
            .flex_col()
            .items_center()
            .size_full()
            .overflow_y_scroll()
            .py_8()
            .bg(theme.sidebar)
            .text_color(theme.text)
            .font_family(FONT_FAMILY)
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
                    .gap_3()
                    .child(img(assets::ROUNDED_ICON).size(px(60.)))
                    .child(
                        div()
                            .id("login-heading")
                            .role(gpui::Role::Heading)
                            .aria_label("Welcome to Luft")
                            .aria_level(1)
                            .pt_4()
                            .text_2xl()
                            .font_weight(FontWeight::MEDIUM)
                            .child("Welcome to Luft"),
                    )
                    .child(
                        div()
                            .pb_4()
                            .text_color(theme.text_muted)
                            .text_center()
                            .child(gpui::text!(
                                "Sign in to access your projects and collaborate with your team"
                            )),
                    )
                    .child(self.button(
                        "Sign in with Tuist",
                        logo(assets::TUIST_LOGO),
                        true,
                        &theme,
                        cx,
                    ))
                    .child(self.button("Sign in with Apple", logo(apple), false, &theme, cx))
                    .child(self.button(
                        "Sign in with Google",
                        logo(assets::GOOGLE_LOGO),
                        false,
                        &theme,
                        cx,
                    ))
                    .child(self.button("Sign in with GitHub", logo(github), false, &theme, cx))
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
                            &theme,
                            cx,
                        ),
                    )
                    .when_some(self.notice.clone(), |column, notice| {
                        column.child(
                            div()
                                .id("notice")
                                .role(gpui::Role::Status)
                                .aria_label(notice.clone())
                                .pt_2()
                                .text_xs()
                                .text_color(theme.text_muted)
                                .text_center()
                                .child(notice),
                        )
                    }),
            )
    }
}

#[wasm_bindgen(start)]
pub fn start() {
    gpui_platform::web_init();
    gpui_platform::single_threaded_web()
        .with_assets(Assets)
        .run(|cx: &mut App| {
            cx.text_system()
                .add_fonts(vec![
                    Cow::Borrowed(include_bytes!("../fonts/IBMPlexSans-Regular.ttf")),
                    Cow::Borrowed(include_bytes!("../fonts/IBMPlexSans-SemiBold.ttf")),
                ])
                .expect("embedded fonts load");
            cx.open_window(WindowOptions::default(), |window, cx| {
                cx.new(|cx| {
                    cx.observe_window_appearance(window, |_, _, cx| cx.notify())
                        .detach();
                    LogIn { notice: None }
                })
            })
            .expect("open the Luft window");
            cx.activate(true);
        });
}
