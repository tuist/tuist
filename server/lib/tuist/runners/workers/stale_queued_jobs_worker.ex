defmodule Tuist.Runners.Workers.StaleQueuedJobsWorker do
  @moduledoc """
  Resolves `runner_jobs` rows stranded in `status = 'queued'` —
  enqueued from a `workflow_job.queued` webhook but never moved to a
  terminal state.

  ## How a row gets stranded in `queued`

  A queued row leaves the queue exactly two ways: a Pod claims it
  (`queued → claimed → running → completed`) or a
  `workflow_job.completed` webhook marks it `completed`. Both can
  fail to happen together:

    * No Tuist runner ever registers with GitHub to accept the job
      (the pool was removed, runners were disabled for the account,
      or the account sat at its concurrency cap until the run was
      abandoned), so it's never claimed. GitHub keeps it `queued` on
      its side too.
    * GitHub therefore never fires `workflow_job.completed` — there
      was no run to complete — or the delivery was lost past the
      15-min `WebhookRedeliveryWorker` window.

  The row then shows `queued` on the dashboard forever.
  `StaleClaimsWorker` only reaps PG `claimed` rows and
  `OrphanedRunnersWorker` only reaps CH `running` rows, so neither
  covers `queued`. This worker closes that gap.

  ## How it works

    1. List `runner_jobs FINAL` rows in `status='queued'` with
       `enqueued_at` older than `@verify_after_seconds`.
    2. For each, `GET /repos/{owner}/{repo}/actions/jobs/{id}` on the
       account's GitHub App installation:
         * `completed` → we missed the webhook; mark completed with
           GitHub's conclusion.
         * `404` → GitHub pruned the job (cancelled + retention, or
           superseded); it can't be live — mark completed.
         * `in_progress` → a runner accepted it outside our dispatch
           flow; it's live and the completed webhook will land. Leave
           it.
         * `queued` → still legitimately pending; leave it, unless it
           is past the hard backstop (below).
    3. Hard backstop: any row queued longer than `@reap_after_seconds`
       that GitHub still reports `queued`, can't be addressed (empty
       repository), or can't be verified (API down) is force-completed
       with conclusion `"stale"`. Past that age nothing will ever move
       it, so the guarantee "a job can't get stuck in queued" holds
       even when GitHub never resolves it.

  `in_progress` is the only state never force-completed: GitHub's own
  per-job execution limit means a genuinely-running job terminates
  (and fires `completed`) well before the backstop matters.

  ## Threshold rationale

  `@verify_after_seconds` (1h) is generous — the warm pool claims a
  queued job within seconds and even an at-cap wait clears in minutes,
  so a job still queued after an hour is anomalous and worth a GitHub
  round-trip. Steady-state candidate count is ~zero, so the GitHub API
  cost is near nil. `@reap_after_seconds` (24h) sits well beyond any
  legitimate queue wait.

  ## Recovery order (PG first)

  `complete/3` frees the PG cap slot before recording the CH terminal
  state, matching the webhook path
  (`Tuist.Runners.Dispatch.mark_completed`). A queued row normally has
  no PG claim, but the `StaleClaimsWorker` CH-first crash window can
  leave CH=`queued` / PG=`claimed`; freeing PG defensively keeps a
  stranded claim from leaking the slot.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.VCS

  require Logger

  @verify_after_seconds 3_600
  @reap_after_seconds 86_400

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    verify_threshold = DateTime.add(now, -@verify_after_seconds, :second)
    reap_threshold = DateTime.add(now, -@reap_after_seconds, :second)

    resolved =
      verify_threshold
      |> Jobs.list_stale_queued()
      |> Enum.count(&recover_one(&1, reap_threshold))

    if resolved > 0 do
      Logger.warning("runners: resolved stale queued rows",
        count: resolved,
        verify_after_seconds: @verify_after_seconds,
        reap_after_seconds: @reap_after_seconds
      )
    end

    :ok
  end

  # No repository on the row (legacy pre-profiles enqueue) — we can't
  # address GitHub's Actions jobs API to verify, so only the hard
  # backstop can resolve it.
  defp recover_one(%{repository: repository} = candidate, reap_threshold) when repository in [nil, ""] do
    reap_if_past_backstop(candidate, reap_threshold)
  end

  defp recover_one(candidate, reap_threshold) do
    %{account_id: account_id, repository: repository, workflow_job_id: workflow_job_id} = candidate

    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id) do
      case GitHubClient.get_workflow_job(installation, repository, workflow_job_id) do
        {:ok, %{status: gh_status, conclusion: conclusion}} ->
          handle_gh_status(gh_status, conclusion, candidate, reap_threshold)

        {:error, :not_found} ->
          complete(workflow_job_id, "", "queued_completed")

        {:error, reason} ->
          Logger.warning("runners: stale-queued GH lookup failed; applying backstop only",
            workflow_job_id: workflow_job_id,
            reason: inspect(reason)
          )

          reap_if_past_backstop(candidate, reap_threshold)
      end
    else
      {:error, reason} ->
        Logger.warning("runners: stale-queued account/installation lookup failed; applying backstop only",
          workflow_job_id: workflow_job_id,
          reason: inspect(reason)
        )

        reap_if_past_backstop(candidate, reap_threshold)
    end
  end

  defp handle_gh_status("completed", conclusion, candidate, _reap_threshold) do
    Logger.warning("runners: stale queued row — GH completed, reconciling",
      workflow_job_id: candidate.workflow_job_id
    )

    complete(candidate.workflow_job_id, conclusion || "", "queued_completed")
  end

  # A runner accepted the job outside our dispatch flow (or we missed
  # the transition). It's live; the completed webhook will land. Never
  # force-complete a running job, no matter how old.
  defp handle_gh_status("in_progress", _conclusion, _candidate, _reap_threshold), do: false

  # GitHub agrees it's still queued. A runner could still pick it up
  # (account at cap, pool scaling), so leave it — unless it's past the
  # hard backstop, where nothing will ever move it.
  defp handle_gh_status("queued", _conclusion, candidate, reap_threshold) do
    reap_if_past_backstop(candidate, reap_threshold)
  end

  defp handle_gh_status(other, _conclusion, candidate, reap_threshold) do
    Logger.debug("runners: stale-queued unrecognised GH state",
      workflow_job_id: candidate.workflow_job_id,
      status: other
    )

    reap_if_past_backstop(candidate, reap_threshold)
  end

  defp reap_if_past_backstop(%{enqueued_at: %DateTime{} = enqueued_at} = candidate, reap_threshold) do
    if DateTime.before?(enqueued_at, reap_threshold) do
      Logger.warning("runners: reaping queued row past backstop",
        workflow_job_id: candidate.workflow_job_id,
        enqueued_at: enqueued_at
      )

      complete(candidate.workflow_job_id, "stale", "queued_reaped")
    else
      false
    end
  end

  defp reap_if_past_backstop(_candidate, _reap_threshold), do: false

  # Free the PG cap slot first (defensive — a queued row normally has
  # no claim, but the StaleClaimsWorker CH-first crash window can leave
  # CH=`queued` / PG=`claimed`), then record the terminal state in CH
  # for customer visibility. Both are idempotent. A DB error crashes
  # the tick; the cron retries in 5 min and the row stays queued
  # meanwhile, which is harmless.
  defp complete(workflow_job_id, conclusion, kind) do
    :ok = Claims.complete(workflow_job_id)
    Jobs.complete(workflow_job_id, conclusion)
    :telemetry.execute(Telemetry.event_name_recovery(), %{count: 1}, %{kind: kind})
    true
  end
end
