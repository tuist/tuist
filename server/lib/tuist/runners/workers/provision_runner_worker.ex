defmodule Tuist.Runners.Workers.ProvisionRunnerWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Repo
  alias Tuist.Runners
  alias Tuist.Runners.Images
  alias Tuist.Runners.OrchardClient
  alias Tuist.Runners.OrchardConfig
  alias Tuist.VCS.GitHubAppInstallation

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"runner_job_id" => runner_job_id}}) do
    with {:ok, job} <- Runners.get_runner_job(runner_job_id),
         {:ok, config} <- Runners.get_runner_configuration_for_account(job.account_id),
         :ok <- check_concurrency(config),
         {:ok, orchard_config} <- OrchardConfig.for_configuration(config),
         {:ok, installation} <- get_installation(config.account_id) do
      runner_name = "tuist-runner-#{short_uuid()}"
      tart_image = Images.resolve_image(job.labels, config.label_prefix, config.default_tart_image)

      with {:ok, %{encoded_jit_config: jit_config}} <-
             GitHubClient.generate_jit_config(%{
               repository_full_name: job.github_repository_full_name,
               installation_id: installation.installation_id,
               runner_name: runner_name,
               runner_group_id: 1,
               labels: job.labels
             }),
           startup_script = build_startup_script(jit_config),
           {:ok, _vm} <-
             OrchardClient.create_vm(orchard_config, %{
               name: runner_name,
               image: tart_image,
               startup_script: startup_script
             }),
           {:ok, _job} <-
             Runners.update_runner_job(job, %{
               status: :provisioning,
               orchard_vm_name: runner_name,
               runner_name: runner_name,
               tart_image: tart_image
             }) do
        :ok
      else
        {:error, reason} ->
          Logger.error("Failed to provision runner for job #{runner_job_id}: #{inspect(reason)}")

          Runners.update_runner_job(job, %{
            status: :failed,
            error_message: "Provisioning failed: #{inspect(reason)}"
          })

          {:error, reason}
      end
    else
      {:error, :concurrency_limit_reached} ->
        Logger.info("Concurrency limit reached for job #{runner_job_id}, will retry")
        {:snooze, 15}

      {:error, reason} ->
        Logger.error("Failed to provision runner for job #{runner_job_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_concurrency(config) do
    active_count = Runners.count_active_jobs(config.id)

    if active_count < config.max_concurrent_jobs do
      :ok
    else
      {:error, :concurrency_limit_reached}
    end
  end

  defp get_installation(account_id) do
    case Repo.get_by(GitHubAppInstallation, account_id: account_id) do
      nil -> {:error, :no_github_installation}
      installation -> {:ok, installation}
    end
  end

  defp build_startup_script(jit_config) do
    """
    #!/bin/bash
    cd /opt/actions-runner
    ./run.sh --jitconfig #{jit_config}
    """
  end

  defp short_uuid do
    UUIDv7.generate() |> String.split("-") |> List.first()
  end
end
