use std::path::Path;

use once_cas::{ActionResult, CacheProvider};

use crate::{local, outputs, remote, Action, Result};

pub(crate) async fn run(
    action: &Action,
    workspace_root: &Path,
    cache: &CacheProvider,
    stream_to_parent: bool,
) -> Result<ActionResult> {
    match action {
        Action::RunCommand {
            argv,
            env,
            cwd,
            input_digest: _,
            outputs,
            output_symlink_mode,
            resources: _,
            timeout_ms,
            remote,
        } => {
            let mut result = match (remote, stream_to_parent) {
                (Some(remote), _) => {
                    remote::execute_command(
                        remote,
                        argv,
                        env,
                        cwd.as_ref(),
                        *timeout_ms,
                        workspace_root,
                        cache,
                        stream_to_parent,
                    )
                    .await?
                }
                (None, true) => {
                    local::execute_command_streaming(
                        argv,
                        env,
                        cwd.as_ref(),
                        *timeout_ms,
                        workspace_root,
                        cache,
                    )
                    .await?
                }
                (None, false) => {
                    local::execute_command(
                        argv,
                        env,
                        cwd.as_ref(),
                        *timeout_ms,
                        workspace_root,
                        cache,
                    )
                    .await?
                }
            };
            if result.exit_code == 0 {
                result.outputs =
                    outputs::capture(outputs, workspace_root, cache, *output_symlink_mode).await?;
            }
            Ok(result)
        }
    }
}
