//! Drawing the dashboard.

use super::app::{App, Session, Tab};
use super::theme;
use crate::events::{ActionOutcome, SessionState};
use crate::util::format_duration;
use bytesize::ByteSize;
use ratatui::crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
use ratatui::prelude::*;
use ratatui::widgets::{
    Block, BorderType, Borders, Cell, Gauge, Paragraph, Row as TableRow, Table, TableState, Wrap,
};
use std::time::Duration;

pub(super) fn panel(title: impl Into<Line<'static>>) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::new().fg(theme::BORDER))
        .style(Style::new().fg(theme::TEXT).bg(theme::PANEL))
        .title_style(Style::new().fg(theme::ACCENT).bold())
        .title(title)
}

/// Bypasses are deliberate refusals to cache, not failures.
pub(super) fn outcome_style(outcome: &ActionOutcome) -> Style {
    match outcome {
        ActionOutcome::Hit => Style::new().fg(theme::HIT),
        ActionOutcome::Miss => Style::new().fg(theme::MISS),
        ActionOutcome::Unconsulted => Style::new().fg(theme::MUTED),
        ActionOutcome::Verification { matched: true } => Style::new().fg(theme::ACCENT),
        ActionOutcome::Verification { matched: false } => Style::new().fg(theme::PURPLE).bold(),
        ActionOutcome::Bypass { .. } => Style::new().fg(theme::WARNING),
    }
}

pub(super) fn state_style(state: SessionState) -> Style {
    match state {
        SessionState::Live => Style::new().fg(theme::HIT).bold(),
        SessionState::Finished => Style::new().fg(theme::MUTED),
        SessionState::Abandoned => Style::new().fg(theme::MISS),
    }
}

pub(super) use crate::savings::nanos as saved_duration;

fn main_area(area: Rect) -> std::rc::Rc<[Rect]> {
    Layout::vertical([
        Constraint::Length(5),
        Constraint::Length(3),
        Constraint::Min(0),
        Constraint::Length(1),
    ])
    .split(area)
}

fn live_columns(area: Rect) -> (Rect, Option<Rect>) {
    if area.width >= 110 && area.height >= 22 {
        let columns = Layout::horizontal([
            Constraint::Min(64),
            Constraint::Length(1),
            Constraint::Length((area.width / 3).clamp(36, 48)),
        ])
        .split(area);
        (columns[0], Some(columns[2]))
    } else {
        (area, None)
    }
}

fn live_areas(area: Rect, app: &App) -> std::rc::Rc<[Rect]> {
    // Let small histories take less room, and leave activity readable on short terminals.
    let builds = (app.sessions().count().min(5) as u16 + 3)
        .min(area.height.saturating_sub(7))
        .max(4);
    Layout::vertical([Constraint::Length(builds), Constraint::Min(0)]).split(area)
}

pub(super) fn action_page_size(area: Rect, app: &App) -> usize {
    let body = main_area(area)[2];
    live_areas(body, app)[1].height.saturating_sub(6).max(1) as usize
}

pub(super) fn scroll_page(app: &mut App, area: Rect, down: bool) {
    if app.tab == Tab::Insights {
        super::insights::scroll(app, main_area(area)[2], down);
    } else if app.tab == Tab::Store {
        let body = main_area(area)[2];
        let page = body.height.saturating_sub(2).max(1) as usize;
        let max = store_lines(app, body.width.saturating_sub(2))
            .len()
            .saturating_sub(page);
        app.store_scroll = if down {
            app.store_scroll.min(max).saturating_add(page).min(max)
        } else {
            app.store_scroll.min(max).saturating_sub(page)
        };
    } else if down {
        app.newer_actions(action_page_size(area, app));
    } else {
        app.older_actions(action_page_size(area, app));
    }
}

