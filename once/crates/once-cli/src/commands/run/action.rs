mod script;
mod task;

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use once_cas::Digest;
use once_core::{Action, InputDigestBuilder, WorkspacePath};

pub(super) struct ActionPlan {
    pub(super) action: Action,
    pub(super) output: String,
    pub(super) output_dir: Option<PathBuf>,
}

pub(super) fn action_for(workspace: &Path, target: &once_frontend::Target) -> Result<ActionPlan> {
    match target.kind.as_str() {
        "script" | "runtime_script" => script::script_action(workspace, target),
        "task" | "runtime_task" | "runner_task" => task::task_action(workspace, target),
        other => anyhow::bail!("running `{other}` targets is not yet supported"),
    }
}

fn parse_attr<T>(target: &once_frontend::Target, name: &str) -> Result<Option<T>>
where
    T: std::str::FromStr,
    T::Err: std::error::Error + Send + Sync + 'static,
{
    target
        .attrs
        .get(name)
        .map(|value| {
            value
                .parse::<T>()
                .with_context(|| format!("parsing {name} for {}", target.id()))
        })
        .transpose()
}

fn source_path(target: &once_frontend::Target, src: &str) -> Result<WorkspacePath> {
    WorkspacePath::from_package_relative(&target.package, src)
        .with_context(|| format!("invalid source path `{src}` in {}", target.id()))
}

fn input_digest(workspace: &Path, target: &once_frontend::Target) -> Result<Option<Digest>> {
    if target.srcs.is_empty() {
        return Ok(None);
    }

    let mut paths: Vec<_> = target
        .srcs
        .iter()
        .map(|src| source_path(target, src))
        .collect::<Result<_>>()?;
    paths.sort_by(|a, b| a.as_str().cmp(b.as_str()));

    let mut builder = InputDigestBuilder::new(b"");
    for path in paths {
        builder
            .push_source(workspace, path.as_str())
            .with_context(|| format!("hashing source input `{path}`"))?;
    }
    Ok(Some(builder.finish()))
}
