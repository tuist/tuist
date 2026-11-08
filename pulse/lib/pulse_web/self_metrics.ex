defmodule PulseWeb.SelfMetrics do
  @moduledoc "Measures HTTP operations, including failures before body parsing completes."

  alias Pulse.SelfMetrics

  @request_key {__MODULE__, :request}
  @ingest_paths %{
    ["v1", "logs"] => :otlp,
    ["v1", "traces"] => :otlp_traces,
    ["v1", "metrics"] => :otlp_metrics,
    ["loki", "api", "v1", "push"] => :loki,
    ["api", "v1", "write"] => :remote_write
  }
  @query_paths [
    ["api", "v1", "query"],
    ["api", "v1", "query_range"],
    ["loki", "api", "v1", "query"],
    ["loki", "api", "v1", "query_range"]
  ]

  def handle_event([:phoenix, :endpoint, :start], _measurements, %{conn: conn}, _config) do
    Process.delete(@request_key)

    if operation = operation(conn) do
      Process.put(@request_key, {operation, System.monotonic_time()})
    end
  end

  def handle_event([:phoenix, :endpoint, :stop], %{duration: duration}, %{conn: conn}, _config) do
    case Process.delete(@request_key) do
      {{kind, dimension}, _start} ->
        outcome = if conn.status < 400, do: :success, else: :error
        SelfMetrics.operation(kind, dimension, outcome, duration)

      nil ->
        :ok
    end
  end

  # Plug.Telemetry's stop event is not emitted for every exception. Phoenix's
  # error renderer uses the original conn on parser failures, losing the pipeline's
  # before-send callbacks. A request-local start covers that path without counting
  # errors twice when the stop event did run.
  def handle_event([:phoenix, :error_rendered], _measurements, _metadata, _config) do
    case Process.delete(@request_key) do
      {{kind, dimension}, start} ->
        SelfMetrics.operation(kind, dimension, :error, System.monotonic_time() - start)

      nil ->
        :ok
    end
  end

  defp operation(conn) do
    path = Enum.map(conn.path_info, &URI.decode/1)
    method = if conn.method == "HEAD", do: "GET", else: conn.method

    case {method, Map.get(@ingest_paths, path)} do
      {"POST", dimension} when not is_nil(dimension) -> {:ingest, dimension}
      _ -> query_operation(method, path)
    end
  end

  defp query_operation(method, path) when method in ["GET", "POST"] and path in @query_paths, do: {:query, :http}

  defp query_operation("POST", ["api", _project, endpoint]) when endpoint in ["envelope", "store"],
    do: {:ingest, :sentry}

  defp query_operation("GET", ["loki", "api", "v1", "labels"]), do: {:query, :http}
  defp query_operation("GET", ["loki", "api", "v1", "label", _name, "values"]), do: {:query, :http}
  defp query_operation(_method, _path), do: nil
end
