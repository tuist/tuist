defmodule Cache.Application do
  @moduledoc false

  use Application

  alias TuistCommon.Appsignal.ErrorFilter

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    if Cache.Config.analytics_enabled?() do
      Cache.Telemetry.attach()
    end

    Oban.Telemetry.attach_default_logger()
    attach_appsignal_error_filter()

    base_children = [
      Cache.PromEx,
      Cache.Repo,
      {Phoenix.PubSub, name: Cache.PubSub},
      Cache.Authentication,
      Cache.KeyValueStore,
      Cache.MultipartUploads,
      CacheWeb.Endpoint,
      Cache.SocketLinker,
      {Finch, name: Cache.Finch, pools: finch_pools()},
      {Oban, Application.get_env(:cache, Oban)}
    ]

    children =
      if Cache.Config.analytics_enabled?() do
        base_children ++ [Cache.CacheEventsPipeline]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp migrate do
    repos = Application.fetch_env!(:cache, :ecto_repos)

    for repo <- repos do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp attach_appsignal_error_filter do
    :logger.add_primary_filter(
      :appsignal_error_filter,
      {&ErrorFilter.filter/2, []}
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    CacheWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp finch_pools do
    server_url = Application.get_env(:cache, :server_url)

    %{
      :default => [size: 10, start_pool_metrics?: true],
      server_url => [
        conn_opts: [
          log: true,
          protocols: [:http2, :http1],
          transport_opts: [
            cacertfile: CAStore.file_path(),
            verify: :verify_peer
          ]
        ],
        size: 10,
        count: 1,
        protocols: [:http2, :http1],
        start_pool_metrics?: true
      ]
    }
  end
end
