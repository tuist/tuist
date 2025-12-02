defmodule Tuist.Runners.Workers.CleanupRunnerWorker do
  @moduledoc """
  Background job for cleaning up runners after job completion.

  This worker handles VM cleanup when a GitHub workflow_job
  webhook with action "completed" is received.
  """
  use Oban.Worker, queue: :runners, max_attempts: 3

  alias Tuist.Runners

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    case Runners.get_runner_job(job_id) do
      nil ->
        Logger.error("CleanupRunnerWorker: Job #{job_id} not found")
        {:error, :job_not_found}

      job ->
        Logger.info("CleanupRunnerWorker: Starting cleanup for job #{job_id}")

        case Runners.update_runner_job(job, %{status: :completed}) do
          {:ok, _updated_job} ->
            Logger.info("CleanupRunnerWorker: Job #{job_id} marked as completed")
            :ok

          {:error, changeset} ->
            Logger.error("CleanupRunnerWorker: Failed to update job #{job_id} status: #{inspect(changeset.errors)}")

            {:error, :status_update_failed}
        end
    end
  end
end
