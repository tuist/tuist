//! Explanations derived from the selected build's recorded actions.

use super::app::{App, Row, Session};
use super::theme;
use super::ui::{outcome_style, panel, saved_duration, state_style};
use crate::events::ActionOutcome;
use crate::util::format_duration;
use bytesize::ByteSize;
use ratatui::prelude::*;
use ratatui::widgets::{Paragraph, Sparkline};
use std::time::Duration;

pub(super) fn draw(frame: &mut Frame, area: Rect, app: &App) {
    if area.width >= 110
        && area.height >= 24
        && app.insight_scroll == 0
        && let Some(session) = app.selected_session()
    {
        dashboard(frame, area, app, session);
        return;
    }
    let block = panel(format!(
        " Insights · {}/{} ",
        if app.is_empty() { 0 } else { app.selected + 1 },
        app.sessions().count()
    ));
    let inner = block.inner(area);
    let Some(session) = app.selected_session() else {
        frame.render_widget(
            Paragraph::new("Run `tuist_cargo_cache build` to collect build insights.").block(block),
            area,
        );
        return;
    };
    let columns = columns(session, inner.width);
    let height = columns.iter().map(Vec::len).max().unwrap_or(0);
    let offset = app
        .insight_scroll
        .min(height.saturating_sub(inner.height as usize));
    let block = block.title_bottom(
        Line::from(format!(
            " {}–{} of {} · PgUp/Dn scroll ",
            offset + 1,
            (offset + inner.height as usize).min(height),
            height,
        ))
        .right_aligned(),
    );
    frame.render_widget(block, area);
    let areas = Layout::horizontal([
        Constraint::Length(column_width(inner.width)),
        Constraint::Length(3),
        Constraint::Min(0),
    ])
    .split(inner);
    for (index, lines) in columns.into_iter().enumerate() {
        let area = if inner.width >= 108 {
            areas[index * 2]
        } else {
            inner
        };
        frame.render_widget(Paragraph::new(lines).scroll((offset as u16, 0)), area);
    }
}

pub(super) fn scroll(app: &mut App, area: Rect, down: bool) {
    let height = area.height.saturating_sub(2) as usize;
    let mut max = app.selected_session().map_or(0, |session| {
        columns(session, area.width.saturating_sub(2))
            .iter()
            .map(Vec::len)
            .max()
            .unwrap_or(0)
            .saturating_sub(height)
    });
    if area.width >= 110 && area.height >= 24 {
        max = max.max(1);
    }
    app.insight_scroll = if down {
        app.insight_scroll
            .min(max)
            .saturating_add(height.max(1))
            .min(max)
    } else {
        app.insight_scroll.min(max).saturating_sub(height.max(1))
    };
}

fn chart_panel(frame: &mut Frame, area: Rect, title: &str, color: Color) -> Rect {
    let block = panel(format!(" {title} ")).border_style(Style::new().fg(color));
    let inner = block.inner(area);
    frame.render_widget(block, area);
    inner
}

