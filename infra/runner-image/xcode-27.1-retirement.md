# Retiring Xcode 27.1 RC

This is the second step after [the additive stable rollout](https://github.com/tuist/tuist/pull/14249).
Merging the first PR is not enough: retirement depends on its **deployed** state.
Do not merge or deploy retirement until the prerequisites below are verified.
Xcode 26.6 remains the default, with its existing warm floor.

## Before merge

- Verify the additive chart is deployed and healthy in every target environment.
  Confirm stable `27-1` RunnerPools exist, including the rack and non-default shapes.
  Check `helm history` in each environment and record the deployed additive (or
  newer) revision: this is the rollback floor for retirement.
- Run a successful stable 27.1 build/test job and verify healthy xcresult processing.
  Image publication and static chart renders are not runtime smoke tests.
- Verify a normal `runner-image@X.Y.Z` release reachable from the retirement commit
  includes `"27.1"` in its committed `infra/runner-image/profiles.json`, and that
  `ghcr.io/tuist/tuist-runner:macos-27-1-X.Y.Z` is published. Retirement removes
  the bootstrap pin, so it must not depend on its own image release finishing.
- Retain `ghcr.io/tuist/tuist-runner:macos-27-1-e99ae738` for rollback. Its verified
  manifest is `sha256:fbced4278400d648c7c121ecb44e96fe5e1547aa8690ad410340f444572b5fd6`.
  Do not overwrite that tag by rebuilding the same Xcode/SHA.
- Re-count RC profiles, active jobs and claims. Plan to observe RC claims until
  all finish or release; deleting pools drains running jobs rather than cancelling them.
- Arrange the required post-rollout reconciliation below with an authorized operator.
  This PR intentionally does not add deployment gates or a new background worker.

## What the migration changes

`20261016130000_move_xcode_27_1_rc_runner_profiles_to_stable.exs` changes only
macOS profiles pinned to `27.1-rc`, preserving account, name, protection, resources
and both cache-writer settings. It rewrites only unclaimed **queued** RC jobs,
preserving site and shape suffixes. Both `workflow_job_id` and
`executed_workflow_job_id` in live claims exclude a job from the rewrite.
Claimed, running and historical rows are not changed. ClickHouse attribution is
not backfilled; the next lifecycle transition publishes the updated fleet.

The claim check uses the statement snapshot. An executed-job binding committed
after that snapshot, while the job row remains queued, can still race the rewrite
and create a redundant stable Pod. Existing execution reconciliation and the
completion webhook recover that state; this migration does not claim to eliminate
the dispatch path's pre-existing assignment race.

Unpinning stable also changes its image to the normal versioned tag. Idle runners
roll and hosts may need a fresh golden-image pull, so expect cold-start latency.

## Required post-rollout reconciliation

A pre-upgrade migration alone is insufficient: old replicas can still save an
RC profile, and a claimed job can return to the queue after its pool is retired.

1. Wait for every Pod on the previous image in **all web/API server Deployments**
   to terminate in the target environment. Processor-mode Pods do not save profiles.
2. Arrange human-granted JIT access through the existing `/elevate <env> [duration]
   <intent>` Slack flow for canary/production, with an intent covering release-console
   execution and this data reconciliation. Agents must not request or approve their
   own elevation. Staging needs no elevation. The Atlas read-only Postgres tools
   cannot execute this update.
3. With authorized Pod-exec access, rerun the **same idempotent statements**
   from the migration using the deployed release. Record both returned counts
   each pass. Do not run a broad update over live claims. `eval` starts only the
   repository, not another web server; unlike `rpc`, it also works when the
   deployed release has `RELEASE_DISTRIBUTION=none`:

   ```sh
   /app/bin/tuist eval '
   Application.load(:tuist)
   {:ok, {:ok, counts}, _apps} = Ecto.Migrator.with_repo(Tuist.Repo, fn _repo ->
     migration = Tuist.Repo.Migrations.MoveXcode271RcRunnerProfilesToStable

     unless Code.ensure_loaded?(migration) do
       Code.require_file(Application.app_dir(:tuist,
         "priv/repo/migrations/20261016130000_move_xcode_27_1_rc_runner_profiles_to_stable.exs"))
     end

     Tuist.Repo.transaction(fn ->
       profiles = Tuist.Repo.query!(migration.profile_statement()).num_rows
       jobs = Tuist.Repo.query!(migration.queued_jobs_statement()).num_rows
       %{profiles: profiles, queued_jobs: jobs}
     end)
   end)
   IO.inspect(counts, label: "RC reconciliation")
   '
   ```

4. Reconcile and check every 30–60 minutes as RC work drains. Continue until both
   **active jobs and claims** are zero: deleting a stopped Pod's claim can precede
   the orphan sweep that requeues its job. No claims alone does not mean no work.
   Never delete a live claim to force migration. Escalate if anything remains after
   24 hours; do not force-complete running jobs to meet that deadline.
5. After all three counts reach zero, wait at least **15 minutes**, reconcile again
   and recheck. Any nonzero count resets verification; repeat until they stay zero:

   ```sql
   SELECT 'profiles' AS kind, count(*) FROM runner_profiles
    WHERE platform = 'macos' AND xcode_version = '27.1-rc'
   UNION ALL
   SELECT 'active_jobs', count(*) FROM runner_workflow_jobs
    WHERE status IN ('queued', 'claimed', 'running')
      AND fleet_name ~ '-macos-([a-z0-9-]+-)?27-1-rc(-[0-9]+vcpu-[0-9]+gb)?$'
   UNION ALL
   SELECT 'claims', count(*) FROM runner_claims
    WHERE fleet_name ~ '-macos-([a-z0-9-]+-)?27-1-rc(-[0-9]+vcpu-[0-9]+gb)?$';
   ```

6. Confirm no RC RunnerPools remain except pools still terminating while busy
   Pods drain, and verify a new stable job succeeds on the **versioned** image. Do not call retirement
   complete while RC profiles, queued work or claims remain.

## Rollback

The migration is forward-only. Roll back only to the deployed additive chart or
newer, which already supports stable profiles. Never redeploy a pre-stable chart
or blindly rewrite all `27.1` profiles back to RC: that would change deliberate
stable opt-ins too. If automatic Helm rollback occurs, verify stable pools are
present and resume reconciliation after recovering forward.
