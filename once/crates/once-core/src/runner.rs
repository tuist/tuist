//! Cache-aware action execution.
//!
//! This module owns the execution lifecycle around an [`Action`]: check
//! the action cache, acquire resource permits for misses, run locally or
//! remotely, restore declared outputs on hits, and write fresh results
//! back to the configured cache.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use once_cas::{ActionResult, CacheProvider, Cas, Digest};
use tracing::{debug, instrument};

use crate::{execute, outputs, Action, ResourceLimits, ResourcePool, Result};

/// Whether a result came from cache or fresh execution.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CacheState {
    Hit,
    Miss,
}

#[derive(Debug, Clone)]
pub struct Outcome {
    /// Digest of the action that produced or looked up this result.
    pub action: Digest,
    /// Process result and declared output digests.
    pub result: ActionResult,
    /// Whether the result came from cache or fresh execution.
    pub cache: CacheState,
}

/// Caller-controlled policy for execution.
#[derive(Debug, Clone, Copy, Default)]
pub struct RunOpts {
    /// If true, non-zero-exit results are written to the cache. Off by
    /// default - a transient infra failure (OOM, disk full, network
    /// blip) shouldn't become a permanent cached failure.
    pub cache_failures: bool,
}

/// Bounded async executor.
///
/// A `Runner` caps in-flight actions with a [`ResourcePool`] so callers
/// driving large graphs cannot exhaust file descriptors, memory, or
/// process slots. The default CPU budget is the host's available
/// parallelism; override with [`Runner::with_max_concurrency`] or
/// [`Runner::with_resource_limits`].
#[derive(Clone)]
pub struct Runner {
    cache: CacheProvider,
    workspace_root: PathBuf,
    opts: RunOpts,
    resources: Arc<ResourcePool>,
}

impl Runner {
    pub fn new(cas: Cas, workspace_root: impl Into<PathBuf>, opts: RunOpts) -> Self {
        Self {
            cache: CacheProvider::Local(cas),
            workspace_root: workspace_root.into(),
            opts,
            resources: Arc::new(ResourcePool::new(ResourceLimits::default())),
        }
    }

    pub fn with_cache(
        cache: CacheProvider,
        workspace_root: impl Into<PathBuf>,
        opts: RunOpts,
    ) -> Self {
        Self {
            cache,
            workspace_root: workspace_root.into(),
            opts,
            resources: Arc::new(ResourcePool::new(ResourceLimits::default())),
        }
    }

    /// Override the concurrency cap. Useful for tests and constrained
    /// environments. A value of 0 is silently raised to 1.
    #[must_use]
    pub fn with_max_concurrency(mut self, n: usize) -> Self {
        let limits = self.resources.limits();
        self.resources = Arc::new(ResourcePool::new(ResourceLimits::new(
            n,
            limits.memory_bytes,
        )));
        self
    }

    #[must_use]
    pub fn with_resource_limits(mut self, limits: ResourceLimits) -> Self {
        self.resources = Arc::new(ResourcePool::new(limits));
        self
    }

    pub fn cache(&self) -> &CacheProvider {
        &self.cache
    }

    pub fn workspace_root(&self) -> &Path {
        &self.workspace_root
    }

    pub async fn run(&self, action: &Action) -> Result<Outcome> {
        let key = action.digest();
        if let Some(hit) = lookup_cached(&self.cache, &self.workspace_root, &key).await? {
            return Ok(hit);
        }
        let _permit = self
            .resources
            .acquire(action.resource_request().clone())
            .await;
        if let Some(hit) = lookup_cached(&self.cache, &self.workspace_root, &key).await? {
            return Ok(hit);
        }
        produce(action, &self.workspace_root, &self.cache, self.opts, key).await
    }
}

/// Convenience: run a single action without constructing a [`Runner`].
/// Production callers (schedulers) should use [`Runner`] instead so the
/// concurrency cap applies.
pub async fn run(
    action: &Action,
    workspace_root: &Path,
    cas: &Cas,
    opts: RunOpts,
) -> Result<Outcome> {
    run_with_cache(
        action,
        workspace_root,
        &CacheProvider::Local(cas.clone()),
        opts,
    )
    .await
}

