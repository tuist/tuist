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
    /// Semantic tokens in noora/css/tokens.css, converted from its base sRGB
    /// OKLCH palette (not its Display P3 overrides) to 8-bit sRGB.
    pub fn noora(dark: bool) -> Self {
        let neutral = |l, c, h| oklch(l, c, h);
        Self {
            dark,
            // surface-background-primary / surface-background-tertiary
            background: if dark {
                neutral(0.162, 0.0, 0.0)
            } else {
                neutral(0.994, 0.0, 0.0)
            },
            sidebar: if dark {
                neutral(0.209, 0.0, 0.0)
            } else {
                neutral(0.976, 0.0, 0.0)
            },
            // surface-border-primary
            border: if dark {
                neutral(0.348, 0.0, 0.0)
            } else {
                neutral(0.844, 0.005, 247.888)
            },
            // surface-label-primary / surface-label-secondary
            text: if dark {
                neutral(0.994, 0.0, 0.0)
            } else {
                neutral(0.217, 0.002, 247.941)
            },
            text_muted: if dark {
                neutral(0.844, 0.005, 247.888)
            } else {
                neutral(0.451, 0.006, 247.965)
            },
            // button-neutral-background-hover / button-neutral-background-active
            row_hover: if dark {
                neutral(0.254, 0.0, 0.0)
            } else {
                neutral(0.955, 0.002, 247.84)
            },
            row_selected: if dark {
                neutral(0.302, 0.0, 0.0)
            } else {
                neutral(0.930, 0.003, 247.86)
            },
            // button-primary-background / button-primary-label
            accent: oklch(0.548, 0.266, 287.4),
            accent_foreground: neutral(0.994, 0.0, 0.0),
            // surface-label-destructive
            error: if dark {
                oklch(0.775, 0.132, 26.2)
            } else {
                oklch(0.548, 0.223, 27.0)
            },
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

// CSS Color 4 OKLab -> linear sRGB -> encoded sRGB; clip only at the gamut edge.
fn oklch(l: f64, c: f64, h: f64) -> u32 {
    let a = c * h.to_radians().cos();
    let b = c * h.to_radians().sin();
    let ll = (l + 0.3963377774 * a + 0.2158037573 * b).powi(3);
    let mm = (l - 0.1055613458 * a - 0.0638541728 * b).powi(3);
    let ss = (l - 0.0894841775 * a - 1.2914855480 * b).powi(3);
    let encode = |v: f64| {
        let v = if v <= 0.0031308 {
            12.92 * v
        } else {
            1.055 * v.powf(1.0 / 2.4) - 0.055
        };
        (v.clamp(0.0, 1.0) * 255.0).round() as u32
    };
    (encode(4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss) << 16)
        | (encode(-1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss) << 8)
        | encode(-0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss)
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
