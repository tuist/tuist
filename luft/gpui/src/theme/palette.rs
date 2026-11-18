//! GPUI-independent theme values. Colors are packed, opaque sRGB (0xRRGGBB).
#[cfg(any(target_os = "linux", test))]
use std::path::{Path, PathBuf};
use tuist_app_core::theme;

#[cfg(test)]
#[path = "tests.rs"]
mod tests;

/// The desktop's roles, each one a Noora token, so every theme the core offers
/// (Noora or an Omarchy palette) restyles the window the same way.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Palette {
    pub dark: bool,
    pub background: u32,
    pub sidebar: u32,
    pub border: u32,
    pub text: u32,
    pub text_muted: u32,
    pub row_hover: u32,
    pub row_selected: u32,
    pub accent: u32,
    pub accent_foreground: u32,
    pub error: u32,
}

impl From<theme::Palette> for Palette {
    fn from(palette: theme::Palette) -> Self {
        let token = |name| palette.color(name).expect("Noora token");
        Self {
            dark: palette.dark,
            background: token("surface-background-primary"),
            sidebar: token("surface-background-tertiary"),
            border: token("surface-border-primary"),
            text: token("surface-label-primary"),
            text_muted: token("surface-label-secondary"),
            row_hover: token("button-neutral-background-hover"),
            row_selected: token("button-neutral-background-active"),
            accent: token("button-primary-background"),
            accent_foreground: token("button-primary-label"),
            error: token("surface-label-destructive"),
        }
    }
}

impl Palette {
    /// Noora's semantic tokens, the colors every Luft client shares
    /// with the server.
    pub fn noora(dark: bool) -> Self {
        theme::Palette::noora(dark).into()
    }

    /// Modern Omarchy first, then pre-v4. These are literal upstream paths,
    /// not XDG overrides: Omarchy itself writes them relative to HOME.
    #[cfg(any(target_os = "linux", test))]
    pub fn omarchy_directories(home: &Path) -> [PathBuf; 2] {
        [
            home.join(".local/state/omarchy/current/theme"),
            home.join(".config/omarchy/current/theme"),
        ]
    }

    /// Reload without caching, including directory/symlink replacements. Call on
    /// a background executor and compare values to notify views only on changes.
    /// An existing modern theme is authoritative, even if corrupt; never revive
    /// a stale legacy palette when the current source is temporarily invalid.
    #[cfg(any(target_os = "linux", test))]
    pub fn load_omarchy_sources(directories: &[PathBuf]) -> Option<Self> {
        let directory = directories.iter().find(|path| path.exists())?;
        // Resolve a legacy current/theme symlink once for both palette and marker.
        let directory = directory.canonicalize().ok()?;
        let source = std::fs::read_to_string(directory.join("colors.toml")).ok()?;
        theme::Palette::from_omarchy(&source, directory.join("light.mode").is_file())
            .map(Into::into)
    }

    /// The active Omarchy theme. Only Linux has one; None elsewhere.
    #[cfg(target_os = "linux")]
    pub fn load_system() -> Option<Self> {
        let home = std::env::var_os("HOME").filter(|home| !home.is_empty())?;
        Self::load_omarchy_sources(&Self::omarchy_directories(Path::new(&home)))
    }
}
