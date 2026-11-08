use gpui::{Hsla, WindowAppearance, rgb};

pub mod palette;
pub use palette::Palette;

/// Linux's background loader publishes here; observers redraw on changes.
pub struct ThemeState(pub Option<Palette>);
impl gpui::Global for ThemeState {}

pub fn init(cx: &mut gpui::App) {
    if cx.try_global::<ThemeState>().is_some() {
        return;
    }
    cx.set_global(ThemeState(None));
    #[cfg(target_os = "linux")]
    cx.spawn(async move |cx| {
        loop {
            let palette = cx
                .background_executor()
                .spawn(async { Palette::load_system() })
                .await;
            if cx
                .update(|cx| {
                    if cx.global::<ThemeState>().0 != palette {
                        // set_global notifies observe_global subscribers itself.
                        cx.set_global(ThemeState(palette));
                    }
                })
                .is_err()
            {
                break;
            }
            cx.background_executor()
                .timer(std::time::Duration::from_secs(1))
                .await;
        }
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
    /// Rendering never reads theme files. Platforms without an Omarchy loader
    /// continue to follow the window's current native appearance.
    pub fn for_appearance(appearance: WindowAppearance, cx: &gpui::App) -> Self {
        Self::from_palette(
            cx.try_global::<ThemeState>()
                .and_then(|state| state.0)
                .unwrap_or_else(|| {
                    Palette::noora(matches!(
                        appearance,
                        WindowAppearance::Dark | WindowAppearance::VibrantDark
                    ))
                }),
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
