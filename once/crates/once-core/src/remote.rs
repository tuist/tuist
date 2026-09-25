use std::collections::BTreeMap;
use std::path::Path;

use once_cas::{ActionResult, CacheProvider};

use crate::{Error, RemoteExecution, Result, WorkspacePath};

mod daytona;
mod microsandbox;

#[allow(clippy::too_many_arguments)]
pub(crate) async fn execute_command(
    remote: &RemoteExecution,
    argv: &[String],
    env: &BTreeMap<String, String>,
    cwd: Option<&WorkspacePath>,
    timeout_ms: Option<u64>,
    workspace_root: &Path,
    cache: &CacheProvider,
    stream_to_parent: bool,
) -> Result<ActionResult> {
    match remote.provider.as_str() {
        "microsandbox" => {
            microsandbox::execute_command(
                argv,
                env,
                cwd,
                timeout_ms,
                workspace_root,
                cache,
                stream_to_parent,
            )
            .await
        }
        "daytona" => {
            daytona::execute_command(argv, env, cwd, timeout_ms, cache, stream_to_parent).await
        }
        provider => Err(Error::UnsupportedRemoteProvider {
            provider: provider.to_string(),
        }),
    }
}

pub(super) fn join_path(root: &str, rel: &str) -> String {
    if root.ends_with('/') {
        format!("{root}{rel}")
    } else {
        format!("{root}/{rel}")
    }
}
