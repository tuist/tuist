use gpui::{
    Context, Div, ElementId, FontWeight, ScrollHandle, SharedString, Stateful, Window, div,
    prelude::*, px,
};

use crate::keyboard::KeyboardControl;
use crate::theme::Theme;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Variant {
    /// Noora's primary button: the one action a view is for.
    Primary,
    /// Noora's secondary button: bordered, on the surface color.
    Secondary,
    /// A borderless control, such as a list row or a back link.
    Ghost,
}

/// A pointer-, keyboard- and screen-reader-operable button. A disabled button
/// leaves the Tab order and ignores activation.
pub struct Button {
    id: ElementId,
    label: SharedString,
    variant: Variant,
    enabled: bool,
}

impl Button {
    pub fn new(id: impl Into<ElementId>, label: impl Into<SharedString>, variant: Variant) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            variant,
            enabled: true,
        }
    }

    pub fn enabled(mut self, enabled: bool) -> Self {
        self.enabled = enabled;
        self
    }

    /// `action` runs on click and on the accessibility Click action. Add the
    /// button's content after this call; it starts with the label.
    pub fn render<V: 'static>(
        self,
        scroll: Option<&ScrollHandle>,
        window: &mut Window,
        cx: &mut Context<V>,
        action: impl Fn(&mut V, &mut Window, &mut Context<V>) + Clone + 'static,
    ) -> Stateful<Div> {
        let theme = Theme::for_appearance(window.appearance(), cx);
        let base = div()
            .id(self.id)
            .flex()
            .items_center()
            .gap_2()
            .min_h(px(32.))
            .px_3()
            .rounded_md()
            .flex_none();
        let base = match self.variant {
            Variant::Primary => base
                .font_weight(FontWeight::MEDIUM)
                .bg(theme.accent)
                .text_color(theme.accent_foreground)
                .when(!self.enabled, |button| button.opacity(0.5)),
            Variant::Secondary => base
                .font_weight(FontWeight::MEDIUM)
                .bg(theme.background)
                .border_1()
                .border_color(theme.border)
                .text_color(if self.enabled {
                    theme.text
                } else {
                    theme.text_muted
                }),
            Variant::Ghost => base.text_color(if self.enabled {
                theme.text
            } else {
                theme.text_muted
            }),
        };
        if !self.enabled {
            return base.child(self.label);
        }
        let variant = self.variant;
        let weak = cx.weak_entity();
        let accessible = action.clone();
        base.cursor_pointer()
            .hover(move |button| match variant {
                Variant::Primary => button.opacity(0.9),
                _ => button.bg(theme.row_hover),
            })
            .keyboard_control(self.label.clone(), theme, scroll, window, cx)
            .on_a11y_action(gpui::AccessibleAction::Click, move |_, window, cx| {
                let _ = weak.update(cx, |this, cx| accessible(this, window, cx));
            })
            .on_click(cx.listener(move |this, _, window, cx| action(this, window, cx)))
            .child(self.label)
    }
}
