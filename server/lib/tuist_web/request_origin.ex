defmodule TuistWeb.RequestOrigin do
  @moduledoc false

  def from_conn(conn) do
    {scheme, port} =
      case Plug.Conn.get_req_header(conn, "x-forwarded-proto") do
        [proto] ->
          {proto, forwarded_port(conn) || default_port(proto)}

        _ ->
          {Atom.to_string(conn.scheme), conn.port}
      end

    authority = if port == default_port(scheme), do: conn.host, else: "#{conn.host}:#{port}"
    "#{scheme}://#{authority}"
  end

  defp forwarded_port(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-port") do
      [port_str] ->
        case Integer.parse(port_str) do
          {port, ""} -> port
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp default_port("https"), do: 443
  defp default_port(_), do: 80
end
