// Adapted from cargo-pretty, Copyright (c) 2026 romancitodev (MIT).
// Upstream: 73777522ccf8e4a485d026b3b60a275af2f8b381, src/ui.rs.
// See LICENSE.cargo-pretty for the complete upstream license.
use super::model::Warning;
use super::norimel::{self as rimel, Border, palette};

/// Fades a whole block toward the background by `alpha` (`0.0` invisible, `1.0` full color),
/// for a list where older rows recede and the newest stands out.
pub fn fade(block: rimel::Block, alpha: f32) -> rimel::Block {
    block.map_cells(move |_, _, style| {
        let fg = if style.fg == rimel::Color::Reset {
            palette::TEXT
        } else {
            style.fg
        };
        style.fg(rimel::blend(fg, palette::BASE, alpha))
    })
}

pub fn warning_panel(warnings: &[Warning], selected: usize, inspecting: bool) -> rimel::Block {
    let w = &warnings[selected];

    let body = if inspecting {
        rimel::text(super::model::strip_ansi(&w.rendered))
    } else {
        let mut inner = vec![rimel::text(&w.message)];
        if let Some(loc) = &w.location {
            inner.push(rimel::text(loc).dim());
        }
        if let Some(help) = &w.help {
            inner.push(rimel::text(""));
            inner.push(rimel::text(format!("help: {help}")).dim());
        }
        rimel::col(inner)
    };
    let boxed = body
        .px(1)
        .border_with(Border::rounded())
        .border_color(palette::YELLOW);

    rimel::col([
        rimel::text("⚠  Build completed with warnings")
            .fg(palette::YELLOW)
            .bold(),
        rimel::text(""),
        rimel::text(format!(
            "{} / {} warning{}",
            selected + 1,
            warnings.len(),
            if warnings.len() == 1 { "" } else { "s" }
        ))
        .dim(),
        rimel::text(""),
        boxed,
        rimel::text(""),
        rimel::text("↑↓ navigate   Enter inspect   Esc dismiss").dim(),
    ])
}
