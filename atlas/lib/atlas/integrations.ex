defmodule Atlas.Integrations do
  @moduledoc """
  Domain boundary for external service integrations managed by Atlas.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Integrations.GitHubApp
  alias Atlas.Integrations.GitHubRepository
  alias Atlas.Repo

  # GitHub Apps

  def list_github_apps do
    GitHubApp
    |> order_by([a], asc: a.name)
    |> Repo.all()
    |> Repo.preload(:repositories)
  end

  def get_github_app(id) do
    GitHubApp
    |> Repo.get(id)
    |> Repo.preload(:repositories)
  end

  def create_github_app(attrs) do
    changeset = GitHubApp.changeset(%GitHubApp{}, attrs)

    changeset
    |> Repo.insert()
    |> record_github_app_change("github_app.created", changeset)
  end

  def update_github_app(%GitHubApp{} = app, attrs) do
    changeset = GitHubApp.changeset(app, attrs)

    changeset
    |> Repo.update()
    |> record_github_app_change("github_app.updated", changeset)
  end

  def delete_github_app(%GitHubApp{} = app) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(
      :repositories,
      from(r in GitHubRepository, where: r.github_app_id == ^app.id)
    )
    |> Ecto.Multi.delete(:app, app)
    |> Repo.transaction()
    |> case do
      {:ok, %{app: app, repositories: {repository_count, _repositories}}} ->
        result = {:ok, app}
        record_github_app_change(result, "github_app.deleted", %{"repositories_deleted" => repository_count})

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  def change_github_app(%GitHubApp{} = app, attrs \\ %{}) do
    GitHubApp.changeset(app, attrs)
  end

  def add_github_repository(%GitHubApp{} = app, attrs) do
    attrs = Map.put(attrs, :github_app_id, app.id)

    %GitHubRepository{}
    |> GitHubRepository.changeset(Map.new(attrs))
    |> Repo.insert()
    |> record_github_repository_change("github_repository.added")
  end

  def delete_github_repository(id) do
    case Repo.get(GitHubRepository, id) do
      nil ->
        {:error, :not_found}

      repository ->
        repository
        |> Repo.delete()
        |> record_github_repository_change("github_repository.deleted")
    end
  end

  def list_github_repositories(%GitHubApp{} = app) do
    GitHubRepository
    |> where([r], r.github_app_id == ^app.id)
    |> order_by([r], asc: r.owner, asc: r.repo)
    |> Repo.all()
  end

  def get_github_repository(owner, repo) when is_binary(owner) and is_binary(repo) do
    GitHubRepository
    |> where([repository], repository.owner == ^owner and repository.repo == ^repo)
    |> preload(:github_app)
    |> Repo.one()
    |> case do
      nil -> {:error, :github_repository_not_configured}
      repository -> {:ok, repository}
    end
  end

  def get_github_repository(github_app_id, owner, repo)
      when is_binary(github_app_id) and is_binary(owner) and is_binary(repo) do
    GitHubRepository
    |> where(
      [repository],
      repository.github_app_id == ^github_app_id and repository.owner == ^owner and repository.repo == ^repo
    )
    |> preload(:github_app)
    |> Repo.one()
    |> case do
      nil -> {:error, :github_repository_not_configured}
      repository -> {:ok, repository}
    end
  end

  defp record_github_app_change({:ok, %GitHubApp{} = app} = result, action, changeset_or_metadata) do
    metadata =
      case changeset_or_metadata do
        %Ecto.Changeset{} = changeset ->
          %{"changed_fields" => changeset.changes |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()}

        metadata when is_map(metadata) ->
          metadata
      end

    Audit.record(action, %{
      target_type: "github_app",
      target_id: app.id,
      target_label: app.name,
      metadata: Map.merge(%{"app_id" => app.app_id}, metadata)
    })

    result
  end

  defp record_github_app_change(result, _action, _metadata), do: result

  defp record_github_repository_change({:ok, %GitHubRepository{} = repository} = result, action) do
    Audit.record(action, %{
      target_type: "github_repository",
      target_id: repository.id,
      target_label: "#{repository.owner}/#{repository.repo}",
      metadata: %{"github_app_id" => repository.github_app_id}
    })

    result
  end

  defp record_github_repository_change(result, _action), do: result
end