pub(super) fn move_vertical(app: &mut App, area: Rect, down: bool) {
    if app.tab == Tab::Store {
        let body = main_area(area)[2];
        let max = store_lines(app, body.width.saturating_sub(2))
            .len()
            .saturating_sub(body.height.saturating_sub(2) as usize);
        app.store_scroll = if down {
            app.store_scroll.min(max).saturating_add(1).min(max)
        } else {
            app.store_scroll.min(max).saturating_sub(1)
        };
    } else if down {
        app.select_next();
    } else {
        app.select_previous();
    }
}

pub(super) fn draw(frame: &mut Frame, app: &App) {
    frame.render_widget(
        Block::default().style(Style::new().fg(theme::TEXT).bg(theme::BACKGROUND)),
        frame.area(),
    );
    if frame.area().width < 48 || frame.area().height < 22 {
        frame.render_widget(
            Paragraph::new("Enlarge the terminal to at least 48 × 22.\nUse tuist_cargo_cache tui --once for a text snapshot.\nq quit")
                .wrap(Wrap { trim: false }),
            frame.area(),
        );
        return;
    }
    let areas = main_area(frame.area());
    header(frame, areas[0], app);
    tabs(frame, areas[1], app);
    match app.tab {
        Tab::Live => live(frame, areas[2], app),
        Tab::Sessions => sessions(frame, areas[2], app),
        Tab::Store => store(frame, areas[2], app),
        Tab::Insights => super::insights::draw(frame, areas[2], app),
    }
    footer(frame, areas[3], app);
}

fn size(bytes: u64) -> String {
    ByteSize::b(bytes).display().iec().to_string()
}

fn header(frame: &mut Frame, area: Rect, app: &App) {
    if area.width >= 110 {
        super::dashboard::header(frame, area, app);
        return;
    }
    let running = app
        .sessions()
        .filter(|session| session.state == SessionState::Live)
        .count();
    let status = if app.paused {
        " PAUSED ".into()
    } else {
        format!(" {running} running ")
    };
    let block = panel(" tuist_cargo_cache ").title_top(
        Line::styled(
            status,
            Style::new()
                .fg(if app.paused {
                    theme::WARNING
                } else {
                    theme::HIT
                })
                .bold(),
        )
        .right_aligned(),
    );
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let rows = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Length(1),
    ])
    .split(inner);
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(
                saved_duration(app.savings.avoided_compiler_ns),
                Style::new().fg(theme::HIT).bold(),
            ),
            Span::raw(if app.savings.since_secs > 0 {
                format!(
                    " compiling saved {}",
                    crate::savings::since(app.savings.since_secs)
                )
            } else {
                " compiling saved · no history yet".into()
            }),
        ])),
        rows[0],
    );
    capacity(frame, rows[1], app);
    pressure(frame, rows[2], app);
}

pub(super) fn pressure(frame: &mut Frame, area: Rect, app: &App) {
    let thrashing = app.health.possible_thrashing(app.store_budget);
    let message = if thrashing {
        format!(
            "! POSSIBLE CACHE THRASHING · {} logical evicted / 5m · {:.0}% misses",
            size(app.health.evicted),
            app.health.miss_rate()
        )
    } else {
        format!(
            "Evicted {} logical / 5m · {} logical total{}",
            size(app.health.evicted),
            size(app.savings.freed_store_bytes),
            if app.gc_auto { "" } else { " · auto GC off" }
        )
    };
    let style = if thrashing && app.health.bright() {
        Style::new().fg(theme::BACKGROUND).bg(theme::MISS).bold()
    } else if thrashing {
        Style::new().fg(theme::WARNING).bold()
    } else {
        Style::new().fg(if app.health.evicted > 0 {
            theme::WARNING
        } else {
            theme::MUTED
        })
    };
    frame.render_widget(Paragraph::new(message).style(style), area);
}

