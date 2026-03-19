defmodule Tuist.HTTP.ServerPromExPlugin do
  @moduledoc """
  Defines Prometheus metrics for Bandit and Thousand Island request handling.
  """
  use PromEx.Plugin

  alias Tuist.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_http_server_request_event_metrics,
        [
          counter(
            [:tuist, :http, :server, :request, :count],
            event_name: Telemetry.event_name_http_server_request(),
            tags: [:request_method, :route, :status_class, :result],
            description: "Counts the number of HTTP requests handled by Bandit."
          ),
          distribution(
            [:tuist, :http, :server, :request, :duration, :milliseconds],
            event_name: Telemetry.event_name_http_server_request(),
            tags: [:request_method, :route, :status_class, :result],
            measurement: :duration,
            unit: {:native, :millisecond},
            description: "Distribution of HTTP request duration as observed by Bandit.",
            reporter_options: [
              buckets: exponential!(5, 2, 12)
            ]
          ),
          distribution(
            [:tuist, :http, :server, :request, :body_read_duration, :milliseconds],
            event_name: Telemetry.event_name_http_server_request(),
            tags: [:request_method, :route, :status_class, :result],
            measurement: :req_body_read_duration,
            unit: {:native, :millisecond},
            keep: &body_read_duration_present?/2,
            description: "Distribution of request body read duration as observed by Bandit.",
            reporter_options: [
              buckets: exponential!(5, 2, 12)
            ]
          ),
          distribution(
            [:tuist, :http, :server, :request, :body_bytes],
            event_name: Telemetry.event_name_http_server_request(),
            tags: [:request_method, :route, :status_class, :result],
            measurement: :req_body_bytes,
            unit: :byte,
            keep: &body_bytes_present?/2,
            description: "Distribution of request body sizes handled by Bandit.",
            reporter_options: [
              buckets: exponential!(256, 2, 18)
            ]
          )
        ]
      ),
      Event.build(
        :tuist_http_server_request_exception_event_metrics,
        [
          counter(
            [:tuist, :http, :server, :request, :exception, :count],
            event_name: Telemetry.event_name_http_server_request_exception(),
            tags: [:request_method, :route, :error_kind],
            description: "Counts unexpected request exceptions seen by Bandit."
          )
        ]
      ),
      Event.build(
        :tuist_http_server_connection_error_event_metrics,
        [
          counter(
            [:tuist, :http, :server, :connection, :error, :count],
            event_name: Telemetry.event_name_http_server_connection_error(),
            tags: [:event, :error],
            description: "Counts Thousand Island connection recv/send/shutdown errors."
          )
        ]
      )
    ]
  end

  defp body_read_duration_present?(_metadata, measurements) do
    is_integer(measurements[:req_body_read_duration])
  end

  defp body_bytes_present?(_metadata, measurements) do
    is_integer(measurements[:req_body_bytes])
  end
end
