use std::collections::BTreeMap;
use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use once_cas::{ActionResult, CacheProvider};
use tokio::process::Command;

use crate::stream::{self, Destination};
use crate::{Error, Result, WorkspacePath};

pub(crate) async fn execute_command(
    argv: &[String],
    env: &BTreeMap<String, String>,
    cwd: Option<&WorkspacePath>,
    timeout_ms: Option<u64>,
    workspace_root: &Path,
    cache: &CacheProvider,
) -> Result<ActionResult> {
    let (program, rest) = argv.split_first().ok_or(Error::EmptyArgv)?;
    tracing::Span::current().record("program", tracing::field::display(program));

    let mut command = Command::new(program);
    command.args(rest);
    command.env_clear();
    for (k, v) in env {
        command.env(k, v);
    }
    command.stdin(Stdio::null());
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());
    command.current_dir(cwd.map_or_else(
        || workspace_root.to_path_buf(),
        |c| c.resolve(workspace_root),
    ));
    command.kill_on_drop(true);

    let mut child = command.spawn().map_err(|source| Error::Spawn {
        program: program.clone(),
        source,
    })?;
    let stdout_pipe = child.stdout.take().expect("stdout was piped");
    let stderr_pipe = child.stderr.take().expect("stderr was piped");

    let work = async {
        let (stdout, stderr) =
            tokio::try_join!(cache.put_stream(stdout_pipe), cache.put_stream(stderr_pipe))?;
        let status = child.wait().await.map_err(|source| Error::Wait {
            program: program.clone(),
            source,
        })?;
        Ok::<_, Error>(ActionResult {
            exit_code: status.code().unwrap_or(-1),
            stdout: Some(stdout),
            stderr: Some(stderr),
            outputs: BTreeMap::new(),
        })
    };

    match timeout_ms {
        Some(ms) => {
            let dur = Duration::from_millis(ms);
            match tokio::time::timeout(dur, work).await {
                Ok(res) => res,
                Err(_) => Err(Error::Timeout(dur)),
            }
        }
        None => work.await,
    }
}

pub(crate) async fn execute_command_streaming(
    argv: &[String],
    env: &BTreeMap<String, String>,
    cwd: Option<&WorkspacePath>,
    timeout_ms: Option<u64>,
    workspace_root: &Path,
    cache: &CacheProvider,
) -> Result<ActionResult> {
    Box::pin(execute_child_streaming(
        argv,
        env,
        cwd,
        timeout_ms,
        workspace_root,
        cache,
        true,
        false,
    ))
    .await
}

#[allow(clippy::too_many_arguments)]
async fn execute_child_streaming(
    argv: &[String],
    env: &BTreeMap<String, String>,
    cwd: Option<&WorkspacePath>,
    timeout_ms: Option<u64>,
    workspace_root: &Path,
    cache: &CacheProvider,
    stream_to_parent: bool,
    inherit_parent_env: bool,
) -> Result<ActionResult> {
    let (program, rest) = argv.split_first().ok_or(Error::EmptyArgv)?;
    tracing::Span::current().record("program", tracing::field::display(program));

    let mut command = Command::new(program);
    command.args(rest);
    if !inherit_parent_env {
        command.env_clear();
    }
    for (k, v) in env {
        command.env(k, v);
    }
    command.stdin(Stdio::null());
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());
    command.current_dir(cwd.map_or_else(
        || workspace_root.to_path_buf(),
        |c| c.resolve(workspace_root),
    ));
    command.kill_on_drop(true);

    let mut child = command.spawn().map_err(|source| Error::Spawn {
        program: program.clone(),
        source,
    })?;
    let stdout_pipe = child.stdout.take().expect("stdout was piped");
    let stderr_pipe = child.stderr.take().expect("stderr was piped");

    let work = Box::pin(async {
        let (stdout, stderr) = tokio::try_join!(
            stream::to_cache(stdout_pipe, Destination::Stdout, cache, stream_to_parent),
            stream::to_cache(stderr_pipe, Destination::Stderr, cache, stream_to_parent)
        )?;
        let status = child.wait().await.map_err(|source| Error::Wait {
            program: program.clone(),
            source,
        })?;
        Ok::<_, Error>(ActionResult {
            exit_code: status.code().unwrap_or(-1),
            stdout: Some(stdout),
            stderr: Some(stderr),
            outputs: BTreeMap::new(),
        })
    });

    match timeout_ms {
        Some(ms) => {
            let dur = Duration::from_millis(ms);
            match tokio::time::timeout(dur, work).await {
                Ok(res) => res,
                Err(_) => Err(Error::Timeout(dur)),
            }
        }
        None => work.await,
    }
}
