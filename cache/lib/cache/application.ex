defmodule Cache.Application do
  @moduledoc false

  use Application

  alias Cache.DBConnection.TelemetryListener
  alias Cache.DistributedKV.Repo
  alias TuistCommon.HTTP.TransportLogger

  require Logger

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    if Cache.Config.analytics_enabled?() do
      Cache.Telemetry.attach()
    end

    Oban.Telemetry.attach_default_logger()
    TuistCommon.ObanTelemetry.attach()
    TransportLogger.attach(:cache)
    start_sentry_logger()
    start_loki_logger()
    start_opentelemetry()

    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  def children do
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
      # Cannot alias Cache.Finch to Finch or it'll conflict with the top-level library
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      {Finch, name: Cache.Finch, pools: Cache.Finch.Pools.config()},
      Cache.PromEx,
      {Oban, Application.get_env(:cache, Oban)}
    ]

    analytics_children =
      if Cache.Config.analytics_enabled?() do
        [Cache.Xcode.EventsPipeline, Cache.Gradle.EventsPipeline, Cache.Registry.EventsPipeline]
      else
        []
      end

    endpoint_children = [
      CacheWeb.Endpoint,
      Cache.SocketLinker
    ]

    base_children ++ [Cache.KeyValueStore] ++ distributed_children ++ analytics_children ++ endpoint_children
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
          :selected_project_handle,
          :method,
          :route,
          :request_path,
          :reason,
          :error,
          :kind,
          :event,
          :duration_ms,
          :remote_address,
          :remote_port,
          :recv_oct,
          :send_oct,
          :req_body_bytes,
          :request_span_context,
          :connection_span_context
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
