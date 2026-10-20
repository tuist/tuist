defmodule Atlas.Engineering.Domains do
  @moduledoc """
  Configures the domains managed by the Engineering surface. Domains are
  reusable tags that can be associated with one or more projects;
  repositories belong to the project, not directly to a domain.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Domains.GitHubRepository
  alias Atlas.Engineering.Projects.ProjectDomain
  alias Atlas.Repo
  alias Ecto.Multi

  def list_domains do
    Domain
    |> order_by([domain], asc: domain.name)
    |> preload(projects: :github_repositories)
    |> Repo.all()
  end

  def list_visible_domains(_user) do
    Domain
    |> order_by([domain], asc: domain.name)
    |> preload(projects: :github_repositories)
    |> Repo.all()
  end

  def get_domain!(id) do
    Domain
    |> preload(projects: :github_repositories)
    |> Repo.get!(id)
  end

  def fetch_visible_domain(id, _user) do
    case Repo.get(Domain, id) do
      nil ->
        {:error, :not_found}

      %Domain{} = domain ->
        {:ok, preload_full(domain)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_domain(domain \\ %Domain{}, attrs \\ %{}) do
    Domain.changeset(domain, attrs)
  end

  def create_domain(attrs) do
    changeset = change_domain(%Domain{}, attrs)
    project_id = project_id_from_changeset(changeset)
    repository_attrs = Domain.repository_attrs(changeset)

    if changeset.valid? do
      Multi.new()
      |> Multi.insert(:domain, changeset)
      |> link_project_multi(project_id)
      |> upsert_repository_multi(repository_attrs, project_id)
      |> Repo.transaction()
      |> case do
        {:ok, %{domain: domain}} ->
          domain = preload_full(domain)
          audit_domain("engineering_domain.created", domain)
          {:ok, domain}

        {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  def delete_domain(%Domain{} = domain) do
    case Repo.delete(domain) do
      {:ok, deleted} ->
        audit_domain("engineering_domain.deleted", deleted)
        {:ok, deleted}

      {:error, _changeset} = error ->
        error
    end
  end

  def update_domain(%Domain{} = domain, attrs) do
    domain = preload_full(domain)
    changeset = change_domain(domain, attrs)
    project_id = project_id_from_changeset(changeset) || first_project_id(domain)
    repository_fields_present? = repository_fields_present?(attrs)
    repository_attrs = Domain.repository_attrs(changeset)

    if changeset.valid? do
      Multi.new()
      |> Multi.update(:domain, changeset)
      |> link_project_multi(project_id)
      |> maybe_replace_repository(repository_attrs, repository_fields_present?, project_id)
      |> Repo.transaction()
      |> case do
        {:ok, %{domain: domain}} ->
          domain = preload_full(domain)
          audit_domain("engineering_domain.updated", domain)
          {:ok, domain}

        {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp audit_domain(action, %Domain{} = domain) do
    Audit.record(action, %{
      target_type: "engineering_domain",
      target_id: domain.id,
      target_label: domain.name,
      metadata: %{}
    })
  end

  def link_domain_to_project(%Domain{id: domain_id}, project_id) when is_binary(project_id) do
    link_domain_to_project(domain_id, project_id)
  end

  def link_domain_to_project(domain_id, project_id) when is_binary(domain_id) and is_binary(project_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      ProjectDomain,
      [
        %{
          domain_id: domain_id,
          project_id: project_id,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:project_id, :domain_id]
    )

    :ok
  end

  def unlink_domain_from_project(%Domain{id: domain_id}, project_id) when is_binary(project_id) do
    unlink_domain_from_project(domain_id, project_id)
  end

  def unlink_domain_from_project(domain_id, project_id) when is_binary(domain_id) and is_binary(project_id) do
    ProjectDomain
    |> where([link], link.domain_id == ^domain_id and link.project_id == ^project_id)
    |> Repo.delete_all()

    :ok
  end

  defp link_project_multi(multi, nil), do: multi

  defp link_project_multi(multi, project_id) do
    Multi.run(multi, :project_domain, fn _repo, %{domain: domain} ->
      link_domain_to_project(domain, project_id)
      {:ok, :linked}
    end)
  end

  defp upsert_repository_multi(multi, nil, _project_id), do: multi
  defp upsert_repository_multi(multi, _repository_attrs, nil), do: multi

  defp upsert_repository_multi(multi, repository_attrs, project_id) do
    Multi.run(multi, :github_repository, fn repo, %{domain: domain} ->
      attrs = Map.put(repository_attrs, :project_id, project_id || domain.project_id)
      get_or_create_github_repository(repo, attrs)
    end)
  end

  defp maybe_replace_repository(multi, _repository_attrs, false, _project_id), do: multi
  defp maybe_replace_repository(multi, nil, true, _project_id), do: multi
  defp maybe_replace_repository(multi, _repository_attrs, true, nil), do: multi

  defp maybe_replace_repository(multi, repository_attrs, true, project_id) do
    Multi.run(multi, :github_repository, fn repo, _changes ->
      attrs = Map.put(repository_attrs, :project_id, project_id)
      get_or_create_github_repository(repo, attrs)
    end)
  end

  defp get_or_create_github_repository(repo, attrs) do
    case repo.get_by(GitHubRepository, owner: attrs.owner, name: attrs.name) do
      %GitHubRepository{} = repository ->
        repository
        |> GitHubRepository.changeset(attrs)
        |> repo.update()

      nil ->
        %GitHubRepository{}
        |> GitHubRepository.changeset(attrs)
        |> repo.insert()
    end
  end

  defp repository_fields_present?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, "github_repository_owner") or
      Map.has_key?(attrs, :github_repository_owner) or
      Map.has_key?(attrs, "github_repository_name") or
      Map.has_key?(attrs, :github_repository_name)
  end

  defp repository_fields_present?(_attrs), do: false

  defp project_id_from_changeset(changeset) do
    changeset
    |> Ecto.Changeset.get_field(:project_id)
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp first_project_id(%{projects: projects}) when is_list(projects) do
    projects
    |> Enum.map(& &1.id)
    |> Enum.find(&is_binary/1)
  end

  defp first_project_id(_domain), do: nil

  defp preload_full(domain), do: Repo.preload(domain, [projects: :github_repositories], force: true)
end
