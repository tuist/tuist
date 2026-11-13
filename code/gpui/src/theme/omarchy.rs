use super::{Palette, contrast_foreground, readable_secondary};
use std::{fs, path::Path};

pub(super) fn load(directory: &Path) -> Option<Palette> {
    // Resolve a legacy current/theme symlink once for both palette and marker.
    let directory = directory.canonicalize().ok()?;
    let source = fs::read_to_string(directory.join("colors.toml")).ok()?;
    parse(&source, directory.join("light.mode").is_file())
}

pub(super) fn parse(source: &str, light_mode: bool) -> Option<Palette> {
    let values: toml::Table = toml::from_str(source).ok()?;
    // A defined but malformed value is an error, not permission to substitute
    // another key. Only absent keys follow upstream's compatibility aliases.
    let color = |keys: &[&str]| -> Option<u32> {
        for key in keys {
            if let Some(value) = values.get(*key) {
                let hex = value.as_str()?.strip_prefix('#')?;
                if hex.len() != 6 || !hex.bytes().all(|c| c.is_ascii_hexdigit()) {
                    return None;
                }
                return u32::from_str_radix(hex, 16).ok();
            }
        }
        None
    };
    let background = color(&["background", "bg", "color0"])?;
    let foreground = color(&["foreground", "fg", "color7"])?;
    let accent = color(&["accent"])?;
    let error = color(&["red", "color1"])?;
    let optional = |keys: &[&str], fallback| {
        if keys.iter().any(|key| values.contains_key(*key)) {
            color(keys)
        } else {
            Some(fallback)
        }
    };
    // Mirror bin/omarchy-theme-color's mode precedence and RGB-sum threshold.
    let dark = if let Some(mode) = values.get("mode").or_else(|| values.get("theme_type")) {
        match mode.as_str()? {
            "dark" => true,
            "light" => false,
            _ => return None,
        }
    } else if light_mode {
        false
    } else {
        ((background >> 16) & 255) + ((background >> 8) & 255) + (background & 255) <= 382
    };
    let muted = optional(
        &["muted", "color8", "dark_foreground", "dark_fg"],
        foreground,
    )?;
    let hover = optional(&["lighter_background", "lighter_bg"], background)?;
    let selection = optional(&["selection", "selection_background", "color8"], background)?;
    Some(Palette {
        dark,
        background,
        sidebar: optional(&["dark_background", "dark_bg"], mix_black(background, 0.25))?,
        border: muted,
        text: foreground,
        // Omarchy's dim/disabled color is not always readable body text.
        text_muted: readable_secondary(
            optional(&["dark_foreground", "dark_fg", "color8"], foreground)?,
            background,
            foreground,
        ),
        row_hover: hover,
        row_selected: selection,
        accent,
        accent_foreground: contrast_foreground(accent),
        error,
    })
}

fn mix_black(color: u32, amount: f64) -> u32 {
    let channel = |shift: u32| {
        ((((color >> shift) & 255u32) as f64 * (1.0 - amount)).round() as u32) << shift
    };
    channel(16) | channel(8) | channel(0)
}
