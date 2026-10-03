//! `once exec` - cache and execute a literal command or script file.
//!
//! Substrate-level escape hatch: bypass the target graph and put any
//! argv through the action cache. Useful for ad-hoc shell-outs and for
//! exercising the cache directly. With `--script`, or when argv looks
//! like `<runtime> <script> [args...]` and the file carries `once`
//! headers, Once treats argv as a script execution request.
//!
//! Stdout always carries the wrapped program's stdout verbatim
//! (transparency), regardless of `--format`. Stderr carries the
//! wrapped program's stderr plus a Once trailer; the trailer's
//! shape is human-readable by default and structured under `json` or
//! `toon`.

use std::collections::BTreeMap;
use std::env;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result};
use once_cas::{CacheProvider, Digest};
use once_core::{
    tool_env, workspace_tool, workspace_tool_env, Action, CacheState, InputDigestBuilder,
    OutputSymlinkMode, RemoteExecution, ResourceRequest, RunOpts, WorkspacePath,
};
use once_frontend::{parse_script_annotations, ScriptAnnotations};
use serde::Serialize;
use tokio::io::AsyncWriteExt;

use crate::cli::{exit_from, Format, Output};
use crate::commands::util::{cache_tag, relative_path};
use crate::render;

const MAX_SCRIPT_GLOB_MATCHES: usize = 1_000;

#[derive(Serialize)]
struct ExecTrailer<'a> {
    action_digest: String,
    cache: &'a str,
    exit_code: i32,
}

/// Inputs to [`exec`], grouped so the function signature stays
/// readable as the verb gains options. Owned types: the call site
/// builds these from clap and hands them over.
pub struct ExecArgs {
    pub script: bool,
    pub env: Vec<(String, String)>,
    pub cwd: Option<WorkspacePath>,
    pub timeout_ms: Option<u64>,
    pub cache_failures: bool,
    pub remote: Option<String>,
    pub argv: Vec<String>,
}

struct ScriptInvocation {
    workspace: PathBuf,
    runtime: String,
    runtime_args: Vec<String>,
    script_path: WorkspacePath,
    script_args: Vec<String>,
    cwd: WorkspacePath,
    env: BTreeMap<String, String>,
    outputs: Vec<WorkspacePath>,
    output_symlink_mode: OutputSymlinkMode,
    input_digest: Option<Digest>,
    timeout_ms: Option<u64>,
    remote: Option<RemoteExecution>,
}

pub async fn exec(
    workspace: &Path,
    cache: &CacheProvider,
    args: ExecArgs,
    output: Output,
) -> Result<ExitCode> {
    let ExecArgs {
        script,
        env,
        cwd,
        timeout_ms,
        cache_failures,
        remote,
        argv,
    } = args;

    let (workspace, action) = if script {
        script_action(workspace, env, cwd, timeout_ms, remote.as_deref(), &argv)?
    } else if let Some(plan) = autodetected_script_action(
        workspace,
        env.clone(),
        cwd.clone(),
        timeout_ms,
        remote.as_deref(),
        &argv,
    )? {
        plan
    } else {
        (
            workspace.to_path_buf(),
            Action::RunCommand {
                argv,
                env: env.into_iter().collect::<BTreeMap<_, _>>(),
                cwd,
                input_digest: None,
                outputs: vec![],
                output_symlink_mode: OutputSymlinkMode::default(),
                resources: ResourceRequest::default(),
                timeout_ms,
                remote: remote_execution(remote.as_deref()),
            },
        )
    };

    let opts = RunOpts { cache_failures };
    let streams_live = action_remote(&action).is_some() && output.format == Format::Human;
    let outcome = if streams_live {
        once_core::run_with_cache_streaming(&action, &workspace, cache, opts)
            .await
            .context("executing action")?
    } else {
        once_core::run_with_cache(&action, &workspace, cache, opts)
            .await
            .context("executing action")?
    };

    let stdout = match outcome.result.stdout {
        Some(digest) => cache.get_blob(&digest).await?,
        None => Vec::new(),
    };
    let stderr = match outcome.result.stderr {
        Some(digest) => cache.get_blob(&digest).await?,
        None => Vec::new(),
    };
    // tokio::io::stdout/stderr are line-buffered. Flush explicitly so
    // the bytes reach the pipe before the process exits; without this,
    // captured output is empty under timing pressure (we observed this
    // as flaky shellspec failures on macOS CI).
    let mut out = tokio::io::stdout();
    let streamed_now = streams_live && outcome.cache == CacheState::Miss;
    if !streamed_now {
        out.write_all(&stdout).await?;
    }
    // Flush explicitly so the wrapped stdout is visible before the
    // Once stderr trailer, even under macOS CI timing pressure.
    out.flush().await?;
    let mut err = tokio::io::stderr();
    if !streamed_now {
        err.write_all(&stderr).await?;
    }

    let tag = cache_tag(outcome.cache);
    let trailer = ExecTrailer {
        action_digest: outcome.action.to_string(),
        cache: tag,
        exit_code: outcome.result.exit_code,
    };
    let trailer = match output.format {
        Format::Human => {
            if output.quiet {
                String::new()
            } else {
                format!(
                    "once: cache {tag} action={} exit={}\n",
                    outcome.action, outcome.result.exit_code
                )
            }
        }
        Format::Json | Format::Toon => render::structured(output.format, &trailer)?,
    };
    if !trailer.is_empty() {
        err.write_all(trailer.as_bytes()).await?;
    }
    err.flush().await?;

    Ok(exit_from(outcome.result.exit_code))
}