fn capacity(frame: &mut Frame, area: Rect, app: &App) {
    let Some(stats) = &app.store_stats else {
        frame.render_widget(Paragraph::new("Store usage unavailable"), area);
        return;
    };
    let used = stats.total_bytes();
    let Some(budget) = app.store_budget else {
        frame.render_widget(
            Paragraph::new(format!("Store {} · budget unavailable", size(used))),
            area,
        );
        return;
    };
    let ratio = if budget == 0 {
        f64::from(used > 0)
    } else {
        used as f64 / budget as f64
    };
    let color = if ratio >= 1.0 {
        theme::MISS
    } else if ratio >= 0.9 {
        theme::WARNING
    } else {
        theme::ACCENT
    };
    let areas = Layout::horizontal([
        Constraint::Min(0),
        Constraint::Length(1),
        Constraint::Length(if area.width < 78 { 8 } else { 14 }),
    ])
    .split(area);
    let percent = if budget == 0 {
        "zero budget".into()
    } else {
        format!("{:.0}%", ratio * 100.0)
    };
    frame.render_widget(
        Paragraph::new(format!(
            "Store {} / {} · {percent}",
            size(used),
            size(budget)
        ))
        .style(Style::new().fg(color)),
        areas[0],
    );
    frame.render_widget(
        Gauge::default()
            .ratio(ratio.clamp(0.0, 1.0))
            .label("")
            .gauge_style(Style::new().fg(color).bg(theme::BORDER))
            .use_unicode(true),
        areas[2],
    );
}

fn tab_areas(area: Rect) -> Vec<(Tab, Rect)> {
    let mut x = area.x;
    Tab::ALL
        .iter()
        .enumerate()
        .map(|(index, tab)| {
            let width = (format!("{} {}", index + 1, tab.title()).len() as u16 + 2)
                .min(area.right().saturating_sub(x));
            let rect = Rect::new(x, area.y, width, area.height);
            x = x.saturating_add(width + 1);
            (*tab, rect)
        })
        .collect()
}

fn build_offset(app: &App, area: Rect) -> usize {
    app.selected
        .saturating_add(1)
        .saturating_sub(area.height.saturating_sub(3) as usize)
}

pub(super) fn handle_mouse(app: &mut App, mouse: MouseEvent, area: Rect) {
    if area.width < 48 || area.height < 22 {
        return;
    }
    let point = Position::new(mouse.column, mouse.row);
    let areas = main_area(area);
    if mouse.kind == MouseEventKind::Down(MouseButton::Left) {
        for (tab, rect) in tab_areas(areas[1]) {
            if rect.contains(point) {
                app.select_tab(tab);
                return;
            }
        }
    }
    let body = areas[2];
    if !body.contains(point) {
        return;
    }
    let builds = match app.tab {
        Tab::Live if !app.is_empty() => Some(live_areas(live_columns(body).0, app)[0]),
        Tab::Sessions => Some(body),
        _ => None,
    };
    if mouse.kind == MouseEventKind::Down(MouseButton::Left) {
        if let Some(builds) = builds {
            let rows = Rect::new(
                builds.x + 1,
                builds.y + 2,
                builds.width.saturating_sub(2),
                builds.height.saturating_sub(3),
            );
            let offset = if app.tab == Tab::Sessions {
                app.scroll
            } else {
                build_offset(app, builds)
            };
            let selected = offset + mouse.row.saturating_sub(rows.y) as usize;
            if rows.contains(point) && selected < app.sessions().count() {
                if app.selected != selected {
                    app.selected = selected;
                    app.action_scroll = 0;
                    app.insight_scroll = 0;
                }
                if app.tab == Tab::Sessions {
                    app.select_tab(Tab::Live);
                }
            }
        }
        return;
    }
    let down = match mouse.kind {
        MouseEventKind::ScrollDown => true,
        MouseEventKind::ScrollUp => false,
        _ => return,
    };
    match app.tab {
        Tab::Live if !app.is_empty() => {
            let panels = live_areas(live_columns(body).0, app);
            if panels[0].contains(point) {
                move_vertical(app, area, down);
            } else if panels[1].contains(point) {
                let page = action_page_size(area, app);
                let max = app
                    .selected_session()
                    .map_or(0, |session| session.rows.len().saturating_sub(page));
                app.action_scroll = if down {
                    app.action_scroll.min(max).saturating_sub(3)
                } else {
                    app.action_scroll.min(max).saturating_add(3).min(max)
                };
            }
        }
        Tab::Sessions | Tab::Store => move_vertical(app, area, down),
        Tab::Insights => super::insights::scroll(app, body, down),
        _ => {}
    }
}

