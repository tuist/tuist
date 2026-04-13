defmodule Tuist.Runners.Workers.CleanupRunnerWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Runners
  alias Tuist.Runners.OrchardClient
  alias Tuist.Runners.OrchardConfig

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"runner_job_id" => runner_job_id}}) do
    with {:ok, job} <- Runners.get_runner_job(runner_job_id),
         {:ok, config} <- Runners.get_runner_configuration_for_account(job.account_id),
         {:ok, orchard_config} <- OrchardConfig.for_configuration(config) do
      if job.orchard_vm_name do
        case OrchardClient.delete_vm(orchard_config, job.orchard_vm_name) do
          :ok ->
            Logger.info("Cleaned up VM #{job.orchard_vm_name} for job #{runner_job_id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to clean up VM #{job.orchard_vm_name} for job #{runner_job_id}: #{inspect(reason)}")

            {:error, reason}
        end
      else
        :ok
      end
    end
  end
end
