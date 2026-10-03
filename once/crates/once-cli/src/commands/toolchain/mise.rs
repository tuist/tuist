use std::collections::BTreeMap;
use std::io;
use std::path::Path;

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use super::contract::{fingerprint, ToolView, ToolchainContract};
use super::lock;
use super::platform;

const MISE_CONFIG: &str = "mise.toml";

#[derive(Debug, Default, Deserialize)]
struct MiseConfig {
    #[serde(default)]
    tools: BTreeMap<String, toml::Value>,
    #[serde(default)]
    env: BTreeMap<String, toml::Value>,
}

pub(super) fn inspect_workspace(
    workspace: &Path,
    requested_platform: Option<&str>,
) -> Result<ToolchainContract> {
    let config = read_mise_config(workspace)?;
    let platform = platform::requested(requested_platform)?;
    let lock = lock::read(workspace)?;

    let tools = config
        .tools
        .iter()
        .map(|(name, request)| ToolView {
            name: name.clone(),
            request: request.clone(),
            locked: lock
                .root
                .as_ref()
                .and_then(|root| lock::locked_tool(root, name, &platform.mise)),
        })
        .collect::<Vec<_>>();

    let fingerprint = fingerprint(&platform, &tools, &config.env)?;

    Ok(ToolchainContract {
        source: "mise",
        config: MISE_CONFIG.to_string(),
        lock: lock.present.then(|| lock::MISE_LOCK.to_string()),
        platform,
        tools,
        env: config.env,
        fingerprint,
    })
}

fn read_mise_config(workspace: &Path) -> Result<MiseConfig> {
    let path = workspace.join(MISE_CONFIG);
    let src = match std::fs::read_to_string(&path) {
        Ok(src) => src,
        Err(source) if source.kind() == io::ErrorKind::NotFound => {
            bail!("no {MISE_CONFIG} found at {}", path.display());
        }
        Err(source) => {
            return Err(source).with_context(|| format!("reading {}", path.display()));
        }
    };
    toml::from_str(&src).with_context(|| format!("parsing {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn inspect_reads_mise_tools_and_env() {
        let tmp = TempDir::new().unwrap();
        std::fs::write(
            tmp.path().join(MISE_CONFIG),
            r#"
[tools]
rust = "1.86"
shellspec = "latest"

[env]
RUST_BACKTRACE = "1"
"#,
        )
        .unwrap();

        let contract = inspect_workspace(tmp.path(), None).unwrap();

        assert_eq!(contract.source, "mise");
        assert_eq!(contract.config, MISE_CONFIG);
        assert_eq!(contract.lock, None);
        assert!(contract.fingerprint.starts_with("blake3:"));
        assert_eq!(contract.tools.len(), 2);
        assert_eq!(contract.tools[0].name, "rust");
        assert_eq!(contract.tools[0].request.as_str(), Some("1.86"));
        assert_eq!(
            contract
                .env
                .get("RUST_BACKTRACE")
                .and_then(toml::Value::as_str),
            Some("1")
        );
    }

    #[test]
    fn inspect_attaches_lockfile_versions_for_requested_platform() {
        let tmp = TempDir::new().unwrap();
        let platform = "linux-x64";
        std::fs::write(
            tmp.path().join(MISE_CONFIG),
            r#"
[tools]
rust = "1.86"
"#,
        )
        .unwrap();
        std::fs::write(
            tmp.path().join(lock::MISE_LOCK),
            format!(
                r#"
[[tools.rust]]
version = "1.86.0"
backend = "core:rust"

[tools.rust.platforms.{platform}]
checksum = "sha256:abc"
size = 123
url = "https://example.test/rust.tar.gz"
"#
            ),
        )
        .unwrap();

        let contract = inspect_workspace(tmp.path(), Some(platform)).unwrap();
        let locked = contract.tools[0].locked.as_ref().unwrap();

        assert_eq!(contract.platform.mise, platform);
        assert_eq!(contract.lock.as_deref(), Some(lock::MISE_LOCK));
        assert_eq!(locked.version, "1.86.0");
        assert_eq!(locked.backend.as_deref(), Some("core:rust"));
        assert_eq!(
            locked.platform.as_ref().and_then(|p| p.checksum.as_deref()),
            Some("sha256:abc")
        );
    }

    #[test]
    fn fingerprint_changes_when_tool_request_changes() {
        let tmp = TempDir::new().unwrap();
        std::fs::write(
            tmp.path().join(MISE_CONFIG),
            r#"
[tools]
rust = "1.86"
"#,
        )
        .unwrap();
        let before = inspect_workspace(tmp.path(), None).unwrap().fingerprint;

        std::fs::write(
            tmp.path().join(MISE_CONFIG),
            r#"
[tools]
rust = "1.87"
"#,
        )
        .unwrap();
        let after = inspect_workspace(tmp.path(), None).unwrap().fingerprint;

        assert_ne!(before, after);
    }
}