pub async fn run_with_cache(
    action: &Action,
    workspace_root: &Path,
    cache: &CacheProvider,
    opts: RunOpts,
) -> Result<Outcome> {
    let key = action.digest();
    if let Some(hit) = lookup_cached(cache, workspace_root, &key).await? {
        return Ok(hit);
    }
    produce(action, workspace_root, cache, opts, key).await
}

pub async fn run_with_cache_streaming(
    action: &Action,
    workspace_root: &Path,
    cache: &CacheProvider,
    opts: RunOpts,
) -> Result<Outcome> {
    let key = action.digest();
    if let Some(hit) = lookup_cached(cache, workspace_root, &key).await? {
        return Ok(hit);
    }
    let result = execute::run(action, workspace_root, cache, true).await?;
    let cacheable = result.exit_code == 0 || opts.cache_failures;
    if cacheable {
        cache.put_action_result(&key, &result).await?;
    } else {
        debug!(
            exit_code = result.exit_code,
            "skipping cache write for failure"
        );
    }
    Ok(Outcome {
        action: key,
        result,
        cache: CacheState::Miss,
    })
}

#[instrument(skip(cache), fields(action_digest = %key))]
async fn lookup_cached(
    cache: &CacheProvider,
    workspace_root: &Path,
    key: &Digest,
) -> Result<Option<Outcome>> {
    if let Some(result) = cache.get_action_result(key).await? {
        debug!("cache hit");
        outputs::restore(&result, workspace_root, cache).await?;
        return Ok(Some(Outcome {
            action: *key,
            result,
            cache: CacheState::Hit,
        }));
    }
    Ok(None)
}

