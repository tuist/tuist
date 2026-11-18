use std::{cell::Cell, ops::Range, rc::Rc};

use gpui::{
    App, Bounds, ClipboardItem, ContentMask, Context, CursorStyle, ElementId, ElementInputHandler,
    Entity, EntityInputHandler, EventEmitter, FocusHandle, Focusable, GlobalElementId, KeyBinding,
    LayoutId, MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent, PaintQuad, Pixels, Point,
    ShapedLine, SharedString, Style, TextRun, UTF16Selection, UnderlineStyle, Window, accesskit,
    actions, div, fill, point, prelude::*, px, relative, size,
};

use crate::theme::Theme;

actions!(
    server_url_input,
    [
        Backspace,
        Delete,
        Left,
        Right,
        SelectLeft,
        SelectRight,
        Home,
        End,
        SelectHome,
        SelectEnd,
        SelectAll,
        Copy,
        Cut,
        Paste,
        Submit
    ]
);

/// Emitted when Enter is pressed outside an IME composition.
pub struct Submitted;

/// Register once at application startup. Shortcuts only apply to this input's context.
pub fn init(cx: &mut App) {
    cx.bind_keys([
        KeyBinding::new("backspace", Backspace, Some("ServerUrlInput")),
        KeyBinding::new("delete", Delete, Some("ServerUrlInput")),
        KeyBinding::new("left", Left, Some("ServerUrlInput")),
        KeyBinding::new("right", Right, Some("ServerUrlInput")),
        KeyBinding::new("shift-left", SelectLeft, Some("ServerUrlInput")),
        KeyBinding::new("shift-right", SelectRight, Some("ServerUrlInput")),
        KeyBinding::new("home", Home, Some("ServerUrlInput")),
        KeyBinding::new("end", End, Some("ServerUrlInput")),
        KeyBinding::new("shift-home", SelectHome, Some("ServerUrlInput")),
        KeyBinding::new("shift-end", SelectEnd, Some("ServerUrlInput")),
        KeyBinding::new("enter", Submit, Some("ServerUrlInput")),
    ]);
    let [select_all, copy, cut, paste] = if cfg!(target_os = "macos") {
        ["cmd-a", "cmd-c", "cmd-x", "cmd-v"]
    } else {
        ["ctrl-a", "ctrl-c", "ctrl-x", "ctrl-v"]
    };
    cx.bind_keys([
        KeyBinding::new(select_all, SelectAll, Some("ServerUrlInput")),
        KeyBinding::new(copy, Copy, Some("ServerUrlInput")),
        KeyBinding::new(cut, Cut, Some("ServerUrlInput")),
        KeyBinding::new(paste, Paste, Some("ServerUrlInput")),
    ]);
    #[cfg(target_os = "macos")]
    cx.bind_keys([
        KeyBinding::new("cmd-left", Home, Some("ServerUrlInput")),
        KeyBinding::new("cmd-right", End, Some("ServerUrlInput")),
        KeyBinding::new("cmd-shift-left", SelectHome, Some("ServerUrlInput")),
        KeyBinding::new("cmd-shift-right", SelectEnd, Some("ServerUrlInput")),
    ]);
}

pub struct TextInput {
    pub focus_handle: FocusHandle,
    content: SharedString,
    placeholder: SharedString,
    selection: Range<usize>,
    reversed: bool,
    marked: Option<Range<usize>>,
    last_line: Option<ShapedLine>,
    last_bounds: Option<Bounds<Pixels>>,
    scroll: Pixels,
    selecting: bool,
    observing_focus: bool,
    validation_error: Option<SharedString>,
    a11y_run_id: Rc<Cell<Option<accesskit::NodeId>>>,
}

impl EventEmitter<Submitted> for TextInput {}

impl TextInput {
    pub fn new(placeholder: impl Into<SharedString>, cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle().tab_stop(true);
        Self {
            focus_handle,
            content: "".into(),
            placeholder: placeholder.into(),
            selection: 0..0,
            reversed: false,
            marked: None,
            last_line: None,
            last_bounds: None,
            scroll: px(0.),
            selecting: false,
            observing_focus: false,
            validation_error: None,
            a11y_run_id: Rc::new(Cell::new(None)),
        }
    }

