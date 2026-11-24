use std::borrow::Cow;

use gpui::{AssetSource, SharedString};

// A bare file name parses as a URI host, which `img` would fetch over HTTP.
pub const ROUNDED_ICON: &str = "brand/rounded-icon.png";
pub const TUIST_LOGO: &str = "logos/tuist.png";
pub const GOOGLE_LOGO: &str = "logos/google.png";
pub const APPLE_LIGHT: &str = "logos/apple-light.png";
pub const APPLE_DARK: &str = "logos/apple-dark.png";
pub const GITHUB_LIGHT: &str = "logos/github-light.png";
pub const GITHUB_DARK: &str = "logos/github-dark.png";
/// The shipping app's `ServerIcon`, tinted in place.
pub const SERVER_ICON: &str = "logos/server.svg";
/// Lucide (ISC) outline icons at Zed's 16px size, tinted in place.
pub const THREADS_ICON: &str = "icons/threads.svg";
pub const LOUNGES_ICON: &str = "icons/lounges.svg";
pub const DMS_ICON: &str = "icons/dms.svg";
pub const PROFILE_ICON: &str = "icons/profile.svg";
pub const EXTERNAL_LINK_ICON: &str = "icons/external-link.svg";

/// The app icon, flattened from the macOS app's `AppIcon.icon`.
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
pub const ICON: &[u8] = include_bytes!("../resources/icon.png");

const EMBEDDED: &[(&str, &[u8])] = &[
    (
        ROUNDED_ICON,
        include_bytes!("../resources/rounded-icon.png"),
    ),
    (TUIST_LOGO, include_bytes!("../resources/logos/tuist.png")),
    (GOOGLE_LOGO, include_bytes!("../resources/logos/google.png")),
    (
        APPLE_LIGHT,
        include_bytes!("../resources/logos/apple-light.png"),
    ),
    (
        APPLE_DARK,
        include_bytes!("../resources/logos/apple-dark.png"),
    ),
    (
        GITHUB_LIGHT,
        include_bytes!("../resources/logos/github-light.png"),
    ),
    (
        GITHUB_DARK,
        include_bytes!("../resources/logos/github-dark.png"),
    ),
    (SERVER_ICON, include_bytes!("../resources/logos/server.svg")),
    (
        THREADS_ICON,
        include_bytes!("../resources/icons/threads.svg"),
    ),
    (
        LOUNGES_ICON,
        include_bytes!("../resources/icons/lounges.svg"),
    ),
    (DMS_ICON, include_bytes!("../resources/icons/dms.svg")),
    (
        PROFILE_ICON,
        include_bytes!("../resources/icons/profile.svg"),
    ),
    (
        EXTERNAL_LINK_ICON,
        include_bytes!("../resources/icons/external-link.svg"),
    ),
    (
        "icons/search.svg",
        include_bytes!("../resources/icons/search.svg"),
    ),
    (
        "icons/circle-check.svg",
        include_bytes!("../resources/icons/circle-check.svg"),
    ),
    (
        "icons/message-square.svg",
        include_bytes!("../resources/icons/message-square.svg"),
    ),
    (
        "icons/rotate-cw.svg",
        include_bytes!("../resources/icons/rotate-cw.svg"),
    ),
];

/// Assets embedded in the binary, so it runs without a resources directory.
pub struct Assets;

impl AssetSource for Assets {
    fn load(&self, path: &str) -> anyhow::Result<Option<Cow<'static, [u8]>>> {
        Ok(EMBEDDED
            .iter()
            .find(|(name, _)| *name == path)
            .map(|(_, bytes)| Cow::Borrowed(*bytes)))
    }

    fn list(&self, path: &str) -> anyhow::Result<Vec<SharedString>> {
        Ok(EMBEDDED
            .iter()
            .filter(|(name, _)| name.starts_with(path))
            .map(|(name, _)| (*name).into())
            .collect())
    }
}