fn tabs(frame: &mut Frame, area: Rect, app: &App) {
    for (index, (tab, rect)) in tab_areas(area).into_iter().enumerate() {
        let title = format!("{} {}", index + 1, tab.title());
        let selected = tab == app.tab;
        let style = if selected {
            Style::new().fg(theme::ACCENT).bg(theme::SELECTION).bold()
        } else {
            Style::new().fg(theme::MUTED).bg(theme::BACKGROUND)
        };
        let block = Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(style)
            .style(style);
        frame.render_widget(
            Paragraph::new(title)
                .alignment(Alignment::Center)
                .style(style)
                .block(block),
            rect,
        );
    }
}

fn live(frame: &mut Frame, area: Rect, app: &App) {
    if app.is_empty() {
        frame.render_widget(
            Paragraph::new("Waiting for builds…\n\nRun `tuist_cargo_cache build` in another terminal.\nBuilds from every workspace will appear here.")
                .wrap(Wrap { trim: false })
                .block(panel(" Builds ")),
            area,
        );
        return;
    }
    let (main, sidebar) = live_columns(area);
    if let Some(sidebar) = sidebar {
        super::dashboard::sidebar(frame, sidebar, app);
    }
    let areas = live_areas(main, app);
    session_list(frame, areas[0], app);
    if let Some(session) = app.selected_session() {
        action_rows(frame, areas[1], session, app.action_scroll);
    }
}

fn right(value: impl Into<String>, style: Style) -> Cell<'static> {
    Cell::from(Line::styled(value.into(), style).right_aligned())
}

fn count(value: u64, color: Color) -> Cell<'static> {
    right(
        value.to_string(),
        Style::new().fg(if value == 0 { theme::MUTED } else { color }),
    )
}

fn table_header(labels: &[&str], numeric_from: usize) -> TableRow<'static> {
    TableRow::new(
        labels
            .iter()
            .enumerate()
            .map(|(i, label)| {
                let line = Line::from((*label).to_string());
                Cell::from(if i >= numeric_from {
                    line.right_aligned()
                } else {
                    line
                })
            })
            .collect::<Vec<_>>(),
    )
    .style(Style::new().fg(theme::MUTED).bold())
}

fn session_list(frame: &mut Frame, area: Rect, app: &App) {
    let wide = area.width >= 120;
    let medium = area.width >= 80;
    let mut labels = vec!["command"];
    let mut widths = vec![Constraint::Min(16)];
    if wide {
        labels.push("workspace");
        widths.push(Constraint::Length(18));
    }
    labels.push("state");
    widths.push(Constraint::Length(9));
    let numeric_from = labels.len();
    if medium {
        labels.extend(["hit", "miss"]);
        widths.extend([Constraint::Length(6), Constraint::Length(6)]);
    }
    if wide {
        labels.extend(["unconsulted", "bypass"]);
        widths.extend([Constraint::Length(11), Constraint::Length(6)]);
    }
    labels.push("rate");
    widths.push(Constraint::Length(5));
    let rows = app
        .sessions()
        .map(|session| {
            let mut cells = vec![Cell::from(session.title())];
            if wide {
                cells.push(Cell::from(
                    session.workspace_name().unwrap_or("").to_string(),
                ));
            }
            cells.push(Cell::from(Span::styled(
                session.state.label(),
                state_style(session.state),
            )));
            if medium {
                cells.extend([
                    count(session.count("hit"), theme::HIT),
                    count(session.count("miss"), theme::MISS),
                ]);
            }
            if wide {
                cells.extend([
                    count(session.count("unconsulted"), theme::MUTED),
                    count(
                        session.bypasses().iter().map(|(_, count)| count).sum(),
                        theme::WARNING,
                    ),
                ]);
            }
            cells.push(right(
                session
                    .hit_rate()
                    .map(|rate| format!("{rate:.0}%"))
                    .unwrap_or_else(|| "-".into()),
                Style::new(),
            ));
            TableRow::new(cells)
        })
        .collect::<Vec<_>>();
    let table = Table::new(rows, widths)
        .header(table_header(&labels, numeric_from))
        .highlight_symbol("▸ ")
        .row_highlight_style(Style::new().bg(theme::SELECTION).bold())
        .block(panel(format!(
            " Builds · {}/{} ",
            app.selected + 1,
            app.sessions().count()
        )));
    // A stateful table keeps the selected row visible, including after a resize.
    let mut state = TableState::default()
        .with_selected(app.selected)
        .with_offset(build_offset(app, area));
    frame.render_stateful_widget(table, area, &mut state);
}

