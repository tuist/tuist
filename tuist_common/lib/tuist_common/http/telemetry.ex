defmodule TuistCommon.HTTP.Telemetry do
  @moduledoc false

  require Logger

  @handler_id "#{__MODULE__}"
  @events [
    [:bandit, :request, :stop],
    [:bandit, :request, :exception],
    [:thousand_island, :connection, :stop],
    [:thousand_island, :connection, :recv_error],
    [:thousand_island, :connection, :send_error]
  ]

  def request_timeout_event, do: [:tuist, :http, :request, :timeout]
  def request_failure_event, do: [:tuist, :http, :request, :failure]
  def connection_drop_event, do: [:tuist, :http, :connection, :drop]
  def connection_error_event, do: [:tuist, :http, :connection, :error]

  def attach do
    case :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def handle_event([:bandit, :request, :stop], measurements, metadata, _config) do
    conn = metadata[:conn]
    request_metadata = request_metadata(conn)

    cond do
      metadata[:error] == "Body read timeout" ->
        :telemetry.execute(
          request_timeout_event(),
          timeout_measurements(measurements),
          request_metadata
        )

        log_request_timeout(measurements, request_metadata)

      is_integer(conn && conn.status) and conn.status >= 500 ->
        :telemetry.execute(
          request_failure_event(),
          %{},
          Map.put(request_metadata, :reason, "server_error")
        )

      not is_nil(metadata[:error]) ->
        :telemetry.execute(
          request_failure_event(),
          %{},
          Map.put(request_metadata, :reason, "protocol_error")
        )

      true ->
        :ok
    end
  end

  def handle_event([:bandit, :request, :exception], _measurements, metadata, _config) do
    request_metadata =
      metadata[:conn]
      |> request_metadata()
      |> Map.put(:reason, "exception")

    :telemetry.execute(request_failure_event(), %{}, request_metadata)
  end

  def handle_event([:thousand_island, :connection, :stop], _measurements, metadata, _config) do
    case metadata[:error] do
      nil ->
        :ok

      error ->
        :telemetry.execute(connection_drop_event(), %{}, %{reason: classify_error(error)})
        log_connection_drop(error)
    end
  end

  def handle_event([:thousand_island, :connection, event], _measurements, _metadata, _config)
      when event in [:recv_error, :send_error] do
    :telemetry.execute(connection_error_event(), %{}, %{event: Atom.to_string(event)})
  end

  def request_metadata(nil), do: %{method: "unknown", route: "unknown"}

  def request_metadata(conn) do
    %{
      method: conn.method || "unknown",
      route: conn.private[:phoenix_route] || conn.request_path || "unknown"
    }
  end

  defp timeout_measurements(measurements) do
    measurements
    |> Map.take([:duration])
    |> maybe_put(
      :body_read_duration,
      duration_between(measurements, :req_body_start_time, :req_body_end_time)
    )
  end

  defp log_request_timeout(measurements, metadata) do
    duration_ms = convert_native_duration(measurements[:duration])

    body_read_duration_ms =
      convert_native_duration(
        duration_between(measurements, :req_body_start_time, :req_body_end_time)
      )

    Logger.warning(
      "Bandit request body timeout method=#{metadata.method} route=#{metadata.route} " <>
        "duration_ms=#{duration_ms || "unknown"} body_read_duration_ms=#{body_read_duration_ms || "unknown"}"
    )
  end

  defp log_connection_drop(error) do
    Logger.warning("Thousand Island connection dropped reason=#{classify_error(error)}")
  end

  defp classify_error(:timeout), do: "timeout"
  defp classify_error(:closed), do: "closed"
  defp classify_error({:shutdown, _}), do: "shutdown"
  defp classify_error(_), do: "other"

  defp duration_between(measurements, start_key, end_key) do
    start_time = measurements[start_key]
    end_time = measurements[end_key]

    if is_integer(start_time) and is_integer(end_time) and end_time >= start_time do
      end_time - start_time
    end
  end

  defp convert_native_duration(nil), do: nil

  defp convert_native_duration(duration),
    do: System.convert_time_unit(duration, :native, :millisecond)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
