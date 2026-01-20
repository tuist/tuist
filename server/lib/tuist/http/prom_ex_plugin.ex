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
            tag_values: &request_metadata_to_tag_values/1,
            tags: [:response_status, :request_method, :request_host],
            description: "Counts the number of HTTP requests."
          ),
          sum(
            [:tuist, :http, :request, :duration, :nanoseconds, :sum],
            event_name: [:finch, :request, :stop],
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
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Counts the number of HTTP requests that have been retrieved from the pool."
          ),
          sum(
            [:tuist, :http, :queue, :duration, :nanoseconds, :sum],
            event_name: [:finch, :queue, :stop],
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Sums the time it takes to take a connection from the pool.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          ),
          sum(
            [:tuist, :http, :queue, :idle_time, :nanoseconds, :sum],
            event_name: [:finch, :queue, :stop],
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Sums the time the connection has been idle waiting to be retrieved.",
            measurement: :idle_time,
            unit: {:native, :nanosecond}
          ),
          distribution(
            [:tuist, :http, :queue, :duration, :nanoseconds],
            event_name: [:finch, :queue, :stop],
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Sums the time it takes to take a connection from the pool.",
            measurement: :duration,
            unit: {:native, :nanosecond},
            reporter_options: [
              buckets: exponential!(2_000_000, 2.15, 15)
            ]
          ),
          distribution(
            [:tuist, :http, :queue, :idle_time, :nanoseconds],
            event_name: [:finch, :queue, :stop],
            tag_values: &queue_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Sums the time the connection has been idle waiting to be retrieved.",
            measurement: :idle_time,
            unit: {:native, :nanosecond},
            reporter_options: [
              buckets: exponential!(2_000_000, 2.15, 15)
            ]
          )
        ]
      ),
      Event.build(
        :tuist_http_connection_event_metrics,
        [
          counter(
            [:tuist, :http, :connection, :count],
            event_name: [:finch, :connect, :stop],
            tag_values: &connection_metadata_to_tag_values/1,
            description: "Counts the number of connections that have been established"
          ),
          sum(
            [:tuist, :http, :connection, :duration, :nanoseconds, :sum],
            event_name: [:finch, :connect, :stop],
            tag_values: &connection_metadata_to_tag_values/1,
            description: "Summary of the time it takes to establish connections against the host.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          ),
          distribution(
            [:tuist, :http, :connection, :duration, :nanoseconds],
            event_name: [:finch, :connect, :stop],
            tag_values: &connection_metadata_to_tag_values/1,
            description: "Summary of the time it takes to establish connections against the host.",
            measurement: :duration,
            unit: {:native, :nanosecond},
            reporter_options: [
              buckets: exponential!(2_000_000, 2.15, 15)
            ]
          )
        ]
      ),
      Event.build(
        :tuist_http_send_event_metrics,
        [
          counter(
            [:tuist, :http, :send, :count],
            event_name: [:finch, :send, :stop],
            tag_values: &send_metadata_to_tag_values/1,
            tags: [:status, :request_method, :request_host],
            description: "Counts the number of requests that have been sent."
          ),
          sum(
            [:tuist, :http, :send, :duration, :nanoseconds, :sum],
            event_name: [:finch, :send, :stop],
            tag_values: &send_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Summary of the time it takes to finish sending the request to the server.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          ),
          distribution(
            [:tuist, :http, :send, :duration, :nanoseconds],
            event_name: [:finch, :send, :stop],
            tag_values: &send_metadata_to_tag_values/1,
            tags: [:request_method, :request_host],
            description: "Summary of the time it takes to finish sending the request to the server.",
            measurement: :duration,
            unit: {:native, :nanosecond},
            reporter_options: [
              buckets: exponential!(2_000_000, 2.15, 15)
            ]
          )
        ]
      ),
      Event.build(
        :tuist_http_receive_event_metrics,
        [
          counter(
            [:tuist, :http, :receive, :count],
            event_name: [:finch, :recv, :stop],
            tag_values: &receive_metadata_to_tag_values/1,
            tags: [:status, :request_host, :request_method],
            description: "Counts the number of responses that have been received."
          ),
          sum(
            [:tuist, :http, :receive, :duration, :nanoseconds, :sum],
            event_name: [:finch, :recv, :stop],
            tag_values: &receive_metadata_to_tag_values/1,
            tags: [:status, :request_host, :request_method],
            description: "Summary of the time it takes to receive responses.",
            measurement: :duration,
            unit: {:native, :nanosecond}
          ),
          distribution(
            [:tuist, :http, :receive, :duration, :nanoseconds],
            event_name: [:finch, :recv, :stop],
            tag_values: &receive_metadata_to_tag_values/1,
            tags: [:status, :request_host, :request_method],
            description: "Summary of the time it takes to receive responses.",
            measurement: :duration,
            unit: {:native, :nanosecond},
            reporter_options: [
              buckets: exponential!(2_000_000, 2.15, 15)
            ]
          )
        ]
      )
    ]
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(millisecond: 100))

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
    response_attrs =
      case metadata[:result] do
        {:ok, %{status: status}} -> %{response_status: status}
        {:error, exception} -> %{error: Sanitizer.sanitize_value(exception)}
      end

    %{
      name: metadata.name
    }
    |> Map.merge(response_attrs)
    |> Map.merge(request_to_tag_values(metadata.request))
  end

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

    case Finch.get_pool_status(Tuist.Finch, url) do
      {:ok, pools} ->
        Enum.each(pools, fn pool ->
          :telemetry.execute(
            Tuist.Telemetry.event_name_http_queue_status(),
            %{
              available_connections: pool.available_connections,
              in_use_connections: pool.in_use_connections
            },
            %{
              url: url,
              size: pool.pool_size,
              index: pool.pool_index
            }
          )
        end)

      {:error, _} ->
        :ok
    end
  end
end