fn action_rows(frame: &mut Frame, area: Rect, session: &Session, scroll: usize) {
    let height = area.height.saturating_sub(6) as usize;
    let scroll = scroll.min(session.rows.len().saturating_sub(height.max(1)));
    let end = session.rows.len().saturating_sub(scroll);
    let start = end.saturating_sub(height);
    let position = if end == 0 {
        "no actions".to_string()
    } else {
        format!("{}–{} of {}", start + 1, end, session.rows.len())
    };
    let mode = if scroll == 0 { "latest" } else { "history" };
    let capped = if session.truncated {
        " · history capped"
    } else {
        ""
    };
    let block = panel(format!(" Activity · {mode} "))
        .title_bottom(Line::from(format!(" {position}{capped} ")).right_aligned());
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let sections = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(2),
        Constraint::Min(0),
    ])
    .split(inner);
    let workspace = session.workspace_name().unwrap_or("unknown workspace");
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(format!("{workspace} · "), Style::new().fg(theme::ACCENT)),
            Span::styled(session.title(), Style::new().bold()),
        ])),
        sections[0],
    );
    let bypasses: u64 = session.bypasses().iter().map(|(_, count)| count).sum();
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(
                format!("{} hit", session.count("hit")),
                Style::new().fg(theme::HIT),
            ),
            Span::raw(" · "),
            Span::styled(
                format!("{} miss", session.count("miss")),
                Style::new().fg(theme::MISS),
            ),
            Span::raw(format!(" · {} unconsulted", session.count("unconsulted"))),
            Span::styled(
                format!(" · {bypasses} bypass"),
                Style::new().fg(theme::WARNING),
            ),
            Span::styled(
                format!(" · {} saved", saved_duration(session.avoided_compiler_ns)),
                Style::new().fg(theme::HIT),
            ),
        ]))
        .wrap(Wrap { trim: true }),
        sections[1],
    );
    if session.rows.is_empty() {
        let message = if session.state == SessionState::Live {
            "Waiting for compilation events…"
        } else {
            "No compilation events recorded for this build."
        };
        frame.render_widget(
            Paragraph::new(message).wrap(Wrap { trim: true }),
            sections[2],
        );
        return;
    }
    let outcome_width = session.rows[start..end]
        .iter()
        .map(|row| Line::from(row.outcome.label()).width() as u16)
        .max()
        .unwrap_or(7)
        .clamp(7, (inner.width / 3).max(7));
    let rows = session.rows[start..end]
        .iter()
        .map(|row| {
            TableRow::new(vec![
                Cell::from(row.crate_name.clone().unwrap_or_else(|| "-".into())),
                Cell::from(Span::styled(
                    row.outcome.label().to_string(),
                    outcome_style(&row.outcome),
                )),
                right(
                    format_duration(Duration::from_nanos(row.duration_ns)),
                    Style::new(),
                ),
            ])
        })
        .collect::<Vec<_>>();
    frame.render_widget(
        Table::new(
            rows,
            [
                Constraint::Min(12),
                Constraint::Length(outcome_width),
                Constraint::Length(10),
            ],
        )
        .column_spacing(2)
        .header(table_header(&["crate", "outcome", "duration"], 2)),
        sections[2],
    );
}

