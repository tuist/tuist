defmodule Tuist.Runners.Workers.OrphanedRunnersWorker do
  @moduledoc """
  Recovers workflow_job lifecycle rows the server transitioned to
  `status = 'running'` but whose GitHub Actions runner never
  actually came up.

  ## What "orphaned running" means

  Happy path:

      Pod polls → server claims → mints JIT → returns 200 to Pod
        → row: status='running', PG claim: lifecycle_state='running'
      Pod execs ./run.sh --jitconfig <JIT>
        → runner registers with GitHub, accepts the workflow_job
        → GitHub fires workflow_job.in_progress
      Job runs → ./run.sh exits → Pod halts → tart-kubelet flips
        to Succeeded → reconciler reaps + boots replacement
      GitHub fires workflow_job.completed → server marks row
        completed, frees PG cap slot

  Failure path this worker catches:

      Pod polls → server claims → mints JIT → returns 200 to Pod
        → row: status='running'
      Pod's tart-kubelet on a degraded node never starts the
        container; OR the runner agent crashes before registering;
        OR network from VM to github.com is broken
        → runner NEVER registers with GitHub
        → no workflow_job.in_progress webhook ever arrives
        → row stays status='running' forever; PG cap slot
          consumed forever; workflow_job stays 'queued' on GitHub
          forever (no runner matched it)
        → customer eventually times out the workflow and ships
          a bug report

  `StaleClaimsWorker` doesn't catch this case: it intentionally
  excludes `lifecycle_state='running'` rows because a real running
  build holds the slot for as long as the build takes (potentially
  hours), and reaping at the 5-min threshold would free the slot
  of an actively-running runner. The signal that distinguishes
  "real running build" from "orphaned mint" is the GitHub-side
  status of the workflow_job — if GH still reports `queued` after
  we've supposedly transitioned through `claimed → running`, the
  runner never registered.

  ## How it works

    1. List lifecycle rows in `status='running'` with
       `started_at < now - @stale_after_seconds`.
    2. For each, call `GET /repos/{owner}/{repo}/actions/jobs/{id}`
       on the org's GitHub App installation.
    3. If GH returns `status: 'queued'` → runner never came up.
       Recover via `Claims.release/2` (with the original
       `claimed_at` as the handle), which deletes the claim and
       re-queues the lifecycle row in one transaction.
    4. If GH returns `status: 'in_progress'` → runner is actually
       running; leave the row alone.
    5. If GH returns `status: 'completed'` → GH has a terminal
       state but we missed the webhook; mark the job completed and
       free the claim.
    6. Any other return / API failure → log and retry next tick.

  ## Threshold

  5 min is the same threshold `StaleClaimsWorker` uses for
  `claimed`. The happy path from mint to runner-registers-with-GH
  is sub-30s in practice (Pod-side: receive JIT → exec run.sh →
  agent registers → GH dispatches the workflow_job); 5 min is a
  generous floor that won't false-positive a slow boot.

  ## Cost

  One GitHub API call per orphaned candidate per tick. Steady-
  state candidates are zero (real running builds are filtered out
  by the GH status check, but only after one call per row). With
  5 concurrent builds and a 1-min cadence that's 5 calls/min ≈
  300/hr per installation, well under the 5,000/hr app-token
  limit.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.VCS

  require Logger

  @stale_after_seconds 300

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@stale_after_seconds, :second)

    rescued =
      threshold
      |> Jobs.list_orphaned_running()
      |> Enum.count(&recover_one/1)

    if rescued > 0 do
      Logger.warning("runners: rescued orphaned running rows",
        count: rescued,
        stale_after_seconds: @stale_after_seconds
      )
    end

    :ok
  end

  defp recover_one(%{
         workflow_job_id: workflow_job_id,
         account_id: account_id,
         repository: repository,
         claimed_at: claimed_at,
         pod_name: pod_name
       }) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id) do
      case GitHubClient.get_workflow_job(installation, repository, workflow_job_id) do
        {:ok, %{status: gh_status, conclusion: conclusion}} ->
          handle_gh_status(gh_status, conclusion, workflow_job_id, claimed_at, pod_name, account)

        {:error, :not_found} ->
          # GH pruned the workflow_job (90-day retention by default).
          # The job can't be live; treat as completed so the PG cap
          # slot doesn't leak forever.
          handle_gh_status("completed", "", workflow_job_id, claimed_at, pod_name, account)

        {:error, reason} ->
          Logger.warning("runners: orphan worker GH lookup failed; will retry next tick",
            workflow_job_id: workflow_job_id,
            reason: inspect(reason)
          )

          false
      end
    else
      {:error, :not_found} ->
        # Account row gone (rare). Leave the orphan; cap accounting
        # is moot if the account itself is deleted.
        false
    end
  end

  defp handle_gh_status("queued", _conclusion, workflow_job_id, claimed_at, pod_name, account) do
    # GitHub still has this job queued, so the runner minted for it never
    # took it. That does NOT mean the Pod holding the claim is idle: GitHub
    # assigns jobs to any label-eligible runner, so it may be busy executing
    # a sibling's job. Releasing on the strength of the claimed job's status
    # alone would delete a live runner's row mid-job, and the executor's
    # `completed` webhook would then find nothing to free — under-counting a
    # working runner for the rest of its run.
    #
    # `executed_workflow_job_id` is set once GitHub proves this runner took
    # some job, so it's the busy signal: skip those and let the executor's
    # completion (or the Pod stopping) free the slot.
    if Claims.executing?(workflow_job_id) do
      Logger.info("runners: orphaned running row — claim's runner is executing another job; leaving it",
        workflow_job_id: workflow_job_id,
        account: account.name,
        pod: pod_name
      )

      false
    else
      requeue_orphan(workflow_job_id, claimed_at, pod_name, account)
    end
  end

  defp handle_gh_status("in_progress", _conclusion, _wfid, _claimed_at, _pod, _account), do: false

  defp handle_gh_status("completed", conclusion, workflow_job_id, _claimed_at, pod_name, account) do
    # GH has a terminal status but we never saw the corresponding
    # `workflow_job.completed` webhook (or it was retry-exhausted
    # before reaching us). Without releasing here, the PG claim
    # stays in `lifecycle_state='running'` forever — StaleClaimsWorker
    # excludes `running`, and this worker would see the same row
    # every minute. The GH lookup already proves the job is not
    # live, so free the cap slot ourselves.
    #
    # Claim-first matches the webhook path
    # (`Tuist.Runners.Dispatch.mark_completed`): frees the slot the
    # instant we know, then records the terminal lifecycle state.
    Logger.warning("runners: orphaned running row — GH completed, freeing claim",
      workflow_job_id: workflow_job_id,
      account: account.name,
      pod: pod_name,
      conclusion: conclusion || ""
    )

    safe_complete_pg(workflow_job_id)
    safe_complete_job(workflow_job_id, conclusion || "")

    :telemetry.execute(
      Telemetry.event_name_recovery(),
      %{count: 1},
      %{kind: "orphan_completed"}
    )

    true
  end

  defp handle_gh_status(other, _conclusion, workflow_job_id, _claimed_at, _pod, _account) do
    # Unknown / future GH status. Log and skip; if it's actually
    # terminal we'll catch it on a later tick once GitHub-side
    # state settles or the 404 fallback above handles retention.
    Logger.debug("runners: orphan worker skipping unrecognised GH state",
      workflow_job_id: workflow_job_id,
      status: other
    )

    false
  end

  defp requeue_orphan(workflow_job_id, claimed_at, pod_name, account) do
    Logger.warning("runners: orphaned running row — GH still queued, recovering",
      workflow_job_id: workflow_job_id,
      account: account.name,
      pod: pod_name
    )

    case Claims.release(workflow_job_id, claimed_at) do
      :ok ->
        :telemetry.execute(
          Telemetry.event_name_recovery(),
          %{count: 1},
          %{kind: "orphan_requeued"}
        )

        true

      {:error, :stale_claim} ->
        # Someone else released + re-claimed between our list and our
        # release; the new claim has a newer claimed_at. Treat as a
        # no-op.
        false
    end
  end

  # `Claims.complete/1` is idempotent and deletes the PG row
  # regardless of the claim handle. Used here because the GH-side
  # job is already terminal — we don't care about handle races, we
  # just want the cap slot back.
  defp safe_complete_pg(workflow_job_id) do
    :ok = Claims.complete(workflow_job_id)
  rescue
    e ->
      Logger.warning("runners: Claims.complete failed in orphan worker; will retry next tick",
        workflow_job_id: workflow_job_id,
        release_error: Exception.message(e)
      )

      :error
  end

  # Terminal lifecycle transition. `Jobs.complete` returns
  # `{:error, :not_found}` when no lifecycle row exists — fine, the
  # claim is already freed by `safe_complete_pg/1`.
  defp safe_complete_job(workflow_job_id, conclusion) do
    case Jobs.complete(workflow_job_id, conclusion) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
    end
  rescue
    e ->
      Logger.warning("runners: Jobs.complete failed in orphan worker; will resolve on next webhook redelivery",
        workflow_job_id: workflow_job_id,
        release_error: Exception.message(e)
      )

      :error
  end
end
