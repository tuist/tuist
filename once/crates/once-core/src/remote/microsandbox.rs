use std::collections::BTreeMap;
use std::path::Path;

use once_cas::{ActionResult, CacheProvider};

use crate::{Error, Result, WorkspacePath};

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
use super::join_path;
#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
use crate::stream::{self, Destination};
#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
use std::time::Duration;

#[allow(clippy::too_many_arguments)]
#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
pub(super) async fn execute_command(
    argv: &[String],
    env: &BTreeMap<String, String>,
    cwd: Option<&WorkspacePath>,
    timeout_ms: Option<u64>,
    workspace_root: &Path,
    cache: &CacheProvider,
    stream_to_parent: bool,
) -> Result<ActionResult> {
    let (program, rest) = argv.split_first().ok_or(Error::EmptyArgv)?;
    let image = std::env::var("ONCE_MICROSANDBOX_IMAGE").unwrap_or_else(|_| "alpine".to_string());
    let guest_root =
        std::env::var("ONCE_MICROSANDBOX_WORKDIR").unwrap_or_else(|_| "/workspace".to_string());
    let guest_cwd = cwd.map_or_else(
        || guest_root.clone(),
        |cwd| join_path(&guest_root, cwd.as_str()),
    );
    let sandbox_name = sandbox_name();
    let sandbox = microsandbox::Sandbox::builder(&sandbox_name)
        .image(image)
        .workdir(&guest_cwd)
        .volume(&guest_root, |mount| mount.bind(workspace_root))
        .create()
        .await
        .map_err(|source| microsandbox_error(&source))?;
    let cleanup = SandboxCleanup::new(sandbox.clone());

    let work = async {
        let mut handle = sandbox
            .exec_stream_with(program, |exec| {
                let exec = exec.args(rest.iter().cloned()).cwd(&guest_cwd);
                env.iter()
                    .fold(exec, |exec, (key, value)| exec.env(key, value))
            })
            .await
            .map_err(|source| microsandbox_error(&source))?;
        collect_output(&mut handle, cache, stream_to_parent).await
    };

    let result = match timeout_ms {
        Some(ms) => {
            let dur = Duration::from_millis(ms);
            match tokio::time::timeout(dur, work).await {
                Ok(result) => result,
                Err(_) => Err(Error::Timeout(dur)),
            }
        }
        None => work.await,
    };

    let cleanup = cleanup.run().await;

    match (result, cleanup) {
        (Ok(result), Ok(())) => Ok(result),
        (Ok(_), Err(err)) | (Err(err), _) => Err(err),
    }
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
struct SandboxCleanup {
    sandbox: Option<microsandbox::Sandbox>,
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
impl SandboxCleanup {
    fn new(sandbox: microsandbox::Sandbox) -> Self {
        Self {
            sandbox: Some(sandbox),
        }
    }

    async fn run(mut self) -> Result<()> {
        let sandbox = self.sandbox.take().expect("cleanup sandbox is present");
        spawn_cleanup(sandbox)
            .await
            .map_err(|source| Error::RemoteProviderApi {
                provider: "microsandbox".to_string(),
                message: format!("cleanup task failed: {source}"),
            })?
    }
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
impl Drop for SandboxCleanup {
    fn drop(&mut self) {
        let Some(sandbox) = self.sandbox.take() else {
            return;
        };
        match tokio::runtime::Handle::try_current() {
            Ok(handle) => {
                handle.spawn(cleanup_sandbox(sandbox));
            }
            Err(error) => {
                tracing::warn!(
                    sandbox = sandbox.name(),
                    %error,
                    "skipping async microsandbox cleanup because no Tokio runtime is available"
                );
            }
        }
    }
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
fn spawn_cleanup(sandbox: microsandbox::Sandbox) -> tokio::task::JoinHandle<Result<()>> {
    tokio::spawn(cleanup_sandbox(sandbox))
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
async fn cleanup_sandbox(sandbox: microsandbox::Sandbox) -> Result<()> {
    let stop_result = sandbox
        .stop_and_wait()
        .await
        .map_err(|source| microsandbox_error(&source));
    let remove_result = sandbox
        .remove_persisted()
        .await
        .map_err(|source| microsandbox_error(&source));
    match (stop_result, remove_result) {
        (Ok(_status), Ok(())) => Ok(()),
        (Err(error), _) | (_, Err(error)) => Err(error),
    }
}

#[allow(clippy::too_many_arguments)]
#[cfg(not(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64"))))]
pub(super) async fn execute_command(
    _argv: &[String],
    _env: &BTreeMap<String, String>,
    _cwd: Option<&WorkspacePath>,
    _timeout_ms: Option<u64>,
    _workspace_root: &Path,
    _cache: &CacheProvider,
    _stream_to_parent: bool,
) -> Result<ActionResult> {
    Err(Error::RemoteProviderConfig {
        provider: "microsandbox".to_string(),
        message:
            "the embedded Microsandbox provider is only available on Linux and Apple Silicon macOS"
                .to_string(),
    })
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
async fn collect_output(
    handle: &mut microsandbox::ExecHandle,
    cache: &CacheProvider,
    stream_to_parent: bool,
) -> Result<ActionResult> {
    let (mut stdout_reader, mut stdout_writer) = tokio::io::duplex(stream::PIPE_CAPACITY);
    let (mut stderr_reader, mut stderr_writer) = tokio::io::duplex(stream::PIPE_CAPACITY);
    let collect = async {
        let mut exit_code = None;
        while let Some(event) = handle.recv().await {
            match event {
                microsandbox::ExecEvent::Started { .. } => {}
                microsandbox::ExecEvent::Stdout(data) => {
                    stream::write_parent(&data, Destination::Stdout, stream_to_parent).await?;
                    stream::write_pipe(&mut stdout_writer, &data).await?;
                }
                microsandbox::ExecEvent::Stderr(data) => {
                    stream::write_parent(&data, Destination::Stderr, stream_to_parent).await?;
                    stream::write_pipe(&mut stderr_writer, &data).await?;
                }
                microsandbox::ExecEvent::Exited { code } => {
                    exit_code = Some(code);
                    break;
                }
                microsandbox::ExecEvent::Failed(payload) => {
                    return Err(Error::RemoteProviderApi {
                        provider: "microsandbox".to_string(),
                        message: format!("{payload:?}"),
                    });
                }
                microsandbox::ExecEvent::StdinError(payload) => {
                    return Err(Error::RemoteProviderApi {
                        provider: "microsandbox".to_string(),
                        message: format!("{payload:?}"),
                    });
                }
            }
        }
        stream::shutdown_pipe(&mut stdout_writer).await?;
        stream::shutdown_pipe(&mut stderr_writer).await?;
        Ok::<_, Error>(exit_code.unwrap_or(-1))
    };
    let stdout_store = async {
        cache
            .put_stream(&mut stdout_reader)
            .await
            .map_err(Error::from)
    };
    let stderr_store = async {
        cache
            .put_stream(&mut stderr_reader)
            .await
            .map_err(Error::from)
    };
    let (exit_code, stdout, stderr) = tokio::try_join!(collect, stdout_store, stderr_store)?;
    Ok(ActionResult {
        exit_code,
        stdout: Some(stdout),
        stderr: Some(stderr),
        outputs: BTreeMap::new(),
    })
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
fn microsandbox_error(source: &microsandbox::MicrosandboxError) -> Error {
    Error::RemoteProviderApi {
        provider: "microsandbox".to_string(),
        message: source.to_string(),
    }
}

#[cfg(any(target_os = "linux", all(target_os = "macos", target_arch = "aarch64")))]
fn sandbox_name() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| duration.as_nanos());
    format!("once-{}-{nanos}", std::process::id())
}
