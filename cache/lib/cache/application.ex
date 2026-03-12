defmodule Cache.Application do
  @moduledoc false

  use Application

  alias Cache.DBConnection.TelemetryListener
  alias Cache.DistributedKV.Repo
  alias TuistCommon.HTTP.TransportLogger
  require Logger

  @impl true
  def start(_type, _args) do
    Cache.Config.validate_distributed_kv!()

    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    if Cache.Config.analytics_enabled?() do
      Cache.Telemetry.attach()
    end

    Oban.Telemetry.attach_default_logger()
    TransportLogger.attach(:cache)
    start_sentry_logger()
    start_loki_logger()
    start_opentelemetry()

    base_children = [
      {DBConnection.TelemetryListener, name: TelemetryListener},
      {Cache.Repo, connection_listeners: {[TelemetryListener], :cache}},
      {Cache.KeyValueRepo, connection_listeners: {[TelemetryListener], :key_value}},
      Cache.KeyValueBuffer,
      Cache.CacheArtifactsBuffer,
      Cache.S3TransfersBuffer,
      {Phoenix.PubSub, name: Cache.PubSub},
      Cache.Authentication,
      Cache.S3,
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

    distributed_children =
      if Cache.Config.distributed_kv_enabled?() do
        [
          Repo,
          Cache.KeyValueAccessTracker,
          Cache.KeyValueReplicationShipper,
          Cache.KeyValueReplicationPoller
        ]
      else
        []
      end

    children =
      if Cache.Config.analytics_enabled?() do
        base_children ++
          distributed_children ++
          [Cache.KeyValueStore] ++
          [Cache.Xcode.EventsPipeline, Cache.Gradle.EventsPipeline, Cache.Registry.EventsPipeline]
      else
        base_children ++ distributed_children ++ [Cache.KeyValueStore]
      end

    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp migrate do
    repos = [Cache.Repo, Cache.KeyValueRepo] ++ if(Cache.Config.distributed_kv_enabled?(), do: [Repo], else: [])

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
        structured_metadata: [
          :trace_id,
          :span_id,
          :request_id,
          :auth_account_handle,
          :selected_account_handle,
          :selected_project_handle
        ]
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
