// Adapted from cargo-pretty's src/main.rs live and completed row rendering.
// Copyright (c) 2026 romancitodev (MIT); see LICENSE.cargo-pretty.
// Upstream revision: 73777522ccf8e4a485d026b3b60a275af2f8b381.
use super::model::{Model, segments};
use super::norimel::{self as rimel, Block, palette};
use super::upstream::{fade, warning_panel};
use crate::util::format_duration;
use std::time::Duration;

const BAR_WIDTH: usize = 28;
const NAME_WIDTH: usize = 32;
const ROWS: usize = 6;
/// Width of the per-crate time column, so the outcome beside it stays in line.
/// Wide enough for the longest reading a compilation produces in practice:
/// "45.32s", "13m 32s", "1h 4m". A crate slower than that spends a column
/// rather than losing a digit.
const TIME_WIDTH: usize = 7;

#[derive(Default)]
pub(super) struct Browser {
    pub selected: usize,
    pub inspecting: bool,
    pub scroll: usize,
}

/// Put the mascot beside the content only when both remain readable. A
/// successful finish leaves just the summary in scrollback; a failure keeps the
/// knocked-over box beside it.
pub(super) fn render(
    model: &mut Model,
    browser: Option<&mut Browser>,
    width: u16,
    height: u16,
) -> Block {
    use super::norimel::Color;
    use crate::cli::mascot::{self, HEIGHT, Inputs, Rgb, WIDTH};
    if browser.is_some()
        || width < 96
        || height < HEIGHT as u16
        || matches!(model.finished, Some((true, _)))
    {
        return render_content(model, browser, width, height);
    }
    // The first compiler error settles the outcome, though Cargo still finishes
    // the jobs in flight before it reports the build.
    let ok = model.finished.map(|(ok, _)| ok).or_else(|| {
        if model.build_ok == Some(false) || !model.errors.is_empty() || model.tests_failed > 0 {
            Some(false)
        } else {
            None
        }
    });
    // The lid follows Cargo's units while testing too. The Model stops
    // counting them when the build finishes, so the lid holds through the tests.
    let pose = mascot::pose_at(Inputs {
        ms: model.started.elapsed().as_millis(),
        since_hit_ms: model.last_hit.map(|at| at.elapsed().as_millis()),
        done: model.units_done,
        total: model.units_total,
        lid_shown: model.lid_shown,
        hits: model.mix.hits,
        misses: model.mix.misses,
        testing: model.testing,
        ok,
    });
    if ok.is_none() {
        model.lid_shown = pose.lid;
    }
    let paint = |color: Option<Rgb>| color.map_or(Color::Reset, |(r, g, b)| Color::Rgb(r, g, b));
    let art = rimel::col(mascot::draw(pose).into_iter().map(|row| {
        rimel::row(
            row.chunk_by(|a, b| (a.fg, a.bg) == (b.fg, b.bg))
                .map(|run| {
                    rimel::text(run.iter().map(|cell| cell.glyph).collect::<String>())
                        .fg(paint(run[0].fg))
                        .bg(paint(run[0].bg))
                }),
        )
    }));
    let content_width = width - WIDTH as u16 - 2;
    let content = render_content(model, None, content_width, height).w(content_width);
    rimel::row([content, rimel::text("  "), art])
}

