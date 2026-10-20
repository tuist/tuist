//! Action graph and parallel scheduler.
//!
//! A [`Plan`] is a topologically-orderable DAG of actions: each node
//! has an [`Action`], a label for telemetry, and indices into the same
//! plan describing the actions it depends on. [`Runner::run_plan`]
//! walks the graph respecting dependencies, runs ready nodes in
//! parallel through the existing concurrency cap, and aborts the plan
//! on the first action failure (so we don't waste work on downstream
//! actions whose inputs would be missing).

use tokio::sync::mpsc;
use tokio::task::JoinSet;

use crate::{Action, Outcome, Runner};

/// One node in a [`Plan`]. `deps` is a list of indices into the
/// containing plan's `nodes` vector, identifying every action that
/// must complete (successfully) before this one runs.
#[derive(Debug, Clone)]
pub struct PlanNode {
    /// Human-readable label, surfaced in telemetry and CLI output.
    /// Typically a target id or a target-local action id, but the
    /// scheduler treats it as opaque text.
    pub label: String,
    pub action: Action,
    pub deps: Vec<usize>,
}

/// A directed acyclic graph of actions.
#[derive(Debug, Clone, Default)]
pub struct Plan {
    pub nodes: Vec<PlanNode>,
}

/// Result of running one plan node. Carries the node's label and index
/// alongside the underlying [`Outcome`] so callers can attribute cache
/// hits/misses back to the originating target.
#[derive(Debug, Clone)]
pub struct PlanOutcome {
    pub index: usize,
    pub label: String,
    pub outcome: Outcome,
}

/// Per-node metadata that travels alongside a [`Plan`] for telemetry
/// and CLI rendering. The `kind` is the originating target kind
/// (`script`, `runtime_script`, ...), kept as a string so the
/// shape is uniform across plugins. Plugin-internal enum
/// representations stay inside the plugin.
#[derive(Debug, Clone)]
pub struct NodeInfo {
    /// Project-root-relative id of the source target, e.g.
    /// `crates/once-cas/once-cas`. Named `label` for historical
    /// continuity with [`PlanNode::label`] and [`PlanOutcome::label`].
    pub label: String,
    pub kind: String,
}

/// A plugin's compiled build description. Every plugin's `build_plan`
/// returns this shape so the CLI dispatches on `target.kind`, then
/// drives a plugin-agnostic execution and rendering pipeline. Adding a
/// new plugin (Go, C++, ...) is a matter of producing a `BuiltPlan`,
/// not extending the CLI's bridge structs.
#[derive(Debug, Clone)]
pub struct BuiltPlan {
    pub plan: Plan,
    pub root_index: usize,
    /// Project-root-relative id of the root target.
    pub root_id: String,
    /// Workspace-relative path to the canonical output of the root
    /// target. Empty for plugins that do not declare a primary output
    /// (e.g. `task` targets).
    pub output: String,
    /// Per-node metadata, indexed in `plan.nodes` order.
    pub nodes: Vec<NodeInfo>,
}

#[derive(Debug, thiserror::Error)]
pub enum PlanError {
    #[error("plan dependency cycle detected")]
    Cycle,
    #[error("dependency index {0} is out of bounds for plan with {1} nodes")]
    BadDep(usize, usize),
    #[error("action `{label}` failed: exit code {exit_code}")]
    Failed { label: String, exit_code: i32 },
    #[error(transparent)]
    Core(#[from] crate::Error),
}

impl Plan {
    pub fn new() -> Self {
        Self { nodes: Vec::new() }
    }

    /// Append a node and return its index. Indices are stable across
    /// the lifetime of the plan, so callers can reference earlier
    /// nodes in later nodes' `deps` lists.
    pub fn push(&mut self, node: PlanNode) -> usize {
        let idx = self.nodes.len();
        self.nodes.push(node);
        idx
    }