#[instrument(skip(action, cache), fields(action_digest = %key))]
async fn produce(
    action: &Action,
    workspace_root: &Path,
    cache: &CacheProvider,
    opts: RunOpts,
    key: Digest,
) -> Result<Outcome> {
    let result = execute::run(action, workspace_root, cache, false).await?;
    let cacheable = result.exit_code == 0 || opts.cache_failures;
    if cacheable {
        cache.put_action_result(&key, &result).await?;
    } else {
        debug!(
            exit_code = result.exit_code,
            "skipping cache write for failure"
        );
    }
    Ok(Outcome {
        action: key,
        result,
        cache: CacheState::Miss,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::time::Duration;

    use crate::action::ACTION_DIGEST_DOMAIN;
    use crate::{Error, OutputSymlinkMode, RemoteExecution, ResourceRequest, WorkspacePath};
    use once_cas::{CacheProvider, Cas, Digest};
    use tempfile::TempDir;

    fn fresh_cas() -> (TempDir, Cas) {
        let tmp = TempDir::new().unwrap();
        let cas = Cas::open(tmp.path());
        (tmp, cas)
    }

    fn echo_action(msg: &str) -> Action {
        Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), format!("printf '{msg}'")],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        }
    }

    #[tokio::test]
    async fn first_run_is_miss_second_is_hit() {
        let (tmp, cas) = fresh_cas();
        let action = echo_action("hello");
        let first = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(first.cache, CacheState::Miss);
        assert_eq!(first.result.exit_code, 0);
        assert_eq!(
            cas.get_blob(&first.result.stdout.unwrap()).await.unwrap(),
            b"hello"
        );

        let second = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(second.cache, CacheState::Hit);
        assert_eq!(second.result, first.result);
    }

    #[tokio::test]
    async fn different_argv_gets_different_cache_slot() {
        let (tmp, cas) = fresh_cas();
        let a = run(&echo_action("a"), tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        let b = run(&echo_action("b"), tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_ne!(a.action, b.action);
    }

    #[tokio::test]
    async fn env_is_part_of_the_cache_key() {
        let mut env_a = BTreeMap::new();
        env_a.insert("X".into(), "1".into());
        let mut env_b = BTreeMap::new();
        env_b.insert("X".into(), "2".into());
        let argv = vec!["/bin/sh".into(), "-c".into(), "true".into()];
        let a = Action::RunCommand {
            argv: argv.clone(),
            env: env_a,
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let b = Action::RunCommand {
            argv,
            env: env_b,
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        assert_ne!(a.digest(), b.digest());
    }

    #[tokio::test]
    async fn failures_are_not_cached_by_default() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "exit 7".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let first = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(first.cache, CacheState::Miss);
        assert_eq!(first.result.exit_code, 7);
        let second = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(second.cache, CacheState::Miss);
    }

    #[tokio::test]
    async fn failures_are_cached_with_opt_in() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "exit 7".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let opts = RunOpts {
            cache_failures: true,
        };
        let first = run(&action, tmp.path(), &cas, opts).await.unwrap();
        assert_eq!(first.cache, CacheState::Miss);
        let second = run(&action, tmp.path(), &cas, opts).await.unwrap();
        assert_eq!(second.cache, CacheState::Hit);
        assert_eq!(second.result.exit_code, 7);
    }

    #[tokio::test]
    async fn timeout_kills_long_running_action() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "sleep 5".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(100),
            remote: None,
        };
        let err = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap_err();
        assert!(matches!(err, Error::Timeout(_)));
    }

    #[tokio::test]
    async fn cwd_resolves_against_workspace_root() {
        let (tmp, cas) = fresh_cas();
        let sub = tmp.path().join("sub");
        std::fs::create_dir(&sub).unwrap();
        std::fs::write(sub.join("marker"), b"present").unwrap();
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "cat marker".into()],
            env: BTreeMap::new(),
            cwd: Some(WorkspacePath::try_from("sub").unwrap()),
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let outcome = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(outcome.result.exit_code, 0);
        assert_eq!(
            cas.get_blob(&outcome.result.stdout.unwrap()).await.unwrap(),
            b"present"
        );
    }

    #[tokio::test]
    async fn captures_binary_stdout_with_null_bytes() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), r"printf 'abc\000def'".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };
        let outcome = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(outcome.result.exit_code, 0);
        let stdout = cas.get_blob(&outcome.result.stdout.unwrap()).await.unwrap();
        assert_eq!(stdout, b"abc\x00def");
    }

    #[tokio::test]
    async fn streams_large_output_without_buffering_in_memory() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec![
                "/bin/sh".into(),
                "-c".into(),
                "yes hello | head -c 4194304".into(),
            ],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(10_000),
            remote: None,
        };
        let outcome = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(outcome.result.exit_code, 0);
        let stdout = cas.get_blob(&outcome.result.stdout.unwrap()).await.unwrap();
        assert_eq!(stdout.len(), 4 * 1024 * 1024);
    }

    #[tokio::test]
    async fn streaming_run_writes_and_reuses_cache_entries() {
        let (tmp, cas) = fresh_cas();
        let cache = CacheProvider::Local(cas.clone());
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "true".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };

        let first = run_with_cache_streaming(&action, tmp.path(), &cache, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(first.cache, CacheState::Miss);
        assert_eq!(
            cas.get_blob(&first.result.stdout.unwrap()).await.unwrap(),
            b""
        );

        let second = run_with_cache_streaming(&action, tmp.path(), &cache, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(second.cache, CacheState::Hit);
    }

    #[tokio::test]
    async fn remote_actions_delegate_to_remote_provider_dispatch() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["true".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: Some(RemoteExecution {
                provider: "unknown-remote".to_string(),
            }),
        };

        let error = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap_err();

        assert!(matches!(
            error,
            Error::UnsupportedRemoteProvider { ref provider } if provider == "unknown-remote"
        ));
    }

    #[tokio::test]
    async fn runner_caps_concurrency() {
        let (tmp, cas) = fresh_cas();
        let runner =
            Runner::new(cas, tmp.path().to_path_buf(), RunOpts::default()).with_max_concurrency(1);
        let mk = |suffix: &str| Action::RunCommand {
            argv: vec![
                "/bin/sh".into(),
                "-c".into(),
                format!("sleep 0.2; printf {suffix}"),
            ],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };
        let started = std::time::Instant::now();
        let action_a = mk("a");
        let action_b = mk("b");
        let (a, b) = tokio::join!(runner.run(&action_a), runner.run(&action_b));
        a.unwrap();
        b.unwrap();
        assert!(
            started.elapsed() >= Duration::from_millis(380),
            "expected serialized execution; took {:?}",
            started.elapsed()
        );
    }

    #[tokio::test]
    async fn runner_respects_action_cpu_slots() {
        let (tmp, cas) = fresh_cas();
        let runner = Runner::new(cas, tmp.path().to_path_buf(), RunOpts::default())
            .with_resource_limits(ResourceLimits::new(2, 0));
        let mk = |suffix: &str| Action::RunCommand {
            argv: vec![
                "/bin/sh".into(),
                "-c".into(),
                format!("sleep 0.2; printf {suffix}"),
            ],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::new(2, 0),
            timeout_ms: Some(5_000),
            remote: None,
        };

        let started = std::time::Instant::now();
        let action_a = mk("a");
        let action_b = mk("b");
        let (a, b) = tokio::join!(runner.run(&action_a), runner.run(&action_b));
        a.unwrap();
        b.unwrap();
        assert!(
            started.elapsed() >= Duration::from_millis(380),
            "expected weighted actions to serialize; took {:?}",
            started.elapsed()
        );
    }

    #[test]
    fn digest_includes_domain_prefix() {
        let action = Action::RunCommand {
            argv: vec!["true".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let expected = {
            let body = serde_json::to_vec(&action).unwrap();
            let mut buf = Vec::with_capacity(ACTION_DIGEST_DOMAIN.len() + body.len());
            buf.extend_from_slice(ACTION_DIGEST_DOMAIN);
            buf.extend_from_slice(&body);
            Digest::of_bytes(&buf)
        };
        assert_eq!(action.digest(), expected);
    }

    #[test]
    fn digest_changes_when_timeout_changes() {
        let mk = |t: Option<u64>| Action::RunCommand {
            argv: vec!["true".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: t,
            remote: None,
        };
        assert_ne!(mk(None).digest(), mk(Some(1000)).digest());
        assert_ne!(mk(Some(1000)).digest(), mk(Some(2000)).digest());
    }

    #[test]
    fn digest_changes_when_cwd_changes() {
        let mk = |c: Option<WorkspacePath>| Action::RunCommand {
            argv: vec!["true".into()],
            env: BTreeMap::new(),
            cwd: c,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let a = mk(None);
        let b = mk(Some(WorkspacePath::try_from("a").unwrap()));
        let c = mk(Some(WorkspacePath::try_from("b").unwrap()));
        assert_ne!(a.digest(), b.digest());
        assert_ne!(b.digest(), c.digest());
    }

    #[test]
    fn digest_changes_when_input_digest_changes() {
        let mk = |input_digest: Option<Digest>| Action::RunCommand {
            argv: vec!["true".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let a = mk(Some(Digest::of_bytes(b"a")));
        let b = mk(Some(Digest::of_bytes(b"b")));
        assert_ne!(mk(None).digest(), a.digest());
        assert_ne!(a.digest(), b.digest());
    }

    #[test]
    fn default_resources_are_wire_compatible() {
        let action = echo_action("hello");
        let encoded = serde_json::to_value(&action).unwrap();
        assert!(encoded.get("resources").is_none());

        let decoded: Action = serde_json::from_value(serde_json::json!({
            "kind": "run_command",
            "argv": ["true"]
        }))
        .unwrap();
        assert_eq!(decoded.resource_request(), &ResourceRequest::default());
    }

    #[test]
    fn workspace_path_deserialization_rejects_absolute() {
        let raw = serde_json::json!({
            "kind": "run_command",
            "argv": ["true"],
            "cwd": "/etc/passwd"
        });
        let err = serde_json::from_value::<Action>(raw).unwrap_err();
        assert!(
            err.to_string().contains("relative"),
            "unexpected error: {err}"
        );
    }

    #[tokio::test]
    async fn empty_argv_returns_empty_argv_error() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec![],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let err = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap_err();
        assert!(matches!(err, Error::EmptyArgv));
    }

    #[tokio::test]
    async fn nonexistent_program_returns_spawn_error() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["/this/program/does/not/exist".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        };
        let err = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap_err();
        assert!(matches!(err, Error::Spawn { .. }), "got {err:?}");
    }

    #[tokio::test]
    async fn child_stdin_is_closed() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "cat".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(2_000),
            remote: None,
        };
        let outcome = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(outcome.result.exit_code, 0);
        assert!(cas
            .get_blob(&outcome.result.stdout.unwrap())
            .await
            .unwrap()
            .is_empty());
    }

    #[tokio::test]
    async fn runner_clones_share_the_same_permit_pool() {
        let (tmp, cas) = fresh_cas();
        let runner =
            Runner::new(cas, tmp.path().to_path_buf(), RunOpts::default()).with_max_concurrency(1);
        let runner2 = runner.clone();
        let action_a = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "sleep 0.2; printf a".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };
        let action_b = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "sleep 0.2; printf b".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };
        let started = std::time::Instant::now();
        let (a, b) = tokio::join!(runner.run(&action_a), runner2.run(&action_b));
        a.unwrap();
        b.unwrap();
        assert!(
            started.elapsed() >= Duration::from_millis(380),
            "clones must share the permit pool; took {:?}",
            started.elapsed()
        );
    }

    #[tokio::test]
    async fn runner_uses_the_supplied_workspace_root() {
        let (tmp, cas) = fresh_cas();
        let sub = tmp.path().join("sub");
        std::fs::create_dir(&sub).unwrap();
        std::fs::write(sub.join("marker"), b"ok").unwrap();
        let runner = Runner::new(cas, tmp.path().to_path_buf(), RunOpts::default());
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "cat marker".into()],
            env: BTreeMap::new(),
            cwd: Some(WorkspacePath::try_from("sub").unwrap()),
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };
        let outcome = runner.run(&action).await.unwrap();
        assert_eq!(outcome.result.exit_code, 0);
        let stdout = runner
            .cache()
            .get_blob(&outcome.result.stdout.unwrap())
            .await
            .unwrap();
        assert_eq!(stdout, b"ok");
    }

    #[tokio::test]
    async fn cache_hits_do_not_queue_on_the_permit_pool() {
        let (tmp, cas) = fresh_cas();
        let action = echo_action("warm");
        run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();

        let runner =
            Runner::new(cas, tmp.path().to_path_buf(), RunOpts::default()).with_max_concurrency(1);
        let started = std::time::Instant::now();
        let mut handles = Vec::new();
        for _ in 0..32 {
            let runner = runner.clone();
            let action = action.clone();
            handles.push(tokio::spawn(
                async move { runner.run(&action).await.unwrap() },
            ));
        }
        for h in handles {
            assert_eq!(h.await.unwrap().cache, CacheState::Hit);
        }
        assert!(
            started.elapsed() < Duration::from_millis(500),
            "32 cache hits took {:?}; permit must not gate lookups",
            started.elapsed()
        );
    }

    #[tokio::test]
    async fn directory_outputs_restore_from_cache() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec![
                "/bin/sh".into(),
                "-c".into(),
                "mkdir -p Demo.app/Nested && printf info > Demo.app/Info.plist && printf bin > Demo.app/Nested/Demo".into(),
            ],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![WorkspacePath::try_from("Demo.app").unwrap()],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };

        let first = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(first.cache, CacheState::Miss);
        std::fs::remove_dir_all(tmp.path().join("Demo.app")).unwrap();

        let second = run(&action, tmp.path(), &cas, RunOpts::default())
            .await
            .unwrap();
        assert_eq!(second.cache, CacheState::Hit);
        assert_eq!(
            std::fs::read_to_string(tmp.path().join("Demo.app/Info.plist")).unwrap(),
            "info"
        );
        assert_eq!(
            std::fs::read_to_string(tmp.path().join("Demo.app/Nested/Demo")).unwrap(),
            "bin"
        );
    }

    #[tokio::test]
    async fn timeout_does_not_pollute_the_cache() {
        let (tmp, cas) = fresh_cas();
        let action = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "sleep 5".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(50),
            remote: None,
        };
        let _ = run(&action, tmp.path(), &cas, RunOpts::default()).await;
        assert!(cas
            .get_action_result(&action.digest())
            .await
            .unwrap()
            .is_none());
    }
}
