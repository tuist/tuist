use gpui::{Div, ElementId, Stateful, div, prelude::*, px, rgb};

use crate::theme::Theme;

/// One message of a conversation. The person's messages sit right in a
/// bubble; the assistant's read as body text; notices and tools are muted.
pub fn message(role: &str, content: String, theme: Theme) -> Div {
    let text = div().whitespace_normal().child(gpui::text!(content));
    match role {
        "user" => div().flex().justify_end().pl_16().child(
            text.px_3()
                .py_2()
                .rounded_lg()
                .bg(theme.row_hover)
                .border_1()
                .border_color(theme.border),
        ),
        "assistant" => div().pr_16().line_height(gpui::rems(1.5)).child(text),
        _ => div().text_xs().text_color(theme.text_muted).child(text),
    }
}

/// The green dot chat apps put next to someone who has the app open. Noora
/// has no presence token, so it uses the same green in every theme.
pub fn presence_dot(id: impl Into<ElementId>) -> Stateful<Div> {
    div()
        .id(id)
        .role(gpui::Role::Image)
        .aria_label("Online")
        .size(px(8.))
        .flex_none()
        .rounded_full()
        .bg(rgb(0x22c55e))
}

/// One message between people, as in chat apps: who wrote it, whether they
/// are online, and when, above the text. Nobody's messages sit apart, since
/// nobody is an assistant.
pub fn chat_message(
    id: impl Into<ElementId>,
    author: String,
    online: bool,
    time: String,
    body: String,
    theme: Theme,
) -> Div {
    div()
        .flex()
        .flex_col()
        .gap_0p5()
        .child(
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(
                    div()
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(gpui::text!(author)),
                )
                .when(online, |row| row.child(presence_dot(id)))
                .child(
                    div()
                        .text_xs()
                        .text_color(theme.text_muted)
                        .child(gpui::text!(time)),
                ),
        )
        .child(
            div()
                .whitespace_normal()
                .line_height(gpui::rems(1.5))
                .child(gpui::text!(body)),
        )
}
