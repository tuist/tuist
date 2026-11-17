//! Themes: Noora's semantic colors, the design tokens the server's components
//! use, and Omarchy's palettes mapped to those same tokens. Every client draws
//! with token names only, so a change to `noora/css/tokens.css` reaches them
//! all through `noora_tokens.py`, and any theme restyles every edge.
use core::ffi::{CStr, c_char};
use std::ffi::CString;
use std::sync::OnceLock;

mod noora;
mod omarchy;
mod omarchy_themes;
#[cfg(test)]
mod tests;
pub use noora::TOKENS;

/// Every token's color for one appearance, packed 0xRRGGBB sRGB.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Palette {
    pub dark: bool,
    colors: [u32; TOKENS.len()],
}

impl Palette {
    pub fn noora(dark: bool) -> Self {
        Self {
            dark,
            colors: std::array::from_fn(|index| {
                let (_, light, night) = TOKENS[index];
                if dark { night } else { light }
            }),
        }
    }

    /// An Omarchy `colors.toml`, resolved like `omarchy-theme-color`. None when
    /// incomplete or malformed, so callers never mix a broken palette with
    /// defaults. `light_mode` is the legacy `light.mode` marker beside the file.
    pub fn from_omarchy(source: &str, light_mode: bool) -> Option<Self> {
        omarchy::parse(source, light_mode)
    }

    /// A Noora token's color, by its CSS name without `--noora-`.
    pub fn color(&self, token: &str) -> Option<u32> {
        TOKENS
            .iter()
            .position(|(name, _, _)| *name == token)
            .map(|index| self.colors[index])
    }
}

/// A theme people pick in Profile. Noora follows the system appearance; an
/// Omarchy theme has one appearance, so `light` and `dark` are the same.
#[derive(Debug)]
pub struct Theme {
    pub id: &'static str,
    pub name: &'static str,
    pub light: Palette,
    pub dark: Palette,
}

impl Theme {
    /// The palette for the system appearance.
    pub fn palette(&self, dark: bool) -> Palette {
        if dark { self.dark } else { self.light }
    }

    /// The appearance an Omarchy theme imposes, or None when it follows the system.
    pub fn appearance(&self) -> Option<bool> {
        (self.light == self.dark).then_some(self.dark.dark)
    }
}

/// The default theme's ID.
pub const DEFAULT: &str = "noora";

/// Noora first, then Omarchy's built-in themes in `omarchy theme list` order.
pub fn themes() -> &'static [Theme] {
    static THEMES: OnceLock<Vec<Theme>> = OnceLock::new();
    THEMES.get_or_init(|| {
        let noora = Theme {
            id: DEFAULT,
            name: "Tuist",
            light: Palette::noora(false),
            dark: Palette::noora(true),
        };
        let omarchy = omarchy_themes::THEMES.iter().map(|(id, name, source)| {
            let palette = Palette::from_omarchy(source, false).expect("built-in Omarchy theme");
            Theme {
                id,
                name,
                light: palette,
                dark: palette,
            }
        });
        std::iter::once(noora).chain(omarchy).collect()
    })
}

/// The theme with this ID, falling back to Noora for an unknown or retired one.
pub fn theme(id: &str) -> &'static Theme {
    themes()
        .iter()
        .find(|theme| theme.id == id)
        .unwrap_or(&themes()[0])
}

/// `{"default":"noora","themes":[{"id","name","appearance":null|"light"|"dark",
/// "light":{"<token>":"#rrggbb",…},"dark":{…}},…]}`, for the native edges.
pub fn json() -> &'static CStr {
    static JSON: OnceLock<CString> = OnceLock::new();
    JSON.get_or_init(|| {
        let tokens = |palette: Palette| {
            TOKENS
                .iter()
                .zip(palette.colors)
                .map(|((name, _, _), value)| (name.to_string(), format!("#{value:06x}").into()))
                .collect::<serde_json::Map<_, _>>()
        };
        let themes: Vec<_> = themes()
            .iter()
            .map(|theme| {
                serde_json::json!({
                    "id": theme.id,
                    "name": theme.name,
                    "appearance": theme.appearance().map(|dark| if dark { "dark" } else { "light" }),
                    "light": tokens(theme.light),
                    "dark": tokens(theme.dark),
                })
            })
            .collect();
        let value = serde_json::json!({"default": DEFAULT, "themes": themes});
        CString::new(value.to_string()).expect("themes contain no NUL")
    })
}

/// The immutable process-lifetime theme catalog JSON; never free it.
#[unsafe(no_mangle)]
pub extern "C" fn tuist_app_theme() -> *const c_char {
    json().as_ptr()
}
