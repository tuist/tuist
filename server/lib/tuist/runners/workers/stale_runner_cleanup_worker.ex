defmodule Tuist.Runners.Workers.StaleRunnerCleanupWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners
  alias Tuist.Runners.OrchardClient
  alias Tuist.Runners.OrchardConfig

  require Logger

  @stale_threshold_hours 2

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_hours, :hour)
    stale_jobs = Runners.find_stale_jobs(cutoff)

    Logger.info("Found #{length(stale_jobs)} stale runner jobs to clean up")

    Enum.each(stale_jobs, &cleanup_stale_job/1)

    :ok
  end

  defp cleanup_stale_job(job) do
    Logger.warning("Cleaning up stale runner job #{job.id} (status: #{job.status}, vm: #{job.orchard_vm_name})")

    if job.orchard_vm_name && job.runner_configuration do
      {:ok, orchard_config} = OrchardConfig.for_configuration(job.runner_configuration)
      OrchardClient.delete_vm(orchard_config, job.orchard_vm_name)
    end

    Runners.update_runner_job(job, %{
      status: :failed,
      error_message: "Job timed out after #{@stale_threshold_hours} hours",
      completed_at: DateTime.utc_now()
    })
  end
end
