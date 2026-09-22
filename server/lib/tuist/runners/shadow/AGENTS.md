# Shadow scheduler snapshot

`Snapshot.capture/0` reads bounded queued demand, active claims and account
platform budgets for the Go runner controller's shadow assignment experiment.
The controller is the policy owner; this module supplies observations only.

- Never claim jobs, mint credentials, mutate lifecycle rows or provision here.
- Exclude repository/workflow names, logs, credentials and cache contents from
  the response. Preserve minimal numeric identifiers for comparison.
- The HTTP endpoint must use `RunnerControllerAuth`, which verifies the exact
  configured controller principal, not merely any authenticated service account.
- Keep protocol version/bounds aligned with
  `infra/runners-controller/internal/shadow/policy.go`. Over-limit data must be
  marked incomplete, not silently sampled: a queue prefix would bias fairness.
- Reads are bounded but not atomic with Kubernetes or each other. This snapshot
  cannot authorize real execution. Actual claims override stale demand in the
  planner, including `executed_job_id` when GitHub selected a different job.

Tests: `mix test test/tuist/runners/shadow/snapshot_test.exs
test/tuist_web/controllers/runner_shadow_controller_test.exs`.
