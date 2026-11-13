//! Shared named, accessible buttons, preserving GPUI's native Enter/Space handling.
use gpui::{
    App, Bounds, Div, FocusHandle, KeyBinding, Pixels, ScrollHandle, SharedString, Stateful,
    Subscription, Window, actions, canvas, prelude::*,
};
use std::{cell::Cell, rc::Rc};

use crate::theme::Theme;

actions!(tuist_focus, [NextFocus, PreviousFocus]);

pub fn init(cx: &mut App) {
    cx.bind_keys([
        KeyBinding::new("tab", NextFocus, None),
        KeyBinding::new("shift-tab", PreviousFocus, None),
    ]);
}

struct ControlFocus {
    handle: FocusHandle,
    bounds: Rc<Cell<Bounds<Pixels>>>,
    _subscription: Subscription,
}

pub trait KeyboardControl {
    fn keyboard_control(
        self,
        label: impl Into<SharedString>,
        theme: Theme,
        scroll: Option<&ScrollHandle>,
        window: &mut Window,
        cx: &mut App,
    ) -> Self
    where
        Self: Sized,
    {
        self.keyboard_control_focused(label, theme, scroll, None, window, cx)
    }

    fn keyboard_control_focused(
        self,
        label: impl Into<SharedString>,
        theme: Theme,
        scroll: Option<&ScrollHandle>,
        focus: Option<&FocusHandle>,
        window: &mut Window,
        cx: &mut App,
    ) -> Self;
}

impl KeyboardControl for Stateful<Div> {
    fn keyboard_control_focused(
        mut self,
        label: impl Into<SharedString>,
        theme: Theme,
        scroll: Option<&ScrollHandle>,
        focus: Option<&FocusHandle>,
        window: &mut Window,
        cx: &mut App,
    ) -> Self {
        let id = self.interactivity().element_id.clone().expect("control ID");
        let scroll = scroll.cloned();
        let state = window.with_id("keyboard-control", |window| {
            window.use_keyed_state(id, cx, |window, cx| {
                let handle = focus
                    .cloned()
                    .unwrap_or_else(|| cx.focus_handle().tab_stop(true));
                let bounds = Rc::new(Cell::new(Bounds::default()));
                let focused_bounds = bounds.clone();
                let subscription = cx.on_focus(&handle, window, move |_, window, cx| {
                    if let Some(scroll) = &scroll {
                        reveal(focused_bounds.get(), scroll, window, cx);
                    }
                    cx.notify();
                });
                ControlFocus {
                    handle,
                    bounds,
                    _subscription: subscription,
                }
            })
        });
        let bounds = state.read(cx).bounds.clone();
        self.relative()
            .role(gpui::Role::Button)
            .aria_label(label)
            .track_focus(&state.read(cx).handle)
            .focus(|style| style.border_2().border_color(theme.text))
            .child(
                canvas(move |value, _, _| bounds.set(value), |_, _, _, _| {})
                    .absolute()
                    .inset_0(),
            )
    }
}

/// Reveal only the obscured edge, without jumping every focused item to the top.
pub fn reveal(bounds: Bounds<Pixels>, scroll: &ScrollHandle, window: &mut Window, cx: &mut App) {
    let viewport = scroll.bounds();
    let delta = if bounds.top() < viewport.top() {
        viewport.top() - bounds.top()
    } else if bounds.bottom() > viewport.bottom() {
        viewport.bottom() - bounds.bottom()
    } else {
        return;
    };
    let mut offset = scroll.offset();
    offset.y += delta;
    scroll.set_offset(offset);
    // Focus notifications run during drawing; refresh after that frame finishes.
    window.defer(cx, |window, _| window.refresh());
}
