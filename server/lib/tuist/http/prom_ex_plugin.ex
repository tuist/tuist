defmodule Tuist.HTTP.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for HTTP outgoing and incoming requests.
  """
  use PromEx.Plugin

  import Telemetry.Metrics

  alias Tuist.Telemetry.Sanitizer

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_http_request_event_metrics,
        [
          counter(
            [:tuist, :http, :request, :count],
            event_name: [:finch, :request, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &request_metadata_to_tag_values/1,
            tags: [:response_status, :request_method, :request_host],
            description: "Counts the number of HTTP requests."
          ),
          sum(
            [:tuist, :http, :request, :duration, :nanoseconds, :sum],
            event_name: [:finch, :request, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &request_metadata_to_tag_values/1,
            tags: [:response_status, :request_method, :request_host],
            description:
              "Summary of the duration of HTTP requests (including the time that they spent waiting to be assigned to a connection)",
            measurement: :duration,
            unit: {:native, :nanosecond}
          ),
          distribution(
            [:tuist, :http, :request, :duration, :nanoseconds],
            event_name: [:finch, :request, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &request_metadata_to_tag_values/1,
            tags: [:response_status, :request_method, :request_host],
            description:
              "Summary of the duration of HTTP requests (including the time that they spent waiting to be assigned to a connection)",
            measurement: :duration,
            unit: {:native, :nanosecond},
            reporter_options: [
              buckets: exponential!(2_000_000, 2.15, 15)
            ]
          )
        ]
      ),
      Event.build(
        :tuist_http_queue_event_metrics,
        [
          counter(
            [:tuist, :http, :queue, :count],
            event_name: [:finch, :queue, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Counts the number of HTTP requests that have been retrieved from the pool."
          ),
          sum(
            [:tuist, :http, :queue, :duration, :nanoseconds, :sum],
            event_name: [:finch, :queue, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Sums the time it takes to take a connection from the pool.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          ),
          sum(
            [:tuist, :http, :queue, :idle_time, :nanoseconds, :sum],
            event_name: [:finch, :queue, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Sums the time the connection has been idle waiting to be retrieved.",
            measurement: :idle_time,
            unit: {:native, :nanosecond}
          )
        ]
      ),
      Event.build(
        :tuist_http_connection_event_metrics,
        [
          counter(
            [:tuist, :http, :connection, :count],
            event_name: [:finch, :connect, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &connection_metadata_to_tag_values/1,
            description: "Counts the number of connections that have been established"
          ),
          sum(
            [:tuist, :http, :connection, :duration, :nanoseconds, :sum],
            event_name: [:finch, :connect, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &connection_metadata_to_tag_values/1,
            description: "Summary of the time it takes to establish connections against the host.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          )
        ]
      ),
      Event.build(
        :tuist_http_send_event_metrics,
        [
          counter(
            [:tuist, :http, :send, :count],
            event_name: [:finch, :send, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &send_metadata_to_tag_values/1,
            tags: [:status, :request_method, :request_host],
            description: "Counts the number of requests that have been sent."
          ),
          sum(
            [:tuist, :http, :send, :duration, :nanoseconds, :sum],
            event_name: [:finch, :send, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &send_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Summary of the time it takes to finish sending the request to the server.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          )
        ]
      ),
      Event.build(
        :tuist_http_receive_event_metrics,
        [
          counter(
            [:tuist, :http, :receive, :count],
            event_name: [:finch, :recv, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &receive_metadata_to_tag_values/1,
            tags: [:status, :request_host, :request_method],
            description: "Counts the number of responses that have been received."
          ),
          sum(
            [:tuist, :http, :receive, :duration, :nanoseconds, :sum],
            event_name: [:finch, :recv, :stop],
            keep: &keep_tuist_finch?/1,
            tag_values: &receive_metadata_to_tag_values/1,
            tags: [:status, :request_host, :request_method],
            description: "Summary of the time it takes to receive responses.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          )
        ]
      )
    ]
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(second: 5))

    [
      Polling.build(
        :tuist_http_queue_manual_metrics,
        poll_rate,
        {__MODULE__, :execute_http_queue_status_telemetry_event, []},
        [
          last_value(
            [:tuist, :http, :queue, :available_connections],
            event_name: Tuist.Telemetry.event_name_http_queue_status(),
            description: "The most recent available connections in a pool.",
            measurement: :available_connections,
            tags: [:url, :size, :index]
          ),
          last_value(
            [:tuist, :http, :queue, :in_use_connections],
            event_name: Tuist.Telemetry.event_name_http_queue_status(),
            description: "The most recent in-use pool connections.",
            measurement: :in_use_connections,
            tags: [:url, :size, :index]
          )
        ]
      )
    ]
  end

  defp request_metadata_to_tag_values(metadata) do
    %{
      name: metadata.name
    }
    |> Map.merge(result_to_tag_values(metadata[:result]))
    |> Map.merge(request_to_tag_values(metadata.request))
  end

  defp result_to_tag_values({:ok, {_request, %{status: status}}}), do: %{response_status: status}
  defp result_to_tag_values({:ok, %{status: status}}), do: %{response_status: status}

  defp result_to_tag_values({:error, exception, {_request, _response}}), do: %{error: Sanitizer.sanitize_value(exception)}

  defp result_to_tag_values({:error, {_request, exception}}), do: %{error: Sanitizer.sanitize_value(exception)}

  defp result_to_tag_values({:error, exception}), do: %{error: Sanitizer.sanitize_value(exception)}
  defp result_to_tag_values(result), do: %{error: Sanitizer.sanitize_value(result)}

  defp queue_metadata_to_tag_values(metadata) do
    Map.merge(%{name: metadata.name}, request_to_tag_values(metadata.request))
  end

  defp connection_metadata_to_tag_values(metadata) do
    metadata
  end

  defp send_metadata_to_tag_values(metadata) do
    Map.merge(%{name: metadata.name}, request_to_tag_values(metadata.request))
  end

  defp receive_metadata_to_tag_values(metadata) do
    Map.merge(
      %{
        name: metadata.name,
        status: Map.get(metadata, :status),
        error: Sanitizer.sanitize_value(Map.get(metadata, :error))
      },
      request_to_tag_values(metadata.request)
    )
  end

  # PromEx subscribes to the global `[:finch, :request|queue|connect|send|recv, :stop]`
  # telemetry events, which fire for every Finch instance in the BEAM, including
  # Req's default `Req.Finch` pool used by webhook delivery, OIDC JWKS fetches,
  # and SSO flows. Those carry per-customer hostnames in `request.host`, which
  # blow up active-series cardinality through the `request_host` label. Keep the
  # metrics scoped to `Tuist.Finch` so per-host visibility stays on for our
  # bounded internal endpoints (GitHub, Tigris, PostHog, Namespace) only.
  defp keep_tuist_finch?(metadata), do: Map.get(metadata, :name) == Tuist.Finch

  defp request_to_tag_values(request) do
    %{
      request_method: request.method,
      request_host: request.host,
      request_path: request.path,
      request_scheme: request.scheme,
      request_query: request.query || "",
      request_port: request.port
    }
  end

  def execute_http_queue_status_telemetry_event do
    url = Tuist.Environment.s3_endpoint()

    emit_configured_pool_status(url)
    emit_default_pool_status()
  end

  defp emit_configured_pool_status(url) do
    case Finch.get_pool_status(Tuist.Finch, url) do
      {:ok, pools} ->
        Enum.each(pools, fn pool ->
          emit_pool_status(url, pool.pool_size, pool.pool_index, pool)
        end)

      {:error, _} ->
        :ok
    end
  end

  # Virtual-hosted buckets and customer-provided storage origins are created
  # from Finch's fallback pool. Aggregate them under one bounded label so pool
  # saturation is visible without exposing customer hostnames or creating an
  # unbounded metric series per origin.
  defp emit_default_pool_status do
    case Finch.get_pool_status(Tuist.Finch, :default) do
      {:ok, pools_by_origin} ->
        totals =
          pools_by_origin
          |> Map.values()
          |> List.flatten()
          |> Enum.reduce(%{available_connections: 0, in_use_connections: 0, pool_size: 0}, fn pool, acc ->
            %{
              available_connections: acc.available_connections + pool.available_connections,
              in_use_connections: acc.in_use_connections + pool.in_use_connections,
              pool_size: acc.pool_size + pool.pool_size
            }
          end)

        emit_pool_status("default", totals.pool_size, 0, totals)

      {:error, _} ->
        :ok
    end
  end

  defp emit_pool_status(url, size, index, pool) do
    :telemetry.execute(
      Tuist.Telemetry.event_name_http_queue_status(),
      %{
        available_connections: pool.available_connections,
        in_use_connections: pool.in_use_connections
      },
      %{
        url: url,
        size: size,
        index: index
      }
    )
  end
end
