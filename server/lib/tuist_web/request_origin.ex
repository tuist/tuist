defmodule TuistWeb.RequestOrigin do
  @moduledoc false

  def from_conn(conn) do
    scheme = forwarded_value(conn, "x-forwarded-proto") || Atom.to_string(conn.scheme)
    host = forwarded_value(conn, "x-forwarded-host") || conn.host
    port = forwarded_value(conn, "x-forwarded-port") || Integer.to_string(conn.port)

    default_port = if scheme == "https", do: "443", else: "80"

    if String.contains?(host, ":") or port == default_port do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  defp forwarded_value(conn, header) do
    case Plug.Conn.get_req_header(conn, header) do
      [value] -> value |> String.split(",", parts: 2) |> List.first() |> String.trim()
      _ -> nil
    end
  end
end