fn dashboard(frame: &mut Frame, area: Rect, app: &App, session: &Session) {
    let rows = Layout::vertical([Constraint::Length(4), Constraint::Min(0)]).split(area);
    let header = chart_panel(
        frame,
        rows[0],
        &format!("Insights · {}/{}", app.selected + 1, app.sessions().count()),
        theme::ACCENT,
    );
    frame.render_widget(
        Paragraph::new(vec![
            Line::styled(
                fit(&session.title(), header.width as usize),
                Style::new().bold(),
            ),
            Line::from(vec![
                Span::styled(
                    format!(
                        "{} · {}",
                        session.workspace_name().unwrap_or("unknown workspace"),
                        session.state.label()
                    ),
                    state_style(session.state),
                ),
                Span::styled(
                    format!(
                        "   {} saved   {} restored",
                        saved_duration(session.avoided_compiler_ns),
                        ByteSize::b(session.restored_bytes).display().iec()
                    ),
                    Style::new().fg(theme::HIT),
                ),
                Span::styled(
                    if session.truncated {
                        "   history capped"
                    } else {
                        "   PgDn full detail"
                    },
                    Style::new().fg(theme::MUTED),
                ),
            ]),
        ]),
        header,
    );
    let columns = Layout::horizontal([
        Constraint::Ratio(1, 2),
        Constraint::Length(1),
        Constraint::Ratio(1, 2),
    ])
    .split(rows[1]);
    let left = Layout::vertical([Constraint::Length(10), Constraint::Min(0)]).split(columns[0]);
    let bypasses = session.bypasses();
    let values = [
        ("hit", session.count("hit"), theme::HIT),
        ("miss", session.count("miss"), theme::MISS),
        ("unconsulted", session.count("unconsulted"), theme::MUTED),
        (
            "bypass",
            bypasses.iter().map(|(_, count)| count).sum(),
            theme::WARNING,
        ),
        ("verification", session.count("verification"), theme::PURPLE),
    ];
    let total = values.iter().map(|(_, count, _)| count).sum();
    let cache = chart_panel(
        frame,
        left[0],
        "Cache outcomes / recorded actions",
        theme::HIT,
    );
    let mut outcomes = bars(&values, total, cache.width);
    outcomes.push(Line::default());
    outcomes.push(Line::styled(
        session.hit_rate().map_or_else(
            || "No attempted lookups".into(),
            |rate| format!("{rate:.0}% lookup hit rate · hits / (hits + misses)"),
        ),
        Style::new().fg(theme::HIT),
    ));
    frame.render_widget(Paragraph::new(outcomes), cache);
    recent_chart(frame, left[1], session);
    let right = Layout::vertical([
        Constraint::Length((bypasses.len() as u16 + 2).clamp(4, 7)),
        Constraint::Length(8),
        Constraint::Min(0),
    ])
    .split(columns[2]);
    let reasons = chart_panel(
        frame,
        right[0],
        "Bypass reasons / most frequent",
        theme::WARNING,
    );
    if bypasses.is_empty() {
        frame.render_widget(
            Paragraph::new("No bypasses recorded.").style(Style::new().fg(theme::MUTED)),
            reasons,
        );
    } else {
        let total = bypasses.iter().map(|(_, count)| count).sum();
        let values = bypasses
            .iter()
            .take(reasons.height as usize)
            .map(|(label, count)| (*label, *count, theme::WARNING))
            .collect::<Vec<_>>();
        frame.render_widget(Paragraph::new(bars(&values, total, reasons.width)), reasons);
    }
    let slowest = chart_panel(frame, right[1], "Slowest recorded actions", theme::MISS);
    let mut rows: Vec<_> = session
        .rows
        .iter()
        .filter(|row| row.duration_ns > 0)
        .collect();
    rows.sort_by_key(|row| std::cmp::Reverse(row.duration_ns));
    let mut lines = ranking(&rows, slowest.width, false);
    if lines.is_empty() {
        lines.push(Line::from("No timed actions recorded."));
    }
    lines.push(Line::styled(
        "hit = restore · otherwise compiler time",
        Style::new().fg(theme::MUTED),
    ));
    frame.render_widget(Paragraph::new(lines), slowest);
    let wins = chart_panel(
        frame,
        right[2],
        "Biggest cache wins / estimated",
        theme::PURPLE,
    );
    let mut rows: Vec<_> = session
        .rows
        .iter()
        .filter(|row| matches!(row.outcome, ActionOutcome::Hit) && row.avoided_compiler_ns > 0)
        .collect();
    rows.sort_by_key(|row| std::cmp::Reverse(row.avoided_compiler_ns));
    let mut lines = ranking(&rows, wins.width, true);
    if lines.is_empty() {
        lines.push(Line::from("No cache savings recorded yet."));
    }
    lines.truncate(wins.height.saturating_sub(1) as usize);
    lines.push(Line::styled(
        format!("Rankings cover {} retained actions.", session.rows.len()),
        Style::new().fg(theme::MUTED),
    ));
    frame.render_widget(Paragraph::new(lines), wins);
}

