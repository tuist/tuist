//! Semantic helpers shared by asynchronous status and error views.
use gpui::{Div, ElementId, SharedString, Stateful, div, prelude::*};

pub fn announcement(
    id: impl Into<ElementId>,
    message: impl Into<SharedString>,
    urgent: bool,
) -> Stateful<Div> {
    let message = message.into();
    div()
        .id(id)
        .role(if urgent {
            gpui::Role::Alert
        } else {
            gpui::Role::Status
        })
        .aria_label(message.clone())
        .a11y_synthetic_children(move |tree| {
            tree.parent_node().set_live(if urgent {
                gpui::accesskit::Live::Assertive
            } else {
                gpui::accesskit::Live::Polite
            });
            tree.parent_node().set_live_atomic();
        })
        .child(message)
}
