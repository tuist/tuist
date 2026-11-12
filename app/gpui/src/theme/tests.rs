use super::Palette;
use std::{
    fs,
    sync::atomic::{AtomicU64, Ordering},
};

// Real upstream Tokyo Night values, including the v4 semantic keys we use.
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
            text: 0xfdfdfd,
            text_muted: 0xc9cccf,
            row_hover: 0x222222,
            row_selected: 0x2e2e2e,
            accent: 0x7339ff,
            accent_foreground: 0xfdfdfd,
            error: 0xff9389,
        }
    );
}

#[test]
fn semantic_dark_palette_and_contrasting_button_label() {
    assert_eq!(
        Palette::from_omarchy(DARK, true).unwrap(),
        Palette {
            dark: true,
            background: 0x1a1b26,
            sidebar: 0x13141c,
            border: 0x414868,
            text: 0xa9b1d6,
            text_muted: 0xa9b1d6,
            row_hover: 0x24283b,
            row_selected: 0x292e42,
            accent: 0x7aa2f7,
            accent_foreground: 0x000000,
            error: 0xf7768e,
        }
    );
    let readable = DARK.replace("#565f89", "#b4bee6");
    assert_eq!(
        Palette::from_omarchy(&readable, false).unwrap().text_muted,
        0xb4bee6
    );
}

#[test]
fn legacy_light_palette_and_mode_precedence() {
    let source = r##"
background = '#ffffff' # TOML comments and literal strings are supported
foreground = '#202020'
accent = '#301060'
color0 = '#eeeeee'
color1 = '#cc0000'
color8 = '#888888'
selection_background = '#ddddff'
"##;
    let palette = Palette::from_omarchy(source, false).unwrap();
    assert!(!palette.dark); // official RGB-sum detection
    assert_eq!(palette.error, 0xcc0000);
    assert_eq!(palette.border, 0x888888);
    assert_eq!(palette.row_selected, 0xddddff);
    assert_eq!(palette.accent_foreground, 0xffffff);
    let dark = source.replace("#ffffff", "#101010");
    assert!(Palette::from_omarchy(&dark, false).unwrap().dark);
    assert!(!Palette::from_omarchy(&dark, true).unwrap().dark);
    assert!(
        Palette::from_omarchy(&format!("{source}\ntheme_type = 'dark'"), true)
            .unwrap()
            .dark
    );
    assert!(
        !Palette::from_omarchy(
            &format!("{source}\ntheme_type = 'dark'\nmode = 'light'"),
            false
        )
        .unwrap()
        .dark
    );
}

#[test]
fn malformed_palette_is_never_partially_used() {
    for invalid in [
        DARK.replace("#7aa2f7", "$(touch /tmp/not-executed)"),
        DARK.replace("#7aa2f7", "#123"),
        DARK.replace("#414868", "#gggggg"),
        DARK.replace("\"#f7768e\"", "42"),
        DARK.replace("mode = \"dark\"", "mode = 'unknown'"),
        format!("{DARK}\naccent = '#ffffff'"),
        "background = [".to_string(),
        "".to_string(),
    ] {
        assert_eq!(Palette::from_omarchy(&invalid, false), None);
    }
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
    assert_eq!(
        Palette::load_sources(false, &directories),
        Palette::noora(false)
    );
    fs::create_dir_all(&directories[1]).unwrap();
    fs::write(directories[1].join("colors.toml"), DARK).unwrap();
    assert_eq!(
        Palette::load_sources(false, &directories),
        Palette::from_omarchy(DARK, false).unwrap()
    );
    fs::create_dir_all(&directories[0]).unwrap();
    fs::write(directories[0].join("colors.toml"), "invalid").unwrap();
    assert_eq!(
        Palette::load_sources(true, &directories),
        Palette::noora(true)
    );
    fs::write(
        directories[0].join("colors.toml"),
        DARK.replace("mode = \"dark\"", ""),
    )
    .unwrap();
    fs::write(directories[0].join("light.mode"), "").unwrap();
    assert!(!Palette::load_sources(true, &directories).dark);
    fs::remove_file(directories[0].join("light.mode")).unwrap();
    assert!(Palette::load_sources(false, &directories).dark);
    let retired = home.join("retired");
    fs::rename(&directories[0], &retired).unwrap();
    fs::create_dir_all(&directories[0]).unwrap();
    assert_eq!(
        Palette::load_sources(false, &directories),
        Palette::noora(false)
    );
    fs::remove_dir_all(home).unwrap();
}
