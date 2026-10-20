//! One palette for the dashboard, with semantic colors shared by every chart.

use ratatui::style::Color;

pub(super) const BACKGROUND: Color = Color::Rgb(13, 19, 29);
pub(super) const PANEL: Color = Color::Rgb(18, 27, 40);
pub(super) const SELECTION: Color = Color::Rgb(34, 54, 72);
pub(super) const BORDER: Color = Color::Rgb(57, 79, 102);
pub(super) const TEXT: Color = Color::Rgb(219, 230, 242);
pub(super) const MUTED: Color = Color::Rgb(139, 160, 183);
pub(super) const ACCENT: Color = Color::Rgb(95, 218, 207);
pub(super) const HIT: Color = Color::Rgb(157, 216, 135);
pub(super) const MISS: Color = Color::Rgb(244, 123, 143);
pub(super) const WARNING: Color = Color::Rgb(241, 198, 116);
pub(super) const PURPLE: Color = Color::Rgb(187, 162, 247);
