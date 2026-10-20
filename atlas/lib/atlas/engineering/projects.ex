defmodule Atlas.Engineering.Projects do
  @moduledoc """
  Projects are the top-level groupings tracked by the Engineering surface:
  a product, codebase, or service. Each project owns its connected GitHub
  repositories and can be tagged with reusable domains.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Domains.GitHubRepository
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Engineering.Projects.ProjectDomain
  alias Atlas.Engineering.Projects.Webhook
  alias Atlas.Engineering.Projects.Webhooks
  alias Atlas.Repo
  alias Ecto.Multi

  def list_projects do
    Project
    |> order_by([project], asc: project.name)
    |> Repo.all()
  end

  def list_visible_projects(_user) do
    # Atlas has no per-user public/private gating today; every authenticated
    # user in Atlas can see the full engineering catalog.
    list_projects()
  end

  def get_project!(id) do
    Project
    |> Repo.get!(id)
    |> Repo.preload([:domains, :github_repositories])
  end

  def fetch_visible_project(id, _user) do
    case Repo.get(Project, id) do
      nil ->
        {:error, :not_found}

      %Project{} = project ->
        {:ok, preload(project)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_project(project \\ %Project{}, attrs \\ %{}), do: Project.changeset(project, attrs)

  def change_repository_for_project(%Project{id: project_id}, attrs \\ %{}) do
    %GitHubRepository{project_id: project_id}
    |> GitHubRepository.changeset(put_project_id(attrs, project_id))
  end

  def create_project(attrs) do
    Multi.new()
    |> Multi.insert(:project, Project.changeset(%Project{}, attrs))
    |> Repo.transaction()
    |> case do
      {:ok, %{project: project}} ->
        audit_project("project.created", project)
        # Mint a default DSN so any Sentry-compatible SDK can start reporting.
        _ = Errors.ensure_default_key(project)
        {:ok, project}

      {:error, :project, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def create_repository_for_project(%Project{id: project_id} = project, attrs) do
    Multi.new()
    |> Multi.insert(
      :repository,
      GitHubRepository.changeset(%GitHubRepository{}, put_project_id(attrs, project_id))
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{repository: repository}} ->
        audit_project("project.repository_linked", project, %{
          "repository_id" => repository.id,
          "owner" => repository.owner,
          "name" => repository.name
        })

        {:ok, repository}

      {:error, :repository, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def update_project(%Project{} = project, attrs) do
    Multi.new()
    |> Multi.update(:project, Project.changeset(project, attrs))
    |> Repo.transaction()
    |> case do
      {:ok, %{project: updated}} ->
        audit_project("project.updated", updated)
        {:ok, updated}

      {:error, :project, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def delete_project(%Project{} = project) do
    Multi.new()
    |> Multi.delete(:project, project)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: deleted}} ->
        audit_project("project.deleted", deleted)
        {:ok, deleted}

      {:error, :project, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def delete_repository_from_project(%Project{id: project_id} = project, repository_id) when is_binary(repository_id) do
    case Repo.get_by(GitHubRepository, id: repository_id, project_id: project_id) do
      %GitHubRepository{} = repository ->
        Multi.new()
        |> Multi.delete(:repository, repository)
        |> Repo.transaction()
        |> case do
          {:ok, %{repository: deleted}} ->
            audit_project("project.repository_unlinked", project, %{
              "repository_id" => deleted.id,
              "owner" => deleted.owner,
              "name" => deleted.name
            })

            {:ok, deleted}

          {:error, :repository, changeset, _changes} ->
            {:error, changeset}
        end

      nil ->
        {:error, :not_found}
    end
  end

  def unlink_domain_from_project(%Project{id: project_id} = project, domain_id) when is_binary(domain_id) do
    Multi.new()
    |> Multi.delete_all(
      :links,
      from(link in ProjectDomain,
        where: link.project_id == ^project_id and link.domain_id == ^domain_id
      )
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        audit_project("project.domain_unlinked", project, %{"domain_id" => domain_id})
        :ok

      {:error, _step, _reason, _changes} ->
        :ok
    end
  end

  def link_domain_to_project(%Project{id: project_id} = project, domain_id) when is_binary(domain_id) do
    case Repo.get(Domain, domain_id) do
      %Domain{} = domain ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Multi.new()
        |> Multi.insert_all(
          :link,
          ProjectDomain,
          [
            %{
              domain_id: domain.id,
              project_id: project_id,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: :nothing,
          conflict_target: [:project_id, :domain_id]
        )
        |> Repo.transaction()
        |> case do
          {:ok, _changes} ->
            audit_project("project.domain_linked", project, %{"domain_id" => domain.id})
            {:ok, domain}

          {:error, _step, changeset, _changes} ->
            {:error, changeset}
        end

      nil ->
        {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def link_domain_to_project(_project, _domain_id), do: {:error, :not_found}

  def list_domains_available_for_project(%Project{id: project_id}) do
    linked_domain_ids =
      ProjectDomain
      |> where([link], link.project_id == ^project_id)
      |> select([link], link.domain_id)

    Domain
    |> where([domain], domain.id not in subquery(linked_domain_ids))
    |> order_by([domain], asc: domain.name)
    |> Repo.all()
  end

  def list_domains_for_project(project_id) when is_binary(project_id) do
    Domain
    |> join(:inner, [domain], link in ProjectDomain, on: link.domain_id == domain.id and link.project_id == ^project_id)
    |> order_by([domain], asc: domain.name)
    |> Repo.all()
  end

  def list_repositories_for_project(project_id) when is_binary(project_id) do
    GitHubRepository
    |> where([repo], repo.project_id == ^project_id)
    |> order_by([repo], asc: repo.owner, asc: repo.name)
    |> Repo.all()
  end

  def list_linked_repository_full_names do
    GitHubRepository
    |> select([repo], {repo.owner, repo.name})
    |> Repo.all()
    |> MapSet.new()
  end

  def create_webhook(%Project{} = project, attrs) do
    case Webhooks.create(project, attrs) do
      {:ok, {webhook, token}} = ok ->
        audit_project("project.webhook_created", project, %{
          "webhook_id" => webhook.id,
          "source" => Atom.to_string(webhook.source),
          "name" => webhook.name
        })

        _ = token
        ok

      {:error, _changeset} = error ->
        error
    end
  end

  def delete_webhook(%Project{} = project, %Webhook{} = webhook) do
    case Webhooks.delete(webhook) do
      {:ok, deleted} ->
        audit_project("project.webhook_deleted", project, %{
          "webhook_id" => deleted.id,
          "source" => Atom.to_string(deleted.source),
          "name" => deleted.name
        })

        {:ok, deleted}

      {:error, _changeset} = error ->
        error
    end
  end

  # Follow-up: wire Grafana webhook ingest once Atlas grows its own alert source.
  def ingest_webhook(:grafana, %Project{} = _project, %Webhook{} = _webhook, _payload) do
    {:error, :not_implemented}
  end

  defp preload(project), do: Repo.preload(project, [:domains, :github_repositories, :webhooks])

  defp put_project_id(attrs, project_id) when is_map(attrs) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, "project_id", project_id)
    else
      Map.put(attrs, :project_id, project_id)
    end
  end

  defp audit_project(action, %Project{} = project, metadata \\ %{}) do
    Audit.record(action, %{
      target_type: "engineering_project",
      target_id: project.id,
      target_label: project.name,
      metadata: metadata
    })
  end
end
