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

/// NSH's shadcn tokens, which a conversation card styles with, as the Noora
/// tokens that carry the same role.
const CARD_TOKENS: &[(&str, &str)] = &[
    ("foreground", "surface-label-primary"),
    ("card-foreground", "surface-label-primary"),
    ("popover", "surface-background-secondary"),
    ("popover-foreground", "surface-label-primary"),
    ("muted", "surface-background-secondary"),
    ("muted-foreground", "surface-label-secondary"),
    ("primary", "button-primary-background"),
    ("primary-foreground", "button-primary-label"),
    ("secondary", "button-neutral-background-hover"),
    ("secondary-foreground", "button-neutral-label"),
    ("accent", "button-neutral-background-hover"),
    ("accent-foreground", "button-neutral-label"),
    ("destructive", "button-destructive-background"),
    ("destructive-foreground", "button-destructive-label"),
    ("border", "surface-border-primary"),
    ("input", "surface-border-primary"),
    ("ring", "button-primary-background"),
];

/// A card's NSH theme overrides (`setThemeOverrides`) for one appearance. The
/// tokens sit under `theme`, so they hold whichever mode NSH thinks it is in,
/// and the edge picks the file for the appearance it shows. The edge draws
/// the card on glass, so its own surfaces are clear.
fn card_theme(palette: Palette) -> serde_json::Value {
    let mut tokens: serde_json::Map<_, _> = CARD_TOKENS
        .iter()
        .map(|(nsh, noora)| {
            let value = palette.color(noora).expect("card tokens are Noora tokens");
            (nsh.to_string(), format!("#{value:06x}").into())
        })
        .collect();
    for clear in ["background", "card"] {
        tokens.insert(clear.into(), "transparent".into());
    }
    serde_json::json!({"cssVars": {"theme": tokens}})
}

/// `{"default":"noora","themes":[{"id","name","appearance":null|"light"|"dark",
/// "light":{"<token>":"#rrggbb",…},"dark":{…},"card":{"light":{…},"dark":{…}}},…]}`,
/// for the native edges; `card` is `card_theme` for each appearance.
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
                    "card": {"light": card_theme(theme.light), "dark": card_theme(theme.dark)},
                })
            })
            .collect();
        let value = serde_json::json!({"default": DEFAULT, "themes": themes});
        CString::new(value.to_string()).expect("themes contain no NUL")
    })
}

/// The ID edges store for a theme the agent made with `set_theme`; Profile
/// lists it as Custom.
pub const CUSTOM: &str = "custom";

/// What each token colors, so the agent knows what it changes.
fn role(token: &str) -> &'static str {
    match token {
        "surface-background-primary" => "Main background of screens and conversations.",
        "surface-background-secondary" => "Grouped rows, cards and the person's message bubbles.",
        "surface-background-tertiary" => "Subtle fills, such as tool calls and inputs.",
        "surface-label-primary" => "Body text and titles.",
        "surface-label-secondary" => "Secondary text, such as timestamps and captions.",
        "surface-label-tertiary" => "Placeholders and the faintest text.",
        "surface-label-destructive" => "Errors and destructive text.",
        "surface-label-disabled" => "Disabled text.",
        "surface-border-primary" => "Borders and separators.",
        "button-primary-background" => "The accent: primary buttons, links, selection and tint.",
        "button-primary-label" => "Text on primary buttons and the accent.",
        "button-primary-disabled-background" => "Disabled primary buttons.",
        "button-primary-disabled-label" => "Text on disabled primary buttons.",
        "button-secondary-background" => "Secondary buttons.",
        "button-secondary-label" => "Text on secondary buttons.",
        "button-neutral-background-hover" => "Hovered rows and neutral buttons.",
        "button-neutral-background-active" => "Pressed rows and neutral buttons.",
        "button-neutral-label" => "Text on neutral buttons.",
        "button-destructive-background" => "Destructive buttons.",
        "button-destructive-label" => "Text on destructive buttons.",
        // A new token needs its own line above; a test fails without one.
        _ => "",
    }
}

