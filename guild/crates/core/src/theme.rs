//! Noora's semantic colors, the design tokens the server's components use.
//! Every client draws with these, so a change to `noora/css/tokens.css`
//! reaches them all through `noora_tokens.py`.
use core::ffi::{CStr, c_char};
use std::ffi::CString;
use std::sync::OnceLock;

mod noora;
pub use noora::TOKENS;

/// A token's color for the appearance, packed 0xRRGGBB sRGB.
pub fn color(name: &str, dark: bool) -> Option<u32> {
    TOKENS
        .iter()
        .find(|(token, _, _)| *token == name)
        .map(|(_, light, night)| if dark { *night } else { *light })
}

/// `{"light":{"<token>":"#rrggbb",…},"dark":{…}}`, for the native edges.
pub fn json() -> &'static CStr {
    static JSON: OnceLock<CString> = OnceLock::new();
    JSON.get_or_init(|| {
        let appearance = |dark: bool| {
            TOKENS
                .iter()
                .map(|(name, light, night)| {
                    let value = if dark { night } else { light };
                    (name.to_string(), format!("#{value:06x}").into())
                })
                .collect::<serde_json::Map<_, _>>()
        };
        let value = serde_json::json!({"light": appearance(false), "dark": appearance(true)});
        CString::new(value.to_string()).expect("tokens contain no NUL")
    })
}

/// The immutable process-lifetime theme JSON; never free it.
#[unsafe(no_mangle)]
pub extern "C" fn tuist_app_theme() -> *const c_char {
    json().as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn edges_receive_every_token_for_both_appearances() {
        let value: serde_json::Value = serde_json::from_str(json().to_str().unwrap()).unwrap();
        for (name, light, dark) in TOKENS {
            assert_eq!(value["light"][name], format!("#{light:06x}"));
            assert_eq!(value["dark"][name], format!("#{dark:06x}"));
        }
        // Spot-check the conversion against Noora's purple-500 and neutral-light-50.
        assert_eq!(color("button-primary-background", false), Some(0x7339ff));
        assert_eq!(color("surface-background-primary", false), Some(0xfdfdfd));
        assert_eq!(color("surface-background-primary", true), Some(0x0e0e0e));
        assert_eq!(color("missing", true), None);
    }
}
