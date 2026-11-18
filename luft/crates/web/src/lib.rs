//! The Luft core for the web edge. Exports stay thin wrappers over core
//! operations, like the C and JNI bridges.

use wasm_bindgen::prelude::*;

/// The theme catalog, the same JSON `tuist_app_theme()` returns on Apple.
#[wasm_bindgen]
pub fn theme_catalog() -> String {
    tuist_app_core::theme::json().to_string_lossy().into_owned()
}
