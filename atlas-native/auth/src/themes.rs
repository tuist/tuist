use crate::transport::{Body, Network, Transport};
use crate::{AuthError, Result, error, server_url};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeSet;

#[derive(Deserialize, Serialize)]
struct Catalog {
    schema_version: u32,
    revision: String,
    default_theme_id: String,
    themes: Vec<Theme>,
}

#[derive(Deserialize, Serialize)]
struct Theme {
    id: String,
    name: String,
    description: String,
    typography: String,
    button_radius: f64,
    card_radius: f64,
    light: Palette,
    dark: Palette,
}

#[derive(Deserialize, Serialize)]
struct Palette {
    background: String,
    surface: String,
    text: String,
    secondary_text: String,
    border: String,
    accent: String,
    on_accent: String,
    tint: String,
}

pub(crate) fn fetch(server: &str) -> Result<Value> {
    fetch_using(&Network, server)
}

fn fetch_using(network: &impl Transport, server: &str) -> Result<Value> {
    let url = server_url(server)?.join("api/native/themes").unwrap();
    let value = network.request(&url, Body::Public { failure })?;
    validate(value)
}

fn failure(status: u16, _: &[u8]) -> AuthError {
    if matches!(status, 404 | 501) {
        error(
            "theme_unsupported",
            "This Atlas server does not publish themes.",
        )
    } else {
        error(
            "theme_unavailable",
            "Atlas themes are temporarily unavailable.",
        )
    }
}

fn invalid() -> AuthError {
    error(
        "invalid_theme",
        "This Atlas theme catalog is not supported.",
    )
}

pub(crate) fn validate(value: Value) -> Result<Value> {
    let catalog: Catalog = serde_json::from_value(value).map_err(|_| invalid())?;
    let mut ids = BTreeSet::new();
    if catalog.schema_version != 1
        || !text(&catalog.revision, 128)
        || catalog.themes.is_empty()
        || catalog.themes.len() > 16
        || !catalog.themes.iter().all(|theme| {
            text(&theme.id, 64)
                && theme.id != "server-default"
                && theme.id.split('-').all(|part| {
                    !part.is_empty()
                        && part
                            .bytes()
                            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
                })
                && ids.insert(&theme.id)
                && text(&theme.name, 80)
                && text(&theme.description, 160)
                && matches!(theme.typography.as_str(), "standard" | "strong" | "rounded")
                && (0.0..=24.0).contains(&theme.button_radius)
                && (0.0..=32.0).contains(&theme.card_radius)
                && palette(&theme.light, "#FFFFFF")
                && palette(&theme.dark, "#1C1C1E")
        })
        || !ids.contains(&catalog.default_theme_id)
    {
        return Err(invalid());
    }
    serde_json::to_value(catalog).map_err(|_| invalid())
}

fn text(value: &str, max: usize) -> bool {
    !value.trim().is_empty() && value.len() <= max
}

fn palette(palette: &Palette, native_surface: &str) -> bool {
    let colors = [
        &palette.background,
        &palette.surface,
        &palette.text,
        &palette.secondary_text,
        &palette.border,
        &palette.accent,
        &palette.on_accent,
        &palette.tint,
    ];
    colors.iter().all(|color| {
        color.len() == 7
            && color.starts_with('#')
            && color.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
    }) && [&palette.background, &palette.surface]
        .iter()
        .all(|surface| {
            [&palette.text, &palette.secondary_text, &palette.tint]
                .iter()
                .all(|color| contrast(color, surface) >= 4.5)
        })
        && contrast(&palette.accent, &palette.on_accent) >= 4.5
        && contrast(&palette.tint, native_surface) >= 4.5
}

fn contrast(left: &str, right: &str) -> f64 {
    let luminance = |color: &str| {
        [0.2126, 0.7152, 0.0722]
            .iter()
            .enumerate()
            .map(|(index, weight)| {
                let channel = u8::from_str_radix(&color[1 + index * 2..3 + index * 2], 16).unwrap()
                    as f64
                    / 255.0;
                let linear = if channel <= 0.04045 {
                    channel / 12.92
                } else {
                    ((channel + 0.055) / 1.055).powf(2.4)
                };
                linear * weight
            })
            .sum::<f64>()
    };
    let a = luminance(left);
    let b = luminance(right);
    (a.max(b) + 0.05) / (a.min(b) + 0.05)
}