fn render_content(
    model: &mut Model,
    browser: Option<&mut Browser>,
    width: u16,
    height: u16,
) -> Block {
    if let Some(browser) = browser {
        let block = if !model.warnings.is_empty() && browser.selected < model.warnings.len() {
            warning_panel(&model.warnings, browser.selected, browser.inspecting)
        } else {
            let index = browser.selected.saturating_sub(model.warnings.len());
            if let Some((name, details)) = model.failures.get(index) {
                rimel::col([
                    rimel::text(format!("✗ {name}")).fg(palette::RED).bold(),
                    rimel::text(if browser.inspecting {
                        details.clone()
                    } else {
                        "Enter inspect failure   ↑↓ navigate   Esc dismiss".into()
                    }),
                ])
            } else {
                summary(model)
            }
        };
        browser.scroll = browser
            .scroll
            .min(usize::from(block.size().1.saturating_sub(height)));
        return crop(block, browser.scroll, width, height);
    }
    if model.finished.is_some() {
        let summary = summary(model);
        let height = height.min(summary.size().1);
        return crop(summary, 0, width, height);
    }
    let mut lines = vec![
        rimel::text(&model.command).dim(),
        rimel::separator(48).dim(),
        rimel::text(if model.testing {
            "Running tests (per-test start times unavailable)"
        } else {
            "Compiling"
        })
        .dim(),
    ];
    let rows = ROWS.min(usize::from(height.saturating_sub(12)) / 2).max(1);
    model.resize_slots(rows);
    for slot in &model.slots {
        if let Some(name) = slot
            && let Some(start) = model.live.get(name)
        {
            lines.push(rimel::row([
                rimel::text("● ").fg(palette::YELLOW),
                rimel::text(format!("{:<NAME_WIDTH$}", short_name(name))).fg(palette::TEXT),
                rimel::text(clock(format_duration(start.elapsed()))).fg(palette::SUBTEXT0),
            ]));
        } else {
            lines.push(rimel::text(""));
        }
    }
    lines.push(rimel::separator(48).dim());
    lines.push(
        rimel::text(if model.testing {
            format!("Tests ({}/{})", model.suite_done, model.suite_total)
        } else {
            format!(
                "Compiled ({} artifacts, {} fresh)",
                model.artifacts, model.fresh
            )
        })
        .dim(),
    );
    let recent: Vec<_> = model.done.iter().rev().take(rows).collect();
    for _ in recent.len()..rows {
        lines.push(rimel::text(""));
    }
    let count = recent.len();
    for (i, row) in recent.into_iter().rev().enumerate() {
        let time = clock(if row.fresh {
            "—".into()
        } else {
            row.duration.map_or("—".into(), format_duration)
        });
        lines.push(fade(
            rimel::row([
                rimel::text(if row.failed { "✗ " } else { "✓ " }).fg(if row.failed {
                    palette::RED
                } else {
                    palette::GREEN
                }),
                rimel::text(format!("{:<NAME_WIDTH$}", short_name(&row.name))).fg(palette::TEXT),
                rimel::text(time).fg(palette::SUBTEXT0),
                rimel::text(format!("  {}", outcome(model, row))).fg(palette::SUBTEXT0),
            ]),
            0.4 + 0.6 * (i + 1) as f32 / count.max(1) as f32,
        ));
    }
    lines.push(rimel::text(""));
    if model.testing {
        let filled = BAR_WIDTH * model.suite_done / model.suite_total.max(1);
        lines.push(rimel::row([
            rimel::text("Tests         ").dim(),
            rimel::text("█".repeat(filled.min(BAR_WIDTH))).fg(palette::SAPPHIRE),
            rimel::text("░".repeat(BAR_WIDTH.saturating_sub(filled))).fg(palette::SURFACE1),
            rimel::text(format!("  {}/{}", model.suite_done, model.suite_total)),
        ]));
    }
    lines.extend(cache(model));
    lines.push(rimel::row([
        rimel::text("Elapsed       ").dim(),
        rimel::text(format_duration(model.started.elapsed())),
    ]));
    if !model.warnings.is_empty() || !model.failures.is_empty() {
        lines.push(
            rimel::text(format!(
                "{} warnings · {} failed tests · TUIST_CARGO_CACHE_PRETTY_INSPECT=1 to browse",
                model.warnings.len(),
                model.tests_failed
            ))
            .fg(palette::YELLOW),
        );
    }
    crop(rimel::col(lines), 0, width, height)
}

