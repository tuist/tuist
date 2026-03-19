defmodule TuistCommon.HTTP.Telemetry do
  @moduledoc false

  require Logger

  @handler_id "#{__MODULE__}"
  @events [
    [:bandit, :request, :stop],
    [:thousand_island, :connection, :stop]
  ]

  def attach do
    case :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def handle_event([:bandit, :request, :stop], measurements, metadata, _config) do
    if bandit_request_timeout?(metadata) do
      request_metadata = bandit_request_metadata(metadata)
      log_request_timeout(measurements, request_metadata)
    end
  end

  def handle_event([:thousand_island, :connection, :stop], _measurements, metadata, _config) do
    case thousand_island_connection_drop_reason(metadata) do
      nil -> :ok
      reason -> Logger.warning("Thousand Island connection dropped reason=#{reason}")
    end
  end

  def bandit_request_timeout?(metadata) do
    metadata[:error] == "Body read timeout"
  end

  def bandit_request_failure_reason(metadata) do
    conn = metadata[:conn]

    cond do
      is_integer(conn && conn.status) and conn.status >= 500 -> "server_error"
      not is_nil(metadata[:error]) -> "protocol_error"
      true -> nil
    end
  end

  def bandit_request_metadata(metadata) do
    conn = metadata[:conn]

    %{
      method: (conn && conn.method) || "unknown",
      route: (conn && (conn.private[:phoenix_route] || conn.request_path)) || "unknown"
    }
  end

  def bandit_exception_metadata(metadata) do
    bandit_request_metadata(metadata)
    |> Map.put(:reason, "exception")
  end

  def thousand_island_connection_drop_reason(metadata) do
    case metadata[:error] do
      nil -> nil
      :timeout -> "timeout"
      :closed -> "closed"
      {:shutdown, _} -> "shutdown"
      _ -> "other"
    end
  end

  def thousand_island_connection_error_metadata(event) when event in [:recv_error, :send_error] do
    %{event: Atom.to_string(event)}
  end

  def bandit_timeout_tag_values(metadata) do
    bandit_request_metadata(metadata)
  end

  def bandit_failure_tag_values(metadata) do
    metadata
    |> bandit_request_metadata()
    |> Map.put(:reason, bandit_request_failure_reason(metadata))
  end

  def bandit_exception_tag_values(metadata) do
    bandit_exception_metadata(metadata)
  end

  defp log_request_timeout(measurements, metadata) do
    duration_ms = convert_native_duration(measurements[:duration])
    body_read_duration_ms = convert_native_duration(body_read_duration(measurements))

    Logger.warning(
      "Bandit request body timeout method=#{metadata.method} route=#{metadata.route} " <>
        "duration_ms=#{duration_ms || "unknown"} body_read_duration_ms=#{body_read_duration_ms || "unknown"}"
    )
  end

  defp body_read_duration(measurements) do
    start_time = measurements[:req_body_start_time]
    end_time = measurements[:req_body_end_time]

    if is_integer(start_time) and is_integer(end_time) and end_time >= start_time do
      end_time - start_time
    end
  end

  defp convert_native_duration(nil), do: nil

  defp convert_native_duration(duration),
    do: System.convert_time_unit(duration, :native, :millisecond)
end
