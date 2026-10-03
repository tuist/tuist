defmodule Atlas.Integrations.GitHubAppBootstrap do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Integrations.GitHubApp
  alias Atlas.Integrations.GitHubRepository
  alias Atlas.Repo

  require Logger

  @required_keys [:name, :app_id, :private_key, :webhook_secret]

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :worker,
      restart: :transient
    }
  end

  def start_link(_opts) do
    case ensure_configured() do
      :ok ->
        :ignore

      {:error, :not_configured} ->
        :ignore

      {:error, reason} ->
        Logger.warning("GitHub App bootstrap skipped: #{inspect(reason)}")
        :ignore
    end
  end

  def ensure_configured do
    ensure_configured(Application.get_env(:atlas, :github_app, []))
  end

  def ensure_configured(config) when is_list(config) do
    with :ok <- validate_config(config),
         owner = Keyword.get(config, :owner, "tuist"),
         repo = Keyword.get(config, :repo, "tuist"),
         {:ok, installation_id} <- installation_id(config, owner),
         {:ok, app} <- upsert_app(config, installation_id),
         {:ok, _repository} <- upsert_repository(app, owner, repo) do
      Logger.info("GitHub App #{app.name} configured for #{owner}/#{repo}")
      :ok
    end
  end

  defp validate_config(config) do
    present_keys =
      Enum.filter(@required_keys, fn key ->
        config
        |> Keyword.get(key)
        |> present?()
      end)

    missing_keys =
      Enum.reject(@required_keys, &(&1 in present_keys))

    cond do
      present_keys == [] -> {:error, :not_configured}
      missing_keys == [] -> :ok
      true -> {:error, {:missing_github_app_config, missing_keys}}
    end
  end

  defp installation_id(config, owner) do
    case Keyword.get(config, :installation_id) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        app = %GitHubApp{
          app_id: Keyword.fetch!(config, :app_id),
          private_key: Keyword.fetch!(config, :private_key)
        }

        GitHubAPI.find_installation_id(app, owner)
    end
  end

  defp upsert_app(config, installation_id) do
    attrs = %{
      name: Keyword.fetch!(config, :name),
      app_id: Keyword.fetch!(config, :app_id),
      private_key: Keyword.fetch!(config, :private_key),
      webhook_secret: Keyword.fetch!(config, :webhook_secret),
      installation_id: installation_id
    }

    case find_app(attrs) do
      nil -> %GitHubApp{}
      app -> app
    end
    |> GitHubApp.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp find_app(%{app_id: app_id, name: name}) do
    GitHubApp
    |> where([app], app.app_id == ^app_id or app.name == ^name)
    |> limit(1)
    |> Repo.one()
  end

  defp upsert_repository(%GitHubApp{} = app, owner, repo) do
    attrs = %{owner: owner, repo: repo, github_app_id: app.id}

    case Repo.get_by(GitHubRepository, owner: owner, repo: repo, github_app_id: app.id) do
      nil -> %GitHubRepository{}
      repository -> repository
    end
    |> GitHubRepository.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
