use std::io;
use std::path::Path;

use anyhow::{Context, Result};

use super::contract::{LockedPlatformView, LockedToolView};

pub(super) const MISE_LOCK: &str = "mise.lock";

pub(super) struct MiseLock {
    pub root: Option<toml::Value>,
    pub present: bool,
}

pub(super) fn read(workspace: &Path) -> Result<MiseLock> {
    let path = workspace.join(MISE_LOCK);
    let src = match std::fs::read_to_string(&path) {
        Ok(src) => src,
        Err(source) if source.kind() == io::ErrorKind::NotFound => {
            return Ok(MiseLock {
                root: None,
                present: false,
            });
        }
        Err(source) => {
            return Err(source).with_context(|| format!("reading {}", path.display()));
        }
    };
    let root = toml::from_str(&src).with_context(|| format!("parsing {}", path.display()))?;
    Ok(MiseLock {
        root: Some(root),
        present: true,
    })
}

pub(super) fn locked_tool(
    root: &toml::Value,
    name: &str,
    platform_key: &str,
) -> Option<LockedToolView> {
    let records = root.get("tools")?.as_table()?.get(name)?.as_array()?;
    let record = records.first()?.as_table()?;

    let version = record.get("version")?.as_str()?.to_string();
    let backend = record
        .get("backend")
        .and_then(toml::Value::as_str)
        .map(ToOwned::to_owned);
    let platform = record
        .get("platforms")
        .and_then(toml::Value::as_table)
        .and_then(|platforms| platforms.get(platform_key))
        .and_then(toml::Value::as_table)
        .map(|table| LockedPlatformView {
            key: platform_key.to_string(),
            checksum: table
                .get("checksum")
                .and_then(toml::Value::as_str)
                .map(ToOwned::to_owned),
            size: table.get("size").and_then(toml::Value::as_integer),
            url: table
                .get("url")
                .and_then(toml::Value::as_str)
                .map(ToOwned::to_owned),
        });

    Some(LockedToolView {
        version,
        backend,
        platform,
    })
}