fn recent_chart(frame: &mut Frame, area: Rect, session: &Session) {
    let inner = chart_panel(frame, area, "Recent actions / duration", theme::ACCENT);
    let rows = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(2),
        Constraint::Min(1),
        Constraint::Length(1),
    ])
    .split(inner);
    let actions = &session.rows[session.rows.len().saturating_sub(inner.width as usize)..];
    let outcomes = actions
        .iter()
        .map(|row| {
            let symbol = match row.outcome {
                ActionOutcome::Hit => "H",
                ActionOutcome::Miss => "M",
                ActionOutcome::Unconsulted => "U",
                ActionOutcome::Bypass { .. } => "B",
                ActionOutcome::Verification { matched: true } => "V",
                ActionOutcome::Verification { matched: false } => "!",
            };
            Span::styled(symbol, outcome_style(&row.outcome))
        })
        .collect::<Vec<_>>();
    frame.render_widget(Paragraph::new(Line::from(outcomes)), rows[0]);
    frame.render_widget(
        Paragraph::new("H hit · M miss · U unconsulted · B bypass\nV verified · ! diverged")
            .style(Style::new().fg(theme::MUTED)),
        rows[1],
    );
    let durations = actions
        .iter()
        .map(|row| row.duration_ns)
        .collect::<Vec<_>>();
    let max = durations.iter().copied().max().unwrap_or(0);
    frame.render_widget(
        Sparkline::default()
            .data(&durations)
            .max(max.max(1))
            .style(Style::new().fg(theme::ACCENT)),
        rows[2],
    );
    frame.render_widget(
        Paragraph::new(format!(
            "older → newer   max {}",
            format_duration(Duration::from_nanos(max))
        ))
        .style(Style::new().fg(theme::MUTED)),
        rows[3],
    );
}

fn heading(title: &str) -> Line<'static> {
    Line::styled(title.to_string(), Style::new().fg(theme::ACCENT).bold())
}

fn fit(value: &str, width: usize) -> String {
    if Line::from(value).width() <= width {
        return value.to_string();
    }
    let mut result = String::new();
    for ch in value.chars() {
        if Line::from(format!("{result}{ch}…")).width() > width {
            break;
        }
        result.push(ch);
    }
    result.push('…');
    result
}

/// All bars share a denominator. The count and percentage stay readable even
/// when a rare outcome is too small to occupy a full terminal cell.
fn bars(values: &[(&str, u64, Color)], total: u64, width: u16) -> Vec<Line<'static>> {
    let label_width = values
        .iter()
        .map(|(label, _, _)| Line::from(*label).width())
        .max()
        .unwrap_or(0)
        .min(width as usize / 2);
    let numbers = values
        .iter()
        .map(|(_, value, _)| {
            let rate = if total == 0 {
                0.0
            } else {
                *value as f64 * 100.0 / total as f64
            };
            format!("{value} {rate:.0}%")
        })
        .collect::<Vec<_>>();
    let number_width = numbers.iter().map(String::len).max().unwrap_or(0);
    let bar_width = (width as usize)
        .saturating_sub(label_width + number_width + 4)
        .min(40);
    values
        .iter()
        .zip(numbers)
        .map(|((label, value, color), number)| {
            let filled = if total == 0 {
                0
            } else {
                ((*value as u128 * bar_width as u128) / total as u128) as usize
            };
            let label = fit(label, label_width);
            let padding = label_width.saturating_sub(Line::from(label.as_str()).width());
            Line::from(vec![
                Span::raw(format!("{label}{}  ", " ".repeat(padding))),
                Span::styled("█".repeat(filled), Style::new().fg(*color)),
                Span::styled(
                    "░".repeat(bar_width - filled),
                    Style::new().fg(theme::BORDER),
                ),
                Span::styled(
                    format!("  {number:>number_width$}"),
                    Style::new().fg(*color),
                ),
            ])
        })
        .collect()
}

