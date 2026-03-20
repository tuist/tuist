defmodule TuistCommon.HTTP.Transport do
  @moduledoc """
  Shared normalization for Bandit and Thousand Island transport telemetry.

  This module intentionally follows the native telemetry contracts exposed by Bandit and
  Thousand Island instead of re-emitting app-specific events.

  Useful upstream references:

  - Bandit telemetry event docs:
    https://github.com/mtrudel/bandit/blob/main/lib/bandit/telemetry.ex
  - Bandit request pipeline, which forwards `error.message` into `[:bandit, :request, ...]`
    telemetry metadata:
    https://github.com/mtrudel/bandit/blob/main/lib/bandit/pipeline.ex
  - Bandit HTTP/1 socket handling, including the `"Body read timeout"` error that we classify
    here:
    https://github.com/mtrudel/bandit/blob/main/lib/bandit/http1/socket.ex
  - Thousand Island telemetry event docs:
    https://github.com/mtrudel/thousand_island/blob/main/lib/thousand_island/telemetry.ex
  - Thousand Island socket internals, which emit `:recv_error`, `:send_error`, and
    `:socket_shutdown` events:
    https://github.com/mtrudel/thousand_island/blob/main/lib/thousand_island/socket.ex

  In practice, this module uses Bandit request metadata to:
  - classify body read timeouts
  - classify request failures
  - extract low-cardinality request tags and log fields

  And it uses Thousand Island connection metadata to:
  - classify connection drops
  - normalize recv/send error tags
  - extract connection-level log fields for incident correlation
  """

  def bandit_request_timeout?(metadata) do
    metadata[:error] == "Body read timeout"
  end

  def bandit_request_failure_reason(metadata) do
    conn = metadata[:conn]
    status = conn && Map.get(conn, :status)

    cond do
      is_integer(status) and status >= 500 -> "server_error"
      not is_nil(metadata[:error]) -> "protocol_error"
      true -> nil
    end
  end

  def bandit_request_metadata(metadata) do
    conn = metadata[:conn]

    %{
      method: (conn && conn.method) || "unknown",
      route: (conn && conn.private[:phoenix_route]) || "unknown"
    }
  end

  def bandit_timeout_log_metadata(measurements, metadata) do
    metadata
    |> bandit_request_metadata()
    |> Map.merge(%{
      request_id: bandit_request_id(metadata),
      request_span_context: format_span_context(metadata[:telemetry_span_context]),
      connection_span_context: format_span_context(metadata[:connection_telemetry_span_context]),
      duration_ms: duration_ms(measurements[:duration]),
      req_body_bytes: measurements[:req_body_bytes],
      error: metadata[:error]
    })
    |> compact_metadata()
  end

  def bandit_exception_log_metadata(measurements, metadata) do
    metadata
    |> bandit_request_metadata()
    |> Map.merge(%{
      request_id: bandit_request_id(metadata),
      request_span_context: format_span_context(metadata[:telemetry_span_context]),
      connection_span_context: format_span_context(metadata[:connection_telemetry_span_context]),
      duration_ms: duration_ms(measurements[:duration]),
      kind: metadata[:kind],
      error: format_exception(metadata[:exception])
    })
    |> compact_metadata()
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

  def thousand_island_connection_error_metadata(event)
      when event in [:recv_error, :send_error] do
    %{event: Atom.to_string(event)}
  end

  def thousand_island_connection_log_metadata(measurements, metadata) do
    %{
      connection_span_context: format_span_context(metadata[:telemetry_span_context]),
      remote_address: format_remote_address(metadata[:remote_address]),
      remote_port: metadata[:remote_port],
      duration_ms: duration_ms(measurements[:duration]),
      recv_oct: measurements[:recv_oct],
      send_oct: measurements[:send_oct]
    }
    |> compact_metadata()
  end

  def thousand_island_drop_log_metadata(measurements, metadata, reason) do
    measurements
    |> thousand_island_connection_log_metadata(metadata)
    |> Map.merge(%{
      reason: reason,
      error: inspect(metadata[:error])
    })
    |> compact_metadata()
  end

  def thousand_island_error_log_metadata(event, measurements, metadata)
      when event in [:recv_error, :send_error] do
    measurements
    |> thousand_island_connection_log_metadata(metadata)
    |> Map.merge(%{
      event: Atom.to_string(event),
      error: inspect(measurements[:error])
    })
    |> compact_metadata()
  end

  defp bandit_request_id(metadata) do
    conn = metadata[:conn]

    conn
    |> then(fn conn -> if conn, do: Map.get(conn, :resp_headers, []), else: [] end)
    |> header_value("x-request-id")
  end

  defp format_exception(exception) do
    case exception do
      nil -> nil
      %{__exception__: true} = exception -> Exception.message(exception)
      other -> inspect(other)
    end
  end

  defp format_remote_address(nil), do: nil

  defp format_remote_address(remote_address) do
    remote_address
    |> :inet.ntoa()
    |> to_string()
  rescue
    _ -> inspect(remote_address)
  end

  defp format_span_context(nil), do: nil
  defp format_span_context(span_context), do: inspect(span_context)

  defp header_value(headers, key) do
    case List.keyfind(headers, key, 0) do
      {_key, value} -> value
      nil -> nil
    end
  end

  defp duration_ms(nil), do: nil
  defp duration_ms(duration), do: System.convert_time_unit(duration, :native, :millisecond)

  defp compact_metadata(metadata) do
    metadata
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
