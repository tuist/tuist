use std::collections::BTreeMap;
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

use super::{
    path::{build_action_path, stable_system_path},
    select_extra_env, tool_env,
};

/// Resolve `tool` through the workspace's mise config when one exists.
///
/// Workspaces without `mise.toml` keep the historical behavior and
/// return the tool name so the runner resolves it through the declared
/// action `PATH`.
pub fn workspace_tool(workspace: &Path, tool: &str) -> Result<String, ToolEnvError> {
    if !has_mise_config(workspace) {
        return Ok(tool.to_string());
    }
    let output = Command::new("mise")
        .args(["which", "-C"])
        .arg(workspace)
        .arg(tool)
        .output()
        .map_err(|source| ToolEnvError::SpawnMise { source })?;
    if !output.status.success() {
        let error = ToolEnvError::MiseFailed {
            command: format!("mise which {tool}"),
            status: output.status.code().unwrap_or(-1),
            stderr: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        };
        if let Some(host_tool) = stable_host_tool(tool) {
            return Ok(host_tool);
        }
        return Err(error);
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Build an action environment from the workspace's pinned mise
/// toolchain when `mise.toml` is present.
///
/// The returned `PATH` is not copied from the parent shell. It contains
/// only the directories for tools Once explicitly needs plus stable
/// system directories for linker/shell helpers. Workspaces without
/// `mise.toml` fall back to the historical allowlist policy.
pub fn workspace_tool_env(
    workspace: &Path,
    tools: &[&str],
    extra_keys: &[&str],
) -> Result<BTreeMap<String, String>, ToolEnvError> {
    if !has_mise_config(workspace) {
        return Ok(tool_env(extra_keys));
    }

    let mise_env = mise_env(workspace)?;
    let mut selected = select_extra_env(&mise_env, extra_keys);
    let path = workspace_path(workspace, tools, &mise_env)?;
    selected.insert("PATH".into(), path);
    Ok(selected)
}

/// Read one variable from the workspace's pinned toolchain environment.
///
/// This is used for cache-key material such as `RUSTUP_TOOLCHAIN`, so
/// invoking Once outside `mise exec` still keys actions on the same
/// toolchain that execution will use.
pub fn workspace_tool_var(workspace: &Path, key: &str) -> Result<Option<String>, ToolEnvError> {
    if !has_mise_config(workspace) {
        return Ok(env::var(key).ok());
    }
    Ok(mise_env(workspace)?.remove(key))
}

fn has_mise_config(workspace: &Path) -> bool {
    workspace.join("mise.toml").is_file()
}

fn stable_host_tool(tool: &str) -> Option<String> {
    stable_system_path()
        .into_iter()
        .map(|dir| dir.join(tool))
        .find(|path| is_executable(path))
        .map(|path| path.to_string_lossy().into_owned())
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;

    path.is_file()
        && path
            .metadata()
            .is_ok_and(|metadata| metadata.permissions().mode() & 0o111 != 0)
}

#[cfg(windows)]
fn is_executable(path: &Path) -> bool {
    if path.is_file() {
        return true;
    }
    ["exe", "bat", "cmd"]
        .iter()
        .map(|extension| path.with_extension(extension))
        .any(|path| path.is_file())
}

fn mise_env(workspace: &Path) -> Result<BTreeMap<String, String>, ToolEnvError> {
    let output = Command::new("mise")
        .args(["env", "--json", "-C"])
        .arg(workspace)
        .output()
        .map_err(|source| ToolEnvError::SpawnMise { source })?;
    if !output.status.success() {
        return Err(ToolEnvError::MiseFailed {
            command: "mise env --json".to_string(),
            status: output.status.code().unwrap_or(-1),
            stderr: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        });
    }
    serde_json::from_slice(&output.stdout).map_err(|source| ToolEnvError::ParseMiseEnv { source })
}

fn workspace_path(
    workspace: &Path,
    tools: &[&str],
    mise_env: &BTreeMap<String, String>,
) -> Result<String, ToolEnvError> {
    let tool_paths = tools
        .iter()
        .map(|tool| workspace_tool(workspace, tool).map(PathBuf::from))
        .collect::<Result<Vec<_>, _>>()?;
    build_action_path(&tool_paths, mise_env)
}

#[derive(Debug, thiserror::Error)]
pub enum ToolEnvError {
    #[error("failed to spawn mise: {source}")]
    SpawnMise {
        #[source]
        source: std::io::Error,
    },
    #[error("{command} failed with exit {status}: {stderr}")]
    MiseFailed {
        command: String,
        status: i32,
        stderr: String,
    },
    #[error("failed to parse mise environment JSON: {source}")]
    ParseMiseEnv {
        #[source]
        source: serde_json::Error,
    },
    #[error("failed to build action PATH: {source}")]
    JoinPath {
        #[source]
        source: env::JoinPathsError,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_without_mise_keeps_legacy_env_policy() {
        let tmp = tempfile::TempDir::new().unwrap();
        let env = workspace_tool_env(tmp.path(), &["rustc"], &["RUSTUP_TOOLCHAIN"]).unwrap();
        assert_eq!(env, tool_env(&["RUSTUP_TOOLCHAIN"]));
        assert_eq!(workspace_tool(tmp.path(), "rustc").unwrap(), "rustc");
    }

    #[cfg(unix)]
    #[test]
    fn stable_host_tool_resolves_system_shells() {
        assert!(stable_host_tool("sh").is_some());
    }
}
