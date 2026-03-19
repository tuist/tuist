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
            event_name: [:bandit, :request, :stop],
            keep: fn metadata, _measurements -> Telemetry.bandit_request_timeout?(metadata) end,
            tag_values: &Telemetry.bandit_timeout_tag_values/1,
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
            event_name: [:bandit, :request, :stop],
            keep: fn metadata, _measurements ->
              not is_nil(Telemetry.bandit_request_failure_reason(metadata))
            end,
            tag_values: &Telemetry.bandit_failure_tag_values/1,
            tags: [:method, :route, :reason],
            description: "Counts failed Bandit requests that indicate unhealthy behavior."
          ),
          counter(
            [:tuist, :http, :request, :failure, :count],
            event_name: [:bandit, :request, :exception],
            tag_values: &Telemetry.bandit_exception_tag_values/1,
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
            event_name: [:thousand_island, :connection, :stop],
            keep: fn metadata, _measurements ->
              not is_nil(Telemetry.thousand_island_connection_drop_reason(metadata))
            end,
            tag_values: fn metadata ->
              %{reason: Telemetry.thousand_island_connection_drop_reason(metadata)}
            end,
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
            event_name: [:thousand_island, :connection, :recv_error],
            tag_values: fn _metadata -> Telemetry.thousand_island_connection_error_metadata(:recv_error) end,
            tags: [:event],
            description: "Counts Thousand Island synchronous recv/send errors."
          ),
          counter(
            [:tuist, :http, :connection, :error, :count],
            event_name: [:thousand_island, :connection, :send_error],
            tag_values: fn _metadata -> Telemetry.thousand_island_connection_error_metadata(:send_error) end,
            tags: [:event],
            description: "Counts Thousand Island synchronous recv/send errors."
          )
        ]
      )
    ]
  end
end
