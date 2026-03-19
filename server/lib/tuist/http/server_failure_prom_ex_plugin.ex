defmodule Tuist.HTTP.ServerFailurePromExPlugin do
  @moduledoc """
  PromEx metrics for shared HTTP failure signals emitted from Bandit and Thousand Island.
  """
  use PromEx.Plugin

  alias TuistCommon.HTTP.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_http_request_timeout_metrics,
        [
          counter(
            [:tuist, :http, :request, :timeout, :count],
            event_name: Telemetry.request_timeout_event(),
            tags: [:method, :route],
            description: "Counts request body read timeouts reported by Bandit."
          )
        ]
      ),
      Event.build(
        :tuist_http_request_failure_metrics,
        [
          counter(
            [:tuist, :http, :request, :failure, :count],
            event_name: Telemetry.request_failure_event(),
            tags: [:method, :route, :reason],
            description: "Counts failed Bandit requests that indicate unhealthy behavior."
          )
        ]
      ),
      Event.build(
        :tuist_http_connection_drop_metrics,
        [
          counter(
            [:tuist, :http, :connection, :drop, :count],
            event_name: Telemetry.connection_drop_event(),
            tags: [:reason],
            description: "Counts Thousand Island connection drops that ended with an error."
          )
        ]
      ),
      Event.build(
        :tuist_http_connection_error_metrics,
        [
          counter(
            [:tuist, :http, :connection, :error, :count],
            event_name: Telemetry.connection_error_event(),
            tags: [:event],
            description: "Counts Thousand Island synchronous recv/send errors."
          )
        ]
      )
    ]
  end
end
