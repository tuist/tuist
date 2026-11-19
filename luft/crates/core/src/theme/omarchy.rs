//! Omarchy palettes (`colors.toml`) mapped to Noora's tokens. Parsing and the
//! alias/fallback cascade mirror `bin/omarchy-theme-color`, the resolver every
//! Omarchy consumer shares, so a theme looks the same here as on the desktop.
use super::{Palette, TOKENS};
use std::collections::HashMap;

/// One complete palette, or None. A defined but malformed color is an error,
/// not permission to fall back to another key; only absent keys follow
/// Omarchy's compatibility aliases. `light_mode` is the `light.mode` marker
/// beside the file.
pub(super) fn parse(source: &str, light_mode: bool) -> Option<Palette> {
    let raw = read(source);
    let get = |key: &str| raw.get(key).map(String::as_str);
    let hex = |key: &str| -> Option<Option<u32>> {
        let value = get(key)?;
        let digits = value
            .strip_prefix('#')
            .filter(|digits| digits.len() == 6 && digits.bytes().all(|c| c.is_ascii_hexdigit()));
        Some(digits.and_then(|digits| u32::from_str_radix(digits, 16).ok()))
    };
    // The first defined key decides; a malformed one fails the whole palette.
    let first = |keys: &[&str]| -> Result<Option<u32>, ()> {
        for key in keys {
            if let Some(value) = hex(key) {
                return value.map(Some).ok_or(());
            }
        }
        Ok(None)
    };
    let resolve = |keys: &[&str], fallback: Option<u32>| first(keys).map(|v| v.or(fallback));

    let background = resolve(&["background", "bg", "color0"], None).ok()??;
    let foreground = resolve(&["foreground", "fg", "color7"], None).ok()??;
    let red = resolve(&["red", "color1"], None).ok()??;
    let accent = resolve(&["accent", "color4", "blue"], None).ok()??;
    let color0 = resolve(&["color0"], None).ok()?;
    let color8 = resolve(&["color8"], None).ok()?;
    let lighter_background = resolve(
        &["lighter_background", "lighter_bg"],
        Some(color0.unwrap_or(background)),
    )
    .ok()??;
    let dark_background = resolve(
        &["dark_background", "dark_bg"],
        Some(mix(background, 0x000000, 0.25)),
    )
    .ok()??;
    let dark_foreground = resolve(
        &["dark_foreground", "dark_fg"],
        Some(color8.unwrap_or(foreground)),
    )
    .ok()??;
    let muted = resolve(&["muted"], Some(color8.unwrap_or(dark_foreground))).ok()??;
    let selection = resolve(
        &["selection", "selection_background"],
        Some(color8.or(color0).unwrap_or(background)),
    )
    .ok()??;

    // Mode precedence: `mode`, legacy `theme_type`, light.mode, then the
    // background's RGB sum, exactly like resolve_theme_mode.
    let dark = match get("mode").or_else(|| get("theme_type")) {
        Some("dark") => true,
        Some("light") => false,
        Some(_) => return None,
        None if light_mode => false,
        None => ((background >> 16) & 255) + ((background >> 8) & 255) + (background & 255) <= 382,
    };

    let disabled = mix(accent, background, 0.5);
    let color = |token: &str| -> u32 {
        match token {
            "surface-background-primary" => background,
            "surface-background-secondary" => lighter_background,
            "surface-background-tertiary" => dark_background,
            "surface-label-primary" => foreground,
            // Omarchy's dim color is not always readable body text.
            "surface-label-secondary" => readable(dark_foreground, background, foreground),
            "surface-label-tertiary" | "surface-label-disabled" => dark_foreground,
            "surface-label-destructive" => red,
            "surface-border-primary" => muted,
            "button-primary-background" => accent,
            "button-primary-label" => contrast(accent),
            "button-primary-disabled-background" => disabled,
            "button-primary-disabled-label" => contrast(disabled),
            "button-secondary-background" | "button-neutral-background-hover" => lighter_background,
            "button-secondary-label" | "button-neutral-label" => foreground,
            "button-neutral-background-active" => selection,
            "button-destructive-background" => red,
            "button-destructive-label" => contrast(red),
            other => unreachable!("map Noora token {other} for Omarchy palettes"),
        }
    };
    Some(Palette {
        dark,
        colors: std::array::from_fn(|index| color(TOKENS[index].0)),
    })
}

/// omarchy-theme-color's parser: `key = value` lines, comments skipped, the
/// value read between its first pair of quotes, later keys replacing earlier.
fn read(source: &str) -> HashMap<String, String> {
    let mut values = HashMap::new();
    for line in source.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key: String = key
            .chars()
            .filter(|c| !matches!(c, '"' | '\'' | ' '))
            .collect();
        if key.is_empty() || key.starts_with('#') {
            continue;
        }
        let value = match value.find(['"', '\'']) {
            Some(open) => {
                let rest = &value[open + 1..];
                &rest[..rest.find(['"', '\'']).unwrap_or(rest.len())]
            }
            None => value.trim(),
        };
        values.insert(key, value.to_string());
    }
    values
}

/// Omarchy's mix_color: a linear blend in 8-bit sRGB, rounded half up.
fn mix(start: u32, end: u32, amount: f64) -> u32 {
    let channel = |shift: u32| {
        let (a, b) = (
            ((start >> shift) & 255) as f64,
            ((end >> shift) & 255) as f64,
        );
        ((a * (1.0 - amount) + b * amount + 0.5) as u32) << shift
    };
    channel(16) | channel(8) | channel(0)
}

fn luminance(color: u32) -> f64 {
    let linear = |shift: u32| {
        let c = ((color >> shift) & 255) as f64 / 255.0;
        if c <= 0.04045 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
}

/// Black or white, whichever contrasts more: Omarchy accents range from pale
/// pastels to saturated darks, so a fixed white label is not always legible.
fn contrast(color: u32) -> u32 {
    let luminance = luminance(color);
    if (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) {
        0x000000
    } else {
        0xffffff
    }
}

/// The candidate when it reaches WCAG AA (4.5:1) on the background, otherwise
/// the palette's normal foreground, instead of inventing a color.
fn readable(candidate: u32, background: u32, foreground: u32) -> u32 {
    let (a, b) = (luminance(candidate), luminance(background));
    if (a.max(b) + 0.05) / (a.min(b) + 0.05) >= 4.5 {
        candidate
    } else {
        foreground
    }
}
