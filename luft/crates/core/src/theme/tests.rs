use super::*;

// Real upstream Tokyo Night values, including the semantic keys we use.
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

fn color(palette: Option<Palette>, token: &str) -> u32 {
    palette.unwrap().color(token).unwrap()
}

#[test]
fn edges_receive_every_theme_and_token() {
    let value: serde_json::Value = serde_json::from_str(json().to_str().unwrap()).unwrap();
    assert_eq!(value["default"], "noora");
    let catalog = value["themes"].as_array().unwrap();
    assert_eq!(catalog.len(), themes().len());
    assert_eq!(catalog[0]["id"], "noora");
    assert_eq!(catalog[0]["appearance"], serde_json::Value::Null);
    for (name, light, dark) in TOKENS {
        assert_eq!(catalog[0]["light"][name], format!("#{light:06x}"));
        assert_eq!(catalog[0]["dark"][name], format!("#{dark:06x}"));
    }
    let tokyo = catalog.iter().find(|t| t["id"] == "tokyo-night").unwrap();
    assert_eq!(tokyo["name"], "Tokyo Night");
    assert_eq!(tokyo["appearance"], "dark");
    assert_eq!(tokyo["light"]["surface-background-primary"], "#1a1b26");
    let latte = catalog
        .iter()
        .find(|t| t["id"] == "catppuccin-latte")
        .unwrap();
    assert_eq!(latte["appearance"], "light");
    // Cards take the theme's colors for the appearance shown, in either NSH mode,
    // over a clear surface the edge's glass shows through.
    let card = &catalog[0]["card"]["dark"]["cssVars"]["theme"];
    assert_eq!(card["card-foreground"], "#f6f6f6");
    assert_eq!(card["muted-foreground"], "#d2d2d2");
    assert_eq!(card["primary"], "#7339ff");
    assert_eq!(card["card"], "transparent");
    assert_eq!(
        catalog[0]["card"]["light"]["cssVars"]["theme"]["card-foreground"],
        "#191a1b"
    );
    assert_eq!(
        tokyo["card"]["light"]["cssVars"]["theme"]["primary"],
        "#7aa2f7"
    );
    // Spot-check the conversion against Noora's purple-500 and neutral-light-50.
    let noora = theme("noora");
    assert_eq!(
        noora.light.color("button-primary-background"),
        Some(0x7339ff)
    );
    assert_eq!(
        noora.light.color("surface-background-primary"),
        Some(0xfdfdfd)
    );
    assert_eq!(
        noora.dark.color("surface-background-primary"),
        Some(0x0e0e0e)
    );
    assert_eq!(noora.dark.color("missing"), None);
    assert_eq!(theme("retired-theme").id, "noora");
}

#[test]
fn semantic_palette_maps_to_noora_tokens() {
    let palette = Palette::from_omarchy(DARK, true);
    assert!(palette.unwrap().dark); // `mode` beats the light.mode marker
    for (token, expected) in [
        ("surface-background-primary", 0x1a1b26),
        ("surface-background-secondary", 0x24283b),
        ("surface-background-tertiary", 0x13141c),
        ("surface-label-primary", 0xa9b1d6),
        // #565f89 is under 4.5:1 on the background, so body text stays readable.
        ("surface-label-secondary", 0xa9b1d6),
        ("surface-label-tertiary", 0x565f89),
        ("surface-border-primary", 0x414868),
        ("button-primary-background", 0x7aa2f7),
        // A pale accent needs a black label, unlike Noora's white one.
        ("button-primary-label", 0x000000),
        ("button-neutral-background-hover", 0x24283b),
        ("button-neutral-background-active", 0x292e42),
        ("surface-label-destructive", 0xf7768e),
        // Omarchy's mix: halfway between #7aa2f7 and #1a1b26, rounded half up.
        ("button-primary-disabled-background", 0x4a5f8f),
    ] {
        assert_eq!(color(palette, token), expected, "{token}");
    }
    let readable = DARK.replace("#565f89", "#b4bee6");
    assert_eq!(
        color(
            Palette::from_omarchy(&readable, false),
            "surface-label-secondary"
        ),
        0xb4bee6
    );
}

#[test]
fn legacy_palette_follows_omarchy_aliases_and_mode_precedence() {
    let source = r##"
background = '#ffffff' # comments and single quotes, as omarchy-theme-color reads them
foreground = '#202020'
color0 = '#eeeeee'
color1 = '#cc0000'
color4 = '#301060'
color8 = '#888888'
selection_background = '#ddddff'
"##;
    let palette = Palette::from_omarchy(source, false);
    assert!(!palette.unwrap().dark); // RGB-sum detection
    assert_eq!(color(palette, "surface-label-destructive"), 0xcc0000);
    assert_eq!(color(palette, "surface-border-primary"), 0x888888);
    assert_eq!(color(palette, "button-neutral-background-active"), 0xddddff);
    // No accent: Omarchy uses color4. No lighter background: color0.
    assert_eq!(color(palette, "button-primary-background"), 0x301060);
    assert_eq!(color(palette, "button-primary-label"), 0xffffff);
    assert_eq!(color(palette, "surface-background-secondary"), 0xeeeeee);
    // No dark background: the background mixed 25% toward black.
    assert_eq!(color(palette, "surface-background-tertiary"), 0xbfbfbf);
    let dark = source.replace("#ffffff", "#101010");
    assert!(Palette::from_omarchy(&dark, false).unwrap().dark);
    assert!(!Palette::from_omarchy(&dark, true).unwrap().dark);
    let typed = format!("{source}\ntheme_type = 'dark'");
    assert!(Palette::from_omarchy(&typed, true).unwrap().dark);
    let both = format!("{typed}\nmode = 'light'");
    assert!(!Palette::from_omarchy(&both, false).unwrap().dark);
    // Later keys replace earlier ones, as in omarchy-theme-color.
    let replaced = format!("{DARK}\naccent = '#ffffff'");
    assert_eq!(
        color(
            Palette::from_omarchy(&replaced, false),
            "button-primary-background"
        ),
        0xffffff
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
        DARK.replace("red = \"#f7768e\"", ""),
        "background = [".to_string(),
        "".to_string(),
    ] {
        assert_eq!(Palette::from_omarchy(&invalid, false), None, "{invalid}");
    }
}

#[test]
fn built_in_themes_resolve_with_their_own_appearance() {
    for theme in themes() {
        for palette in [theme.light, theme.dark] {
            let text = palette.color("surface-label-primary").unwrap();
            let background = palette.color("surface-background-primary").unwrap();
            assert_ne!(text, background, "{}", theme.id);
            assert_eq!(theme.appearance().is_none(), theme.id == DEFAULT);
        }
    }
}

#[test]
fn every_token_says_what_it_colors() {
    for (name, _, _) in TOKENS {
        assert!(!role(name).is_empty(), "{name} needs a role in theme::role");
    }
}
