defmodule Tuist.Runners.Workers.LostQueuedJobsWorker do
  @moduledoc """
  Enqueues Tuist jobs GitHub holds `queued` that never reached the
  lifecycle table because their `workflow_job.queued` webhook was lost.

  The webhook is the only path that queues a GitHub job.
  `WebhookRedeliveryWorker` covers a delivery GitHub attempted and saw fail,
  but not one GitHub never attempted, or one we acknowledged and then lost:
  on 2026-11-25, during a GitHub incident, the Backward-Compatibility job
  139343212238 of a production deployment run (`tuist-macos-26-6`) left no
  trace on our side while two jobs GitHub created in the same second were
  enqueued, and the run waited until someone cancelled it 40 minutes later.
  `StaleQueuedJobsWorker` only resolves rows we already have.

  ## How it works

    1. List the GitHub runs that had a job enqueued in the last
       `@lookback_seconds` (`WorkflowJobs.list_recent_github_runs/1`). A run
       whose job was lost almost always has a sibling we did receive.
    2. List each run's jobs on the account's App installation.
    3. Keep jobs that are `queued` or `waiting` on GitHub, were created more
       than `@grace_seconds` ago (a webhook in flight is not lost), have no
       lifecycle row, and whose labels resolve to a Tuist dispatch target.
       The label check keeps jobs for other runners, such as
       `ubuntu-latest`, from logging an ignore every tick.
    4. Hand each to `Dispatch.handle_webhook/3` as the `queued` delivery it
       missed, bound to the run's account. The enqueue takes the per-job
       ordering lock and skips a job that has a row or a recorded
       completion, so a late webhook or a cancelled job is not queued twice.

  ## Cost

  One `GET /repos/{repo}/actions/runs/{id}/jobs` per recently active run per
  tick, on that account's installation token. Runs drop out an hour after
  their last enqueued job.

  Emits `tuist_runners_recovery_count{kind="queued_reconciled"}` per job
  enqueued.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.VCS

  require Logger

  @lookback_seconds 3_600
  @grace_seconds 120

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    created_before = DateTime.add(now, -@grace_seconds, :second)

    enqueued =
      now
      |> DateTime.add(-@lookback_seconds, :second)
      |> WorkflowJobs.list_recent_github_runs()
      |> Enum.group_by(& &1.account_id)
      |> Enum.reduce(0, fn {account_id, runs}, acc -> acc + reconcile_account(account_id, runs, created_before) end)

    if enqueued > 0 do
      Logger.warning("runners: enqueued queued jobs whose webhook was lost", count: enqueued)
    end

    :ok
  end

  defp reconcile_account(account_id, runs, created_before) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(account_id),
         {installation_id, ""} <- Integer.parse(to_string(installation.installation_id)) do
      Enum.reduce(runs, 0, fn run, acc ->
        acc + reconcile_run(account, installation, installation_id, run, created_before)
      end)
    else
      reason ->
        Logger.warning("runners: lost-queued account/installation lookup failed",
          account_id: account_id,
          reason: inspect(reason)
        )

        0
    end
  end

  defp reconcile_run(account, installation, installation_id, run, created_before) do
    case GitHubClient.list_workflow_run_jobs(installation, run.repository, run.workflow_run_id) do
      {:ok, jobs} ->
        jobs
        |> Enum.filter(&lost?(&1, account, created_before))
        |> Enum.count(&enqueue(&1.job, account, installation_id, run.repository))

      {:error, reason} ->
        Logger.warning("runners: lost-queued lookup of run #{run.workflow_run_id} failed; will retry next tick",
          repository: run.repository,
          reason: inspect(reason)
        )

        0
    end
  end

  defp lost?(%{id: id, status: status, job: job}, account, created_before) when status in ["queued", "waiting"] do
    created_before?(job["created_at"], created_before) and not WorkflowJobs.exists?(id) and
      match?({:ok, _target}, Dispatch.resolve_dispatch_target(account, job["labels"] || []))
  end

  defp lost?(_job, _account, _created_before), do: false

  defp created_before?(created_at, threshold) when is_binary(created_at) do
    case DateTime.from_iso8601(created_at) do
      {:ok, at, _offset} -> DateTime.before?(at, threshold)
      _ -> false
    end
  end

  defp created_before?(_created_at, _threshold), do: false

  defp enqueue(job, account, installation_id, repository) do
    payload = %{
      "action" => "queued",
      "workflow_job" => job,
      "repository" => %{"full_name" => repository},
      "installation" => %{"id" => installation_id}
    }

    case Dispatch.handle_webhook(payload, installation_id, account.id) do
      {:ok, _kind} ->
        Logger.warning("runners: enqueued queued job whose webhook was lost",
          account: account.name,
          repository: repository,
          workflow_job_id: job["id"],
          labels: inspect(job["labels"])
        )

        :telemetry.execute(Telemetry.event_name_recovery(), %{count: 1}, %{kind: "queued_reconciled"})
        true

      other ->
        Logger.warning("runners: lost-queued enqueue did not queue the job",
          repository: repository,
          workflow_job_id: job["id"],
          reason: inspect(other)
        )

        false
    end
  end
end