fn cache(model: &Model) -> Vec<Block> {
    let filled = if model.build_ok == Some(true) {
        BAR_WIDTH
    } else {
        model.units_total.map_or(BAR_WIDTH, |total| {
            BAR_WIDTH * model.units_done.min(total) / total.max(1)
        })
    };
    let [hits, misses, bypasses] = segments(&model.mix, filled);
    let label = match (model.build_ok, model.units_total) {
        (Some(true), Some(_)) => "build complete".into(),
        (Some(true), None) => "complete · total unknown".into(),
        (_, Some(total)) => format!("{}/{} units", model.units_done, total),
        (_, None) => "total unknown".into(),
    };
    vec![
        rimel::row([
            rimel::text("Build / cache ").dim(),
            rimel::text("█".repeat(hits)).fg(palette::GREEN),
            rimel::text("█".repeat(misses)).fg(palette::YELLOW),
            rimel::text("█".repeat(bypasses)).fg(palette::SUBTEXT0),
            rimel::text("░".repeat(BAR_WIDTH - filled)).fg(palette::SURFACE1),
            rimel::text(format!("  {label}")),
        ]),
        rimel::row([
            rimel::text(format!("{} hits  ", model.mix.hits)).fg(palette::GREEN),
            rimel::text(format!("{} misses  ", model.mix.misses)).fg(palette::YELLOW),
            rimel::text(format!(
                "{} bypassed · {} not looked up",
                model.mix.bypasses, model.mix.unconsulted
            ))
            .fg(palette::SUBTEXT0),
        ]),
        rimel::text(format!(
            "Estimated compiler time saved: {}",
            format_duration(Duration::from_nanos(model.mix.saved_ns))
        ))
        .dim(),
    ]
}

pub(super) fn summary(model: &Model) -> Block {
    let (ok, elapsed) = model.finished.unwrap_or((true, model.started.elapsed()));
    let verb = if !ok {
        "Failed"
    } else if model.testing {
        "Tested"
    } else if matches!(model.verb.as_str(), "check" | "c" | "clippy") {
        "Checked"
    } else {
        "Built"
    };
    let mut lines = vec![
        rimel::text(format!(
            "{} {verb} in {} · saved ~{} compiler work",
            if ok { "✓" } else { "✗" },
            format_duration(elapsed),
            format_duration(Duration::from_nanos(model.mix.saved_ns))
        ))
        .fg(if ok { palette::GREEN } else { palette::RED })
        .bold(),
        rimel::text(format!(
            "{} hits · {} misses · {} bypassed · {} fresh · {} not looked up",
            model.mix.hits,
            model.mix.misses,
            model.mix.bypasses,
            model.fresh,
            model.mix.unconsulted
        ))
        .dim(),
        rimel::text("Savings estimate sums compiler work, not wall-clock time.").dim(),
    ];
    if model.testing {
        lines.push(rimel::text(format!(
            "  {} passed · {} failed · {} ignored",
            model.tests_passed, model.tests_failed, model.tests_ignored
        )));
    }
    if !model.warnings.is_empty() {
        lines.push(
            rimel::text(format!(
                "{} warnings · TUIST_CARGO_CACHE_PRETTY_INSPECT=1 to browse",
                model.warnings.len()
            ))
            .fg(palette::YELLOW),
        );
    }
    rimel::col(lines)
}

fn crop(block: Block, scroll: usize, width: u16, height: u16) -> Block {
    // Preserve styles while clipping both axes; browsing can reach every line
    // of a diagnostic even when the terminal is smaller than the upstream view.
    let mut lines: Vec<Vec<Block>> = vec![Vec::new(); usize::from(height)];
    for (x, y, text, style) in block.runs() {
        let y = usize::from(y);
        if y < scroll || y >= scroll + lines.len() || x >= width {
            continue;
        }
        let text_width = rimel::width_of(&text);
        let mut segment = rimel::text(text).style(style);
        if text_width > width - x {
            segment = segment.w(width - x);
        }
        lines[y - scroll].push(segment);
    }
    rimel::col(lines.into_iter().map(|line| {
        if line.is_empty() {
            rimel::text("")
        } else {
            rimel::row(line)
        }
    }))
}

fn short_name(name: &str) -> &str {
    name.rsplit_once(" v").map_or(name, |(name, _)| name)
}

/// Right-align a time in the crate rows so the column beside it starts at one
/// place. The times vary in width now that a long compile reads "1m 23s"
/// instead of a run of digits, and a fresh crate has no time at all.
fn clock(time: String) -> String {
    let width = TIME_WIDTH.saturating_sub(time.chars().count());
    format!("{:width$}{time}", "")
}

fn outcome<'a>(model: &'a Model, row: &super::model::Row) -> &'a str {
    if row.fresh {
        return "fresh";
    }
    let Some(target) = &row.cache_target else {
        return if model.testing { "" } else { "unknown" };
    };
    let Some(outcomes) = model.outcomes.get(target) else {
        return "unknown";
    };
    if outcomes.len() == 1 {
        outcomes.first().map(String::as_str).unwrap_or("unknown")
    } else {
        "mixed"
    }
}