    pub fn value(&self) -> &str {
        &self.content
    }

    /// Expose the parent form's validation error as this input's description.
    pub fn set_validation_error(&mut self, error: Option<SharedString>, cx: &mut Context<Self>) {
        if self.validation_error != error {
            self.validation_error = error;
            cx.notify();
        }
    }

    pub fn set_value(&mut self, value: String, cx: &mut Context<Self>) {
        self.content = single_line(&value).into();
        self.selection = self.content.len()..self.content.len();
        self.reversed = false;
        self.marked = None;
        self.last_line = None;
        self.scroll = px(0.);
        cx.notify();
    }

    fn cursor(&self) -> usize {
        if self.reversed {
            self.selection.start
        } else {
            self.selection.end
        }
    }

    fn move_to(
        &mut self,
        offset: usize,
        extend: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if extend {
            let anchor = if self.reversed {
                self.selection.end
            } else {
                self.selection.start
            };
            self.selection = anchor.min(offset)..anchor.max(offset);
            self.reversed = offset < anchor;
        } else {
            self.selection = offset..offset;
            self.reversed = false;
        }
        window.notify_text_selection_changed(&self.focus_handle);
        cx.notify();
    }

    fn previous(&self) -> usize {
        self.content[..self.cursor()]
            .char_indices()
            .next_back()
            .map_or(0, |(i, _)| i)
    }

    fn next(&self) -> usize {
        self.content[self.cursor()..]
            .chars()
            .next()
            .map_or(self.content.len(), |ch| self.cursor() + ch.len_utf8())
    }

    fn left(&mut self, _: &Left, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(
            if self.selection.is_empty() {
                self.previous()
            } else {
                self.selection.start
            },
            false,
            window,
            cx,
        );
    }

    fn right(&mut self, _: &Right, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(
            if self.selection.is_empty() {
                self.next()
            } else {
                self.selection.end
            },
            false,
            window,
            cx,
        );
    }

    fn select_left(&mut self, _: &SelectLeft, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(self.previous(), true, window, cx);
    }

    fn select_right(&mut self, _: &SelectRight, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(self.next(), true, window, cx);
    }

    fn home(&mut self, _: &Home, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(0, false, window, cx);
    }

    fn end(&mut self, _: &End, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(self.content.len(), false, window, cx);
    }

    fn select_home(&mut self, _: &SelectHome, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(0, true, window, cx);
    }

    fn select_end(&mut self, _: &SelectEnd, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(self.content.len(), true, window, cx);
    }

    fn select_all(&mut self, _: &SelectAll, window: &mut Window, cx: &mut Context<Self>) {
        self.move_to(0, false, window, cx);
        self.move_to(self.content.len(), true, window, cx);
    }

    fn backspace(&mut self, _: &Backspace, window: &mut Window, cx: &mut Context<Self>) {
        if self.selection.is_empty() {
            self.move_to(self.previous(), true, window, cx);
        }
        self.replace_text_in_range(None, "", window, cx);
    }

    fn delete(&mut self, _: &Delete, window: &mut Window, cx: &mut Context<Self>) {
        if self.selection.is_empty() {
            self.move_to(self.next(), true, window, cx);
        }
        self.replace_text_in_range(None, "", window, cx);
    }

    fn copy(&mut self, _: &Copy, _: &mut Window, cx: &mut Context<Self>) {
        if !self.selection.is_empty() {
            cx.write_to_clipboard(ClipboardItem::new_string(
                self.content[self.selection.clone()].to_owned(),
            ));
        }
    }

    fn cut(&mut self, _: &Cut, window: &mut Window, cx: &mut Context<Self>) {
        if !self.selection.is_empty() {
            self.copy(&Copy, window, cx);
            self.replace_text_in_range(None, "", window, cx);
        }
    }

