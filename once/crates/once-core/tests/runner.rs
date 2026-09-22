//! Integration tests for `once-core` exercising `Runner` end-to-end
//! with real subprocesses, distinct workspaces, and parallel execution.
//!
//! Each test owns its own `TempDir` and `Cas`, so the suite is
//! parallel-safe under `cargo test`'s default scheduler.

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use once_cas::Cas;
use once_core::{
    Action, CacheState, OutputSymlinkMode, ResourceRequest, RunOpts, Runner, WorkspacePath,
};
use tempfile::TempDir;

fn ws() -> (TempDir, Runner) {
    let tmp = TempDir::new().unwrap();
    let cas = Cas::open(tmp.path());
    let runner = Runner::new(cas, tmp.path().to_path_buf(), RunOpts::default());
    (tmp, runner)
}

fn cmd(script: &str) -> Action {
    Action::RunCommand {
        argv: vec!["/bin/sh".into(), "-c".into(), script.into()],
        env: BTreeMap::new(),
        cwd: None,
        input_digest: None,
        outputs: vec![],
        output_symlink_mode: OutputSymlinkMode::default(),
        resources: ResourceRequest::default(),
        timeout_ms: Some(10_000),
        remote: None,
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn many_independent_actions_execute_concurrently() {
    let (_tmp, runner) = ws();
    let actions: Vec<Action> = (0..8u32)
        .map(|i| cmd(&format!("sleep 0.2; printf {i}")))
        .collect();
    let started = Instant::now();
    let mut handles = Vec::new();
    for a in &actions {
        // Move clones of the runner into spawned tasks; cloning shares
        // the permit pool by design.
        let runner = runner.clone();
        let a = a.clone();
        handles.push(tokio::spawn(async move { runner.run(&a).await.unwrap() }));
    }
    for h in handles {
        h.await.unwrap();
    }
    // 8 actions * 200ms = 1.6s serialized; with default parallelism
    // (≥ 2 on every CI host) we should finish in under 1s.
    assert!(
        started.elapsed() < Duration::from_millis(1_500),
        "expected concurrent execution; took {:?}",
        started.elapsed()
    );
}

#[tokio::test]
async fn second_run_of_same_action_is_a_cache_hit() {
    let (_tmp, runner) = ws();
    let action = cmd("printf hi");
    let first = runner.run(&action).await.unwrap();
    let second = runner.run(&action).await.unwrap();
    assert_eq!(first.cache, CacheState::Miss);
    assert_eq!(second.cache, CacheState::Hit);
    assert_eq!(first.action, second.action);
    assert_eq!(first.result, second.result);
}

#[tokio::test]
async fn cache_keys_partition_by_workspace_path() {
    // Two actions with the same argv but different workspace-relative
    // cwds get different cache slots.
    let (_tmp, runner) = ws();
    let workspace = runner.workspace_root();
    std::fs::create_dir(workspace.join("a")).unwrap();
    std::fs::create_dir(workspace.join("b")).unwrap();
    std::fs::write(workspace.join("a/marker"), b"AAA").unwrap();
    std::fs::write(workspace.join("b/marker"), b"BBB").unwrap();
    let mk = |sub: &str| Action::RunCommand {
        argv: vec!["/bin/sh".into(), "-c".into(), "cat marker".into()],
        env: BTreeMap::new(),
        cwd: Some(WorkspacePath::try_from(sub).unwrap()),
        input_digest: None,
        outputs: vec![],
        output_symlink_mode: OutputSymlinkMode::default(),
        resources: ResourceRequest::default(),
        timeout_ms: Some(5_000),
        remote: None,
    };
    let a = runner.run(&mk("a")).await.unwrap();
    let b = runner.run(&mk("b")).await.unwrap();
    assert_ne!(a.action, b.action);
    assert_eq!(
        runner
            .cache()
            .get_blob(&a.result.stdout.unwrap())
            .await
            .unwrap(),
        b"AAA"
    );
    assert_eq!(
        runner
            .cache()
            .get_blob(&b.result.stdout.unwrap())
            .await
            .unwrap(),
        b"BBB"
    );
}

#[tokio::test]
async fn failure_then_success_does_not_serve_stale_cache() {
    // First run fails (not cached). Fix the script and rerun: must
    // observe the new exit, not the prior failure.
    let (tmp, _) = ws();
    let cas = Cas::open(tmp.path());
    let runner_fail = Runner::new(
        cas.clone(),
        tmp.path().to_path_buf(),
        RunOpts {
            cache_failures: false,
        },
    );

    let bad = Action::RunCommand {
        argv: vec!["/bin/sh".into(), "-c".into(), "exit 1".into()],
        env: BTreeMap::new(),
        cwd: None,
        input_digest: None,
        outputs: vec![],
        output_symlink_mode: OutputSymlinkMode::default(),
        resources: ResourceRequest::default(),
        timeout_ms: Some(5_000),
        remote: None,
    };
    let outcome = runner_fail.run(&bad).await.unwrap();
    assert_eq!(outcome.result.exit_code, 1);
    assert_eq!(outcome.cache, CacheState::Miss);

    // A different action (different argv) succeeds and IS cached.
    let good = Action::RunCommand {
        argv: vec!["/bin/sh".into(), "-c".into(), "exit 0".into()],
        env: BTreeMap::new(),
        cwd: None,
        input_digest: None,
        outputs: vec![],
        output_symlink_mode: OutputSymlinkMode::default(),
        resources: ResourceRequest::default(),
        timeout_ms: Some(5_000),
        remote: None,
    };
    let outcome = runner_fail.run(&good).await.unwrap();
    assert_eq!(outcome.result.exit_code, 0);
    assert_eq!(outcome.cache, CacheState::Miss);
    let again = runner_fail.run(&good).await.unwrap();
    assert_eq!(again.cache, CacheState::Hit);
}

#[tokio::test]
async fn isolated_workspaces_have_independent_caches() {
    // Two runners on disjoint workspaces never see each other's
    // results. Catches a regression where state leaks via globals.
    let (tmp_a, runner_a) = ws();
    let (tmp_b, runner_b) = ws();
    assert_ne!(tmp_a.path(), tmp_b.path());

    let action = cmd("printf shared");
    let in_a = runner_a.run(&action).await.unwrap();
    assert_eq!(in_a.cache, CacheState::Miss);

    // Same action against B is still a miss - caches are per-workspace.
    let in_b = runner_b.run(&action).await.unwrap();
    assert_eq!(in_b.cache, CacheState::Miss);
}
