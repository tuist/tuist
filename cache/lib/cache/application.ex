defmodule Cache.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    if Cache.Config.analytics_enabled?() do
      Cache.Telemetry.attach()
    end

    Oban.Telemetry.attach_default_logger()
    start_sentry_logger()
    start_loki_logger()
    start_opentelemetry()

    base_children = [
      Cache.Repo,
      Cache.KeyValueBuffer,
      Cache.CacheArtifactsBuffer,
      Cache.S3TransfersBuffer,
      {Phoenix.PubSub, name: Cache.PubSub},
      Cache.Authentication,
      Cache.S3,
      Cache.KeyValueStore,
      Cache.MultipartUploads,
      Cache.Registry.Metadata,
      CacheWeb.Endpoint,
      Cache.SocketLinker,
      # Cannot alias Cache.Finch to Finch or it'll conflict with the top-level library
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      {Finch, name: Cache.Finch, pools: Cache.Finch.Pools.config()},
      Cache.PromEx,
      {Oban, Application.get_env(:cache, Oban)}
    ]

    children =
      if Cache.Config.analytics_enabled?() do
        base_children ++ [Cache.CASEventsPipeline, Cache.GradleCacheEventsPipeline]
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

  defp start_sentry_logger do
    if Application.get_env(:sentry, :dsn) do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })
    end
  end

  defp start_loki_logger do
    loki_url = System.get_env("LOKI_URL")

    if loki_url do
      LokiLoggerHandler.attach(:loki_handler,
        loki_url: loki_url,
        storage: :memory,
        labels: %{
          app: {:static, "tuist-cache"},
          service_name: {:static, "tuist-cache"},
          service_namespace: {:static, "tuist"},
          env: {:static, System.get_env("DEPLOY_ENV") || "production"},
          level: :level
        },
        structured_metadata: [:trace_id, :span_id, :request_id]
      )
    end
  end

  defp start_opentelemetry do
    if Application.get_env(:opentelemetry, :traces_exporter) != :none do
      OpentelemetryLoggerMetadata.setup()
      OpentelemetryBandit.setup()
      OpentelemetryPhoenix.setup(adapter: :bandit)
      OpentelemetryEcto.setup(event_prefix: [:cache, :repo])
      OpentelemetryFinch.setup()
      OpentelemetryBroadway.setup()
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    CacheWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