    fn paste(&mut self, _: &Paste, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) {
            self.replace_text_in_range(None, &text, window, cx);
        }
    }

    fn submit(&mut self, _: &Submit, _: &mut Window, cx: &mut Context<Self>) {
        if self.marked.is_none() {
            cx.emit(Submitted);
        }
    }

    fn mouse_index(&self, position: Point<Pixels>) -> usize {
        if self.content.is_empty() {
            return 0;
        }
        match (&self.last_line, self.last_bounds) {
            (Some(line), Some(bounds)) if line.text == self.content => {
                line.closest_index_for_x(position.x - bounds.left() + self.scroll)
            }
            // An edit can arrive before the next frame updates hit testing.
            _ => self.cursor(),
        }
    }

    fn mouse_down(&mut self, event: &MouseDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        window.focus(&self.focus_handle, cx);
        self.selecting = true;
        self.move_to(
            self.mouse_index(event.position),
            event.modifiers.shift,
            window,
            cx,
        );
    }

    fn mouse_move(&mut self, event: &MouseMoveEvent, window: &mut Window, cx: &mut Context<Self>) {
        if self.selecting {
            self.move_to(self.mouse_index(event.position), true, window, cx);
        }
    }

    fn mouse_up(&mut self, _: &MouseUpEvent, _: &mut Window, _: &mut Context<Self>) {
        self.selecting = false;
    }

    fn to_utf16(&self, range: Range<usize>) -> Range<usize> {
        self.content[..range.start].encode_utf16().count()
            ..self.content[..range.end].encode_utf16().count()
    }

    fn utf16_to_utf8(&self, range: Range<usize>) -> Range<usize> {
        let start = utf8_offset(&self.content, range.start);
        let end = utf8_offset(&self.content, range.end);
        start.min(end)..start.max(end)
    }

    fn a11y_text(
        content: &str,
        selection: Range<usize>,
        reversed: bool,
        run_id: accesskit::NodeId,
    ) -> (accesskit::Node, accesskit::TextSelection) {
        let mut run = accesskit::Node::new(accesskit::Role::TextRun);
        run.set_value(content.to_string());
        // Cursor movement selects Unicode scalars, not UTF-16 units or graphemes.
        run.set_character_lengths(
            content
                .chars()
                .map(|ch| ch.len_utf8() as u8)
                .collect::<Vec<_>>(),
        );
        let start = content[..selection.start].chars().count();
        let end = content[..selection.end].chars().count();
        let (anchor, focus) = if reversed { (end, start) } else { (start, end) };
        (
            run,
            accesskit::TextSelection {
                anchor: accesskit::TextPosition {
                    node: run_id,
                    character_index: anchor,
                },
                focus: accesskit::TextPosition {
                    node: run_id,
                    character_index: focus,
                },
            },
        )
    }

    fn a11y_listener(
        action: accesskit::Action,
        cx: &Context<Self>,
    ) -> impl FnMut(Option<&accesskit::ActionData>, &mut Window, &mut App) + 'static + use<> {
        let input = cx.entity().downgrade();
        move |data, window, cx| {
            input
                .update(cx, |input, cx| {
                    input.apply_a11y_action(action, data, window, cx);
                })
                .ok();
        }
    }

    fn apply_a11y_action(
        &mut self,
        action: accesskit::Action,
        data: Option<&accesskit::ActionData>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match (action, data) {
            (accesskit::Action::Focus, _) => {
                window.focus(&self.focus_handle, cx);
                cx.notify();
            }
            (accesskit::Action::SetValue, Some(accesskit::ActionData::Value(value))) => {
                let range = self.to_utf16(0..self.content.len());
                self.replace_text_in_range(Some(range), value, window, cx);
                self.scroll = px(0.);
                self.last_line = None;
            }
            (accesskit::Action::ReplaceSelectedText, Some(accesskit::ActionData::Value(value))) => {
                // An assistive edit replaces the selection, not an IME marked range.
                let range = self.to_utf16(self.selection.clone());
                self.replace_text_in_range(Some(range), value, window, cx);
            }
            (
                accesskit::Action::SetTextSelection,
                Some(accesskit::ActionData::SetTextSelection(selection)),
            ) => {
                let Some(run_id) = self.a11y_run_id.get() else {
                    return;
                };
                if selection.anchor.node != run_id || selection.focus.node != run_id {
                    return;
                }
                let offset = |index| {
                    self.content
                        .char_indices()
                        .map(|(offset, _)| offset)
                        .chain(std::iter::once(self.content.len()))
                        .nth(index)
                };
                let (Some(anchor), Some(focus)) = (
                    offset(selection.anchor.character_index),
                    offset(selection.focus.character_index),
                ) else {
                    return;
                };
                self.selection = anchor.min(focus)..anchor.max(focus);
                self.reversed = focus < anchor;
                window.notify_text_selection_changed(&self.focus_handle);
                cx.notify();
            }
            _ => {}
        }
    }
}