pub(super) fn ranking(rows: &[&Row], width: u16, savings: bool) -> Vec<Line<'static>> {
    rows.iter()
        .take(5)
        .map(|row| {
            let duration = if savings {
                saved_duration(row.avoided_compiler_ns)
            } else {
                format_duration(Duration::from_nanos(row.duration_ns))
            };
            let outcome = fit(row.outcome.label(), 16);
            let suffix = format!("  {outcome}  {duration}");
            let name_width = (width as usize).saturating_sub(Line::from(suffix.as_str()).width());
            let name = fit(
                row.crate_name.as_deref().unwrap_or("unnamed action"),
                name_width,
            );
            let padding = name_width.saturating_sub(Line::from(name.as_str()).width());
            Line::from(vec![
                Span::raw(format!("{name}{}", " ".repeat(padding))),
                Span::styled(suffix, outcome_style(&row.outcome)),
            ])
        })
        .collect()
}

fn column_width(width: u16) -> u16 {
    if width >= 108 { (width - 3) / 2 } else { width }
}

fn columns(session: &Session, width: u16) -> Vec<Vec<Line<'static>>> {
    let [overview, details] = sections(session, column_width(width));
    if width >= 108 {
        vec![overview, details]
    } else {
        vec![
            overview
                .into_iter()
                .chain([Line::default()])
                .chain(details)
                .collect(),
        ]
    }
}

