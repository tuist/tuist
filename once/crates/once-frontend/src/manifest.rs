//! TOML frontend for workspace configuration.

use std::path::Path;

use serde::Deserialize;

use crate::cache_provider::{CacheProviderToml, InfrastructureToml};
use crate::error::{Error, Result};
use crate::target::Target;

#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Manifest {
    infrastructure: InfrastructureToml,
    cache_provider: Option<CacheProviderToml>,
}

pub fn load_toml_str(path: &str, src: &str) -> Result<Vec<Target>> {
    load_toml_with(path, src, Path::new("."), "")
}

pub(crate) fn load_toml_with(
    display_name: &str,
    src: &str,
    _workspace_root: &Path,
    _package: &str,
) -> Result<Vec<Target>> {
    let _manifest: Manifest = toml::from_str(src).map_err(|source| Error::Parse {
        path: display_name.to_string(),
        message: source.to_string(),
    })?;
    Ok(Vec::new())
}

pub fn load_cache_provider_toml_str(
    path: &str,
    src: &str,
) -> Result<Option<crate::cache_provider::CacheProviderConfig>> {
    let manifest: Manifest = toml::from_str(src).map_err(|source| Error::Parse {
        path: path.to_string(),
        message: source.to_string(),
    })?;
    if let Some(raw) = manifest.infrastructure.cache {
        return raw.into_config(path).map(Some);
    }
    manifest
        .cache_provider
        .map(|raw| raw.into_config(path))
        .transpose()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_config_does_not_declare_targets() {
        let targets = load_toml_str("once.toml", "").unwrap();
        assert!(targets.is_empty());
    }

    #[test]
    fn rejects_script_declarations() {
        let src = r#"
[[script]]
name = "hello"
argv = ["sh", "-c", "printf hello"]
"#;
        let err = load_toml_str("once.toml", src).unwrap_err().to_string();
        assert!(err.contains("unknown field `script`"));
    }
}
