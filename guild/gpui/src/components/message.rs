use gpui::{Div, div, prelude::*};

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
