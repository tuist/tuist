use gpui::{Hsla, WindowAppearance, rgb};
use std::path::PathBuf;
use tuist_app_core::theme as catalog;

pub mod palette;
pub use palette::Palette;

/// The choice that follows the desktop's Omarchy theme, offered only while one is active.
pub const OMARCHY: &str = "omarchy";

/// Linux's background loader publishes the Omarchy palette here, and Profile
/// the chosen theme; observers redraw on changes.
#[derive(Clone, Default, PartialEq)]
pub struct ThemeState {
    pub omarchy: Option<Palette>,
    /// None until someone picks a theme: Omarchy when present, otherwise Noora.
    pub selected: Option<String>,
}
impl gpui::Global for ThemeState {}

impl ThemeState {
    /// The selected theme's ID, resolving the default and a vanished Omarchy.
    pub fn current(&self) -> &str {
        match self.selected.as_deref() {
            Some(OMARCHY) | None if self.omarchy.is_some() => OMARCHY,
            Some(OMARCHY) | None => catalog::DEFAULT,
            Some(id) => catalog::theme(id).id,
        }
    }

    pub fn palette(&self, dark: bool) -> Palette {
        match (self.current(), self.omarchy) {
            (OMARCHY, Some(palette)) => palette,
            (id, _) => catalog::theme(id).palette(dark).into(),
        }
    }
}

/// `<data>/desktop/settings.json`, next to the saved accounts.
fn settings_path() -> PathBuf {
    tuist_credentials::Directories::from_env()
        .data
        .join("desktop/settings.json")
}

pub fn init(cx: &mut gpui::App) {
    if cx.try_global::<ThemeState>().is_some() {
        return;
    }
    // Read once at launch, never while rendering.
    let selected = std::fs::read(settings_path())
        .ok()
        .and_then(|bytes| serde_json::from_slice::<serde_json::Value>(&bytes).ok())
        .and_then(|settings| Some(settings.get("theme")?.as_str()?.to_owned()));
    cx.set_global(ThemeState {
        omarchy: None,
        selected,
    });
    #[cfg(target_os = "linux")]
    cx.spawn(async move |cx| {
        loop {
            let palette = cx
                .background_executor()
                .spawn(async { Palette::load_system() })
                .await;
            cx.update(|cx| {
                if cx.global::<ThemeState>().omarchy != palette {
                    // set_global notifies observe_global subscribers itself.
                    let selected = cx.global::<ThemeState>().selected.clone();
                    cx.set_global(ThemeState {
                        omarchy: palette,
                        selected,
                    });
                }
            });
            cx.background_executor()
                .timer(std::time::Duration::from_secs(1))
                .await;
        }
    })
    .detach();
}

/// Applies a theme from Profile at once and saves it off the UI thread.
pub fn select(id: &str, cx: &mut gpui::App) {
    let omarchy = cx
        .try_global::<ThemeState>()
        .and_then(|state| state.omarchy);
    cx.set_global(ThemeState {
        omarchy,
        selected: Some(id.to_owned()),
    });
    let settings = serde_json::json!({ "theme": id }).to_string();
    cx.background_executor()
        .spawn(async move {
            let path = settings_path();
            if let Some(parent) = path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = tuist_credentials::atomic_write_private(&path, settings.as_bytes());
        })
        .detach();
}

/// Semantic colors for the current window appearance.
#[derive(Clone, Copy)]
pub struct Theme {
    pub dark: bool,
    pub background: Hsla,
    pub sidebar: Hsla,
    pub border: Hsla,
    pub text: Hsla,
    pub text_muted: Hsla,
    pub row_hover: Hsla,
    pub row_selected: Hsla,
    pub accent: Hsla,
    pub accent_foreground: Hsla,
    pub error: Hsla,
}

impl Theme {
    /// Rendering never reads theme files. Noora follows the window's current
    /// native appearance; an Omarchy palette has its own.
    pub fn for_appearance(appearance: WindowAppearance, cx: &gpui::App) -> Self {
        let dark = matches!(
            appearance,
            WindowAppearance::Dark | WindowAppearance::VibrantDark
        );
        Self::from_palette(
            cx.try_global::<ThemeState>()
                .map_or_else(|| Palette::noora(dark), |state| state.palette(dark)),
        )
    }

    pub fn from_palette(palette: Palette) -> Self {
        Self {
            dark: palette.dark,
            background: rgb(palette.background).into(),
            sidebar: rgb(palette.sidebar).into(),
            border: rgb(palette.border).into(),
            text: rgb(palette.text).into(),
            text_muted: rgb(palette.text_muted).into(),
            row_hover: rgb(palette.row_hover).into(),
            row_selected: rgb(palette.row_selected).into(),
            accent: rgb(palette.accent).into(),
            accent_foreground: rgb(palette.accent_foreground).into(),
            error: rgb(palette.error).into(),
        }
    }
}
