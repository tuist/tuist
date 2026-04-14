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

  # ExAws.S3.download_file opens ~8 parallel GET Range requests per download.
  # The default 50-conn/1-count pool wedges under concurrent build processing:
  # chunk Task.async_stream timeouts leak in-flight connections faster than
  # they're released, starving new requests with "excess queuing" errors.
  # Mirror the server's sizing (size 500, count = schedulers_online, http1).
  defp finch_pools do
    s3_endpoint = s3_endpoint()
    base = %{default: [size: 10]}

    if is_nil(s3_endpoint) do
      base
    else
      Map.put(base, s3_endpoint,
        size: 500,
        count: System.schedulers_online(),
        protocols: [:http1]
      )
    end
  end

  defp s3_endpoint do
    case Application.get_env(:ex_aws, :s3) do
      nil ->
        nil

      s3_config ->
        scheme = Keyword.get(s3_config, :scheme, "https://")
        host = Keyword.get(s3_config, :host)
        port = Keyword.get(s3_config, :port)

        cond do
          is_nil(host) -> nil
          is_nil(port) -> "#{scheme}#{host}"
          true -> "#{scheme}#{host}:#{port}"
        end
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
