defmodule TuistRegistry.Application do
  @moduledoc false

  use Application

  alias TuistCommon.HTTP.TransportLogger
  alias TuistRegistry.DBConnection.TelemetryListener

  require Logger

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    Oban.Telemetry.attach_default_logger()
    TuistCommon.ObanTelemetry.attach()
    TransportLogger.attach(:tuist_registry)
    start_sentry_logger()
    start_loki_logger()
    start_opentelemetry()

    base_children = [
      {DBConnection.TelemetryListener, name: TelemetryListener},
      {TuistRegistry.Repo, connection_listeners: {[TelemetryListener], :tuist_registry}},
      TuistRegistry.CacheArtifactsBuffer,
      TuistRegistry.S3TransfersBuffer,
      {Phoenix.PubSub, name: TuistRegistry.PubSub},
      TuistRegistry.S3,
      TuistRegistry.Swift.Metadata,
      TuistRegistry.Swift.AlternateManifests,
      TuistRegistryWeb.Endpoint,
      TuistRegistry.SocketLinker,
      # Cannot alias TuistRegistry.Finch to Finch or it'll conflict with the top-level library
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      {Finch, name: TuistRegistry.Finch, pools: TuistRegistry.Finch.Pools.config()},
      TuistRegistry.PromEx,
      {Oban, Application.get_env(:tuist_registry, Oban)}
    ]

    children =
      if TuistRegistry.Config.analytics_enabled?() do
        base_children ++ [TuistRegistry.Swift.EventsPipeline]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: TuistRegistry.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp migrate do
    repos = Application.fetch_env!(:tuist_registry, :ecto_repos)

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
          app: {:static, "tuist-registry"},
          service_name: {:static, "tuist-registry"},
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
      OpentelemetryEcto.setup(event_prefix: [:tuist_registry, :repo])
      OpentelemetryFinch.setup()
      OpentelemetryBroadway.setup()
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    TuistRegistryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
