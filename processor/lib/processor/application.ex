defmodule Processor.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    start_sentry_logger()
    start_loki_logger()
    start_opentelemetry()
    cleanup_stale_temp_dirs()

    children = [
      {Phoenix.PubSub, name: Processor.PubSub},
      {Finch, name: Processor.Finch, pools: finch_pools()},
      ProcessorWeb.Endpoint,
      Processor.PromEx
    ]

    opts = [strategy: :one_for_one, name: Processor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp finch_pools do
    base = %{default: [size: 10]}

    case TuistCommon.FinchPools.s3_endpoint_from_ex_aws_config() do
      nil ->
        base

      endpoint ->
        {s3_endpoint, s3_pool_opts} = TuistCommon.FinchPools.s3_pool(endpoint: endpoint)
        Map.put(base, s3_endpoint, s3_pool_opts)
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
          app: {:static, "tuist-processor"},
          service_name: {:static, "tuist-processor"},
          service_namespace: {:static, "tuist"},
          env: {:static, System.get_env("DEPLOY_ENV") || "production"},
          level: :level
        },
        structured_metadata: [
          :trace_id,
          :span_id,
          :request_id
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

  defp cleanup_stale_temp_dirs do
    tmp_dir = System.tmp_dir!()

    case File.ls(tmp_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.starts_with?(&1, "processor_"))
        |> Enum.each(fn entry ->
          File.rm_rf(Path.join(tmp_dir, entry))
        end)

      _ ->
        :ok
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    ProcessorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