fn sections(session: &Session, width: u16) -> [Vec<Line<'static>>; 2] {
    let mut lines = vec![
        Line::styled(fit(&session.title(), width as usize), Style::new().bold()),
        Line::from(vec![
            Span::styled(
                fit(
                    session.workspace_name().unwrap_or("unknown workspace"),
                    width.saturating_sub(14) as usize,
                ),
                Style::new().fg(theme::ACCENT),
            ),
            Span::raw(" · "),
            Span::styled(session.state.label(), state_style(session.state)),
        ]),
        Line::from(format!(
            "{} estimated compiler time saved",
            saved_duration(session.avoided_compiler_ns)
        )),
        Line::from(format!(
            "{} restored from cache",
            ByteSize::b(session.restored_bytes).display().iec()
        )),
    ];
    if let Some(finished) = session.finished_ms {
        lines.push(Line::from(format!(
            "{} build elapsed",
            format_duration(Duration::from_millis(
                finished.saturating_sub(session.started_ms)
            ))
        )));
    }
    if session.truncated {
        lines.push(Line::styled(
            "History capped; recorded data is incomplete.",
            Style::new().fg(theme::WARNING),
        ));
    }
    lines.extend([
        Line::default(),
        heading("Cache outcomes · recorded actions"),
    ]);
    let bypasses = session.bypasses();
    let values = [
        ("hit", session.count("hit"), theme::HIT),
        ("miss", session.count("miss"), theme::MISS),
        ("unconsulted", session.count("unconsulted"), theme::MUTED),
        (
            "bypass",
            bypasses.iter().map(|(_, count)| count).sum(),
            theme::WARNING,
        ),
        ("verification", session.count("verification"), theme::ACCENT),
    ];
    let total = values.iter().map(|(_, count, _)| count).sum();
    lines.extend(bars(&values, total, width));
    lines.push(Line::from(session.hit_rate().map_or_else(
        || "Lookup hit rate: - (no attempted lookups)".to_string(),
        |rate| format!("Lookup hit rate: {rate:.0}% (hits / (hits + misses))"),
    )));
    lines.extend([
        Line::default(),
        heading("Recent outcomes · oldest → newest"),
    ]);
    let recent = session
        .rows
        .iter()
        .rev()
        .take(width as usize)
        .collect::<Vec<_>>();
    lines.push(Line::from(
        recent
            .iter()
            .rev()
            .map(|row| {
                let symbol = match row.outcome {
                    ActionOutcome::Hit => "H",
                    ActionOutcome::Miss => "M",
                    ActionOutcome::Unconsulted => "U",
                    ActionOutcome::Bypass { .. } => "B",
                    ActionOutcome::Verification { matched: true } => "V",
                    ActionOutcome::Verification { matched: false } => "!",
                };
                Span::styled(symbol, outcome_style(&row.outcome))
            })
            .collect::<Vec<_>>(),
    ));
    lines.push(Line::from("H hit · M miss · U unconsulted · B bypass"));
    lines.push(Line::from("V verified · ! verification mismatch"));
    let overview = lines;
    let mut lines = vec![heading("Bypass reasons · most frequent first")];
    if bypasses.is_empty() {
        lines.push(Line::from("No bypasses recorded."));
    } else {
        let total = bypasses.iter().map(|(_, count)| count).sum();
        let values = bypasses
            .iter()
            .map(|(label, count)| (*label, *count, theme::WARNING))
            .collect::<Vec<_>>();
        lines.extend(bars(&values, total, width));
    }
    lines.extend([Line::default(), heading("Slowest recorded actions")]);
    lines.push(Line::from("Hit time = restore; other times = compiler."));
    let mut slowest: Vec<_> = session
        .rows
        .iter()
        .filter(|row| row.duration_ns > 0)
        .collect();
    slowest.sort_by_key(|row| std::cmp::Reverse(row.duration_ns));
    if slowest.is_empty() {
        lines.push(Line::from("No timed actions recorded."));
    } else {
        lines.extend(ranking(&slowest, width, false));
    }
    lines.extend([
        Line::default(),
        heading("Biggest cache wins · estimated time saved"),
    ]);
    let mut wins: Vec<_> = session
        .rows
        .iter()
        .filter(|row| matches!(row.outcome, ActionOutcome::Hit) && row.avoided_compiler_ns > 0)
        .collect();
    wins.sort_by_key(|row| std::cmp::Reverse(row.avoided_compiler_ns));
    if wins.is_empty() {
        lines.push(Line::from("No cache savings recorded yet."));
    } else {
        lines.extend(ranking(&wins, width, true));
    }
    lines.push(Line::from(format!(
        "Rankings cover {} retained actions.",
        session.rows.len()
    )));
    lines.push(Line::from("Compiler time saved is not wall-clock time."));
    [overview, lines]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(lines: Vec<Vec<Line<'_>>>) -> String {
        lines
            .into_iter()
            .flatten()
            .map(|line| line.to_string())
            .collect::<Vec<_>>()
            .join("\n")
    }

    #[test]
    fn charts_separate_lookup_rate_from_all_outcomes() {
        let mut session = Session::default();
        session.counts.extend([
            ("hit".into(), 3),
            ("miss".into(), 1),
            ("unconsulted".into(), 4),
            ("incremental".into(), 2),
        ]);
        let screen = text(columns(&session, 78));
        assert!(screen.contains("3 30%"));
        assert!(screen.contains("Lookup hit rate: 75%"));
        assert!(screen.contains("incremental"));
        assert!(screen.contains("2 100%"));
    }

    #[test]
    fn rankings_distinguish_restore_cost_from_compiler_savings() {
        let session = Session {
            rows: vec![
                Row {
                    outcome: ActionOutcome::Miss,
                    crate_name: Some("slow_compile".into()),
                    duration_ns: 10_000_000_000,
                    avoided_compiler_ns: 0,
                },
                Row {
                    outcome: ActionOutcome::Hit,
                    crate_name: Some("valuable_hit".into()),
                    duration_ns: 1_000_000,
                    avoided_compiler_ns: 90_000_000_000,
                },
            ],
            truncated: true,
            ..Session::default()
        };
        let screen = text(columns(&session, 78));
        let slowest = screen.split("Slowest recorded actions").nth(1).unwrap();
        assert!(slowest.find("slow_compile").unwrap() < slowest.find("valuable_hit").unwrap());
        let wins = screen.split("Biggest cache wins").nth(1).unwrap();
        assert!(wins.contains("valuable_hit"));
        assert!(wins.contains("1m 30s"));
        assert!(!wins.contains("slow_compile"));
        assert!(screen.contains("History capped"));
    }

    #[test]
    fn chart_labels_fit_unicode_and_empty_data_has_no_nan() {
        let rendered = bars(&[("编译原因很长的名称", 0, theme::WARNING)], 0, 46);
        assert!(rendered.iter().all(|line| line.width() <= 46));
        assert!(!text(vec![rendered]).contains("NaN"));
        assert!(text(columns(&Session::default(), 46)).contains("no attempted lookups"));
    }
}
