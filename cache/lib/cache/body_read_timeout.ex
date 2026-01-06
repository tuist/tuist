defmodule Cache.BodyReadTimeout do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  require Logger

  def read_body(conn, opts) do
    Plug.Conn.read_body(conn, opts)
  rescue
    error in [Bandit.HTTPError] ->
      if String.contains?(error.message, "Body read timeout") do
        log_timeout(conn, error.message)
        {:error, :timeout, conn}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp log_timeout(conn, message) do
    Logger.info(
      "Request body read timeout",
      request_id: request_id(conn),
      method: conn.method,
      path: conn.request_path,
      content_length: header(conn, "content-length"),
      user_agent: header(conn, "user-agent"),
      remote_ip: format_remote_ip(conn.remote_ip),
      error_message: message
    )
  end

  defp request_id(conn) do
    conn.assigns[:request_id] || header(conn, "x-request-id")
  end

  defp header(conn, key) do
    case get_req_header(conn, key) do
      [value | _rest] -> value
      [] -> nil
    end
  end

  defp format_remote_ip(nil), do: nil

  defp format_remote_ip(ip) when is_tuple(ip) do
    ip |> :inet.ntoa() |> to_string()
  end
end
