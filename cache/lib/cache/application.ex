defmodule Cache.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    if analytics_enabled?() do
      Cache.Telemetry.attach()
    end

    Oban.Telemetry.attach_default_logger()

    base_children = [
      Cache.PromEx,
      Cache.Repo,
      {Phoenix.PubSub, name: Cache.PubSub},
      Cache.Authentication,
      Cache.KeyValueStore,
      Cache.MultipartUploads,
      CacheWeb.Endpoint,
      Cache.SocketLinker,
      {Finch, name: Cache.Finch},
      {Oban, Application.get_env(:cache, Oban)}
    ]

    children =
      if analytics_enabled?() do
        base_children ++ [Cache.CASEventsPipeline]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp analytics_enabled? do
    case Application.get_env(:cache, :cas, []) |> Keyword.get(:api_key) do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  defp migrate do
    repos = Application.fetch_env!(:cache, :ecto_repos)

    for repo <- repos do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    CacheWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
