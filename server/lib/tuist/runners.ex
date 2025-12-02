defmodule Tuist.Runners do
  @moduledoc """
  The Runners context for managing Tuist Runners functionality.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.RunnerHost
  alias Tuist.Runners.RunnerJob
  alias Tuist.Runners.RunnerOrganization

  require Logger

  @doc """
  Returns the list of runner hosts.
  """
  def list_runner_hosts do
    Repo.all(RunnerHost)
  end

  @doc """
  Gets a single runner host.
  """
  def get_runner_host(id), do: Repo.get(RunnerHost, id)

  @doc """
  Creates a runner host.
  """
  def create_runner_host(attrs \\ %{}) do
    %RunnerHost{id: UUIDv7.generate()}
    |> RunnerHost.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a runner host.
  """
  def update_runner_host(%RunnerHost{} = runner_host, attrs) do
    runner_host
    |> RunnerHost.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a runner host.
  """
  def delete_runner_host(%RunnerHost{} = runner_host) do
    Repo.delete(runner_host)
  end

  @doc """
  Returns the list of runner jobs.
  """
  def list_runner_jobs do
    Repo.all(RunnerJob)
  end

  @doc """
  Gets a single runner job.
  """
  def get_runner_job(id), do: Repo.get(RunnerJob, id)

  @doc """
  Gets a single runner job with its associated host preloaded.
  """
  def get_runner_job_with_host(id) do
    RunnerJob
    |> Repo.get(id)
    |> Repo.preload(:host)
  end

  @doc """
  Gets a runner job by GitHub job ID.
  """
  def get_runner_job_by_github_job_id(github_job_id) do
    Repo.one(RunnerJob.by_github_job_id_query(github_job_id))
  end

  @doc """
  Creates a runner job.
  """
  def create_runner_job(attrs \\ %{}) do
    %RunnerJob{id: UUIDv7.generate()}
    |> RunnerJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a runner job.
  """
  def update_runner_job(%RunnerJob{} = runner_job, attrs) do
    runner_job
    |> RunnerJob.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a runner job.
  """
  def delete_runner_job(%RunnerJob{} = runner_job) do
    Repo.delete(runner_job)
  end

  @doc """
  Returns the list of runner organizations.
  """
  def list_runner_organizations do
    Repo.all(RunnerOrganization)
  end

  @doc """
  Gets a single runner organization.
  """
  def get_runner_organization(id), do: Repo.get(RunnerOrganization, id)

  @doc """
  Gets a runner organization by account ID.
  """
  def get_runner_organization_by_account_id(account_id) do
    Repo.one(RunnerOrganization.by_account_id_query(account_id))
  end

  @doc """
  Gets a runner organization by GitHub app installation ID.
  """
  def get_runner_organization_by_github_installation_id(installation_id) do
    Repo.one(RunnerOrganization.by_github_installation_id_query(installation_id))
  end

  @doc """
  Creates a runner organization.
  """
  def create_runner_organization(attrs \\ %{}) do
    %RunnerOrganization{id: UUIDv7.generate()}
    |> RunnerOrganization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a runner organization.
  """
  def update_runner_organization(%RunnerOrganization{} = runner_organization, attrs) do
    runner_organization
    |> RunnerOrganization.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a runner organization.
  """
  def delete_runner_organization(%RunnerOrganization{} = runner_organization) do
    Repo.delete(runner_organization)
  end

  @doc """
  Gets available runner hosts for job assignment.
  Returns hosts that are online and have capacity for more jobs.
  """
  def get_available_hosts do
    Repo.all(RunnerHost.available_query())
  end

  @doc """
  Gets the best available host for a new job.
  Returns the host with the most available capacity (least loaded).
  """
  def get_best_available_host do
    RunnerHost.by_available_capacity_query()
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets the count of active jobs for a host.
  Active jobs are those in pending, spawning, running, or cleanup states.
  """
  def get_active_job_count(host_id) do
    host_id
    |> RunnerJob.by_host_query()
    |> where([j], j.status in [:pending, :spawning, :running, :cleanup])
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if a host has capacity for another job.
  """
  def host_has_capacity?(%RunnerHost{} = host) do
    get_active_job_count(host.id) < host.capacity
  end

  @doc """
  Gets the count of active jobs for an organization.
  """
  def get_organization_active_job_count(organization_id) do
    Repo.aggregate(
      from(j in RunnerJob,
        where: j.organization_id == ^organization_id,
        where: j.status in [:pending, :spawning, :running, :cleanup]
      ),
      :count
    )
  end

  @doc """
  Checks if an organization has capacity for another job.
  Returns true if max_concurrent_jobs is nil (unlimited) or if under the limit.
  """
  def organization_has_capacity?(%RunnerOrganization{max_concurrent_jobs: nil}), do: true

  def organization_has_capacity?(%RunnerOrganization{} = org) do
    get_organization_active_job_count(org.id) < org.max_concurrent_jobs
  end

  @doc """
  Gets pending runner jobs.
  """
  def get_pending_jobs do
    Repo.all(RunnerJob.pending_query())
  end

  @doc """
  Gets enabled runner organizations.
  """
  def get_enabled_organizations do
    Repo.all(RunnerOrganization.enabled_query())
  end

  @default_label_prefix "tuist-runners"

  @doc """
  Checks if a job with the given labels should be handled by Tuist Runners.

  Returns `{:ok, runner_organization}` if the job should be handled,
  or `{:ignore, reason}` if it should be ignored.
  """
  def should_handle_job?(labels, installation_id) when is_list(labels) do
    case get_runner_organization_by_github_installation_id(installation_id) do
      nil ->
        {:ignore, :organization_not_found}

      %RunnerOrganization{enabled: false} ->
        {:ignore, :organization_disabled}

      %RunnerOrganization{} = org ->
        label_prefix = org.label_prefix || @default_label_prefix

        if Enum.any?(labels, &(&1 == label_prefix)) do
          {:ok, org}
        else
          {:ignore, :label_prefix_not_matched}
        end
    end
  end

  @doc """
  Creates a runner job from a GitHub workflow_job webhook payload.
  """
  def create_job_from_webhook(workflow_job, organization, runner_org) do
    attrs = %{
      github_job_id: workflow_job["id"],
      run_id: workflow_job["run_id"],
      org: organization["login"],
      repo: "tuist",
      # repo: workflow_job["repository_full_name"] || extract_repo_name(workflow_job),
      labels: workflow_job["labels"] || [],
      status: :pending,
      organization_id: runner_org.id,
      github_workflow_url: workflow_job["html_url"]
    }

    create_runner_job(attrs)
  end

  defp extract_repo_name(%{"head_repository" => %{"full_name" => name}}), do: name
  defp extract_repo_name(_), do: nil
end