fn sessions(frame: &mut Frame, area: Rect, app: &App) {
    let wide = area.width >= 100;
    let medium = area.width >= 70;
    let mut labels = vec!["command", "state"];
    let mut widths = vec![Constraint::Min(16), Constraint::Length(9)];
    if medium {
        labels.extend(["hits", "misses"]);
        widths.extend([Constraint::Length(6), Constraint::Length(6)]);
    }
    if wide {
        labels.push("unconsulted");
        widths.push(Constraint::Length(11));
    }
    labels.push("saved");
    widths.push(Constraint::Length(10));
    let rows = app
        .sessions()
        .skip(app.scroll)
        .map(|session| {
            let totals = session.totals.as_ref();
            let field = |key: &str, color| {
                totals
                    .map(|totals| count(crate::events::stat(totals, key), color))
                    .unwrap_or_else(|| right("-", Style::new().fg(theme::MUTED)))
            };
            let mut cells = vec![
                Cell::from(session.title()),
                Cell::from(Span::styled(
                    session.state.label(),
                    state_style(session.state),
                )),
            ];
            if medium {
                cells.extend([field("hits", theme::HIT), field("misses", theme::MISS)]);
            }
            if wide {
                cells.push(field("unconsulted", theme::MUTED));
            }
            cells.push(right(
                totals
                    .map(|totals| {
                        saved_duration(crate::events::stat(
                            totals,
                            "estimated_compiler_duration_avoided_ns",
                        ))
                    })
                    .unwrap_or_else(|| "-".into()),
                Style::new().fg(theme::HIT),
            ));
            TableRow::new(cells)
        })
        .collect::<Vec<_>>();
    frame.render_widget(
        Table::new(rows, widths)
            .header(table_header(&labels, 2))
            .block(panel(format!(
                " Sessions · {} builds ",
                app.sessions().count()
            ))),
        area,
    );
}

fn store_lines(app: &App, width: u16) -> Vec<Line<'static>> {
    let mut lines = Vec::new();
    match &app.store_stats {
        Some(stats) => {
            lines.push(Line::from(format!(
                "objects:        {} ({})",
                stats.objects,
                ByteSize::b(stats.object_bytes).display().iec()
            )));
            lines.push(Line::from(format!(
                "action results: {} ({})",
                stats.action_results,
                ByteSize::b(stats.action_result_bytes).display().iec()
            )));
            lines.push(Line::from(format!(
                "checkouts:      {} live, {} stale",
                stats.live_checkouts, stats.stale_checkouts
            )));
            lines.push(Line::from(format!(
                "total:          {}",
                ByteSize::b(stats.total_bytes()).display().iec()
            )));
        }
        None => lines.push(Line::from("the store could not be read")),
    }
    lines.push(Line::from(format!("store: {}", app.store_dir().display())));
    if let Some(budget) = app.store_budget {
        lines.push(Line::from(format!(
            "configured store budget: {}",
            size(budget)
        )));
        lines.push(Line::from(
            "A combined target/store budget can reduce this limit.",
        ));
    }
    lines.push(Line::from(format!(
        "automatic collection: {}",
        if app.gc_auto { "on" } else { "off" }
    )));
    lines.push(Line::from(format!(
        "evicted while watching (last 5m): {} logical",
        size(app.health.evicted)
    )));
    lines.push(Line::from(format!(
        "eviction counter increases (last 5m): {}",
        app.health.eviction_updates
    )));
    if app.health.possible_thrashing(app.store_budget) {
        lines.push(Line::styled(
            "! POSSIBLE CACHE THRASHING",
            Style::new().fg(theme::MISS).bold(),
        ));
        lines.push(Line::from(format!(
            "{} logical evicted with {:.0}% misses in the last 5m.",
            size(app.health.evicted),
            app.health.miss_rate()
        )));
        lines.push(Line::from(
            "Consider a larger gc.max_size budget; inspect misses.",
        ));
    }
    let lifetime = crate::stats::Lifetime::from(&app.savings);
    lines.push(Line::default());
    lines.push(Line::styled(
        lifetime.since(),
        Style::new().fg(theme::ACCENT).bold(),
    ));
    lines.extend(
        lifetime
            .rows()
            .into_iter()
            .map(|(label, value)| Line::from(format!("{label:<23} {value}"))),
    );
    if let Some(sharing) = &app.sharing {
        lines.push(Line::default());
        lines.push(Line::styled(
            "Workspace sharing · estimated",
            Style::new().fg(theme::ACCENT).bold(),
        ));
        lines.extend(
            sharing
                .rows()
                .into_iter()
                .map(|(label, value)| Line::from(format!("{label:<23} {value}"))),
        );
        lines.push(Line::from(
            "Logical cache bytes; excludes target directories.",
        ));
    }
    if app.sharing.is_none() && app.sharing_loading() {
        lines.push(Line::default());
        lines.push(Line::from("Calculating workspace sharing…"));
    }
    if app.cheeky
        && let Some(quip) = lifetime.quip()
    {
        lines.push(Line::default());
        lines.push(Line::styled(quip, Style::new().fg(theme::HIT)));
    }
    lines.push(Line::default());
    lines.push(Line::from(
        "Pruned totals are logical file sizes, not physical space reclaimed.",
    ));
    lines.push(Line::from(
        "Copying avoided is cumulative, not current disk savings.",
    ));
    wrap_lines(lines, width)
}

