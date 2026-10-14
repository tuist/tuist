//! Colors and text attributes, as rímel's own vocabulary.
//!
//! Not a newtype over anybody else's: this is the seed of the theme layer, and it converts
//! at the border — into crossterm's for the ANSI a [`Block`](super::Block) prints, and into
//! ratatui's for the cells one paints. It carries only what something actually paints today.

/// A terminal color.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Color {
    /// Whatever the terminal's own default is.
    #[default]
    Reset,
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    Gray,
    DarkGray,
    LightRed,
    LightGreen,
    LightYellow,
    LightBlue,
    LightMagenta,
    LightCyan,
    White,
    /// True color. Falls back to the nearest palette entry on terminals without it.
    Rgb(u8, u8, u8),
}

/// Catppuccin Mocha. The default palette everything in nobubbles is painted with.
///
/// True colour, so a terminal without it falls back to the nearest of the sixteen.
pub mod palette {
    use super::Color;

    pub const ROSEWATER: Color = Color::Rgb(0xf5, 0xe0, 0xdc);
    pub const FLAMINGO: Color = Color::Rgb(0xf2, 0xcd, 0xcd);
    pub const PINK: Color = Color::Rgb(0xf5, 0xc2, 0xe7);
    pub const MAUVE: Color = Color::Rgb(0xcb, 0xa6, 0xf7);
    pub const RED: Color = Color::Rgb(0xf3, 0x8b, 0xa8);
    pub const MAROON: Color = Color::Rgb(0xeb, 0xa0, 0xac);
    pub const PEACH: Color = Color::Rgb(0xfa, 0xb3, 0x87);
    pub const YELLOW: Color = Color::Rgb(0xf9, 0xe2, 0xaf);
    pub const GREEN: Color = Color::Rgb(0xa6, 0xe3, 0xa1);
    pub const TEAL: Color = Color::Rgb(0x94, 0xe2, 0xd5);
    pub const SKY: Color = Color::Rgb(0x89, 0xdc, 0xeb);
    pub const SAPPHIRE: Color = Color::Rgb(0x74, 0xc7, 0xec);
    pub const BLUE: Color = Color::Rgb(0x89, 0xb4, 0xfa);
    pub const LAVENDER: Color = Color::Rgb(0xb4, 0xbe, 0xfe);

    pub const TEXT: Color = Color::Rgb(0xcd, 0xd6, 0xf4);
    pub const SUBTEXT1: Color = Color::Rgb(0xba, 0xc2, 0xde);
    pub const SUBTEXT0: Color = Color::Rgb(0xa6, 0xad, 0xc8);
    pub const OVERLAY2: Color = Color::Rgb(0x93, 0x99, 0xb2);
    pub const OVERLAY1: Color = Color::Rgb(0x7f, 0x84, 0x9c);
    pub const OVERLAY0: Color = Color::Rgb(0x6c, 0x70, 0x86);
    pub const SURFACE2: Color = Color::Rgb(0x58, 0x5b, 0x70);
    pub const SURFACE1: Color = Color::Rgb(0x45, 0x47, 0x5a);
    pub const SURFACE0: Color = Color::Rgb(0x31, 0x32, 0x44);
    pub const BASE: Color = Color::Rgb(0x1e, 0x1e, 0x2e);
}

/// Blends `fg` toward `bg` by `alpha` (`0.0` = fully `bg`, `1.0` = fully `fg`) — real RGB
/// compositing, not the `dim` attribute's terminal-dependent guess. Only two true colours have
/// channels to mix; a named 16-colour or `Reset` passes through unchanged.
#[must_use]
pub fn blend(fg: Color, bg: Color, alpha: f32) -> Color {
    let (Color::Rgb(fr, fg_g, fb), Color::Rgb(br, bg_g, bb)) = (fg, bg) else {
        return fg;
    };
    let a = alpha.clamp(0.0, 1.0);
    let mix = |f: u8, b: u8| (f32::from(b) + (f32::from(f) - f32::from(b)) * a).round() as u8;
    Color::Rgb(mix(fr, br), mix(fg_g, bg_g), mix(fb, bb))
}

/// How a piece of text is painted.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct Style {
    pub fg: Color,
    pub bg: Color,
    pub bold: bool,
    pub dim: bool,
    pub italic: bool,
}

impl Style {
    /// A style that changes nothing.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn fg(mut self, color: Color) -> Self {
        self.fg = color;
        self
    }

    #[must_use]
    pub fn bg(mut self, color: Color) -> Self {
        self.bg = color;
        self
    }

    #[must_use]
    pub fn bold(mut self) -> Self {
        self.bold = true;
        self
    }

    #[must_use]
    pub fn dim(mut self) -> Self {
        self.dim = true;
        self
    }

    #[must_use]
    pub fn italic(mut self) -> Self {
        self.italic = true;
        self
    }

    /// This style, with anything it leaves unsaid taken from `under`.
    ///
    /// `Reset` is what "unsaid" means for a colour, so a run that never picked a background
    /// inherits the block's the way a child element inherits from its parent. Attributes only
    /// ever add: nothing here can un-bold something.
    #[must_use]
    pub fn over(self, under: Self) -> Self {
        Self {
            fg: if self.fg == Color::Reset {
                under.fg
            } else {
                self.fg
            },
            bg: if self.bg == Color::Reset {
                under.bg
            } else {
                self.bg
            },
            bold: self.bold || under.bold,
            dim: self.dim || under.dim,
            italic: self.italic || under.italic,
        }
    }
}