fn script_action(
    workspace: &Path,
    explicit_env: Vec<(String, String)>,
    cwd_override: Option<WorkspacePath>,
    timeout_ms_override: Option<u64>,
    remote_override: Option<&str>,
    argv: &[String],
) -> Result<(PathBuf, Action)> {
    let invocation = script_invocation(
        workspace,
        explicit_env.into_iter().collect(),
        cwd_override,
        timeout_ms_override,
        remote_override,
        argv,
    )?;
    let program = resolve_runtime(&invocation.workspace, &invocation.runtime)?;
    let mut argv = vec![program];
    argv.extend(invocation.runtime_args);
    argv.push(host_script_path(
        invocation.script_path.as_str(),
        Some(&invocation.cwd),
    )?);
    argv.extend(invocation.script_args);

    Ok((
        invocation.workspace,
        Action::RunCommand {
            argv,
            env: invocation.env,
            cwd: Some(invocation.cwd),
            input_digest: invocation.input_digest,
            outputs: invocation.outputs,
            output_symlink_mode: invocation.output_symlink_mode,
            resources: ResourceRequest::default(),
            timeout_ms: invocation.timeout_ms,
            remote: invocation.remote,
        },
    ))
}

fn remote_execution(provider: Option<&str>) -> Option<RemoteExecution> {
    provider.map(|provider| RemoteExecution {
        provider: provider.to_string(),
    })
}

fn action_remote(action: &Action) -> Option<&RemoteExecution> {
    match action {
        Action::RunCommand { remote, .. } => remote.as_ref(),
    }
}

fn autodetected_script_action(
    workspace: &Path,
    explicit_env: Vec<(String, String)>,
    cwd_override: Option<WorkspacePath>,
    timeout_ms_override: Option<u64>,
    remote_override: Option<&str>,
    argv: &[String],
) -> Result<Option<(PathBuf, Action)>> {
    let Ok((_, _, script_arg, _)) = parse_script_exec_argv(workspace, argv) else {
        return Ok(None);
    };
    let Ok(script_abs) = resolve_script_abs(workspace, script_arg) else {
        return Ok(None);
    };
    let Ok(annotations) = parse_script_annotations(&script_abs, script_arg) else {
        return Ok(None);
    };
    if !has_once_annotations(&annotations) {
        return Ok(None);
    }
    script_action(
        workspace,
        explicit_env,
        cwd_override,
        timeout_ms_override,
        remote_override,
        argv,
    )
    .map(Some)
}

