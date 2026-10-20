//! Compact dashboard panels for terminals with room to show charts alongside work.

use super::app::{App, Session};
use super::theme;
use super::ui::{panel, pressure, saved_duration};
use crate::events::{ActionOutcome, SessionState};
use bytesize::ByteSize;
use ratatui::prelude::*;
use ratatui::widgets::{Gauge, Paragraph, Sparkline};

fn size(bytes: u64) -> String {
    ByteSize::b(bytes).display().iec().to_string()
}

fn number(value: u64) -> String {
    let value = value.to_string();
    let mut result = String::new();
    for (index, ch) in value.chars().enumerate() {
        if index > 0 && (value.len() - index).is_multiple_of(3) {
            result.push(',');
        }
        result.push(ch);
    }
    result
}

fn card(frame: &mut Frame, area: Rect, title: &str, color: Color) -> Rect {
    let block = panel(format!(" {title} ")).border_style(Style::new().fg(color));
    let inner = block.inner(area);
    frame.render_widget(block, area);
    inner
}

pub(super) fn header(frame: &mut Frame, area: Rect, app: &App) {
    let rows = Layout::vertical([Constraint::Length(4), Constraint::Length(1)]).split(area);
    let columns = Layout::horizontal([
        Constraint::Ratio(1, 3),
        Constraint::Ratio(1, 3),
        Constraint::Ratio(1, 3),
    ])
    .split(rows[0]);
    let saved = card(
        frame,
        columns[0],
        "tuist_cargo_cache / compiler time saved",
        theme::ACCENT,
    );
    frame.render_widget(
        Paragraph::new(vec![
            Line::styled(
                saved_duration(app.savings.avoided_compiler_ns),
                Style::new().fg(theme::HIT).bold(),
            ),
            Line::styled(
                if app.savings.since_secs > 0 {
                    crate::savings::since(app.savings.since_secs)
                } else {
                    "waiting for your first build".into()
                },
                Style::new().fg(theme::MUTED),
            ),
        ]),
        saved,
    );
    let ratio = match (&app.store_stats, app.store_budget) {
        (Some(stats), Some(budget)) if budget > 0 => {
            Some(stats.total_bytes() as f64 / budget as f64)
        }
        _ => None,
    };
    let color = match ratio {
        Some(ratio) if ratio >= 1.0 => theme::MISS,
        Some(ratio) if ratio >= 0.9 => theme::WARNING,
        _ if app.store_budget == Some(0)
            && app
                .store_stats
                .as_ref()
                .is_some_and(|stats| stats.total_bytes() > 0) =>
        {
            theme::MISS
        }
        _ => theme::ACCENT,
    };
    let store = card(
        frame,
        columns[1],
        &ratio.map_or_else(
            || "Store".into(),
            |ratio| format!("Store / {:.0}%", ratio * 100.0),
        ),
        color,
    );
    let label = match (&app.store_stats, app.store_budget) {
        (Some(stats), Some(budget)) => format!(
            "{} / {}{}",
            size(stats.total_bytes()),
            size(budget),
            if budget == 0 { " · zero budget" } else { "" }
        ),
        (Some(stats), None) => format!("{} · budget unavailable", size(stats.total_bytes())),
        _ => "Store usage unavailable".into(),
    };
    frame.render_widget(
        Paragraph::new(label).style(Style::new().fg(theme::TEXT).bold()),
        Rect::new(store.x, store.y, store.width, 1),
    );
    frame.render_widget(
        Gauge::default()
            .ratio(
                ratio
                    .unwrap_or_else(|| if color == theme::MISS { 1.0 } else { 0.0 })
                    .clamp(0.0, 1.0),
            )
            .label("")
            .gauge_style(Style::new().fg(color).bg(theme::SELECTION))
            .use_unicode(true),
        Rect::new(store.x, store.y + 1, store.width, 1),
    );
    let evictions = card(frame, columns[2], "Evictions / 5m · logical", theme::PURPLE);
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(vec![
                Span::styled(
                    size(app.health.evicted),
                    Style::new().fg(theme::WARNING).bold(),
                ),
                Span::styled(
                    format!("   {} updates", app.health.eviction_updates),
                    Style::new().fg(theme::MUTED),
                ),
            ]),
            Line::styled(
                format!("{} logical lifetime", size(app.savings.freed_store_bytes)),
                Style::new().fg(theme::MUTED),
            ),
        ]),
        evictions,
    );
    if app.health.possible_thrashing(app.store_budget) {
        pressure(frame, rows[1], app);
    } else {
        let running = app
            .sessions()
            .filter(|session| session.state == SessionState::Live)
            .count();
        frame.render_widget(
            Paragraph::new(Line::from(vec![
                Span::styled(
                    if app.paused {
                        " ○ PAUSED ".into()
                    } else {
                        format!(" ● {running} running ")
                    },
                    Style::new().fg(if app.paused {
                        theme::WARNING
                    } else {
                        theme::HIT
                    }),
                ),
                Span::styled(
                    format!(
                        " · {} builds recorded · {} cache hits{}",
                        number(app.savings.builds),
                        number(app.savings.cached_compilations),
                        if app.gc_auto { "" } else { " · auto GC off" }
                    ),
                    Style::new().fg(theme::MUTED),
                ),
            ])),
            rows[1],
        );
    }
}

