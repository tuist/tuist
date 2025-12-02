defmodule Tuist.Runners do
  @moduledoc """
  The Runners context for managing Tuist Runners functionality.
  """

  alias Tuist.Runners.RunnerHost
  alias Tuist.Runners.RunnerImage
  alias Tuist.Runners.RunnerJob
  alias Tuist.Runners.RunnerOrganization

  @doc """
  Returns the list of runner hosts.
  """
  def list_runner_hosts do
    Tuist.Repo.all(RunnerHost)
  end

  @doc """
  Gets a single runner host.
  """
  def get_runner_host(id), do: Tuist.Repo.get(RunnerHost, id)

  @doc """
  Creates a runner host.
  """
  def create_runner_host(attrs \\ %{}) do
    %RunnerHost{id: UUIDv7.generate()}
    |> RunnerHost.changeset(attrs)
    |> Tuist.Repo.insert()
  end

  @doc """
  Updates a runner host.
  """
  def update_runner_host(%RunnerHost{} = runner_host, attrs) do
    runner_host
    |> RunnerHost.changeset(attrs)
    |> Tuist.Repo.update()
  end

  @doc """
  Deletes a runner host.
  """
  def delete_runner_host(%RunnerHost{} = runner_host) do
    Tuist.Repo.delete(runner_host)
  end

  @doc """
  Returns the list of runner images.
  """
  def list_runner_images do
    Tuist.Repo.all(RunnerImage)
  end

  @doc """
  Gets a single runner image.
  """
  def get_runner_image(id), do: Tuist.Repo.get(RunnerImage, id)

  @doc """
  Creates a runner image.
  """
  def create_runner_image(attrs \\ %{}) do
    %RunnerImage{id: UUIDv7.generate()}
    |> RunnerImage.changeset(attrs)
    |> Tuist.Repo.insert()
  end

  @doc """
  Updates a runner image.
  """
  def update_runner_image(%RunnerImage{} = runner_image, attrs) do
    runner_image
    |> RunnerImage.changeset(attrs)
    |> Tuist.Repo.update()
  end

  @doc """
  Deletes a runner image.
  """
  def delete_runner_image(%RunnerImage{} = runner_image) do
    Tuist.Repo.delete(runner_image)
  end

  @doc """
  Returns the list of runner jobs.
  """
  def list_runner_jobs do
    Tuist.Repo.all(RunnerJob)
  end

  @doc """
  Gets a single runner job.
  """
  def get_runner_job(id), do: Tuist.Repo.get(RunnerJob, id)

  @doc """
  Gets a runner job by GitHub job ID.
  """
  def get_runner_job_by_github_job_id(github_job_id) do
    Tuist.Repo.one(RunnerJob.by_github_job_id_query(github_job_id))
  end

  @doc """
  Creates a runner job.
  """
  def create_runner_job(attrs \\ %{}) do
    %RunnerJob{id: UUIDv7.generate()}
    |> RunnerJob.changeset(attrs)
    |> Tuist.Repo.insert()
  end

  @doc """
  Updates a runner job.
  """
  def update_runner_job(%RunnerJob{} = runner_job, attrs) do
    runner_job
    |> RunnerJob.changeset(attrs)
    |> Tuist.Repo.update()
  end

  @doc """
  Deletes a runner job.
  """
  def delete_runner_job(%RunnerJob{} = runner_job) do
    Tuist.Repo.delete(runner_job)
  end

  @doc """
  Returns the list of runner organizations.
  """
  def list_runner_organizations do
    Tuist.Repo.all(RunnerOrganization)
  end

  @doc """
  Gets a single runner organization.
  """
  def get_runner_organization(id), do: Tuist.Repo.get(RunnerOrganization, id)

  @doc """
  Gets a runner organization by account ID.
  """
  def get_runner_organization_by_account_id(account_id) do
    Tuist.Repo.one(RunnerOrganization.by_account_id_query(account_id))
  end

  @doc """
  Gets a runner organization by GitHub app installation ID.
  """
  def get_runner_organization_by_github_installation_id(installation_id) do
    Tuist.Repo.one(RunnerOrganization.by_github_installation_id_query(installation_id))
  end

  @doc """
  Creates a runner organization.
  """
  def create_runner_organization(attrs \\ %{}) do
    %RunnerOrganization{id: UUIDv7.generate()}
    |> RunnerOrganization.changeset(attrs)
    |> Tuist.Repo.insert()
  end

  @doc """
  Updates a runner organization.
  """
  def update_runner_organization(%RunnerOrganization{} = runner_organization, attrs) do
    runner_organization
    |> RunnerOrganization.changeset(attrs)
    |> Tuist.Repo.update()
  end

  @doc """
  Deletes a runner organization.
  """
  def delete_runner_organization(%RunnerOrganization{} = runner_organization) do
    Tuist.Repo.delete(runner_organization)
  end

  @doc """
  Gets available runner hosts for job assignment.
  """
  def get_available_hosts do
    Tuist.Repo.all(RunnerHost.available_query())
  end

  @doc """
  Gets pending runner jobs.
  """
  def get_pending_jobs do
    Tuist.Repo.all(RunnerJob.pending_query())
  end

  @doc """
  Gets active runner images by labels.
  """
  def get_active_images_by_labels(labels) do
    labels
    |> RunnerImage.by_labels_query()
    |> Tuist.Repo.all()
  end

  @doc """
  Gets enabled runner organizations.
  """
  def get_enabled_organizations do
    Tuist.Repo.all(RunnerOrganization.enabled_query())
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
      repo: workflow_job["repository_full_name"] || extract_repo_name(workflow_job),
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