fn script_invocation(
    workspace: &Path,
    explicit_env: BTreeMap<String, String>,
    cwd_override: Option<WorkspacePath>,
    timeout_ms_override: Option<u64>,
    remote_override: Option<&str>,
    argv: &[String],
) -> Result<ScriptInvocation> {
    let (runtime, runtime_args, script_arg, script_args) = parse_script_exec_argv(workspace, argv)?;
    let script_abs = resolve_script_abs(workspace, script_arg)?;
    let annotations = parse_script_annotations(&script_abs, script_arg)
        .with_context(|| format!("parsing once headers for `{script_arg}`"))?;
    let workspace =
        resolve_script_workspace(workspace, &script_abs, &annotations, cwd_override.as_ref())?;
    let script_path = workspace_path_for_file(&workspace, &script_abs)?;
    if annotations.runtime != runtime {
        anyhow::bail!(
            "script `{}` declares runtime `{}` in its shebang, but the command used `{}`; invoke it with the shebang runtime, for example `once exec -- {} {}`, or update the shebang",
            script_path,
            annotations.runtime,
            runtime,
            annotations.runtime,
            script_path
        );
    }
    let merged_runtime_args = merge_runtime_args(&annotations.runtime_args, runtime_args);
    let script_dir = parent_workspace_path(&script_path)?;
    let mut inputs = resolve_script_inputs(&workspace, &script_dir, &annotations.inputs)?;
    if !inputs.iter().any(|input| input == &script_path) {
        inputs.push(script_path.clone());
    }
    inputs.sort_by(|a, b| a.as_str().cmp(b.as_str()));
    inputs.dedup();

    let outputs = resolve_script_outputs(&script_dir, &annotations.outputs)?;
    let cwd = match cwd_override {
        Some(cwd) => cwd,
        None => resolve_script_cwd(&script_dir, annotations.cwd.as_deref())?,
    };
    let input_digest = Some(script_input_digest(&workspace, &inputs)?);
    let timeout_ms = timeout_ms_override;
    let env = script_env(&workspace, &runtime, &annotations.env_vars, explicit_env)?;
    let remote = remote_execution(remote_override.or(annotations.remote.as_deref()));
    let output_symlink_mode = output_symlink_mode(annotations.output_symlinks.as_deref())?;

    Ok(ScriptInvocation {
        workspace,
        runtime: runtime.to_string(),
        runtime_args: merged_runtime_args,
        script_path,
        script_args,
        cwd,
        env,
        outputs,
        output_symlink_mode,
        input_digest,
        timeout_ms,
        remote,
    })
}

fn parse_script_exec_argv<'a>(
    workspace: &Path,
    argv: &'a [String],
) -> Result<(String, &'a [String], &'a str, Vec<String>)> {
    let Some((runtime, rest)) = argv.split_first() else {
        anyhow::bail!("`once exec --script` expects `<runtime> <script> [args...]`");
    };
    if rest.is_empty() {
        anyhow::bail!("`once exec --script` expects `<runtime> <script> [args...]`");
    }
    let mut script_idx = None;
    let mut candidate_error = None;
    for (index, value) in rest.iter().enumerate() {
        match script_file_candidate(workspace, value) {
            Ok(candidate) if candidate.is_file() => {
                script_idx = Some(index);
                break;
            }
            Ok(_) => {}
            Err(err) => {
                candidate_error.get_or_insert(err);
            }
        }
    }
    let Some(script_idx) = script_idx else {
        if let Some(err) = candidate_error {
            return Err(err);
        }
        anyhow::bail!(
            "`once exec --script` could not find a script file in `<runtime> <script> [args...]`"
        );
    };
    let script_arg = rest[script_idx].as_str();
    let runtime_args = &rest[..script_idx];
    let script_args = rest[script_idx + 1..].to_vec();
    Ok((runtime.clone(), runtime_args, script_arg, script_args))
}

fn script_file_candidate(workspace: &Path, value: &str) -> Result<PathBuf> {
    if Path::new(value).is_absolute() {
        Ok(PathBuf::from(value))
    } else {
        let ws_path = WorkspacePath::try_from(value).with_context(|| {
            format!("script path `{value}` must stay within the selected workspace")
        })?;
        Ok(ws_path.resolve(workspace))
    }
}