pub(super) fn sidebar(frame: &mut Frame, area: Rect, app: &App) {
    let rows = Layout::vertical([
        Constraint::Length(9),
        Constraint::Length(8),
        Constraint::Min(5),
    ])
    .split(area);
    traffic(frame, rows[0], app);
    if let Some(session) = app.selected_session() {
        cache_mix(frame, rows[1], session);
        wins(frame, rows[2], session);
    }
}

fn traffic(frame: &mut Frame, area: Rect, app: &App) {
    let inner = card(frame, area, "Lookup traffic / 5m", theme::ACCENT);
    let rows = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(2),
        Constraint::Length(1),
        Constraint::Length(2),
        Constraint::Length(1),
    ])
    .split(inner);
    let (hits, misses) = app.health.lookup_series(inner.width as usize);
    let max = hits
        .iter()
        .chain(&misses)
        .copied()
        .max()
        .unwrap_or(1)
        .max(1);
    frame.render_widget(
        Paragraph::new(format!("HITS   {}", number(app.health.hits)))
            .style(Style::new().fg(theme::HIT).bold()),
        rows[0],
    );
    frame.render_widget(
        Sparkline::default()
            .data(&hits)
            .max(max)
            .style(Style::new().fg(theme::HIT)),
        rows[1],
    );
    frame.render_widget(
        Paragraph::new(format!("MISSES {}", number(app.health.misses)))
            .style(Style::new().fg(theme::MISS).bold()),
        rows[2],
    );
    frame.render_widget(
        Sparkline::default()
            .data(&misses)
            .max(max)
            .style(Style::new().fg(theme::MISS)),
        rows[3],
    );
    frame.render_widget(
        Paragraph::new(
            Line::styled(
                "5m ago                 now →",
                Style::new().fg(theme::MUTED),
            )
            .right_aligned(),
        ),
        rows[4],
    );
}

fn cache_mix(frame: &mut Frame, area: Rect, session: &Session) {
    let inner = card(frame, area, "Selected build / cache", theme::HIT);
    let rows = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Min(0),
    ])
    .split(inner);
    frame.render_widget(
        Paragraph::new(session.hit_rate().map_or_else(
            || "— no lookups yet".into(),
            |rate| format!("{rate:.0}% lookup hit rate"),
        ))
        .style(Style::new().fg(theme::HIT).bold()),
        rows[0],
    );
    frame.render_widget(
        Gauge::default()
            .ratio(session.hit_rate().unwrap_or(0.0) / 100.0)
            .label("")
            .gauge_style(Style::new().fg(theme::HIT).bg(theme::SELECTION))
            .use_unicode(true),
        rows[1],
    );
    let bypasses: u64 = session.bypasses().iter().map(|(_, count)| count).sum();
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(vec![
                Span::styled(
                    format!("{} hit", number(session.count("hit"))),
                    Style::new().fg(theme::HIT),
                ),
                Span::styled(
                    format!("   {} miss", number(session.count("miss"))),
                    Style::new().fg(theme::MISS),
                ),
            ]),
            Line::styled(
                format!(
                    "{} unconsulted · {} bypass",
                    number(session.count("unconsulted")),
                    number(bypasses)
                ),
                Style::new().fg(theme::MUTED),
            ),
            Line::from(format!("{} restored", size(session.restored_bytes))),
            Line::styled(
                format!(
                    "{} compiler time saved",
                    saved_duration(session.avoided_compiler_ns)
                ),
                Style::new().fg(theme::HIT),
            ),
        ]),
        rows[2],
    );
}

fn wins(frame: &mut Frame, area: Rect, session: &Session) {
    let block = panel(" Biggest cache wins ")
        .border_style(Style::new().fg(theme::PURPLE))
        .title_bottom(
            Line::styled(
                " estimated · retained actions ",
                Style::new().fg(theme::MUTED),
            )
            .right_aligned(),
        );
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let mut wins: Vec<_> = session
        .rows
        .iter()
        .filter(|row| matches!(row.outcome, ActionOutcome::Hit) && row.avoided_compiler_ns > 0)
        .collect();
    wins.sort_by_key(|row| std::cmp::Reverse(row.avoided_compiler_ns));
    if wins.is_empty() {
        frame.render_widget(
            Paragraph::new("No cache savings recorded yet.").style(Style::new().fg(theme::MUTED)),
            inner,
        );
        return;
    }
    frame.render_widget(
        Paragraph::new(super::insights::ranking(
            &wins[..wins.len().min(inner.height as usize)],
            inner.width,
            true,
        )),
        inner,
    );
}

