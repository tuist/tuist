defmodule TuistCommon.HTTP.TransportPromExPlugin do
  @moduledoc """
  PromEx transport metrics for Bandit and Thousand Island.

  The current metric set focuses on transport-layer failures and timeouts.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_http_request_timeout_metrics,
        [
          counter(
            [:tuist, :http, :request, :timeout, :count],
            event_name: [:bandit, :request, :stop],
            keep: fn metadata, _measurements -> bandit_request_timeout?(metadata) end,
            tag_values: &bandit_timeout_tag_values/1,
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
              not is_nil(bandit_request_failure_reason(metadata))
            end,
            tag_values: &bandit_failure_tag_values/1,
            tags: [:method, :route, :reason],
            description: "Counts failed Bandit requests that indicate unhealthy behavior."
          ),
          counter(
            [:tuist, :http, :request, :failure, :count],
            event_name: [:bandit, :request, :exception],
            tag_values: &bandit_exception_tag_values/1,
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
              not is_nil(thousand_island_connection_drop_reason(metadata))
            end,
            tag_values: fn metadata ->
              %{reason: thousand_island_connection_drop_reason(metadata)}
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
            tag_values: fn _metadata -> thousand_island_connection_error_metadata(:recv_error) end,
            tags: [:event],
            description: "Counts Thousand Island synchronous recv/send errors."
          ),
          counter(
            [:tuist, :http, :connection, :error, :count],
            event_name: [:thousand_island, :connection, :send_error],
            tag_values: fn _metadata -> thousand_island_connection_error_metadata(:send_error) end,
            tags: [:event],
            description: "Counts Thousand Island synchronous recv/send errors."
          )
        ]
      )
    ]
  end

  defp bandit_request_timeout?(metadata) do
    metadata[:error] == "Body read timeout"
  end

  defp bandit_request_failure_reason(metadata) do
    conn = metadata[:conn]
    status = conn && Map.get(conn, :status)

    cond do
      is_integer(status) and status >= 500 -> "server_error"
      not is_nil(metadata[:error]) -> "protocol_error"
      true -> nil
    end
  end

  defp bandit_request_metadata(metadata) do
    conn = metadata[:conn]

    %{
      method: (conn && conn.method) || "unknown",
      route: (conn && (conn.private[:phoenix_route] || conn.request_path)) || "unknown"
    }
  end

  defp bandit_timeout_tag_values(metadata), do: bandit_request_metadata(metadata)

  defp bandit_failure_tag_values(metadata) do
    metadata
    |> bandit_request_metadata()
    |> Map.put(:reason, bandit_request_failure_reason(metadata))
  end

  defp bandit_exception_tag_values(metadata) do
    bandit_request_metadata(metadata)
    |> Map.put(:reason, "exception")
  end

  defp thousand_island_connection_drop_reason(metadata) do
    case metadata[:error] do
      nil -> nil
      :timeout -> "timeout"
      :closed -> "closed"
      {:shutdown, _} -> "shutdown"
      _ -> "other"
    end
  end

  defp thousand_island_connection_error_metadata(event)
       when event in [:recv_error, :send_error] do
    %{event: Atom.to_string(event)}
  end
end