fn resolve_script_abs(workspace: &Path, script_arg: &str) -> Result<PathBuf> {
    let candidate = script_file_candidate(workspace, script_arg)?;
    std::fs::canonicalize(&candidate)
        .with_context(|| format!("resolving script path `{script_arg}`"))
}

fn resolve_script_workspace(
    workspace: &Path,
    script_abs: &Path,
    annotations: &ScriptAnnotations,
    cwd_override: Option<&WorkspacePath>,
) -> Result<PathBuf> {
    let canonical_workspace =
        std::fs::canonicalize(workspace).context("canonicalizing workspace root")?;
    if script_abs.starts_with(&canonical_workspace) {
        return Ok(canonical_workspace);
    }
    if cwd_override.is_some() {
        anyhow::bail!(
            "script `{}` is outside workspace `{}`; pass `-C` to select the workspace explicitly",
            script_abs.display(),
            canonical_workspace.display()
        );
    }
    infer_script_workspace(script_abs, annotations)
}

fn infer_script_workspace(script_abs: &Path, annotations: &ScriptAnnotations) -> Result<PathBuf> {
    let script_dir = script_abs.parent().ok_or_else(|| {
        anyhow::anyhow!("script `{}` has no parent directory", script_abs.display())
    })?;
    let mut ancestor = lexical_normalize(script_dir);
    for raw in &annotations.inputs {
        ancestor = shared_ancestor(ancestor, &annotation_anchor(script_dir, raw))?;
    }
    for raw in &annotations.outputs {
        ancestor = shared_ancestor(ancestor, &annotation_anchor(script_dir, raw))?;
    }
    if let Some(raw) = annotations.cwd.as_deref() {
        ancestor = shared_ancestor(ancestor, &annotation_anchor(script_dir, raw))?;
    }
    Ok(ancestor)
}

fn annotation_anchor(script_dir: &Path, raw: &str) -> PathBuf {
    let mut anchor = PathBuf::from(script_dir);
    let mut saw_component = false;
    for component in Path::new(raw).components() {
        let text = component.as_os_str().to_string_lossy();
        if has_glob(&text) {
            break;
        }
        saw_component = true;
        anchor.push(component.as_os_str());
    }
    if !saw_component {
        return lexical_normalize(script_dir);
    }
    lexical_normalize(&anchor)
}

fn lexical_normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

fn shared_ancestor(mut left: PathBuf, right: &Path) -> Result<PathBuf> {
    let right = lexical_normalize(right);
    while !right.starts_with(&left) {
        if !left.pop() {
            anyhow::bail!(
                "could not infer a workspace root that contains both `{}` and `{}`",
                left.display(),
                right.display()
            );
        }
    }
    Ok(left)
}

fn workspace_path_for_file(workspace: &Path, abs: &Path) -> Result<WorkspacePath> {
    let workspace = std::fs::canonicalize(workspace).context("canonicalizing workspace root")?;
    let rel = abs
        .strip_prefix(&workspace)
        .with_context(|| format!("script `{}` is outside the workspace", abs.display()))?
        .to_string_lossy()
        .replace(std::path::MAIN_SEPARATOR, "/");
    WorkspacePath::try_from(rel).context("normalizing script path")
}

fn parent_workspace_path(path: &WorkspacePath) -> Result<WorkspacePath> {
    let parent = Path::new(path.as_str())
        .parent()
        .map(|parent| {
            parent
                .to_string_lossy()
                .replace(std::path::MAIN_SEPARATOR, "/")
        })
        .filter(|parent| !parent.is_empty() && parent != ".")
        .unwrap_or_default();
    WorkspacePath::try_from(parent).context("normalizing script parent")
}

