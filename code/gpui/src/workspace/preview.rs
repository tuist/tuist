use gpui::{ClipboardItem, Context, IntoElement, Window, div, prelude::*};
use tuist_navigation::{Preview, Route};

use super::Workspace;
use crate::keyboard::KeyboardControl;
use crate::theme::Theme;

impl Workspace {
    pub(super) fn preview_detail(
        &self,
        preview: Preview,
        theme: Theme,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let url = Route::Preview(preview.clone())
            .url(&url::Url::parse(&self.server).unwrap())
            .unwrap();
        let copy_url = url.to_string();
        div().flex().flex_col().p_6().gap_4()
            .child(div().id("back-to-previews").cursor_pointer().text_color(theme.accent)
                .keyboard_control("Back to previews", theme, Some(&self.scroll), window, cx)
                .child("Back to previews")
                .on_a11y_action(gpui::AccessibleAction::Click, {
                    let navigation = self.navigation.clone();
                    move |_, _, cx| navigation.update(cx, |nav, cx| { nav.navigate(Route::Previews); cx.notify(); })
                })
                .on_click(cx.listener(|this, _, _, cx| {
                    this.navigation.update(cx, |nav, cx| { nav.navigate(Route::Previews); cx.notify(); });
                })))
            .child(div().text_xl().child(gpui::text!(format!("{}/{}", preview.account, preview.project))))
            .child(div().text_color(theme.text_muted).child(gpui::text!(format!("Preview {}", preview.id))))
            .child(gpui::text!("Preview details are available on the web. Opening this link does not install or run the preview."))
            .child(div().flex().gap_4()
                .child(div().id("open-preview-on-web").px_3().py_2().rounded_lg()
                    .bg(theme.accent).text_color(theme.accent_foreground).cursor_pointer().child("Open on web")
                    .keyboard_control("Open preview on web", theme, Some(&self.scroll), window, cx)
                    .on_a11y_action(gpui::AccessibleAction::Click, {
                        let url = url.clone();
                        move |_, _, cx| cx.open_url(url.as_str())
                    })
                    .on_click(move |_, _, cx| cx.open_url(url.as_str())))
                .child(div().id("copy-preview-link").px_3().py_2().rounded_lg()
                    .border_1().border_color(theme.border).cursor_pointer().child("Copy link")
                    .keyboard_control("Copy preview link", theme, Some(&self.scroll), window, cx)
                    .on_a11y_action(gpui::AccessibleAction::Click, {
                        let url = copy_url.clone();
                        move |_, _, cx| cx.write_to_clipboard(ClipboardItem::new_string(url.clone()))
                    })
                    .on_click(move |_, _, cx| cx.write_to_clipboard(ClipboardItem::new_string(copy_url.clone())))))
    }
}
