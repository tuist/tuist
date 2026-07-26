defmodule TuistRegistry.Application do
  @moduledoc false

  use Application

  alias TuistCommon.HTTP.TransportLogger

  require Logger

  @impl true
  def start(_type, _args) do
    TransportLogger.attach(:tuist_registry)
    start_sentry_logger()
    start_loki_logger()
    start_opentelemetry()

    base_children = [
      {Phoenix.PubSub, name: TuistRegistry.PubSub},
      TuistRegistry.S3,
      TuistRegistry.Swift.Metadata,
      TuistRegistry.Swift.AlternateManifests,
      TuistRegistryWeb.Endpoint,
      # Cannot alias TuistRegistry.Finch to Finch or it'll conflict with the top-level library
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      {Finch, name: TuistRegistry.Finch, pools: TuistRegistry.Finch.Pools.config()},
      TuistRegistry.PromEx
    ]

    opts = [strategy: :one_for_one, name: TuistRegistry.Supervisor]
    Supervisor.start_link(base_children, opts)
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
      OpentelemetryFinch.setup()
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    TuistRegistryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