impl From<Color> for ratatui::crossterm::style::Color {
    fn from(color: Color) -> Self {
        match color {
            Color::Reset => Self::Reset,
            Color::Black => Self::Black,
            Color::Red => Self::DarkRed,
            Color::Green => Self::DarkGreen,
            Color::Yellow => Self::DarkYellow,
            Color::Blue => Self::DarkBlue,
            Color::Magenta => Self::DarkMagenta,
            Color::Cyan => Self::DarkCyan,
            Color::Gray => Self::Grey,
            Color::DarkGray => Self::DarkGrey,
            Color::LightRed => Self::Red,
            Color::LightGreen => Self::Green,
            Color::LightYellow => Self::Yellow,
            Color::LightBlue => Self::Blue,
            Color::LightMagenta => Self::Magenta,
            Color::LightCyan => Self::Cyan,
            Color::White => Self::White,
            Color::Rgb(r, g, b) => Self::Rgb { r, g, b },
        }
    }
}

impl From<Style> for ratatui::crossterm::style::ContentStyle {
    fn from(style: Style) -> Self {
        use ratatui::crossterm::style::Attribute;

        // `Reset` goes out as nothing at all rather than as an explicit reset: a run that does
        // not care about the background should inherit whatever is already under it, and saying
        // "default" out loud would punch a hole through the block behind it.
        let color = |color| match color {
            Color::Reset => None,
            other => Some(ratatui::crossterm::style::Color::from(other)),
        };

        let mut attributes = ratatui::crossterm::style::Attributes::default();
        if style.bold {
            attributes.set(Attribute::Bold);
        }
        if style.dim {
            attributes.set(Attribute::Dim);
        }
        if style.italic {
            attributes.set(Attribute::Italic);
        }

        Self {
            foreground_color: color(style.fg),
            background_color: color(style.bg),
            underline_color: None,
            attributes,
        }
    }
}

impl From<Color> for ratatui::style::Color {
    fn from(color: Color) -> Self {
        match color {
            Color::Reset => Self::Reset,
            Color::Black => Self::Black,
            Color::Red => Self::Red,
            Color::Green => Self::Green,
            Color::Yellow => Self::Yellow,
            Color::Blue => Self::Blue,
            Color::Magenta => Self::Magenta,
            Color::Cyan => Self::Cyan,
            Color::Gray => Self::Gray,
            Color::DarkGray => Self::DarkGray,
            Color::LightRed => Self::LightRed,
            Color::LightGreen => Self::LightGreen,
            Color::LightYellow => Self::LightYellow,
            Color::LightBlue => Self::LightBlue,
            Color::LightMagenta => Self::LightMagenta,
            Color::LightCyan => Self::LightCyan,
            Color::White => Self::White,
            Color::Rgb(r, g, b) => Self::Rgb(r, g, b),
        }
    }
}

impl From<Style> for ratatui::style::Style {
    fn from(style: Style) -> Self {
        use ratatui::style::Modifier;

        let mut modifier = Modifier::empty();
        modifier.set(Modifier::BOLD, style.bold);
        modifier.set(Modifier::DIM, style.dim);
        modifier.set(Modifier::ITALIC, style.italic);

        Self::default()
            .fg(style.fg.into())
            .bg(style.bg.into())
            .add_modifier(modifier)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blend_interpolates_between_two_true_colours() {
        let white = Color::Rgb(255, 255, 255);
        let black = Color::Rgb(0, 0, 0);

        assert_eq!(blend(white, black, 1.0), white);
        assert_eq!(blend(white, black, 0.0), black);
        assert_eq!(blend(white, black, 0.5), Color::Rgb(128, 128, 128));
    }

    #[test]
    fn blend_passes_through_colours_with_no_channels_to_mix() {
        assert_eq!(blend(Color::Red, Color::Rgb(0, 0, 0), 0.5), Color::Red);
        assert_eq!(blend(Color::Reset, Color::Rgb(0, 0, 0), 0.5), Color::Reset);
    }

    #[test]
    fn builders_stack_onto_one_style() {
        let style = Style::new().fg(Color::Rgb(1, 2, 3)).bold().dim().italic();

        let converted: ratatui::crossterm::style::ContentStyle = style.into();
        assert_eq!(
            converted.foreground_color,
            Some(ratatui::crossterm::style::Color::Rgb { r: 1, g: 2, b: 3 })
        );
        assert!(
            converted
                .attributes
                .has(ratatui::crossterm::style::Attribute::Bold)
        );
        assert!(
            converted
                .attributes
                .has(ratatui::crossterm::style::Attribute::Dim)
        );
        assert!(
            converted
                .attributes
                .has(ratatui::crossterm::style::Attribute::Italic)
        );
    }

    /// A default background is left unsaid, so a run drops onto whatever is behind it.
    #[test]
    fn a_reset_colour_is_not_written_at_all() {
        let converted: ratatui::crossterm::style::ContentStyle = Style::new().into();

        assert_eq!(converted.foreground_color, None);
        assert_eq!(converted.background_color, None);
    }

    #[test]
    fn the_ratatui_conversion_carries_colour_and_modifiers() {
        let style = Style::new().fg(Color::Rgb(1, 2, 3)).bold().dim().italic();

        let converted: ratatui::style::Style = style.into();
        assert_eq!(converted.fg, Some(ratatui::style::Color::Rgb(1, 2, 3)));
        assert!(converted.add_modifier.contains(
            ratatui::style::Modifier::BOLD
                | ratatui::style::Modifier::DIM
                | ratatui::style::Modifier::ITALIC
        ));
    }
}
