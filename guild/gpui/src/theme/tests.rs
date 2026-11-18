use super::Palette;
use std::{
    fs,
    sync::atomic::{AtomicU64, Ordering},
};

// Real upstream Tokyo Night values; the core tests how palettes map to tokens.
const DARK: &str = r##"
mode = "dark"
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"
dark_background = "#13141c"
lighter_background = "#24283b"
foreground = "#a9b1d6"
dark_foreground = "#565f89"
red = "#f7768e"
"##;

#[test]
fn noora_semantic_values() {
    assert_eq!(
        Palette::noora(false),
        Palette {
            dark: false,
            background: 0xfdfdfd,
            sidebar: 0xf7f7f7,
            border: 0xc9cccf,
            text: 0x191a1b,
            text_muted: 0x535659,
            row_hover: 0xeff0f1,
            row_selected: 0xe6e8ea,
            accent: 0x7339ff,
            accent_foreground: 0xfdfdfd,
            error: 0xd40117,
        }
    );
    assert_eq!(
        Palette::noora(true),
        Palette {
            dark: true,
            background: 0x0e0e0e,
            sidebar: 0x181818,
            border: 0x3a3a3a,
            text: 0xf6f6f6,
            text_muted: 0xd2d2d2,
            row_hover: 0x222222,
            row_selected: 0x2e2e2e,
            accent: 0x7339ff,
            accent_foreground: 0xfdfdfd,
            error: 0xff9389,
        }
    );
}

/// What the window draws with when no theme is chosen: Omarchy, else Noora.
fn load_sources(dark: bool, directories: &[std::path::PathBuf]) -> Palette {
    Palette::load_omarchy_sources(directories).unwrap_or_else(|| Palette::noora(dark))
}

#[test]
fn loading_falls_back_wholly_and_rereads_replacements() {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let home = std::env::temp_dir().join(format!(
        "tuist-theme-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let directories = Palette::omarchy_directories(&home);
    assert_eq!(load_sources(false, &directories), Palette::noora(false));
    fs::create_dir_all(&directories[1]).unwrap();
    fs::write(directories[1].join("colors.toml"), DARK).unwrap();
    assert_eq!(
        Palette::load_omarchy_sources(&directories),
        tuist_app_core::theme::Palette::from_omarchy(DARK, false).map(Palette::from)
    );
    fs::create_dir_all(&directories[0]).unwrap();
    fs::write(directories[0].join("colors.toml"), "invalid").unwrap();
    assert_eq!(load_sources(true, &directories), Palette::noora(true));
    fs::write(
        directories[0].join("colors.toml"),
        DARK.replace("mode = \"dark\"", ""),
    )
    .unwrap();
    fs::write(directories[0].join("light.mode"), "").unwrap();
    assert!(!load_sources(true, &directories).dark);
    fs::remove_file(directories[0].join("light.mode")).unwrap();
    assert!(load_sources(false, &directories).dark);
    let retired = home.join("retired");
    fs::rename(&directories[0], &retired).unwrap();
    fs::create_dir_all(&directories[0]).unwrap();
    assert_eq!(load_sources(false, &directories), Palette::noora(false));
    fs::remove_dir_all(home).unwrap();
}

#[test]
fn chosen_theme_beats_omarchy_until_it_is_chosen_again() {
    use crate::theme::{OMARCHY, ThemeState};
    let omarchy = tuist_app_core::theme::Palette::from_omarchy(DARK, false).map(Palette::from);
    let state = |omarchy, selected: Option<&str>| ThemeState {
        omarchy,
        selected: selected.map(str::to_owned),
    };
    // Nothing chosen: the desktop's Omarchy theme, otherwise Noora.
    assert_eq!(state(omarchy, None).current(), OMARCHY);
    assert_eq!(state(omarchy, None).palette(false), omarchy.unwrap());
    assert_eq!(state(None, None).current(), "noora");
    assert_eq!(state(None, None).palette(true), Palette::noora(true));
    // A theme picked in Profile wins over the desktop, in either appearance.
    let white = state(omarchy, Some("white"));
    assert_eq!(white.current(), "white");
    assert!(!white.palette(true).dark);
    // Omarchy chosen but no longer installed, or a retired theme: Noora.
    assert_eq!(state(None, Some(OMARCHY)).current(), "noora");
    assert_eq!(state(omarchy, Some("retired")).current(), "noora");
}
