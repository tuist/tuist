use gpui::{Div, Entity, Stateful, div, prelude::*, px};

use crate::input::TextInput;
use crate::theme::Theme;

/// The bar docked at the bottom of a conversation pane: a text field and its
/// send button, as in chat apps.
pub fn composer(input: &Entity<TextInput>, send: Stateful<Div>, theme: Theme) -> Div {
    div()
        .flex_none()
        .border_t_1()
        .border_color(theme.border)
        .bg(theme.sidebar)
        .px_6()
        .py_3()
        .child(
            div()
                .flex()
                .items_center()
                .gap_2()
                .w_full()
                .max_w(px(760.))
                .mx_auto()
                .child(div().flex_1().min_w_0().child(input.clone()))
                .child(send),
        )
}
