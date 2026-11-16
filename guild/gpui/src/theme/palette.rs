//! GPUI-independent theme values. Colors are packed, opaque sRGB (0xRRGGBB).
#[cfg(any(target_os = "linux", test))]
use std::path::{Path, PathBuf};

#[cfg(any(target_os = "linux", test))]
#[path = "omarchy.rs"]
mod omarchy;

#[cfg(test)]
#[path = "tests.rs"]
mod tests;

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

impl Palette {
    /// Noora's semantic tokens, the colors every Tuist Guild client shares
    /// with the server (`tuist_app_core::theme`).
    pub fn noora(dark: bool) -> Self {
        let token = |name| tuist_app_core::theme::color(name, dark).expect("Noora token");
        Self {
            dark,
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
    #[cfg(test)]
    pub fn load_sources(dark: bool, directories: &[PathBuf]) -> Self {
        Self::load_omarchy_sources(directories).unwrap_or_else(|| Self::noora(dark))
    }

    #[cfg(any(target_os = "linux", test))]
    pub fn load_omarchy_sources(directories: &[PathBuf]) -> Option<Self> {
        directories
            .iter()
            .find(|path| path.exists())
            .and_then(|path| omarchy::load(path))
    }

    /// Only Linux opts in automatically; None preserves live OS appearance.
    #[cfg(target_os = "linux")]
    pub fn load_system() -> Option<Self> {
        if let Some(home) = std::env::var_os("HOME").filter(|home| !home.is_empty()) {
            return Self::load_omarchy_sources(&Self::omarchy_directories(Path::new(&home)));
        }
        None
    }

    /// Parse one complete palette, without accessing the filesystem or running
    /// any Omarchy scripts. `light_mode` is the legacy light.mode marker.
    #[cfg(test)]
    pub fn from_omarchy(source: &str, light_mode: bool) -> Option<Self> {
        omarchy::parse(source, light_mode)
    }
}

#[cfg(any(target_os = "linux", test))]
fn luminance(color: u32) -> f64 {
    let linear = |shift: u32| {
        let c = ((color >> shift) & 255u32) as f64 / 255.0;
        if c <= 0.04045 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
}

#[cfg(any(target_os = "linux", test))]
pub(super) fn contrast_foreground(color: u32) -> u32 {
    let luminance = luminance(color);
    if (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) {
        0x000000
    } else {
        0xffffff
    }
}

#[cfg(any(target_os = "linux", test))]
pub(super) fn readable_secondary(candidate: u32, background: u32, foreground: u32) -> u32 {
    let (a, b) = (luminance(candidate), luminance(background));
    if (a.max(b) + 0.05) / (a.min(b) + 0.05) >= 4.5 {
        candidate
    } else {
        foreground
    }
}
