//! Disk-side loaders for single manifests and recursive workspace scans.

use std::path::{Path, PathBuf};

use walkdir::WalkDir;

use crate::cache_provider::CacheProviderConfig;
use crate::error::{Error, Result};
use crate::manifest::{load_cache_provider_toml_str, load_toml_with};
use crate::target::Target;
use crate::TOML_BUILD_FILE_NAME;

/// Load a single manifest from disk and return its targets.
pub fn load_file(path: &Path) -> Result<Vec<Target>> {
    let display = path.display().to_string();
    let src = std::fs::read_to_string(path).map_err(|source| Error::Read {
        path: display.clone(),
        source,
    })?;
    let workspace_root = path
        .parent()
        .map_or_else(|| PathBuf::from("."), Path::to_path_buf);
    load_toml_with(&display, &src, &workspace_root, "")
}

/// Recursively scan `root` for `once.toml` files and return every
/// script-like target they declare.
pub fn load_workspace(root: &Path) -> Result<Vec<Target>> {
    let walker = WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| {
            if entry.depth() == 0 {
                return true;
            }
            entry
                .file_name()
                .to_str()
                .is_none_or(|name| !name.starts_with('.'))
        });
    let mut entries: Vec<(String, PathBuf)> = Vec::new();
    for entry in walker {
        let entry = entry.map_err(|source| Error::Walk {
            root: root.display().to_string(),
            source,
        })?;
        if entry.file_type().is_file() && is_manifest_file(entry.file_name().to_str()) {
            let parent = entry.path().parent().unwrap_or(root);
            let pkg = parent
                .strip_prefix(root)
                .unwrap_or(parent)
                .to_string_lossy()
                .replace(std::path::MAIN_SEPARATOR, "/");
            entries.push((pkg, entry.into_path()));
        }
    }
    entries.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));

    let mut all = Vec::new();
    for (pkg, path) in entries {
        let src = std::fs::read_to_string(&path).map_err(|source| Error::Read {
            path: path.display().to_string(),
            source,
        })?;
        let filename = path.file_name().unwrap().to_string_lossy();
        let display = if pkg.is_empty() {
            filename.to_string()
        } else {
            format!("{pkg}/{filename}")
        };
        let targets = load_toml_with(&display, &src, root, &pkg)?;
        all.extend(targets);
    }
    Ok(all)
}

/// Load the workspace-level cache provider config from the root
/// `once.toml`.
pub fn load_cache_provider_override(root: &Path) -> Result<Option<CacheProviderConfig>> {
    let path = root.join(TOML_BUILD_FILE_NAME);
    let src = match std::fs::read_to_string(&path) {
        Ok(src) => src,
        Err(source) if source.kind() == std::io::ErrorKind::NotFound => {
            return Ok(None);
        }
        Err(source) => {
            return Err(Error::Read {
                path: path.display().to_string(),
                source,
            });
        }
    };
    load_cache_provider_toml_str(TOML_BUILD_FILE_NAME, &src)
}

/// Load the workspace-level cache provider config from the root
/// `once.toml`. Missing files or missing config default to the local
/// on-disk provider.
pub fn load_cache_provider(root: &Path) -> Result<CacheProviderConfig> {
    Ok(load_cache_provider_override(root)?.unwrap_or(CacheProviderConfig::Local))
}

fn is_manifest_file(name: Option<&str>) -> bool {
    matches!(name, Some(TOML_BUILD_FILE_NAME))
}