fn normalize_from_script_dir(script_dir: &WorkspacePath, raw: &str) -> Result<WorkspacePath> {
    let mut parts = script_dir
        .as_str()
        .split('/')
        .filter(|part| !part.is_empty())
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    for component in Path::new(raw).components() {
        match component {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                if parts.pop().is_none() {
                    anyhow::bail!("workspace path must not escape the workspace");
                }
            }
            std::path::Component::Normal(part) => {
                parts.push(part.to_string_lossy().into_owned());
            }
            std::path::Component::RootDir | std::path::Component::Prefix(_) => {
                anyhow::bail!("workspace path must be relative");
            }
        }
    }
    WorkspacePath::try_from(parts.join("/"))
        .with_context(|| format!("normalizing script path `{raw}`"))
}

fn resolve_script_inputs(
    workspace: &Path,
    script_dir: &WorkspacePath,
    inputs: &[String],
) -> Result<Vec<WorkspacePath>> {
    let mut out = Vec::new();
    for input in inputs {
        if has_glob(input) {
            let mut expanded = expand_script_globs(workspace, script_dir, input)?;
            out.append(&mut expanded);
            continue;
        }
        let ws_path = normalize_from_script_dir(script_dir, input)?;
        let abs = ws_path.resolve(workspace);
        if abs.is_dir() {
            for entry in walkdir::WalkDir::new(&abs)
                .into_iter()
                .filter_map(std::result::Result::ok)
            {
                if !entry.file_type().is_file() {
                    continue;
                }
                out.push(workspace_path_for_file(workspace, entry.path())?);
            }
        } else {
            out.push(ws_path);
        }
    }
    out.sort_by(|a, b| a.as_str().cmp(b.as_str()));
    out.dedup();
    Ok(out)
}

fn resolve_script_outputs(
    script_dir: &WorkspacePath,
    outputs: &[String],
) -> Result<Vec<WorkspacePath>> {
    outputs
        .iter()
        .map(|output| normalize_from_script_dir(script_dir, output))
        .collect()
}

fn resolve_script_cwd(script_dir: &WorkspacePath, raw: Option<&str>) -> Result<WorkspacePath> {
    raw.map_or_else(
        || Ok(script_dir.clone()),
        |raw| normalize_from_script_dir(script_dir, raw),
    )
}

fn expand_script_globs(
    workspace: &Path,
    script_dir: &WorkspacePath,
    pattern: &str,
) -> Result<Vec<WorkspacePath>> {
    expand_script_globs_with_limit(workspace, script_dir, pattern, MAX_SCRIPT_GLOB_MATCHES)
}

fn expand_script_globs_with_limit(
    workspace: &Path,
    script_dir: &WorkspacePath,
    pattern: &str,
    limit: usize,
) -> Result<Vec<WorkspacePath>> {
    let abs_pattern = script_dir.resolve(workspace).join(pattern);
    let pattern_str = abs_pattern
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("non-utf8 glob pattern: {}", abs_pattern.display()))?;
    let mut out = Vec::new();
    for entry in
        glob::glob(pattern_str).with_context(|| format!("invalid glob pattern `{pattern}`"))?
    {
        let path = entry.with_context(|| format!("glob walk failed for `{pattern}`"))?;
        if !path.is_file() {
            continue;
        }
        out.push(workspace_path_for_file(
            workspace,
            &std::fs::canonicalize(&path)?,
        )?);
        if out.len() > limit {
            anyhow::bail!(
                "glob `{pattern}` matched more than {limit} files; narrow the pattern before running it through `once exec`"
            );
        }
    }
    out.sort_by(|a, b| a.as_str().cmp(b.as_str()));
    out.dedup();
    Ok(out)
}

fn has_glob(value: &str) -> bool {
    value.contains('*') || value.contains('?') || value.contains('[')
}

fn has_once_annotations(annotations: &ScriptAnnotations) -> bool {
    !annotations.inputs.is_empty()
        || !annotations.outputs.is_empty()
        || !annotations.env_vars.is_empty()
        || annotations.cwd.is_some()
        || annotations.remote.is_some()
        || annotations.output_symlinks.is_some()
}

fn output_symlink_mode(raw: Option<&str>) -> Result<OutputSymlinkMode> {
    raw.unwrap_or("materialize-external")
        .parse()
        .map_err(anyhow::Error::msg)
        .context("parsing output-symlinks")
}