    /// Validate dep indices and detect cycles before any action runs.
    pub fn validate(&self) -> std::result::Result<(), PlanError> {
        for node in &self.nodes {
            for &d in &node.deps {
                if d >= self.nodes.len() {
                    return Err(PlanError::BadDep(d, self.nodes.len()));
                }
            }
        }
        // Kahn's algorithm: any unvisited node after the queue empties
        // is part of a cycle.
        let mut indeg: Vec<usize> = self.nodes.iter().map(|n| n.deps.len()).collect();
        let mut ready: Vec<usize> = (0..self.nodes.len()).filter(|&i| indeg[i] == 0).collect();
        let mut visited = 0usize;
        while let Some(i) = ready.pop() {
            visited += 1;
            for (j, node) in self.nodes.iter().enumerate() {
                if node.deps.contains(&i) {
                    indeg[j] -= 1;
                    if indeg[j] == 0 {
                        ready.push(j);
                    }
                }
            }
        }
        if visited != self.nodes.len() {
            return Err(PlanError::Cycle);
        }
        Ok(())
    }
}

/// Internal completion signal sent by every spawned task back to the
/// driver loop. `index` identifies the node; `result` carries the
/// outcome or the failure that should abort the plan.
struct Done {
    index: usize,
    label: String,
    result: std::result::Result<Outcome, crate::Error>,
}

impl Runner {
    /// Execute every node in `plan` in dependency order, with eligible
    /// nodes running concurrently subject to the runner's permit cap.
    /// On the first failed action the scheduler stops launching new
    /// work and waits for in-flight actions to complete before
    /// returning.
    pub async fn run_plan(&self, plan: &Plan) -> std::result::Result<Vec<PlanOutcome>, PlanError> {
        plan.validate()?;
        let n = plan.nodes.len();
        if n == 0 {
            return Ok(Vec::new());
        }

        // Reverse-edge map and in-degree counter, owned by the single
        // driver loop. No locking needed because only the loop touches
        // them.
        let mut dependents: Vec<Vec<usize>> = vec![Vec::new(); n];
        let mut indeg: Vec<usize> = vec![0; n];
        for (i, node) in plan.nodes.iter().enumerate() {
            indeg[i] = node.deps.len();
            for &d in &node.deps {
                dependents[d].push(i);
            }
        }

        let (tx, mut rx) = mpsc::unbounded_channel::<Done>();
        let mut tasks: JoinSet<()> = JoinSet::new();
        let mut outcomes: Vec<Option<PlanOutcome>> = (0..n).map(|_| None).collect();
        let mut aborted: Option<PlanError> = None;
        let mut in_flight = 0usize;

        // Seed: every node with no deps is immediately runnable.
        for (i, node) in plan.nodes.iter().enumerate() {
            if indeg[i] == 0 {
                spawn(&mut tasks, self.clone(), tx.clone(), i, node.clone());
                in_flight += 1;
            }
        }

        if in_flight == 0 {
            // `validate` would already have caught a no-leaves graph
            // as a cycle. Belt and braces.
            return Ok(Vec::new());
        }

        // Driver loop. We hold `tx` ourselves so the channel stays
        // open until we explicitly drop it; without that, a brief
        // window where every spawned sender has been dropped would
        // close `rx` and exit the loop while we still have work to
        // schedule.
        loop {
            let Some(done) = rx.recv().await else { break };
            in_flight -= 1;
            match done.result {
                Ok(outcome) => {
                    if outcome.result.exit_code != 0 {
                        if aborted.is_none() {
                            aborted = Some(PlanError::Failed {
                                label: done.label.clone(),
                                exit_code: outcome.result.exit_code,
                            });
                        }
                    } else {
                        outcomes[done.index] = Some(PlanOutcome {
                            index: done.index,
                            label: done.label.clone(),
                            outcome,
                        });
                        if aborted.is_none() {
                            for &d in &dependents[done.index] {
                                indeg[d] -= 1;
                                if indeg[d] == 0 {
                                    spawn(
                                        &mut tasks,
                                        self.clone(),
                                        tx.clone(),
                                        d,
                                        plan.nodes[d].clone(),
                                    );
                                    in_flight += 1;
                                }
                            }
                        }
                    }
                }
                Err(e) => {
                    if aborted.is_none() {
                        aborted = Some(PlanError::Core(e));
                    }
                }
            }
            if in_flight == 0 {
                break;
            }
        }
        drop(tx);

        // Drain any panics or cancellations from the JoinSet. Success
        // and execution errors already routed through the channel.
        while let Some(joined) = tasks.join_next().await {
            if joined.is_err() && aborted.is_none() {
                aborted = Some(PlanError::Core(crate::Error::EmptyArgv));
            }
        }

        if let Some(err) = aborted {
            return Err(err);
        }

        let mut out = Vec::with_capacity(n);
        for slot in outcomes {
            out.push(slot.expect("scheduler must populate every outcome slot before returning"));
        }
        Ok(out)
    }
}

fn spawn(
    tasks: &mut JoinSet<()>,
    runner: Runner,
    tx: mpsc::UnboundedSender<Done>,
    index: usize,
    node: PlanNode,
) {
    tasks.spawn(async move {
        let label = node.label.clone();
        let result = runner.run(&node.action).await;
        // Send first; dropping the sender after closes the channel
        // when this is the last live task.
        let _ = tx.send(Done {
            index,
            label,
            result,
        });
    });
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;
    use crate::{OutputSymlinkMode, ResourceRequest, RunOpts, WorkspacePath};
    use once_cas::Cas;
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

    #[test]
    fn validate_rejects_out_of_bounds_dep() {
        let mut plan = Plan::new();
        plan.push(PlanNode {
            label: "a".into(),
            action: cmd("true"),
            deps: vec![5],
        });
        assert!(matches!(plan.validate(), Err(PlanError::BadDep(_, _))));
    }

    #[test]
    fn validate_rejects_cycle() {
        let mut plan = Plan::new();
        plan.push(PlanNode {
            label: "a".into(),
            action: cmd("true"),
            deps: vec![1],
        });
        plan.push(PlanNode {
            label: "b".into(),
            action: cmd("true"),
            deps: vec![0],
        });
        assert!(matches!(plan.validate(), Err(PlanError::Cycle)));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn empty_plan_returns_empty_outcomes() {
        let (_tmp, runner) = ws();
        let plan = Plan::new();
        let outcomes = runner.run_plan(&plan).await.unwrap();
        assert!(outcomes.is_empty());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn linear_chain_runs_in_order() {
        let (tmp, runner) = ws();
        let marker = tmp.path().join("marker");
        let mk = |name: &str| Action::RunCommand {
            argv: vec![
                "/bin/sh".into(),
                "-c".into(),
                format!("printf {name} > {}", marker.display()),
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
        let mut plan = Plan::new();
        let a = plan.push(PlanNode {
            label: "a".into(),
            action: mk("AAA"),
            deps: vec![],
        });
        let b = plan.push(PlanNode {
            label: "b".into(),
            action: mk("BBB"),
            deps: vec![a],
        });
        let _c = plan.push(PlanNode {
            label: "c".into(),
            action: mk("CCC"),
            deps: vec![b],
        });
        let outcomes = runner.run_plan(&plan).await.unwrap();
        assert_eq!(outcomes.len(), 3);
        let final_marker = std::fs::read_to_string(&marker).unwrap();
        assert_eq!(final_marker, "CCC");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn independent_leaves_run_in_parallel() {
        let (_tmp, runner) = ws();
        let mut plan = Plan::new();
        for i in 0..6u32 {
            plan.push(PlanNode {
                label: format!("leaf-{i}"),
                action: cmd(&format!("sleep 0.2; printf {i}")),
                deps: vec![],
            });
        }
        let started = std::time::Instant::now();
        let outcomes = runner.run_plan(&plan).await.unwrap();
        assert_eq!(outcomes.len(), 6);
        assert!(
            started.elapsed() < std::time::Duration::from_millis(1_000),
            "expected parallel scheduling; took {:?}",
            started.elapsed()
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn failure_aborts_the_plan() {
        let (_tmp, runner) = ws();
        let mut plan = Plan::new();
        let bad = plan.push(PlanNode {
            label: "boom".into(),
            action: cmd("exit 7"),
            deps: vec![],
        });
        plan.push(PlanNode {
            label: "downstream".into(),
            action: cmd("printf should-not-run"),
            deps: vec![bad],
        });
        let err = runner.run_plan(&plan).await.unwrap_err();
        match err {
            PlanError::Failed { label, exit_code } => {
                assert_eq!(label, "boom");
                assert_eq!(exit_code, 7);
            }
            other => panic!("expected Failed, got {other:?}"),
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn declared_outputs_flow_into_dependents() {
        let (tmp, runner) = ws();
        let producer = Action::RunCommand {
            argv: vec![
                "/bin/sh".into(),
                "-c".into(),
                "mkdir -p out && printf 'hello world' > out/produced.txt".into(),
            ],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![WorkspacePath::try_from("out/produced.txt").unwrap()],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };
        let consumer = Action::RunCommand {
            argv: vec!["/bin/sh".into(), "-c".into(), "cat out/produced.txt".into()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![],
            output_symlink_mode: OutputSymlinkMode::default(),
            resources: ResourceRequest::default(),
            timeout_ms: Some(5_000),
            remote: None,
        };
        let mut plan = Plan::new();
        let p = plan.push(PlanNode {
            label: "producer".into(),
            action: producer.clone(),
            deps: vec![],
        });
        plan.push(PlanNode {
            label: "consumer".into(),
            action: consumer,
            deps: vec![p],
        });
        let outcomes = runner.run_plan(&plan).await.unwrap();
        assert_eq!(outcomes.len(), 2);
        let consumer_stdout = runner
            .cache()
            .get_blob(&outcomes[1].outcome.result.stdout.unwrap())
            .await
            .unwrap();
        assert_eq!(consumer_stdout, b"hello world");

        // Restore-on-hit: delete the produced file, run the producer
        // alone; the cache hit must restore the file from CAS.
        std::fs::remove_file(tmp.path().join("out/produced.txt")).unwrap();
        let outcome = runner.run(&producer).await.unwrap();
        assert_eq!(outcome.cache, crate::CacheState::Hit);
        let restored = std::fs::read_to_string(tmp.path().join("out/produced.txt")).unwrap();
        assert_eq!(restored, "hello world");
    }
}