/// The `set_theme` tool Luft offers a thread's agent (`crate::live`): its
/// schema lists every token with what it colors and Noora's values.
pub fn tool() -> serde_json::Value {
    let colors: serde_json::Map<_, _> = TOKENS
        .iter()
        .map(|(name, light, dark)| {
            let description = format!(
                "{} Tuist's default: #{light:06x} light, #{dark:06x} dark.",
                role(name)
            );
            (
                name.to_string(),
                serde_json::json!({"type":"string","pattern":"^#[0-9a-fA-F]{6}$","description":description}),
            )
        })
        .collect();
    let ids: Vec<_> = themes().iter().map(|theme| theme.id).collect();
    serde_json::json!({
        "name": "set_theme",
        "description": "Restyles this app with a custom theme, live. Starts from `base` in its appearance and \
            overrides any of its design tokens with sRGB hex colors; tokens left out keep the base's color. \
            Keep text legible against its background. The theme replaces the person's theme choice in \
            Profile, where it shows as Custom, until they pick another.",
        "parameters": {
            "type": "object",
            "properties": {
                "base": {"type": "string", "enum": ids,
                    "description": "The theme to start from: noora is Tuist's own, the others are Omarchy's. Default noora."},
                "appearance": {"type": "string", "enum": ["light", "dark"],
                    "description": "Whether the theme is light or dark; system controls follow it. Required with noora, \
                        which has both. The other bases have one appearance, which is used when this is left out; \
                        asking for the other is refused."},
                "colors": {"type": "object", "properties": colors, "additionalProperties": false},
            },
            "additionalProperties": false,
        },
    })
}

/// The custom theme `set_theme` describes, in the catalog's theme shape with
/// `id` `custom`, or a message for the agent saying what to fix.
pub fn custom(args: &serde_json::Value) -> Result<serde_json::Value, String> {
    let base_id = args["base"].as_str().unwrap_or(DEFAULT);
    let base = themes()
        .iter()
        .find(|theme| theme.id == base_id)
        .ok_or_else(|| format!("`{base_id}` isn't a theme. Use one of the `base` values."))?;
    let requested = match args
        .get("appearance")
        .and_then(|v| (!v.is_null()).then_some(v))
    {
        None => None,
        Some(value) => match value.as_str() {
            Some("dark") => Some(true),
            Some("light") => Some(false),
            _ => return Err("Set `appearance` to light or dark.".into()),
        },
    };
    // An Omarchy base has one appearance; its surfaces under the other
    // appearance's system chrome would be illegible.
    let dark = match (base.appearance(), requested) {
        (Some(fixed), Some(asked)) if fixed != asked => {
            let fixed = if fixed { "dark" } else { "light" };
            return Err(format!(
                "`{base_id}` is a {fixed} theme. Leave out `appearance`, set it to {fixed}, or start from noora."
            ));
        }
        (Some(fixed), _) => fixed,
        (None, Some(asked)) => asked,
        (None, None) => {
            return Err("Set `appearance` to light or dark when starting from noora.".into());
        }
    };
    let mut palette = base.palette(dark);
    palette.dark = dark;
    if let Some(colors) = args.get("colors").filter(|v| !v.is_null()) {
        let colors = colors.as_object().ok_or("`colors` must be an object.")?;
        for (token, value) in colors {
            let index = TOKENS
                .iter()
                .position(|(name, _, _)| name == token)
                .ok_or_else(|| format!("`{token}` isn't a token. Use the names in `colors`."))?;
            palette.colors[index] = value
                .as_str()
                .and_then(|v| v.strip_prefix('#'))
                .filter(|v| v.len() == 6)
                .and_then(|v| u32::from_str_radix(v, 16).ok())
                .ok_or_else(|| format!("`{token}` must be a hex color such as #1a1b26."))?;
        }
    }
    let tokens: serde_json::Map<_, _> = TOKENS
        .iter()
        .zip(palette.colors)
        .map(|((name, _, _), value)| (name.to_string(), format!("#{value:06x}").into()))
        .collect();
    Ok(serde_json::json!({
        "id": CUSTOM,
        "name": "Custom",
        "appearance": if dark { "dark" } else { "light" },
        "light": tokens,
        "dark": tokens,
        "card": {"light": card_theme(palette), "dark": card_theme(palette)},
    }))
}

/// The immutable process-lifetime theme catalog JSON; never free it.
#[unsafe(no_mangle)]
pub extern "C" fn tuist_app_theme() -> *const c_char {
    json().as_ptr()
}