pub(super) fn wrap_lines(lines: Vec<Line<'static>>, width: u16) -> Vec<Line<'static>> {
    let mut wrapped = Vec::new();
    for line in lines {
        if line.width() <= width as usize {
            wrapped.push(line);
            continue;
        }
        let mut part = String::new();
        for word in line.to_string().split_whitespace() {
            if !part.is_empty() && Line::from(format!("{part} {word}")).width() > width as usize {
                wrapped.push(Line::styled(std::mem::take(&mut part), line.style));
            }
            if !part.is_empty() {
                part.push(' ');
            }
            part.push_str(word);
        }
        wrapped.push(Line::styled(part, line.style));
    }
    wrapped
}

fn store(frame: &mut Frame, area: Rect, app: &App) {
    if area.width >= 110
        && area.height >= 27
        && app.store_scroll == 0
        && super::dashboard::store(frame, area, app)
    {
        return;
    }
    let lines = store_lines(app, area.width.saturating_sub(2));
    let offset = app.store_scroll.min(
        lines
            .len()
            .saturating_sub(area.height.saturating_sub(2) as usize),
    );
    frame.render_widget(
        Paragraph::new(lines)
            .scroll((offset as u16, 0))
            .block(panel(" Store · tuist_cargo_cache stats for a text report ")),
        area,
    );
}

fn footer(frame: &mut Frame, area: Rect, app: &App) {
    let mut keys = vec![
        ("q", "quit"),
        ("p", if app.paused { "resume" } else { "pause" }),
        ("←→/tab", "tabs"),
    ];
    keys.push((
        "↑↓",
        if app.tab == Tab::Store || app.tab == Tab::Sessions {
            "scroll"
        } else {
            "build"
        },
    ));
    if app.tab == Tab::Live && area.width >= 76 {
        keys.extend([("PgUp/Dn", "history"), ("End", "latest")]);
    } else if matches!(app.tab, Tab::Live | Tab::Insights | Tab::Store) {
        keys.push(("PgUp/Dn", "scroll"));
    }
    let spans = keys
        .into_iter()
        .flat_map(|(key, label)| {
            [
                Span::styled(key, Style::new().fg(theme::ACCENT).bold()),
                Span::styled(format!(" {label}  "), Style::new().fg(theme::MUTED)),
            ]
        })
        .collect::<Vec<_>>();
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

#[cfg(test)]
#[path = "ui_tests.rs"]
mod tests;
