//! Once manifest frontend.
//!
//! Loads declarative `once.toml` package files into a shared
//! [`Target`] IR. TOML keeps cacheable script declarations literal
//! and straightforward for humans and agents to patch.

mod cache_provider;
mod error;
mod manifest;
mod script;
mod target;
mod target_ref;
mod workspace;

/// The declarative per-package manifest file.
pub const TOML_BUILD_FILE_NAME: &str = "once.toml";

pub const BUILD_FILE_NAME: &str = TOML_BUILD_FILE_NAME;

pub use cache_provider::{
    CacheProviderConfig, NamedCacheProviderConfig, TuistCacheProviderConfig, DEFAULT_TUIST_URL,
};
pub use error::{Error, Result};
pub use manifest::{load_cache_provider_toml_str, load_toml_str};
pub use script::{parse_script_annotations, ScriptAnnotations};
pub use target::Target;
pub use target_ref::{
    absolutize, normalize_cli_target, normalize_cli_target_from, target_id, validate_target_name,
    TargetIdError,
};
pub use workspace::{load_cache_provider, load_cache_provider_override, load_file, load_workspace};
