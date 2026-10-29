# Bitrise runner integration

`Tuist.Runners.Bitrise` runs builds of a customer's self-hosted Bitrise runner
pools on the shared fleet. A connection holds the workspace slug and an API
token; each pool binds a build `stack_identifier` to one Tuist profile and holds
that pool's intro secret.

- Bitrise has no per-build runner credential and no pool queue API. Demand comes
  from `GET /builds?owner_slug=<workspace>&status=0`: a build with no
  `started_on_worker_at` on a pool's stack is waiting for an agent.
- The VM connects `bitrise-den-agent connect --single-task` with the pool's intro
  secret, passed as `BITRISE_DEN_AGENT_INTRO_SECRET`, never on the command line.
  Bitrise hands that agent any build of the pool, so the claim is GitHub-shaped:
  never treat the dispatched build as the one that ran. Bitrise and GitHub rows
  are not `assigned_job?` in `Tuist.Runners.serve_claim/2`.
- The binding comes from the Bitrise CLI's agent-mode `do_on_build_start` hook
  (`infra/runner-image/bitrise-hooks/build-start`, identical Linux copy). It
  posts the build slug with the Bitrise report token to
  `RunnerBitriseReportsController`, which goes through
  `Dispatch.record_execution/3`. A failing start hook fails the customer's build,
  so the hook must exit 0 on every path. A reported build no poll has seen is
  read from Bitrise and queued before it is bound; one on a stack the account
  did not connect is refused.
- The poller, not the VM, completes builds. A live row whose build left the
  unfinished listing is read once and completed with Bitrise's
  `started_on_worker_at`/`finished_at` as the billable window. Settlement runs
  on every pass, including while runners are disabled or the allowance is
  exhausted; only queueing stops then. A failed session write leaves the row
  for the next pass.
- Bitrise report tokens authorize only the start report. They are not accepted
  by the log or finish endpoints.
- Jobs are untrusted (`job_trusted?` false): no cache signing grant or shared
  cache volumes until fork detection for Bitrise pull request builds exists.
- Logs are not ingested; the dashboard links to the Bitrise build.
- Pools should be dedicated to Tuist. Builds that a non-Tuist agent of the same
  pool takes leave a Tuist VM idle until the watchdog stops it.
- Tests use synthetic tokens and stubbed `Client` calls. Never use a customer's
  Bitrise credentials for local validation.
