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
end