// Strip line breaks at every entry point, including platform IME and programmatic updates.
fn single_line(text: &str) -> String {
    text.chars()
        .filter(|ch| !matches!(ch, '\r' | '\n' | '\u{85}' | '\u{2028}' | '\u{2029}'))
        .collect()
}

fn utf8_offset(text: &str, utf16_offset: usize) -> usize {
    let mut units = 0;
    for (offset, ch) in text.char_indices() {
        if units >= utf16_offset {
            return offset;
        }
        units += ch.len_utf16();
    }
    text.len()
}

impl EntityInputHandler for TextInput {
    fn text_for_range(
        &mut self,
        range: Range<usize>,
        actual: &mut Option<Range<usize>>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<String> {
        let range = self.utf16_to_utf8(range);
        *actual = Some(self.to_utf16(range.clone()));
        Some(self.content[range].to_owned())
    }

    fn selected_text_range(
        &mut self,
        _: bool,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<UTF16Selection> {
        Some(UTF16Selection {
            range: self.to_utf16(self.selection.clone()),
            reversed: self.reversed,
        })
    }

    fn set_selected_text_range(
        &mut self,
        range: Range<usize>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.selection = self.utf16_to_utf8(range);
        self.reversed = false;
        window.notify_text_selection_changed(&self.focus_handle);
        cx.notify();
    }

    fn text_length_utf16(&mut self, _: &mut Window, _: &mut Context<Self>) -> Option<usize> {
        Some(self.content.encode_utf16().count())
    }

    fn marked_text_range(&self, _: &mut Window, _: &mut Context<Self>) -> Option<Range<usize>> {
        self.marked.clone().map(|range| self.to_utf16(range))
    }

    fn unmark_text(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.marked = None;
        window.notify_text_input_changed(&self.focus_handle);
        cx.notify();
    }

    fn replace_text_in_range(
        &mut self,
        range: Option<Range<usize>>,
        text: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let range = range
            .map(|range| self.utf16_to_utf8(range))
            .or(self.marked.clone())
            .unwrap_or(self.selection.clone());
        let text = single_line(text);
        self.content =
            (self.content[..range.start].to_owned() + &text + &self.content[range.end..]).into();
        let cursor = range.start + text.len();
        self.selection = cursor..cursor;
        self.reversed = false;
        self.marked = None;
        window.notify_text_input_changed(&self.focus_handle);
        cx.notify();
    }

    fn replace_and_mark_text_in_range(
        &mut self,
        range: Option<Range<usize>>,
        text: &str,
        selected: Option<Range<usize>>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let range = range
            .map(|range| self.utf16_to_utf8(range))
            .or(self.marked.clone())
            .unwrap_or(self.selection.clone());
        // The IME's selection is relative to its replacement, not the whole input.
        let relative = selected.map(|selection| {
            single_line(&text[..utf8_offset(text, selection.start)]).len()
                ..single_line(&text[..utf8_offset(text, selection.end)]).len()
        });
        let text = single_line(text);
        self.content =
            (self.content[..range.start].to_owned() + &text + &self.content[range.end..]).into();
        self.marked = (!text.is_empty()).then_some(range.start..range.start + text.len());
        self.selection = relative
            .map(|selection| range.start + selection.start..range.start + selection.end)
            .unwrap_or(range.start + text.len()..range.start + text.len());
        self.reversed = false;
        window.notify_text_input_changed(&self.focus_handle);
        cx.notify();
    }

    fn bounds_for_range(
        &mut self,
        range: Range<usize>,
        _: Bounds<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<Bounds<Pixels>> {
        let line = self.last_line.as_ref()?;
        let bounds = self.last_bounds?;
        let range = self.utf16_to_utf8(range);
        Some(Bounds::from_corners(
            point(
                bounds.left() + line.x_for_index(range.start) - self.scroll,
                bounds.top(),
            ),
            point(
                bounds.left() + line.x_for_index(range.end) - self.scroll,
                bounds.bottom(),
            ),
        ))
    }

    fn character_index_for_point(
        &mut self,
        position: Point<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<usize> {
        self.last_bounds?.localize(&position)?;
        Some(self.to_utf16(0..self.mouse_index(position)).end)
    }
}

struct InputText {
    input: Entity<TextInput>,
}

struct InputPaint {
    line: ShapedLine,
    origin: Point<Pixels>,
    scroll: Pixels,
    caret: PaintQuad,
    selection: Option<PaintQuad>,
}

impl IntoElement for InputText {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl Element for InputText {
    type RequestLayoutState = ();
    type PrepaintState = InputPaint;

    fn id(&self) -> Option<ElementId> {
        None
    }
    fn source_location(&self) -> Option<&'static core::panic::Location<'static>> {
        None
    }

    fn request_layout(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, ()) {
        let mut style = Style::default();
        style.size.width = relative(1.).into();
        style.size.height = window.line_height().into();
        (window.request_layout(style, [], cx), ())
    }

    fn prepaint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        bounds: Bounds<Pixels>,
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) -> InputPaint {
        let input = self.input.read(cx);
        let theme = Theme::for_appearance(window.appearance(), cx);
        let style = window.text_style();
        let empty = input.content.is_empty();
        let text = if empty {
            input.placeholder.clone()
        } else {
            input.content.clone()
        };
        let run = TextRun {
            len: text.len(),
            font: style.font(),
            color: if empty { theme.text_muted } else { theme.text },
            background_color: None,
            underline: None,
            strikethrough: None,
        };
        let runs = if let Some(marked) = &input.marked {
            vec![
                TextRun {
                    len: marked.start,
                    ..run.clone()
                },
                TextRun {
                    len: marked.len(),
                    underline: Some(UnderlineStyle {
                        color: Some(theme.text),
                        thickness: px(1.),
                        wavy: false,
                    }),
                    ..run.clone()
                },
                TextRun {
                    len: text.len() - marked.end,
                    ..run
                },
            ]
            .into_iter()
            .filter(|run| run.len > 0)
            .collect()
        } else {
            vec![run]
        };
        let line = window.text_system().shape_line(
            text,
            style.font_size.to_pixels(window.rem_size()),
            &runs,
            None,
        );
        let cursor_x = line.x_for_index(input.cursor());
        let width = (bounds.size.width - px(2.)).max(px(0.));
        let max_scroll = (line.x_for_index(input.content.len()) - width).max(px(0.));
        let scroll = input
            .scroll
            .max(cursor_x - width)
            .min(cursor_x)
            .max(px(0.))
            .min(max_scroll);
        let origin = point(bounds.left() - scroll, bounds.top());
        let caret = fill(
            Bounds::new(
                point(origin.x + cursor_x, origin.y),
                size(px(1.), bounds.size.height),
            ),
            theme.accent,
        );
        let selection = (!input.selection.is_empty()).then(|| {
            fill(
                Bounds::from_corners(
                    point(
                        origin.x + line.x_for_index(input.selection.start),
                        bounds.top(),
                    ),
                    point(
                        origin.x + line.x_for_index(input.selection.end),
                        bounds.bottom(),
                    ),
                ),
                theme.row_selected,
            )
        });
        InputPaint {
            line,
            origin,
            scroll,
            caret,
            selection,
        }
    }

    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        bounds: Bounds<Pixels>,
        _: &mut (),
        state: &mut InputPaint,
        window: &mut Window,
        cx: &mut App,
    ) {
        let focus = self.input.read(cx).focus_handle.clone();
        window.handle_input(
            &focus,
            ElementInputHandler::new(bounds, self.input.clone()),
            cx,
        );
        window.with_content_mask(Some(ContentMask { bounds }), |window| {
            if let Some(selection) = state.selection.take() {
                window.paint_quad(selection);
            }
            let _ = state.line.paint(
                state.origin,
                window.line_height(),
                gpui::TextAlign::Left,
                None,
                window,
                cx,
            );
            if focus.is_focused(window) && self.input.read(cx).selection.is_empty() {
                window.paint_quad(state.caret.clone());
            }
        });
        self.input.update(cx, |input, _| {
            input.last_line = Some(state.line.clone());
            input.last_bounds = Some(bounds);
            input.scroll = state.scroll;
        });
    }
}

impl Focusable for TextInput {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for TextInput {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        // Construction does not need a Window; attach its focus listeners on first render.
        if !self.observing_focus {
            self.observing_focus = true;
            cx.observe_global::<crate::theme::ThemeState>(|_, cx| cx.notify())
                .detach();
            cx.observe_window_appearance(window, |_, _, cx| cx.notify())
                .detach();
            cx.on_focus(&self.focus_handle, window, |_, _, cx| cx.notify())
                .detach();
            cx.on_blur(&self.focus_handle, window, |this, _, cx| {
                this.selecting = false;
                cx.notify();
            })
            .detach();
        }
        let theme = Theme::for_appearance(window.appearance(), cx);
        let content = self.content.clone();
        let selection = self.selection.clone();
        let reversed = self.reversed;
        let run_id = self.a11y_run_id.clone();
        let invalid = self.validation_error.is_some();
        div()
            .id("server-url-input")
            .role(accesskit::Role::TextInput)
            .accessibility_id("server-url-input")
            .aria_label("Server URL")
            .aria_value(self.content.clone())
            .aria_placeholder(self.placeholder.clone())
            .when_some(self.validation_error.clone(), |input, error| {
                input.aria_description(error)
            })
            .a11y_synthetic_children(move |builder| {
                let id = builder.synthetic_node_id("content");
                run_id.set(Some(id));
                let (run, selection) = Self::a11y_text(&content, selection, reversed, id);
                builder.push_child(id, run);
                builder.parent_node().set_text_selection(selection);
                if invalid {
                    builder.parent_node().set_invalid(accesskit::Invalid::True);
                }
            })
            .on_a11y_action(
                accesskit::Action::Focus,
                Self::a11y_listener(accesskit::Action::Focus, cx),
            )
            .on_a11y_action(
                accesskit::Action::SetValue,
                Self::a11y_listener(accesskit::Action::SetValue, cx),
            )
            .on_a11y_action(
                accesskit::Action::ReplaceSelectedText,
                Self::a11y_listener(accesskit::Action::ReplaceSelectedText, cx),
            )
            .on_a11y_action(
                accesskit::Action::SetTextSelection,
                Self::a11y_listener(accesskit::Action::SetTextSelection, cx),
            )
            .key_context("ServerUrlInput")
            .track_focus(&self.focus_handle)
            .cursor(CursorStyle::IBeam)
            .w_full()
            .min_w_0()
            .px_3()
            .py_2()
            .rounded_md()
            .border_1()
            .border_color(if self.focus_handle.is_focused(window) {
                theme.accent
            } else {
                theme.border
            })
            .bg(theme.background)
            .text_color(theme.text)
            .text_size(px(14.))
            .line_height(px(22.))
            .on_action(cx.listener(Self::left))
            .on_action(cx.listener(Self::right))
            .on_action(cx.listener(Self::select_left))
            .on_action(cx.listener(Self::select_right))
            .on_action(cx.listener(Self::home))
            .on_action(cx.listener(Self::end))
            .on_action(cx.listener(Self::select_home))
            .on_action(cx.listener(Self::select_end))
            .on_action(cx.listener(Self::select_all))
            .on_action(cx.listener(Self::backspace))
            .on_action(cx.listener(Self::delete))
            .on_action(cx.listener(Self::copy))
            .on_action(cx.listener(Self::cut))
            .on_action(cx.listener(Self::paste))
            .on_action(cx.listener(Self::submit))
            .on_mouse_down(MouseButton::Left, cx.listener(Self::mouse_down))
            .on_mouse_move(cx.listener(Self::mouse_move))
            .on_mouse_up(MouseButton::Left, cx.listener(Self::mouse_up))
            .on_mouse_up_out(MouseButton::Left, cx.listener(Self::mouse_up))
            .child(InputText { input: cx.entity() })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_all_line_breaks() {
        assert_eq!(
            single_line("https://tu\r\nist.dev\u{85}\u{2028}\u{2029}"),
            "https://tuist.dev"
        );
    }

    #[test]
    fn utf16_offsets_stay_on_utf8_boundaries() {
        let text = "a😀é";
        assert_eq!(
            (0..=5).map(|i| utf8_offset(text, i)).collect::<Vec<_>>(),
            [0, 1, 5, 5, 7, 7]
        );
    }

    #[test]
    fn accessible_text_uses_scalar_indices_and_preserves_direction() {
        let id = accesskit::NodeId(42);
        // Combining marks remain individually selectable, just like arrow movement.
        let text = "a😀e\u{301}";
        for reversed in [false, true] {
            let (run, selection) = TextInput::a11y_text(text, 1..text.len(), reversed, id);
            assert_eq!(run.role(), accesskit::Role::TextRun);
            assert_eq!(run.value(), Some(text));
            assert_eq!(run.character_lengths(), &[1, 4, 1, 2]);
            assert_eq!(selection.anchor.node, id);
            assert_eq!(selection.focus.node, id);
            assert_eq!(
                selection.anchor.character_index,
                if reversed { 4 } else { 1 }
            );
            assert_eq!(
                selection.focus.character_index,
                if reversed { 1 } else { 4 }
            );
        }
        let (run, caret) = TextInput::a11y_text("", 0..0, false, id);
        assert_eq!(run.value(), Some(""));
        assert!(run.character_lengths().is_empty());
        assert_eq!(caret.anchor, caret.focus);
        assert_eq!(caret.focus.character_index, 0);
    }

    #[gpui::test]
    fn rendered_input_exposes_name_value_and_edit_actions(cx: &mut gpui::TestAppContext) {
        let window = cx.add_window(|_, cx| TextInput::new("https://tuist.dev", cx));
        window
            .update(cx, |input, window, cx| {
                input.set_value("https://example.com".into(), cx);
                input.set_validation_error(Some("Use an HTTPS server URL".into()), cx);
                let element = input.render(window, cx).into_element();
                assert_eq!(element.id(), Some("server-url-input".into()));
                assert_eq!(element.a11y_role(), Some(accesskit::Role::TextInput));
                let mut node = accesskit::Node::new(element.a11y_role().unwrap());
                element.write_a11y_info(&mut node);
                assert_eq!(node.author_id(), Some("server-url-input"));
                assert_eq!(node.label(), Some("Server URL"));
                assert_eq!(node.value(), Some("https://example.com"));
                assert_eq!(node.placeholder(), Some("https://tuist.dev"));
                assert_eq!(node.description(), Some("Use an HTTPS server URL"));
                for action in [
                    accesskit::Action::Focus,
                    accesskit::Action::SetValue,
                    accesskit::Action::ReplaceSelectedText,
                    accesskit::Action::SetTextSelection,
                ] {
                    assert!(node.supports_action(action));
                }
            })
            .unwrap();
        window
            .update(cx, |input, window, cx| {
                input.set_validation_error(None, cx);
                let element = input.render(window, cx).into_element();
                let mut node = accesskit::Node::new(accesskit::Role::TextInput);
                element.write_a11y_info(&mut node);
                assert_eq!(node.description(), None);
            })
            .unwrap();
    }

    // TestWindow does not retain AccessKit adapter callbacks. Invoke the exact
    // listener installed by render, outside an entity update, then query through
    // GPUI's public native input interface. This is not OS adapter dispatch.
    fn accessible_action(
        cx: &mut gpui::TestAppContext,
        window: gpui::WindowHandle<TextInput>,
        action: accesskit::Action,
        data: Option<accesskit::ActionData>,
    ) {
        let mut listener = window
            .update(cx, |_, _, cx| TextInput::a11y_listener(action, cx))
            .unwrap();
        cx.update_window(window.into(), |_, window, cx| {
            listener(data.as_ref(), window, cx)
        })
        .unwrap();
    }

    #[gpui::test]
    fn assistive_edits_round_trip_through_native_input(cx: &mut gpui::TestAppContext) {
        use gpui::InputHandler;

        let window = cx.add_window(|_, cx| TextInput::new("Server", cx));
        let entity = window.root(cx).unwrap();
        let mut native = ElementInputHandler::new(Bounds::default(), entity);
        let id = accesskit::NodeId(42);
        window
            .update(cx, |input, _, _| input.a11y_run_id.set(Some(id)))
            .unwrap();
        accessible_action(cx, window, accesskit::Action::Focus, None);
        window
            .update(cx, |input, window, _| {
                assert!(input.focus_handle.is_focused(window));
            })
            .unwrap();
        accessible_action(
            cx,
            window,
            accesskit::Action::SetValue,
            Some(accesskit::ActionData::Value("a😀é\r\n".into())),
        );
        cx.update_window(window.into(), |_, window, cx| {
            let selection = native.selected_text_range(false, window, cx).unwrap();
            assert_eq!(selection.range, 4..4);
            assert!(!selection.reversed);
            assert_eq!(native.text_length_utf16(window, cx), Some(4));
        })
        .unwrap();

        let selection = accesskit::TextSelection {
            anchor: accesskit::TextPosition {
                node: id,
                character_index: 3,
            },
            focus: accesskit::TextPosition {
                node: id,
                character_index: 1,
            },
        };
        accessible_action(
            cx,
            window,
            accesskit::Action::SetTextSelection,
            Some(accesskit::ActionData::SetTextSelection(selection)),
        );
        cx.update_window(window.into(), |_, window, cx| {
            let selection = native.selected_text_range(false, window, cx).unwrap();
            assert_eq!(selection.range, 1..4);
            assert!(selection.reversed);
        })
        .unwrap();

        for invalid in [
            accesskit::TextSelection {
                anchor: accesskit::TextPosition {
                    node: accesskit::NodeId(99),
                    ..selection.anchor
                },
                ..selection
            },
            accesskit::TextSelection {
                focus: accesskit::TextPosition {
                    character_index: 4,
                    ..selection.focus
                },
                ..selection
            },
        ] {
            accessible_action(
                cx,
                window,
                accesskit::Action::SetTextSelection,
                Some(accesskit::ActionData::SetTextSelection(invalid)),
            );
        }
        accessible_action(cx, window, accesskit::Action::SetValue, None);
        accessible_action(
            cx,
            window,
            accesskit::Action::ReplaceSelectedText,
            Some(accesskit::ActionData::NumericValue(7.0)),
        );
        cx.update_window(window.into(), |_, window, cx| {
            let current = native.selected_text_range(false, window, cx).unwrap();
            assert_eq!(current.range, 1..4);
            assert!(current.reversed);
            assert_eq!(
                native
                    .text_for_range(0..4, &mut None, window, cx)
                    .as_deref(),
                Some("a😀é")
            );
        })
        .unwrap();
        accessible_action(
            cx,
            window,
            accesskit::Action::ReplaceSelectedText,
            Some(accesskit::ActionData::Value("ß\u{2028}".into())),
        );
        cx.update_window(window.into(), |_, window, cx| {
            assert_eq!(
                native
                    .text_for_range(0..2, &mut None, window, cx)
                    .as_deref(),
                Some("aß")
            );
            let selection = native.selected_text_range(false, window, cx).unwrap();
            assert_eq!(selection.range, 2..2);
            assert!(!selection.reversed);
            assert_eq!(native.marked_text_range(window, cx), None);
        })
        .unwrap();
    }

    #[gpui::test]
    fn assistive_replacement_uses_selection_not_ime_mark(cx: &mut gpui::TestAppContext) {
        use gpui::InputHandler;

        let window = cx.add_window(|_, cx| TextInput::new("Server", cx));
        let mut native = ElementInputHandler::new(Bounds::default(), window.root(cx).unwrap());
        cx.update_window(window.into(), |_, window, cx| {
            native.replace_and_mark_text_in_range(None, "a😀é", Some(1..3), window, cx);
            assert_eq!(native.marked_text_range(window, cx), Some(0..4));
        })
        .unwrap();
        accessible_action(
            cx,
            window,
            accesskit::Action::ReplaceSelectedText,
            Some(accesskit::ActionData::Value("x".into())),
        );
        cx.update_window(window.into(), |_, window, cx| {
            assert_eq!(
                native
                    .text_for_range(0..3, &mut None, window, cx)
                    .as_deref(),
                Some("axé")
            );
            assert_eq!(native.marked_text_range(window, cx), None);
        })
        .unwrap();
    }
}
