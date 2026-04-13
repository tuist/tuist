defmodule Tuist.Runners do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.RunnerConfiguration
  alias Tuist.Runners.RunnerJob
  alias Tuist.VCS.GitHubAppInstallation

  def get_runner_configuration_for_account(account_id) do
    case Repo.get_by(RunnerConfiguration, account_id: account_id) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  def get_runner_configuration_by_installation_id(installation_id) do
    query =
      from rc in RunnerConfiguration,
        join: gai in GitHubAppInstallation,
        on: gai.account_id == rc.account_id,
        where: gai.installation_id == ^to_string(installation_id),
        where: rc.enabled == true

    case Repo.one(query) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  def create_runner_configuration(attrs) do
    attrs
    |> RunnerConfiguration.create_changeset()
    |> Repo.insert()
  end

  def update_runner_configuration(%RunnerConfiguration{} = config, attrs) do
    config
    |> RunnerConfiguration.update_changeset(attrs)
    |> Repo.update()
  end

  def create_runner_job(attrs) do
    attrs
    |> RunnerJob.create_changeset()
    |> Repo.insert()
  end

  def update_runner_job(%RunnerJob{} = job, attrs) do
    job
    |> RunnerJob.update_changeset(attrs)
    |> Repo.update()
  end

  def get_runner_job(id) do
    case Repo.get(RunnerJob, id) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  def get_runner_job_by_github_id(github_workflow_job_id) do
    case Repo.get_by(RunnerJob, github_workflow_job_id: github_workflow_job_id) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  def list_runner_jobs(runner_configuration_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    RunnerJob
    |> where([j], j.runner_configuration_id == ^runner_configuration_id)
    |> order_by([j], desc: j.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def count_active_jobs(runner_configuration_id) do
    RunnerJob
    |> where([j], j.runner_configuration_id == ^runner_configuration_id)
    |> where([j], j.status in [:queued, :provisioning, :in_progress])
    |> Repo.aggregate(:count)
  end

  def labels_match?(job_labels, label_prefix) do
    Enum.any?(job_labels, &String.starts_with?(&1, label_prefix))
  end

  def find_stale_jobs(cutoff) do
    RunnerJob
    |> where([j], j.status in [:provisioning, :in_progress])
    |> where([j], j.updated_at < ^cutoff)
    |> Repo.all()
    |> Repo.preload(:runner_configuration)
  end
end