pub(crate) fn defaults() -> Value {
    json!({
        "schema_version": 1, "revision": "bundled-1", "default_theme_id": "atlas",
        "themes": [{
            "id": "atlas", "name": "Atlas", "description": "Original Atlas appearance.",
            "typography": "standard", "button_radius": 8, "card_radius": 12,
            "light": {
                "background": "#F2F2F7", "surface": "#FFFFFF", "text": "#171A1C",
                "secondary_text": "#575B62", "border": "#7D8289",
                "accent": "#087CAA", "on_accent": "#FFFFFF", "tint": "#086185"
            },
            "dark": {
                "background": "#000000", "surface": "#1F2126", "text": "#FDFDFD",
                "secondary_text": "#B9BDC4", "border": "#858B95",
                "accent": "#66C7E8", "on_accent": "#000000", "tint": "#66C7E8"
            }
        }]
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bridge;

    #[test]
    fn public_bridge_normalizes_future_fields_and_preserves_custom_theme_values() {
        let mut catalog = defaults();
        catalog["company_metadata"] = json!({"ignored": true});
        catalog["themes"][0]["future_token"] = json!("ignored");
        catalog["themes"][0]["button_radius"] = json!(5.5);
        let output: Value = serde_json::from_str(&bridge::execute(
            &json!({
                "operation": "validate_themes", "catalog": catalog
            })
            .to_string(),
        ))
        .unwrap();
        assert_eq!(output["ok"]["themes"][0]["button_radius"], 5.5);
        assert!(output["ok"].get("company_metadata").is_none());
        assert!(output["ok"]["themes"][0].get("future_token").is_none());
        assert!(validate(defaults()).is_ok());
    }

    #[test]
    fn rejects_incompatible_catalogs_and_unreadable_colors_without_rejecting_authentication() {
        for (path, value) in [
            ("/schema_version", json!(2)),
            ("/default_theme_id", json!("missing")),
            ("/themes/0/id", json!("../external")),
            ("/themes/0/id", json!("server-default")),
            ("/themes/0/button_radius", json!(25)),
            ("/themes/0/light/secondary_text", json!("#FFFFFF")),
            ("/themes/0/dark/on_accent", json!("#66C7E8")),
            ("/themes/0/light/border", json!("#abcdéf")),
        ] {
            let mut catalog = defaults();
            *catalog.pointer_mut(path).unwrap() = value;
            let output: Value = serde_json::from_str(&bridge::execute(
                &json!({
                    "operation": "validate_themes", "catalog": catalog
                })
                .to_string(),
            ))
            .unwrap();
            assert_eq!(output["error"]["kind"], "invalid_theme", "{path}");
        }
        for (mode, surface, text) in [
            ("light", "#000000", "#FFFFFF"),
            ("dark", "#FFFFFF", "#000000"),
        ] {
            let mut catalog = defaults();
            for token in ["background", "surface"] {
                catalog["themes"][0][mode][token] = json!(surface);
            }
            for token in ["text", "secondary_text", "tint"] {
                catalog["themes"][0][mode][token] = json!(text);
            }
            let output: Value = serde_json::from_str(&bridge::execute(
                &json!({"operation": "validate_themes", "catalog": catalog}).to_string(),
            ))
            .unwrap();
            assert_eq!(output["error"]["kind"], "invalid_theme", "{mode}");
        }
        let mut duplicate = defaults();
        duplicate["themes"]
            .as_array_mut()
            .unwrap()
            .push(defaults()["themes"][0].clone());
        assert!(validate(duplicate).is_err());
    }

    struct OldServer(u16);
    impl Transport for OldServer {
        fn request<T: serde::de::DeserializeOwned>(
            &self,
            url: &url::Url,
            body: Body<'_>,
        ) -> Result<T> {
            assert_eq!(url.as_str(), "https://atlas.example/api/native/themes");
            match body {
                Body::Public { failure } => Err(failure(self.0, b"untrusted response")),
                _ => panic!("Themes must not use authentication or token requests"),
            }
        }
    }

    #[test]
    fn old_servers_and_proxy_failures_never_become_oauth_credential_rejections() {
        for status in [401, 403, 404, 500, 501] {
            let failure = fetch_using(&OldServer(status), "https://atlas.example").unwrap_err();
            assert_eq!(
                failure.kind,
                if matches!(status, 404 | 501) {
                    "theme_unsupported"
                } else {
                    "theme_unavailable"
                }
            );
            assert!(!failure.message.contains("untrusted"));
        }
    }
}
