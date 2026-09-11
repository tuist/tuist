defmodule Tuist.Runners.JobReports do
  @moduledoc "Common job-scoped log, outcome and billing handling for runner-reported providers."

  alias Tuist.Repo
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Runners.WorkflowJob

  require Logger

  @archive_delay_seconds 300

  @doc """
  Whether a job is still accepting log lines.

  Open while the job has not completed, and for `grace_seconds` after it
  did: the log is uploaded after the finish report, so a settled job is
  still expecting its own upload. Past that a recovered token can no
  longer append to a job that is done.

  A job with no lifecycle row has not settled as far as we can tell, so
  it stays open. The token already proves the job exists, and the line
  ceiling bounds what it can store; refusing here would drop the logs of
  any job whose lifecycle write did not land.
  """
  def log_window_open?(workflow_job_id, grace_seconds) when is_integer(workflow_job_id) do
    case Repo.get(WorkflowJob, workflow_job_id) do
      nil -> true
      %WorkflowJob{completed_at: nil} -> true
      %WorkflowJob{completed_at: at} -> DateTime.diff(DateTime.utc_now(), at, :second) <= grace_seconds
    end
  end

  @doc """
  The runner name bound to a job's open session.

  The finish report names its job through the report token, but the claim
  and session layers are keyed on the runner, so the two have to be
  joined before the completion can release anything. Returns
  `{:error, :no_session}` once the session is closed, which is a settled
  job rather than a failure.
  """
  def runner_name_for_job(workflow_job_id, account_id) do
    case RunnerSessions.live_for_workflow_job(workflow_job_id, account_id) do
      {:ok, %{runner_name: runner_name}} when is_binary(runner_name) and runner_name != "" ->
        {:ok, runner_name}

      _ ->
        {:error, :no_session}
    end
  end

  @doc """
  Completes a runner-reported job from what its agent reported on the way out.

  The GitHub lane learns all of this from the `workflow_job.completed`
  webhook. Here the agent runs inside our own VM, so the VM is the
  source: a `pre-exit` hook posts the window and the exit status, which
  means the customer configures no webhook and hands us no second
  credential.

  The billable window is the job's own start and finish, not the Pod's,
  for the same reason as the GitHub lane: the Pod boots a VM before the
  job can start and holds the host through cache work afterwards, and
  that overhead is ours.
  """
  def record_job_finished(runner_name, account_id, report) when is_binary(runner_name) and is_integer(account_id) do
    %{workflow_job_id: workflow_job_id, conclusion: conclusion} = report

    window = observed_window(workflow_job_id)

    case RunnerSessions.record_execution(runner_name, workflow_job_id, account_id, window) do
      {:error, changeset} ->
        # The window is recorded nowhere else, so a failed write here is
        # lost usage rather than lost attribution. Refuse the report and
        # let the agent's retry carry it.
        {:error, {:session_execution_write_failed, inspect(changeset.errors)}}

      _outcome ->
        Jobs.with_workflow_job_ordering_lock(workflow_job_id, fn ->
          Claims.complete_by_runner_name(runner_name, account_id, workflow_job_id)

          case Jobs.complete(workflow_job_id, conclusion) do
            {:ok, _job} -> enqueue_archive(workflow_job_id, account_id)
            {:error, :not_found} -> :ok
            other -> other
          end
        end)
    end
  end

  # The billable window is measured by us, never reported by the job.
  #
  # The report arrives from a hook running inside the customer's own job,
  # which can read its credential and post whatever it likes. Timestamps
  # taken from that body would let a job bill itself for zero seconds.
  # `started_at` is the lifecycle row's, stamped server-side when the
  # dispatch marked the job running, and the end is when this report
  # lands. The hook posts the finish before uploading the log so that
  # upload is not inside the window.
  defp observed_window(workflow_job_id) do
    case Repo.get(WorkflowJob, workflow_job_id) do
      %WorkflowJob{started_at: %DateTime{} = started_at} ->
        %{started_at: started_at, ended_at: DateTime.utc_now()}

      _ ->
        %{started_at: nil, ended_at: nil}
    end
  end

  # The GitHub lane archives from `FetchLogsWorker`, at the end of the
  # pull that ingested the lines. Here ingestion finished before this
  # report arrived, so the finish is the point at which the log is known
  # to be whole.
  defp enqueue_archive(workflow_job_id, account_id) do
    %{workflow_job_id: workflow_job_id, account_id: account_id}
    |> ArchiveLogsWorker.new(schedule_in: @archive_delay_seconds)
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("runners: failed to enqueue runner log archive",
          workflow_job_id: workflow_job_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  @doc """
  An exit status the agent reported, as a lifecycle conclusion.

  Buildkite's own vocabulary for a finished job is a numeric exit status
  plus a cancellation flag; the lifecycle table speaks GitHub's, and the
  dashboard renders that. Mapping here keeps the difference from
  reaching either.
  """
  def conclusion_for(%{cancelled: true}), do: "cancelled"
  def conclusion_for(%{exit_status: 0}), do: "success"
  def conclusion_for(_report), do: "failure"
end