/// Fall back to the scrollable report if a path or a value needs more room.
pub(super) fn store(frame: &mut Frame, area: Rect, app: &App) -> bool {
    let rows = Layout::vertical([Constraint::Min(0), Constraint::Length(6)]).split(area);
    let columns = Layout::horizontal([
        Constraint::Ratio(1, 2),
        Constraint::Length(1),
        Constraint::Ratio(1, 2),
    ])
    .split(rows[0]);
    let left = Layout::vertical([Constraint::Length(12), Constraint::Min(0)]).split(columns[0]);
    let mut inventory = match &app.store_stats {
        Some(stats) => vec![
            Line::from(format!(
                "{} objects · {}",
                number(stats.objects),
                size(stats.object_bytes)
            )),
            Line::from(format!(
                "{} action results · {}",
                number(stats.action_results),
                size(stats.action_result_bytes)
            )),
            Line::from(format!(
                "{} live checkouts · {} stale",
                stats.live_checkouts, stats.stale_checkouts
            )),
        ],
        None => vec![Line::from("Store usage unavailable")],
    };
    inventory.extend([
        Line::default(),
        Line::styled(
            app.store_dir().display().to_string(),
            Style::new().fg(theme::MUTED),
        ),
        Line::default(),
        Line::from(format!(
            "Automatic collection: {}",
            if app.gc_auto { "on" } else { "off" }
        )),
        Line::from(format!(
            "{} evicted in {} updates / 5m",
            size(app.health.evicted),
            app.health.eviction_updates
        )),
        Line::styled(
            "Combined budgets may lower the store allowance.",
            Style::new().fg(theme::MUTED),
        ),
    ]);
    let lifetime = crate::stats::Lifetime::from(&app.savings);
    let mut savings = vec![
        Line::styled(lifetime.since(), Style::new().fg(theme::HIT).bold()),
        Line::default(),
    ];
    savings.extend(lifetime.rows().into_iter().map(|(label, value)| {
        Line::from(vec![
            Span::styled(format!("{label:<23} "), Style::new().fg(theme::MUTED)),
            Span::styled(value, Style::new().fg(theme::TEXT)),
        ])
    }));
    let mut sharing = app.sharing.as_ref().map_or_else(
        || {
            vec![Line::from(if app.sharing_loading() {
                "Calculating workspace sharing…"
            } else {
                "Workspace sharing unavailable"
            })]
        },
        |sharing| {
            sharing
                .rows()
                .into_iter()
                .map(|(label, value)| Line::from(format!("{label:<23} {value}")))
                .collect()
        },
    );
    sharing.extend([
        Line::default(),
        Line::styled(
            "Logical cache bytes; excludes target directories.",
            Style::new().fg(theme::MUTED),
        ),
    ]);
    let mut notes = Vec::new();
    if app.cheeky
        && let Some(quip) = lifetime.quip()
    {
        notes.push(Line::styled(quip, Style::new().fg(theme::HIT).bold()));
    }
    notes.extend([
        Line::styled(
            "Pruned totals are logical file sizes, not physical space reclaimed. Requested removals are separate.",
            Style::new().fg(theme::MUTED),
        ),
        Line::styled(
            "Compiler time and copying avoided are cumulative, not wall time or current disk savings.",
            Style::new().fg(theme::MUTED),
        ),
    ]);
    let panels = [
        (left[0], "Store / inventory", theme::ACCENT, inventory),
        (
            left[1],
            "Workspace sharing / estimated",
            theme::PURPLE,
            sharing,
        ),
        (columns[2], "Lifetime / the receipts", theme::HIT, savings),
        (
            rows[1],
            "tuist_cargo_cache stats / take these numbers with you",
            theme::BORDER,
            notes,
        ),
    ]
    .map(|(area, title, color, lines)| {
        (
            area,
            title,
            color,
            super::ui::wrap_lines(lines, area.width.saturating_sub(2)),
        )
    });
    if panels.iter().any(|(area, _, _, lines)| {
        lines.len() > area.height.saturating_sub(2) as usize
            || lines
                .iter()
                .any(|line| line.width() > area.width.saturating_sub(2) as usize)
    }) {
        return false;
    }
    for (area, title, color, content) in panels {
        let inner = card(frame, area, title, color);
        frame.render_widget(Paragraph::new(content), inner);
    }
    true
}
