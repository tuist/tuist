defmodule Tuist.HTTP.ServerTelemetry do
  @moduledoc false

  alias Plug.Conn
  alias Tuist.Telemetry
  alias Tuist.Telemetry.Sanitizer

  require Logger

  @handler_id "#{__MODULE__}"
  @events [
    [:bandit, :request, :stop],
    [:bandit, :request, :exception],
    [:thousand_island, :connection, :recv_error],
    [:thousand_island, :connection, :send_error],
    [:thousand_island, :connection, :socket_shutdown]
  ]

  def attach do
    case :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def handle_event([:bandit, :request, :stop], measurements, metadata, _config) do
    normalized_measurements = normalize_request_measurements(measurements)
    normalized_metadata = normalize_request_metadata(metadata)

    :telemetry.execute(
      Telemetry.event_name_http_server_request(),
      normalized_measurements,
      normalized_metadata
    )

    maybe_log_timeout(normalized_measurements, normalized_metadata)
  end

  def handle_event([:bandit, :request, :exception], _measurements, metadata, _config) do
    normalized_metadata =
      metadata
      |> normalize_request_metadata()
      |> Map.merge(%{
        error_kind: Sanitizer.sanitize_value(metadata[:kind]),
        exception: Sanitizer.sanitize_value(metadata[:exception])
      })

    :telemetry.execute(
      Telemetry.event_name_http_server_request_exception(),
      %{},
      normalized_metadata
    )
  end

  def handle_event([:thousand_island, :connection, event], measurements, metadata, _config)
      when event in [:recv_error, :send_error, :socket_shutdown] do
    normalized_metadata = %{
      event: Atom.to_string(event),
      error: Sanitizer.sanitize_value(measurements[:error])
    }

    :telemetry.execute(
      Telemetry.event_name_http_server_connection_error(),
      %{},
      Map.merge(normalized_metadata, Map.take(metadata, [:telemetry_span_context]))
    )
  end

  def normalize_request_measurements(measurements) do
    measurements
    |> Map.take([:duration, :req_body_bytes, :resp_body_bytes])
    |> maybe_put(:req_header_duration, duration_between(measurements, :req_header_end_time, :monotonic_time))
    |> maybe_put(:req_body_read_duration, duration_between(measurements, :req_body_start_time, :req_body_end_time))
    |> maybe_put(:resp_send_duration, duration_between(measurements, :resp_start_time, :resp_end_time))
  end

  def normalize_request_metadata(metadata) do
    conn = metadata[:conn]
    error = metadata[:error]
    status = conn && conn.status

    %{
      request_method: conn && conn.method,
      request_path: conn && conn.request_path,
      route: route(conn),
      status: status,
      status_class: status_class(status),
      request_id: request_id(conn),
      result: request_result(status, error),
      error: Sanitizer.sanitize_value(error)
    }
  end

  defp maybe_log_timeout(measurements, %{result: "request_timeout"} = metadata) do
    duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)

    body_read_duration_ms =
      case measurements[:req_body_read_duration] do
        nil -> "unknown"
        duration -> Integer.to_string(System.convert_time_unit(duration, :native, :millisecond))
      end

    Logger.warning(
      "Bandit request body timeout method=#{metadata.request_method} route=#{metadata.route} " <>
        "path=#{metadata.request_path} status=#{metadata.status} duration_ms=#{duration_ms} " <>
        "body_read_duration_ms=#{body_read_duration_ms} body_bytes=#{measurements[:req_body_bytes] || 0} " <>
        "request_id=#{metadata.request_id || "unknown"}"
    )
  end

  defp maybe_log_timeout(_measurements, _metadata), do: :ok

  defp request_result(_status, "Body read timeout"), do: "request_timeout"
  defp request_result(status, _error) when is_integer(status) and status >= 500, do: "server_error"
  defp request_result(status, _error) when is_integer(status) and status >= 400, do: "client_error"
  defp request_result(_status, error) when not is_nil(error), do: "error"
  defp request_result(_, _), do: "ok"

  defp route(nil), do: "unknown"

  defp route(conn) do
    conn.private[:phoenix_route] || conn.request_path || "unknown"
  end

  defp request_id(nil), do: nil

  defp request_id(conn) do
    conn
    |> Conn.get_resp_header("x-request-id")
    |> List.first()
  end

  defp status_class(status) when is_integer(status), do: "#{div(status, 100)}xx"
  defp status_class(_), do: "unknown"

  defp duration_between(measurements, start_key, end_key) do
    start_time = measurements[start_key]
    end_time = measurements[end_key]

    if is_integer(start_time) and is_integer(end_time) and end_time >= start_time do
      end_time - start_time
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
