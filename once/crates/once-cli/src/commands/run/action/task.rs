use std::collections::BTreeMap;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use once_cas::Digest;
use once_core::{Action, OutputSymlinkMode, ResourceRequest, WorkspacePath};

use super::{input_digest, parse_attr, ActionPlan};

pub(super) fn task_action(workspace: &Path, target: &once_frontend::Target) -> Result<ActionPlan> {
    let cache = target
        .attrs
        .get("cache")
        .map_or(Ok(true), |raw| raw.parse::<bool>())
        .with_context(|| format!("parsing cache setting for task {}", target.id()))?;
    let input_digest = if cache {
        input_digest(workspace, target)?
    } else {
        Some(uncached_task_digest(target))
    };

    Ok(ActionPlan {
        action: Action::RunCommand {
            argv: task_argv(target)?,
            env: task_env(target)?,
            cwd: task_cwd(target)?,
            input_digest,
            outputs: task_outputs(target)?,
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: task_resources(target)?,
            timeout_ms: parse_attr::<u64>(target, "timeout_ms")?,
            remote: None,
        },
        output: String::new(),
        output_dir: None,
    })
}

fn task_argv(target: &once_frontend::Target) -> Result<Vec<String>> {
    let argv_json = target
        .attrs
        .get("argv_json")
        .ok_or_else(|| anyhow::anyhow!("task {} has no argv", target.id()))?;
    let argv: Vec<String> = serde_json::from_str(argv_json)
        .with_context(|| format!("parsing argv for task {}", target.id()))?;
    if argv.is_empty() {
        anyhow::bail!("task {} has empty argv", target.id());
    }
    Ok(argv)
}

fn task_env(target: &once_frontend::Target) -> Result<BTreeMap<String, String>> {
    match target.attrs.get("env_json") {
        Some(raw) => serde_json::from_str(raw)
            .with_context(|| format!("parsing env for task {}", target.id())),
        None => Ok(BTreeMap::new()),
    }
}

fn task_cwd(target: &once_frontend::Target) -> Result<Option<WorkspacePath>> {
    target
        .attrs
        .get("cwd")
        .map(|raw| {
            WorkspacePath::try_from(raw.as_str())
                .with_context(|| format!("invalid cwd for task {}", target.id()))
        })
        .transpose()
}

fn task_outputs(target: &once_frontend::Target) -> Result<Vec<WorkspacePath>> {
    let Some(raw) = target.attrs.get("outputs_json") else {
        return Ok(Vec::new());
    };
    serde_json::from_str::<Vec<String>>(raw)
        .with_context(|| format!("parsing outputs for task {}", target.id()))?
        .iter()
        .map(|value| {
            WorkspacePath::try_from(value.as_str())
                .with_context(|| format!("invalid output `{value}` in {}", target.id()))
        })
        .collect()
}

fn task_resources(target: &once_frontend::Target) -> Result<ResourceRequest> {
    let cpu_slots = parse_attr::<usize>(target, "cpu_slots")?.unwrap_or(1);
    let memory_bytes = parse_attr::<u64>(target, "memory_bytes")?.unwrap_or(0);
    Ok(ResourceRequest::new(cpu_slots, memory_bytes))
}

fn uncached_task_digest(target: &once_frontend::Target) -> Digest {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut buf = Vec::new();
    buf.extend_from_slice(b"once.task.uncached.v1\0");
    buf.extend_from_slice(target.id().as_bytes());
    buf.push(0);
    buf.extend_from_slice(&nonce.to_le_bytes());
    Digest::of_bytes(&buf)
}
