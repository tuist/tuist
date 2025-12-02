defmodule Tuist.Runners.Workers.SpawnRunnerWorker do
  @moduledoc """
  Background job for spawning runners on Mac hosts.

  This worker handles async runner spawning when a GitHub workflow_job
  webhook with action "queued" is received.
  """
  use Oban.Worker, queue: :runners, max_attempts: 3

  alias Tuist.Runners

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    case Runners.get_runner_job(job_id) do
      nil ->
        Logger.error("SpawnRunnerWorker: Job #{job_id} not found")
        {:error, :job_not_found}

      job ->
        Logger.info("SpawnRunnerWorker: Starting spawn for job #{job_id}")

        case Runners.update_runner_job(job, %{status: :spawning}) do
          {:ok, _updated_job} ->
            :ok

          {:error, changeset} ->
            Logger.error("SpawnRunnerWorker: Failed to update job #{job_id} status: #{inspect(changeset.errors)}")

            {:error, :status_update_failed}
        end
    end
  end
end