fn script_input_digest(workspace: &Path, inputs: &[WorkspacePath]) -> Result<Digest> {
    let mut builder = InputDigestBuilder::new(b"once.exec.script.input.v1\0");
    for input in inputs {
        builder
            .push_source(workspace, input.as_str())
            .with_context(|| format!("hashing script input `{input}`"))?;
    }
    Ok(builder.finish())
}

fn merge_runtime_args(parsed: &[String], explicit: &[String]) -> Vec<String> {
    if parsed == explicit {
        return parsed.to_vec();
    }
    let mut out = parsed.to_vec();
    out.extend(explicit.iter().cloned());
    out
}

fn script_env(
    workspace: &Path,
    runtime: &str,
    env_vars: &[String],
    explicit_env: BTreeMap<String, String>,
) -> Result<BTreeMap<String, String>> {
    let env_keys = env_vars.iter().map(String::as_str).collect::<Vec<_>>();
    let mut out = if runtime.contains('/') {
        tool_env(&env_keys)
    } else {
        workspace_tool_env(workspace, &[runtime], &env_keys)
            .with_context(|| format!("building tool environment for script runtime `{runtime}`"))?
    };
    for name in env_vars {
        if let Ok(value) = env::var(name) {
            out.insert(name.clone(), value);
        }
    }
    for (key, value) in explicit_env {
        out.insert(key, value);
    }
    Ok(out)
}

fn resolve_runtime(workspace: &Path, runtime: &str) -> Result<String> {
    if runtime.contains('/') {
        return Ok(runtime.to_string());
    }
    workspace_tool(workspace, runtime)
        .with_context(|| format!("resolving script runtime `{runtime}`"))
}

