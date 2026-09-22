use std::collections::BTreeMap;

use anyhow::{Context, Result};
use once_cas::Digest;
use serde::Serialize;

use super::platform::PlatformView;

#[derive(Debug, Serialize)]
pub(super) struct ToolchainContract {
    pub source: &'static str,
    pub config: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lock: Option<String>,
    pub platform: PlatformView,
    pub tools: Vec<ToolView>,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub env: BTreeMap<String, toml::Value>,
    pub fingerprint: String,
}

#[derive(Debug, Serialize)]
pub(super) struct ToolView {
    pub name: String,
    pub request: toml::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub locked: Option<LockedToolView>,
}

#[derive(Debug, Serialize)]
pub(super) struct LockedToolView {
    pub version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backend: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub platform: Option<LockedPlatformView>,
}

#[derive(Debug, Serialize)]
pub(super) struct LockedPlatformView {
    pub key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checksum: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

pub(super) fn fingerprint(
    platform: &PlatformView,
    tools: &[ToolView],
    env: &BTreeMap<String, toml::Value>,
) -> Result<String> {
    #[derive(Serialize)]
    struct Material<'a> {
        source: &'static str,
        platform: &'a PlatformView,
        tools: &'a [ToolView],
        env: &'a BTreeMap<String, toml::Value>,
    }

    let material = Material {
        source: "mise",
        platform,
        tools,
        env,
    };
    let bytes = serde_json::to_vec(&material).context("serializing toolchain fingerprint input")?;
    Ok(format!("blake3:{}", Digest::of_bytes(&bytes)))
}