fn host_script_path(script_path: &str, cwd: Option<&WorkspacePath>) -> Result<String> {
    let script = WorkspacePath::try_from(script_path)
        .with_context(|| format!("invalid script path `{script_path}`"))?;
    let Some(cwd) = cwd else {
        return Ok(script.as_str().to_string());
    };
    Ok(relative_path(cwd.as_str(), script.as_str()))
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::TempDir;

    use super::*;

    #[test]
    fn finds_script_after_runtime_args() {
        let tmp = TempDir::new().unwrap();
        let script = tmp.path().join("scripts").join("build.py");
        fs::create_dir_all(script.parent().unwrap()).unwrap();
        fs::write(&script, "#!/usr/bin/env python3\nprint('hi')\n").unwrap();

        let argv = vec![
            "python3".to_string(),
            "-O".to_string(),
            "scripts/build.py".to_string(),
            "--flag".to_string(),
        ];

        let (runtime, runtime_args, script_arg, script_args) =
            parse_script_exec_argv(tmp.path(), &argv).unwrap();

        assert_eq!(runtime, "python3");
        assert_eq!(runtime_args, &["-O".to_string()]);
        assert_eq!(script_arg, "scripts/build.py");
        assert_eq!(script_args, vec!["--flag".to_string()]);
    }

    #[test]
    fn computes_relative_paths_from_cwd_to_script() {
        assert_eq!(relative_path("scripts", "scripts/build.sh"), "build.sh");
        assert_eq!(
            relative_path("tools/gen", "scripts/build.sh"),
            "../../scripts/build.sh"
        );
        assert_eq!(relative_path("", "scripts/build.sh"), "scripts/build.sh");
    }

    #[test]
    fn normalizes_script_relative_paths_before_workspace_validation() {
        let script_dir = WorkspacePath::try_from("scripts").unwrap();

        let input = normalize_from_script_dir(&script_dir, "../input.txt").unwrap();
        assert_eq!(input.as_str(), "input.txt");

        let err = normalize_from_script_dir(&script_dir, "../../escape.txt").unwrap_err();
        assert!(
            err.to_string().contains("must not escape the workspace"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn autodetects_annotated_scripts_without_script_flag() {
        let tmp = TempDir::new().unwrap();
        let script = tmp.path().join("scripts").join("build.sh");
        fs::create_dir_all(script.parent().unwrap()).unwrap();
        fs::write(
            &script,
            "#!/bin/bash\n# once input \"../input.txt\"\ncat ../input.txt\n",
        )
        .unwrap();
        fs::write(tmp.path().join("input.txt"), "hello\n").unwrap();

        let plan = autodetected_script_action(
            tmp.path(),
            Vec::new(),
            None,
            None,
            None,
            &["/bin/bash".to_string(), "scripts/build.sh".to_string()],
        )
        .unwrap()
        .expect("annotated script should be autodetected");

        match plan.1 {
            Action::RunCommand {
                argv,
                cwd,
                input_digest,
                ..
            } => {
                assert_eq!(argv, vec!["/bin/bash".to_string(), "build.sh".to_string()]);
                assert_eq!(cwd.unwrap().as_str(), "scripts");
                assert!(input_digest.is_some());
            }
        }
    }

    #[test]
    fn script_annotation_sets_output_symlink_mode() {
        let tmp = TempDir::new().unwrap();
        let script = tmp.path().join("scripts").join("build.sh");
        fs::create_dir_all(script.parent().unwrap()).unwrap();
        fs::write(
            &script,
            "#!/bin/bash\n# once output-symlinks \"preserve\"\ntrue\n",
        )
        .unwrap();

        let (_, action) = script_action(
            tmp.path(),
            Vec::new(),
            None,
            None,
            None,
            &["/bin/bash".to_string(), "scripts/build.sh".to_string()],
        )
        .unwrap();

        match action {
            Action::RunCommand {
                output_symlink_mode,
                ..
            } => {
                assert_eq!(output_symlink_mode, OutputSymlinkMode::Preserve);
            }
        }
    }

    #[test]
    fn rejects_invalid_output_symlink_mode() {
        let tmp = TempDir::new().unwrap();
        let script = tmp.path().join("scripts").join("build.sh");
        fs::create_dir_all(script.parent().unwrap()).unwrap();
        fs::write(
            &script,
            "#!/bin/bash\n# once output-symlinks \"copy-everything\"\ntrue\n",
        )
        .unwrap();

        let err = script_action(
            tmp.path(),
            Vec::new(),
            None,
            None,
            None,
            &["/bin/bash".to_string(), "scripts/build.sh".to_string()],
        )
        .unwrap_err();

        assert!(err.to_string().contains("parsing output-symlinks"));
    }

    #[test]
    fn rejects_relative_script_paths_that_escape_the_workspace() {
        let tmp = TempDir::new().unwrap();
        let outside = tmp.path().parent().unwrap().join("outside.sh");
        fs::write(&outside, "#!/bin/bash\n").unwrap();

        let err = parse_script_exec_argv(
            tmp.path(),
            &["bash".to_string(), "../outside.sh".to_string()],
        )
        .unwrap_err();

        assert!(err
            .to_string()
            .contains("must stay within the selected workspace"));
    }

    #[test]
    fn rejects_globs_that_match_too_many_files() {
        let tmp = TempDir::new().unwrap();
        fs::create_dir_all(tmp.path().join("scripts")).unwrap();
        fs::create_dir_all(tmp.path().join("scripts/src")).unwrap();
        fs::write(tmp.path().join("scripts/src/one.txt"), "1\n").unwrap();
        fs::write(tmp.path().join("scripts/src/two.txt"), "2\n").unwrap();

        let script_dir = WorkspacePath::try_from("scripts").unwrap();
        let err =
            expand_script_globs_with_limit(tmp.path(), &script_dir, "src/*.txt", 1).unwrap_err();

        assert!(err.to_string().contains("matched more than 1 files"));
    }

    #[test]
    fn does_not_autodetect_unannotated_scripts() {
        let tmp = TempDir::new().unwrap();
        let script = tmp.path().join("scripts").join("build.sh");
        fs::create_dir_all(script.parent().unwrap()).unwrap();
        fs::write(&script, "#!/bin/bash\ncat ../input.txt\n").unwrap();

        let detected = autodetected_script_action(
            tmp.path(),
            Vec::new(),
            None,
            None,
            None,
            &["/bin/bash".to_string(), "scripts/build.sh".to_string()],
        )
        .unwrap();

        assert!(detected.is_none());
    }
}
